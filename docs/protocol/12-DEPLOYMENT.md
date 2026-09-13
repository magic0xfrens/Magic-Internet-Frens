# 12 — Deployment

A fresh testnet deployment, derived from the deploy scripts rather than from the
older runbooks. Where a runbook and a script disagree, the script is described.

Everything below is a read of `contracts/solidity/deploy/*.s.sol` and
`scripts/*.sh` at `20d6de2`. No transaction was broadcast to produce it.

---

## 1. The one-command path

```
./scripts/go-testnet.sh
```

Five steps (`scripts/go-testnet.sh:3-9`):

| Step | Action | Lines |
|---|---|---|
| 1 | Arm the **old** deployment's break-glass, starting its immutable delay | `:61-76` |
| 2 | Deploy the new stack (`deploy-testnet.sh`) | `:78-84` |
| 3 | Mint out the presale in batches of 250 | `:86-100` |
| 4 | `finalize()` → summon | `:102-107` |
| 5 | Fold the mined addresses into the manifest | `:109-111` |

It refuses to start unless the resolved signer is the expected deployer
(`:52-57`), and if it took a key from a gitignored `.env` it deletes that file
on any exit, including Ctrl-C (`:38-46`).

Arming the old deployment moves nothing. It forces redemption open — the
intended holder protection — and starts the old registry's `emergencyDelay`,
which is immutable (`:61-64`).

Step 2 reads the presale address back out of the deploy log by grepping for
`MiFrensGenesis : 0x…` and aborts if it cannot find it (`:82-83`). Step 3
batches at 250 because `mint()` loops `_mint` at roughly 55 k gas per token, so
1110 in one call would not fit in a block (`:86-88`). Step 4 is the transaction
that creates the market: `finalize()` summons the pool with the presale's entire
balance (`:102-104`).

---

## 2. What `deploy-testnet.sh` sets

Every value that differs from mainnet lives in one block, so the mainnet deploy
is this file with that block deleted (`scripts/deploy-testnet.sh:4-7`).

| Variable | Testnet | Mainnet intent | Line |
|---|---|---|---|
| `POOL_MANAGER` | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` | — | `:12` |
| `POSITION_MANAGER` | `0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4` | — | `:13` |
| `TESTNET_GOV` | `true` — waives the contract's own 1-day floors | unset | `:21` |
| `GOV_VOTING_PERIOD` | 300 s | 3 days | `:22` |
| `GOV_COOLDOWN` | 60 s | 7 days | `:23` |
| `GOV_EXECUTION_WINDOW` | 1800 s | 3 days | `:24` |
| `GOV_ENVELOPE_LIFETIME` | 7200 s | 30 days | `:25` |
| `EMERGENCY_DELAY` | 600 s | 48 h | `:30` |
| `PRESALE_PRICE` | 5e14 wei | 0.0062 ETH | `:42` |
| `PRESALE_MAXWALLET` | 1111 | 100 | `:43` |
| `GENESIS_BONUS_BPS` | 1400 (= 17.5 % of mint price) | same | `:47` |
| `PRIME_BUY_ETH` | 1e17 wei | — | `:53` |
| `SEED_WINDOW` | 300 s | 900+ | `:58` |
| `BADGE_ART` | `true` (~167 KB, ~33 M gas) | — | `:63` |
| `MINT_OUT_TARGET_USD` | 8e21 ($8 k) | $2 M | `:70` |
| `HEARTBEAT_ETH` | 21600 s | 4 h | `:77` |
| `HEARTBEAT_USDC` | 172800 s | 12 h | `:78` |
| `VENUE_ETH` / `VENUE_USDG` | 5e15 / 15e6 | — | `:81-82` |

Two of these are load-bearing rather than cosmetic.

- **`PRESALE_PRICE` is also the pool's seed liquidity.** `finalize()` summons
  with the presale's whole balance, so pricing too cheaply launches a pool too
  thin to open a perp against or to rotate — the test then measures nothing
  (`:32-41`).
- **The Sepolia heartbeats are widened because the feeds are loose.** The
  USDC/USD pair was measured 23.7 h stale against a 12 h mainnet heartbeat, which
  made `QuoteOracle` report 0 ("cannot judge") for USDG and would have made a
  USDG-quoted generation record no volume at all (`:72-78`).

The script then runs one `forge script`:

```
forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com "${SIGNER[@]}" --broadcast
```

(`:112-115`.)

---

## 3. Contract order and constructor arguments

All of the following happen in one `vm.startBroadcast()` block
(`DeployLaunchpad.s.sol:123-546`).

| # | Contract | Constructor arguments | Line |
|---|---|---|---|
| 0 | `TimelockController` | `(tlDelay, [deployer], [deployer], deployer)` — proposer, executor, canceller all the deployer EOA | `:130-132` |
| 1 | `MiFrensGenesis` | `("MiFrens","MIFREN", supply, artCap, price, maxWallet, "https://mifrens.xyz/api/mifren/")` | `:136-138` |
| 2 | `CauldronHook` | CREATE2 with a mined salt: `(poolManager, deathThreshold, address(0), deployer, deployer)` | `:142-154` |
| 3 | `CauldronRegistry` | `(poolManager, positionManager, hook, emergencyAdmin, emergencyDelay)` | `:185-186` |
| 3b | `RedemptionExt` | `()` | `:192` |
| 4 | `CauldronGovernor` | `(presale)` | `:197` |
| 4b | `CauldronFactory` | `()` | `:201` |
| 4c | `MiFrensDividend` | `(presale, TREASURY ?? deployer)` | `:207` |
| 4d | `CauldronGachaRouter` | `(poolManager, hook, registry, deployer)` | `:212-213` |
| 4e | `CollectionLedger` | `(registry)` | `:219` |
| 4f | `LiquidatoorRenderer` | `()`, only when `BADGE_ART` | `:227-236` |
| 5 | `MintCurvePolicy` | `(curveBase, spread, knee, n)` | `:317` |
| 6 | `CauldronSeeder` | `(registry, positionManager, poolManager)`, only when `SEED_WINDOW > 0` | `:359-360` |
| 7 | `QuoteRotator` | `(registry, poolManager)` | `:431` |
| 8 | `TreasuryGovernor` | `(IVotes721(presale), registry, timelock ?: deployer, votingPeriod, envelopeLifetime, cooldown, executionWindow, testnetGov)` | `:460-469` |
| 9 | Rotation stack | `MockQuoteToken("Magic USD","USDG",6)`, `QuoteOracle(deployer)`, `VenueSeeder()` | `:600-601`, `:650` |

The hook's address is **mined**: `HookMiner.find` searches for a salt whose
resulting address carries the required V4 permission flags —
`AFTER_INITIALIZE`, `BEFORE_SWAP`, `BEFORE_SWAP_RETURNS_DELTA`, `AFTER_SWAP`,
`AFTER_SWAP_RETURNS_DELTA` (`:142-150`) — and the script asserts the deployed
address equals the mined one (`:154`).

### Immutables that cannot be corrected

- `CauldronRegistry.emergencyAdmin` is immutable and must be the timelock from
  birth, which is why the timelock is deployed **first** (`:126-129`).
- `CauldronRegistry.emergencyDelay` is immutable, and **zero is refused at
  deploy** (`require`, `:184`). The comment records the consequence of the old
  zero default: the registry's arm-and-wait was skipped entirely, so
  `emergencyReadyAt` was never set, and because the redemption exit guarantee
  keys off exactly that variable, the "arming forces redemption open" protection
  silently did not exist. Round 31 shipped that way and cannot be fixed without
  a redeploy (`:163-183`).
- `TreasuryGovernor`'s four timing parameters are fixed at construction with no
  setter, so nothing can shorten them afterwards (`:447-448`).

---

## 4. Wiring calls, in order

Read this as a sequence. The ordering constraints in §5 explain why it is this
sequence and not another.

| Order | Call | Line |
|---|---|---|
| 1 | `registry.setRedemptionExt(redemptionExt)` | `:193` |
| 2 | `hook.setRegistry(registry)` | `:239` |
| 3 | `hook.setGuild(dividend)` | `:240` |
| 4 | `hook.setOpener(gacha, true)` | `:241` |
| 5 | `gacha.setOracle(quoteOracle)` — only if `QUOTE_ORACLE` is set | `:251` |
| 6 | `hook.setDeathThreshold(...)` | `:275` |
| 7 | `hook.setPolicies(0, 0, curve)` | `:318` |
| 8 | `hook.setOpener(registry, true)` + `hook.setTaxExempt(registry, true)` | `:332-333` |
| 9 | `registry.setRoyalty(dividend, 500)` / `presale.setRoyalty(dividend, 500)` | `:335-336` |
| 10 | `presale.setDividend(dividend)` | `:339` |
| 11 | `dividend.setRegistry(registry)` | `:343` |
| 12 | `dividend.setFunder(hook)` | `:348` |
| 13 | `registry.setFactory(factory)` | `:349` |
| 14 | `registry.setGovernor(governor)` | `:350` |
| 15 | `registry.setSeeder(seeder)` (also wires `hook.setSeeder`) | `:361` |
| 16 | `registry.setSeedWindow(seedWindow)` | `:362` |
| 17 | `hook.setOpener(seeder, true)` + `hook.setTaxExempt(seeder, true)` | `:369-370` |
| 18 | `hook.setSnipeParams(snipeBlocks, SNIPE_MAX_BPS)` | `:382` |
| 19 | `seeder.fundPrime{value: PRIME_BUY_ETH}(PRIME_TO)` | `:389` |
| 20 | `registry.setCollectionLedger(ledger)` | `:402` |
| 21 | `hook.setLegacyBuyback(registry, LEGACY_BPS, LEGACY_THRESHOLD)` | `:403-407` |
| 22 | `registry.setGenesisMetadata(Renderer, "", gnomeRenderer)` | `:408` |
| 23 | `presale.setLiquidatorRenderer(badgeRenderer)` | `:413` |
| 24 | `factory.setLiquidatorRenderer(badgeRenderer)` | `:421` |
| 25 | `treasuryGov.setQuoteOracle(quoteOracle)` | `:475` |
| 26 | **`registry.setRotationWiring(rotator, treasuryGov)`** | `:476` |
| 27 | Rotation stack: `oracle.setFeed`, `oracle.setBounds`, `oracle.setPegged`, `rotator.setArbParams`, `registry.setAllowedQuote(usdg, true, 1e18)`, `rotator.setVenue(...)` | `:614-656` |
| 28 | `registry.setGenesisBonus(presale, bonusBps, supply)` | `:493` |
| 29 | `registry.setAirdropReserve(...)` — only if `AIRDROP_RESERVE > 0` | `:501` |
| 30 | `hook.setTaxExempt(SNIPE_WALLET ?? deployer, true)` | `:504` |
| 31 | `registry.setPrimeFunder(PRIME_FUNDER ?? deployer)` | `:511` |
| 32 | `registry.setGuardian(GUARDIAN ?? deployer)` | `:516` |
| 33 | `governor.setRegistry(registry)` | `:517` |
| 34 | `presale.setRegistry(registry)` | `:518` |
| 35 | `presale.setFinalizer(FINALIZER ?? deployer)` | `:524` |
| 36 | `registry.setIgniter(presale)` | `:538` |
| 37 | **`registry.transferOwnership(timelock)`** | `:539` |

Hook ownership deliberately stays with the deployer past the end of this script
so `DeployPerp` can still call `hook.setPerpEngine`; `DeployPerp` performs the
final hook→timelock and engine→timelock handoff (`:541-544`).

### Then `DeployPerp.s.sol`

| Order | Call | Line |
|---|---|---|
| 1 | `new PerpEngine(...)` | `:72` |
| 2 | `new PerpVault(engine, registry)` | `:77` |
| 3 | `hook.setPerpEngine(engine)` — enables `afterSwap` auto-liquidation | `:83` |
| 4 | `engine.setVault(vault)` | `:89` |
| 5 | `engine.setVaultLimits(MAX_UTIL_BPS=8000, INSURANCE_FLOOR_WEI=0.05 ETH)` | `:94-96` |
| 6 | `engine.setGuards(TWAP_WINDOW=300, MAX_LIQ_BPS=2000, MAX_FUNDING_BPS=5000)` | `:121-125` |
| 7 | `engine.setRouting(dividend, treasury, nftBeneficiary, markSource)` | `:147` |
| 8 | Optional PLV seed via the vault | `:155` |
| 9 | `hook.setPerpEngine(engine)` again, then `hook.transferOwnership(timelock)` and `engine.transferOwnership(timelock)` | `:165-168` |

It reads `HOOK`, `REGISTRY`, `PRESALE`, `DIVIDEND`, `POOL_MANAGER` from the
environment and takes `PRIVATE_KEY` via `vm.envUint` (`:55-68`) — unlike
`DeployLaunchpad`, which supports `--account` (`:89-98`).

---

## 5. Ordering constraints, and where a gap lets a stranger act first

These are the constraints that actually matter. Most are "this must happen while
the deployer still owns the contract"; two are launch-timing gaps.

1. **Timelock before registry.** `emergencyAdmin` is immutable
   (`DeployLaunchpad.s.sol:126-129`). Deploying the registry first would permanently
   bind the wrong admin.
2. **Hook before registry.** The hook address is a registry constructor argument
   (`:186`), and it is CREATE2-mined, so it cannot be predicted from a nonce.
3. **`setRedemptionExt` before any ownership handoff.** It is `onlyOwner` and
   one-shot (`:189-193`). Miss it and every OG-redemption and rotation
   forwarder is dead, because the registry has no catch-all fallback.
4. **`setRotationWiring` before the handoff.** `RedemptionExt.rotateSlice` reads
   both `quoteRotator` and `treasuryGovernor` off the registry and reverts
   `NotConfigured` if either is zero. The script's own comment records that this
   script previously deployed the rotator and stopped, and no script anywhere
   deployed a governor or called `setRotationWiring` — so **every rotation
   reverted on every deployment that has ever existed** (`:434-443`).
5. **One script must own the whole rotation stack.** Two scripts each deploying
   a `QuoteRotator` meant the venue could end up curated on the rotator the
   registry was *not* pointing at, and the failure is silent: every rotation
   reverts `NoRoute` while both contracts look perfectly deployed
   (`:479-485`).
6. **Wire the gacha oracle in the same operation as `setDeathThreshold`.** The
   hook restates its odds curve from ether into USD the moment an oracle is
   wired; without the same oracle on the router it hands a wei numerator to a USD
   denominator and collapses its own players' odds by roughly the ETH price
   (`:242-251`).
7. **`isOpener` AND `taxExempt` together.** The registry's first-block market buy
   must skip both the base tax and the anti-sniper surtax or its ETH is taxed
   away mid-buy and `relaunch()` reverts `OutOfFunds`. The hook requires *both*
   flags deliberately, so a direct swapper cannot forge an exemption through
   `hookData` (`:326-333`, same for the seeder at `:364-370`).
8. **The anti-snipe window must track the seed window.** They are independently
   configured and were pulling opposite ways: a 30-block surtax window (~6 min)
   against a 900 s seed window (~75 blocks) meant the surtax decayed to zero
   with only ~54 % of ledger A placed, and the remaining 46 % streamed into a
   book with no sniper protection at all. `snipeBlocks` now defaults to
   `seedWindow / BLOCK_TIME` (`:372-382`).
9. **Ignition is a role, not ownership.** The old script transferred registry
   ownership to the presale purely so `finalize()` could reach `summon()`, which
   permanently burned every `onlyOwner` setter — including `setGovernor` and
   `setFactory`, both called from inside `relaunch()`. Ignition is now
   `setIgniter` and ownership goes to the timelock (`:526-539`).
10. **`transferOwnership` is last.** After `:539` no `onlyOwner` registry setter
    is reachable except through the timelock. Anything forgotten before this
    line needs a timelock proposal — or, for the one-shot setters, a redeploy.
11. **`DeployPerp` before the hook handoff.** The hook must still be
    deployer-owned when `setPerpEngine` is called (`:541-544`,
    `DeployPerp.s.sol:165-168`).

### Gaps where a stranger could act first

- **`presale.setFinalizer` (`:519-524`).** While `finalizer == 0`, a sold-out
  presale can be ignited by **anyone**, and a watching bot then picks the block
  the green candle lands in. The script sets it to the deployer by default, but
  the window between `MiFrensGenesis` being deployed (`:136`) and `setFinalizer`
  (`:524`) is ~35 transactions long. It is only exploitable once the presale is
  sold out, which on the scripted path is later — but on a deploy that is
  interrupted after step 1 and resumed with a live mint, this is the race.
  `FINALIZER=0x0` deliberately restores permissionless ignition.
- **`hook.setOpener(gacha, true)` (`:241`) and `registry.setIgniter` (`:538`)**
  are the two "nothing works until this lands" gates. Between hook deployment
  and `setRegistry` (`:239`) the hook is live on-chain with no registry, so any
  pool initialised against it in that window is not the protocol's pool. The
  PoolKey for a generation is derivable, so this window should not be left open
  across a manual pause.
- **`DeployRotationStack.s.sol:210-219`** is explicit about the post-handoff
  case: if the registry is already owned by the timelock, it cannot call
  `setAllowedQuote` or `setRotationWiring` and instead prints the calls to
  queue. A deploy that takes that branch is *not* finished when the script
  exits.
- **`DeployLaunchSniper.s.sol`** must be run *before* selling out the presale,
  and its own header says so (`:17-18`). Commit `834063c`
  ("the sniper script assumed the gacha was already a hook opener") and `79a3fed`
  ("the atomic launch buy called a router function that does not exist") both
  landed today; re-read that script before using it.

---

## 6. Post-deploy verification

1. **`node scripts/apply-deployment.mjs --dry`** — preview the addresses it
   would write, then run it without `--dry`. It reads Foundry's broadcast
   artifacts, which record what was *mined*, not what a script intended
   (`scripts/apply-deployment.mjs:12-13`). It reads all three broadcasts
   (`DeployLaunchpad`, `DeployRotationStack`, `DeployPerp`) because a manifest
   that captured only one would be half-stale, which is worse than wholly stale:
   the app half-works and the failures look like bugs (`:15-17`).
2. **`node scripts/verify-manifest.mjs`** — must exit 0. It enforces the
   required contract set, address shape, no duplicate addresses, a
   Postgres-safe `schema`, an absolute `indexerUrl` and positive block numbers
   (`:24-70`). Confirm the `hook` entry is the hook and not a linked library —
   that failure has shipped before (`scripts/apply-deployment.mjs:79-90`).
3. **Rotation is wired but unapproved.** `audit/DEPLOY_RUNBOOK.md:52-58` gives
   the call:
   ```
   cast call $REGISTRY \
     "rotateSlice(uint16,uint256,(address,address,uint24,int24,address))(uint256,uint256)" \
     2500 0 "(0x0,$USDG,3000,60,0x0)" --rpc-url $RPC
   ```
   Expect `0xcd5a2fee` = `NoRotationApproved()` — wired, awaiting a vote. A
   `RotationNotWired` error means step 26 did not land. These are now distinct
   errors; on the old code both were `NotConfigured`, which is part of why the
   fault survived so long. The three-argument `rotateSlice` used here is a real
   registry entrypoint (`contracts/solidity/CauldronRegistry.sol:240`) that
   hardcodes leg 0; the UI calls the four-argument `rotateSliceFrom`
   (`:264`).
4. **Perp badge minter.** `DeployPerp.s.sol:174-177` prints the active
   collection's `liquidatorMinter()` and says it should equal the `PerpEngine`
   address above it. Check that line in the deploy output.
5. **Bump the indexer.** Change `schema` in `indexer/deployments/round.json` to
   force a clean reindex, then `cd indexer && railway up`
   (`scripts/go-testnet.sh:114`).
6. **Rebuild the frontend** so it picks up the manifest
   (`scripts/go-testnet.sh:115`).
7. **Freshness.** `GET <indexerUrl>/freshness` returns 200 with
   `indexedGen === chainGen` and `curPoolId` present in `indexedPools`.
8. **Recover the old round** once its delay elapses:
   `./scripts/recover-live.sh` for the round you just replaced, or
   `./scripts/reclaim-old-lp.sh` (dry run first) for an older one.

---

## 7. The deployment records disagree

There are **four** JSON files describing a deployment. Only one is read by the
build.

| File | Status | Round | Registry |
|---|---|---|---|
| `indexer/deployments/round.json` | **Canonical — read by the frontend, the indexer, `keeper.sh`, `mint-presale.sh`, `recover-live.sh`, `api/brand.ts`, `api/cauldron/liquidatoor.ts`** | 38 | `0x018efe32…` |
| `deployments/sepolia.json` | Declares itself "CANONICAL … SINGLE SOURCE OF TRUTH" (`:2`) | 20 | `0x60f5e17f…` |
| `contracts/solidity/deployments/sepolia.json` | `_status: SUPERSEDED` (`:2`) | — | `0x0dcc4D2d…` |
| `contracts/solidity/deployments/sepolia-launch.json` | `_status: SUPERSEDED` (`:2`) | v7 | `0x09579fbb…` |
| `contracts/solidity/deployments/sepolia-final.json` | `_status: SUPERSEDED` (`:2`) | — | `0x4Cdb936e…` |

Commit `a6a56f8` ("three files each called itself canonical; a mainnet deploy
could pick any of them") added the `SUPERSEDED` headers to the three files under
`contracts/solidity/deployments/`. Those three now correctly point at
`deployments/sepolia.json` and state that nothing in the build reads them and
that the deploy scripts take their addresses from environment variables.

**The conflict that remains** is between the two files that are *not* marked
superseded:

| Key | `deployments/sepolia.json` | `indexer/deployments/round.json` |
|---|---|---|
| round | 20 (`:3`) | 38 (`:3`) |
| registry | `0x60f5e17f0A7cb39503B4C5A844b16DBc6604BB51` (`:10`) | `0x018efe32379bfc3f38ed7e592f5c9f214b6e3ded` (`:13`) |
| hook | `0xB8494825bCa113753DD1549f76B305Fe8c0810cc` (`:11`) | `0xa319112cc4896f89ae0770b7be00c990c64010cc` (`:14`) |
| gachaRouter | `0x13D8b35477A106882f43778E838704bdD137f885` (`:13`) | `0x5e9aa391edbfd1e5029e528981b1b362a933bf54` (`:20`) |
| dividend | `0x057777F6c8B84Dc88c81421453EE448BD40E4b5F` (`:14`) | `0xe0b3dd1cda3cca883af546237ca20ba2f7ac5b85` (`:18`) |
| governor | `0xe3B1f662307d2431C4B07D2644Bece5cAe5C69f0` (`:15`) | `0x4d8afe933683172f0af8b455a1caf905dec77314` (`:17`) |
| factory | `0x44E45792B91002D772329B50B189a36bcB534AeD` (`:16`) | `0xf61db0761246e18a44a094d74b3db12211cb20e8` (`:26`) |
| presale / `mifrens` | `0x2fcB2a68cc8B43F1cF288CA1361fae9C8a22A577` (`:17`) | `0x9589089c648797b5b1246a2514b4cb4820f22089` (`:19`) |
| perpEngine | `0x26ae199E143d98be557Eaf89EF7764291bcc51e5` (`:18`) | `0x43cb1942df7ad2072a27f73b509fc1ee4c21ff92` (`:23`) |
| perpVault | `0x06dB1ea16180d6D3aefED3B4B54fF962431Ce46E` (`:19`) | `0xfc9b5eed31ef11b90b53538bccf7b2b51d112569` (`:24`) |
| indexer URL | `mifrens-indexer-app-production.up.railway.app` (`:5`) | `indexer-production-102c.up.railway.app` (`:6`) |
| schema | `cauldron_prod21` (`:6`) | `cauldron_r38` (`:4`) |
| start block | 11590392 (`:7`) | 11675010 (`:8-10`) |

Only `poolManager` and `positionManager` agree.

Nothing in the build reads `deployments/sepolia.json` — `verify-manifest.mjs`
guards `indexer/deployments/round.json` (`:22`) and every consumer listed above
imports that path. But `deployments/sepolia.json:2` still calls itself the
single source of truth and instructs the reader to run
`scripts/sync-deploy.mjs`, and the three superseded files point *at it* as the
canonical record. **That chain of pointers is wrong and should be corrected to
name `indexer/deployments/round.json`.** Until it is, an operator following the
headers arrives at round-20 addresses.

`scripts/marketmaker.sh:30-33,51` is the one place those round-20 addresses are
still hardcoded and used.

---

## Verification

- `git rev-parse --short HEAD` → `20d6de2`
- Disagreements found:
  1. `deployments/sepolia.json:2` declares itself the canonical single source of
     truth, but the frontend, the indexer and every operator script read
     `indexer/deployments/round.json`. The two records agree on nothing but
     `poolManager` and `positionManager`.
  2. The three `contracts/solidity/deployments/*.json` files correctly mark
     themselves superseded but name `deployments/sepolia.json` as canonical,
     which is itself stale.
  3. `deployments/sepolia.json:2` and `indexer/ponder.config.ts:16` point at
     `scripts/sync-deploy.mjs` / `scripts/deploy-round.mjs` as the propagation
     step, while `scripts/go-testnet.sh:111` runs
     `scripts/apply-deployment.mjs`.
- Not verified: `DeployMigrationVesting.s.sol`, `DeployRenderer.s.sol`,
  `DeployCauldron.s.sol`, `FixFactoryWiring.s.sol`, `SellVolume.s.sol`,
  `SnipeBuy.s.sol` and `SwapVolume.s.sol` were identified by their headers only
  and are not part of the scripted bring-up path; the mainnet timing values in
  §2 are the script's own comments, not values this deployment has run.
