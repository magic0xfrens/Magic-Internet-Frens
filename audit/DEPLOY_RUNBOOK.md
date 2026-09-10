# Sepolia redeploy runbook

Everything below was dry-run end to end against a local Anvil fork of Sepolia. The
addresses in the examples are from that fork and are **not** real; yours will differ.

The only step I cannot run is the one that spends real ETH — it needs your key.

---

## 0. Why a redeploy is required

The source is ahead of the deployed contracts in ways that cannot be patched in place:

| finding | contract | effect on the live deployment |
|---|---|---|
| B-15 | `RedemptionExt` | `setRotationWiring` forwarded into a facet that never implemented it, so `quoteRotator`/`treasuryGovernor` could never be set and **every rotation reverted** |
| F-11 | `QuoteRotator` | one `owner` slot served two incompatible roles, so a rotation reverted `NotOwner` **even when wired** |
| F-10 | `RedemptionExt`, `PerpEngine` | a completed rotation never updated `generationQuote`, and the perp engine could never re-adopt it |
| B-09/B-10 | `CauldronGovernor` | unbounded proposal payload could put `relaunch()` permanently out of gas; spam erased a voted mandate |
| B-11 | `QuoteOracle` | a reverting feed bypassed the cache and silently zeroed volume |
| B-12 | `QuoteRotator` | venue allowlist (fails closed — see step 2) |
| B-13 | `PoolOps` | one wei of a second quote outranked the entire recovered position |
| B-14 | `RedemptionExt`, `TreasuryGovernor` | a full de-risking rotation took ~80 days; now ~4 |

Additionally, the deployed `QuoteRotator.quoteOracle()` **reverts** — it predates that
function entirely — and `generationPositionId[1]` reads `0` on the live registry.

---

## 1. Deploy the core stack

```
cd contracts/solidity
FOUNDRY_PROFILE=cauldron \
PRIVATE_KEY=<your key> \
POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4 \
forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
```

This now also deploys a **TreasuryGovernor** and calls **`setRotationWiring`** — neither
of which any script did before, which is why rotation had never worked.

Deploys: MiFrensGenesis · CauldronHook · CauldronRegistry · RedemptionExt ·
CauldronGovernor · **TreasuryGovernor** · QuoteRotator · MiFrensDividend ·
CollectionLedger · CauldronGachaRouter · CauldronFactory.

### Verify before going further

```
cast call $REGISTRY "rotateSlice(uint16,uint256,(address,address,uint24,int24,address))(uint256,uint256)" \
  2500 0 "(0x0000000000000000000000000000000000000000,$USDG,3000,60,0x0000000000000000000000000000000000000000)" \
  --rpc-url $RPC
```

Expect **`0xcd5a2fee` = `NoRotationApproved()`**. That means wired, awaiting a vote —
the healthy state.

`0x...RotationNotWired` would mean step 1 failed to wire. These are now **different
errors**; on the old code both were `NotConfigured`, which is part of why B-15 survived
so long.

---

## 2. Quote assets, oracle feeds, and the venue

```
FOUNDRY_PROFILE=cauldron \
PRIVATE_KEY=<your key> \
REGISTRY=<from step 1> \
POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4 \
forge script deploy/DeployRotationStack.s.sol --tc DeployRotationStack \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
```

Deploys USDG (6dp mock), a `QuoteOracle`, **creates and seeds the ETH/USDG Uniswap v4
pool**, and **curates it as a venue**.

Price feeds are **real Chainlink**, probed live on Sepolia rather than taken from a list:

| asset | feed | measured |
|---|---|---|
| ETH | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | $2481.38, 113s old |
| USDG | `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E` (USDC/USD) | $0.9999, 3.1h old |

USDG is a mock USD stablecoin, so pricing it off the real USDC/USD feed is the accurate
model, not a fabrication. Heartbeats are 4h/12h — sized to what testnet feeds actually
do (DAI/USD was 13h stale when measured; a mainnet-cadence heartbeat would reject
working feeds).

> **The venue allowlist fails closed.** `setVenue` is called by this script. If you ever
> point a rotation at a different pool, curate it first or every slice reverts `NoRoute`.
> That is deliberate: an uncurated venue lets a keeper self-deal at the governed floor.

---

## 3. Perps (optional, only if you want the leverage UI live)

```
FOUNDRY_PROFILE=cauldron PRIVATE_KEY=<key> \
POOL_MANAGER=... HOOK=<step1> REGISTRY=<step1> PRESALE=<step1> DIVIDEND=<step1> \
forge script deploy/DeployPerp.s.sol --tc DeployPerp --rpc-url $RPC --broadcast
```

---

## 4. Fold the addresses into the manifest

```
node scripts/apply-deployment.mjs        # add --dry to preview
```

Reads Foundry's broadcast artifact (what was actually mined, not what the script
intended), writes `indexer/deployments/round.json`, and **bumps `round` + `schema`** so
Ponder drops the old tables and reindexes. Without that bump the app serves the previous
round's data against the new addresses.

`round.json` is the single source of truth for **both** the frontend and the indexer.
Never mirror these into hosting env vars — an env override wins silently and the two
drift the moment one changes alone.

---

## 5. Redeploy the indexer, rebuild the frontend

```
cd indexer && railway up          # picks up round.json + the new /treasury endpoint
cd .. && npm run build
```

The indexer gained a `/treasury` endpoint (LP positions per quote, oracle-priced) and
`pool.quote` / `pool.isPrimary` columns. The frontend reads treasury composition from
that endpoint — **the browser makes no RPC calls for it**, which is the convention the
rest of the app follows and which my first draft violated.

---

## 6. Drive a rotation from the UI

`#/cauldrons?v=governance` shows two surfaces:

- **Govern** — propose an envelope (destination + budget), 3-day vote.
- **Execute** — anyone sends 25% slices. 12 slices converts **96.83%**.

The panel pre-checks `isVenueAllowed` and warns before you press, rather than letting a
slice revert.

**Timeline for a full ETH→USDG rotation: ~4 days** (3-day vote + ~1 day of slicing).
A second envelope, after the 7-day cooldown, takes it past 99%. It never reaches exactly
100% — each slice takes a share of what *remains*, so the series is geometric.

---

## What is deliberately NOT automated

**xNVDA / any tokenized equity.** Sepolia carries no equity feed, so it could only be
priced by a mock. Shipping a second quote nobody can price honestly, just to have a third
row in the UI, is not worth the surface. `MockAggregator` is in the tree for the unit
suites if you want it later.

**Oracle ownership handoff.** The script transfers the oracle to the registry owner only
when that is not the deployer. On a timelocked deployment, queue it.
