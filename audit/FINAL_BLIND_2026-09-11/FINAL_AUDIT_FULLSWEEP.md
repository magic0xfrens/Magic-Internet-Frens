# Smart Contract Security Audit Report
Magic Internet Frens — Cauldron: FULL-SURFACE COMPLEMENT SWEEP

## Executive Summary

**Project:** Magic Internet Frens / The Cauldron (eternal-machine launchpad)
**Auditor:** Solidity security auditor (full-surface sweep, blind to the prior review's findings list)
**Date:** 2026-09-12
**Commit:** `c4481ee` (branch `redteam/2026-09-11`)
**Solidity Version:** `^0.8.26` (compiled with solc 0.8.30, profile `cauldron`)

### Scope rationale

This pass is the deliberate **complement** of the long review. The elevated-risk
subsystems (hook fee routing, legacy buffer, perp engine/vault, quote rotation,
oracle, both governors, genesis ignite, gacha churn, vesting) were attacked hard
already. This sweep targets the code that got the **least** attention, in the
order the brief set: `PoolOps.sol` first (1,462 lines, the most-delegatecalled
library in the system, and only one node of it changed across the entire prior
review), then the seeder, the collection + ledger, the dividend, non-ignite
genesis, and the six small contracts.

### Overview

`PoolOps` is the money-moving core: it creates every pool, prices every launch,
seeds both tranches, migrates holders, recycles collections and crystallises
floors — all by `delegatecall` from the registry, so every line runs with the
registry's balances and identity. It was audited line by line here, with
particular attention to (a) the four `public` library functions and the nine
`external` ones, all of which are directly callable at the deployed library
address; (b) every division and rounding direction; (c) the behaviour of every
stored amount under a 6-decimal quote.

Two new findings came out of it. The headline one, **Z-01**, is a *denomination*
bug in the oldest and least-touched arithmetic in the repo — the five-line
`_sqrtPrice` helper. It makes the mandatory rebirth path revert, permanently,
whenever a non-native generation is reborn with a modest amount of a 6-decimal
quote. It is the same permanent-freeze class as the B-05 walls, sitting one
layer deeper than any of them, and it is reachable on the **live** round-40
configuration because `DeployLaunchpad.s.sol:668` allowlists a 6-decimal USDG.

The second, **Z-02**, is a permissionless and **permanently irreversible**
inflation of a dead collection's crystallised entitlement, via the dying floor
vault's open `receive()`. The prior review fixed the *denomination* of that same
`vaultSwept` value (finding X5c); it did not address its *magnitude*, and
`CollectionLedger` has no downward adjuster — which the brief flagged as a thing
to hunt, correctly.

### Risk Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High     | 5 |
| Medium   | 4 |
| Low      | 7 |
| Info     | 3 |

### Key Findings

- **Z-17 (CRITICAL)** — `CauldronSeeder.poke()` is permissionless
  (`CauldronSeeder.sol:231`) and the treasury prime buy it drives has **no
  slippage bound whatsoever** — `sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1`
  and no `minAmountOut` (`:286-295`) — while `_placeStep` anchors the streamed
  liquidity to **live spot** read from `getSlot0` (`:368`). One EOA in one
  transaction can push the price, call `poke()` to make the protocol place its
  liquidity and spend its prime budget at that price, and sell back through it.
  Measured with a real v4 `PoolManager` and production seed parameters: the
  treasury received **68,794 tokens instead of 46,122,162 (−99.9%)** and the
  attacker netted **+12.157 ETH**.
- **Z-01 (High)** — `PoolOps._sqrtPrice` cannot represent a launch price below
  ~42.1 million quote **base units**. In an 18-decimal quote that is 42 gwei
  (harmless). In a 6-decimal quote it is **42.12 tokens**, and `_greenCandle`
  halves the headroom again, so a rebirth funded with under ~84 USDG reverts
  inside `FullMath.mulDiv` — after `governor.markConsumed`, which permanently
  bricks the eternal machine. The registry's only pre-seed guard is
  `totalETH == 0` (`CauldronRegistry.sol:994`), which is denomination-blind.
  **PoC: 4/4 passing, boundary pinned to one base unit.**
- **Z-02 (High)** — anyone can donate ether to a live generation's
  `CauldronVault.receive()` (`CauldronVault.sol:72`). At that generation's death
  the donation is swept into `vaultSwept` and inflates the dead collection's
  crystallised entitlement toward 100% of the newborn's active tranche.
  `CollectionLedger.crystallize` is one-shot (`AlreadyCrystallized`) and nothing
  can lower `entitledTokens`/`totalEntitled`, so the inflated `legacy` is
  subtracted from **every future generation's** active supply forever.
- **Z-08 (High)** — **the gacha reveal is grindable without limit.** The M-03
  "re-anchor" branch (`CauldronCollection.sol:265-269`,
  `MiFrensGenesis.sol:532-536`) lets a holder who dislikes the tier they can
  already read off-chain simply *decline to reveal*, wait out the 256-block
  `blockhash` window, and get a free fresh draw — unbounded. The comment above it
  asserts "there is always exactly ONE unknowable draw"; the code delivers
  best-of-unlimited. The prior M-03 fix closed best-of-two and opened this.
- **Z-09 (High)** — a winning proposal picks `nftSupply` with **no lower bound**
  (`CauldronGovernor.sol:316` bounds only the top), while `MintCurvePolicy` is an
  immutable ladder calibrated for one supply that *discards* the per-generation
  curve the registry writes (`MintCurvePolicy.sol:95`). A 100-NFT proposal mints
  the whole collection out for ~$80 of volume instead of ~$20,000 and captures
  that generation's entire collection floor.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Scope](#scope)
3. [Methodology](#methodology)
4. [Findings](#findings)
5. [Attacked and Found Clean](#attacked-and-found-clean)
6. [Redeploy Verdict](#redeploy-verdict)

---

## Scope

### Contracts in Scope

| Contract | Lines | Attention it had before |
|----------|-------|-------------------------|
| `cauldron/PoolOps.sol` | 1462 | one node changed in the whole prior review |
| `cauldron/ReserveLib.sol` | 107 | reserve tick/liquidity math |
| `cauldron/CollectionLedger.sol` | 156 | floor accounting, no downward adjuster |
| `cauldron/CauldronCollection.sol` | 432 | mint authority, reveal, custody |
| `cauldron/CauldronVault.sol` | 126 | only the *swept denomination* was fixed |
| `CauldronToken.sol` | — | burn authority (gate verification only) |
| `CauldronRegistry.sol` | — | call sites + gates of the above only |

### Out of Scope (covered by the prior review, per the brief)

Hook fee routing and legacy buffer; perp engine and vault; quote rotation and
oracle; both governors; genesis ignite; gacha churn; vesting. Also excluded:
OpenZeppelin, v4-core, v4-periphery.

### Deployment Information

- **Network:** Sepolia, round 40 live, containing every fix to date.
- **Relevant live config:** `DeployLaunchpad.s.sol:625` deploys USDG with
  **6 decimals**; `:668` calls `registry.setAllowedQuote(usdg, true, 1e18)`.
  A 6-decimal quote is therefore an allowlisted, governance-selectable quote on
  the live system — which is what makes Z-01 reachable rather than theoretical.

---

## Methodology

### Tools Used
- Manual line-by-line review of `PoolOps.sol` (both halves, 1,462 lines).
- Targeted `grep` verification of every symbol before citation.
- The project's own machine-validated function graph (`audit/graph/pool.md`,
  `nft.md`) for authority/gate/loop-bound cross-checks.
- Foundry PoC (`forge test`, profile `cauldron`, solc 0.8.30) against the **real
  linked library**, not a reimplementation.

### Review Process
1. Read `PoolOps.sol` end to end; enumerated every `public`/`external` entry and
   asked, for each, "what happens when a stranger calls this at the deployed
   library address, where `address(this)` is the library and not the registry?"
2. Verified every downstream authority gate that defence depends on.
3. Re-derived every division and its rounding direction.
4. Re-evaluated every stored amount, threshold and constant in 6-decimal and
   18-decimal quotes.
5. Wrote a boundary-sharp PoC for the one arithmetic finding.

### A note on evidence discipline

Per the brief, comments in this tree are not evidence — `audit/graph/*.md`
records 146 comment-vs-code contradictions. Every claim below carries a
`File.sol:line` that was read, and the code is quoted before it is
characterised. Findings are tagged **VERIFIED** (traced fully in code, or
executed) or **DERIVED** (sound inference, not executed).

---

## Findings

### Z-01 — HIGH — The launch-price helper cannot represent a small 6-decimal quote amount, and the revert sits behind `markConsumed`

**Tag:** VERIFIED (PoC, 4/4 passing, boundary pinned to one base unit)
**Location:** `contracts/solidity/cauldron/PoolOps.sol:181-190` (`_sqrtPrice`),
reached from `PoolOps.sol:462-467` (`_greenCandle`), `PoolOps.sol:221`
(`createAndSeed`), `PoolOps.sol:297` (`createAndSeedProgressive`),
`PoolOps.sol:876` (`openOrAddPair`).
**Guard that fails to cover it:** `CauldronRegistry.sol:994`.
**PoC:** `contracts/solidity/test/attacks/Z1_SeedPriceDenominationFloor.t.sol`

#### The code

```solidity
// PoolOps.sol:181-190
function _sqrtPrice(uint256 tokenAmount, uint256 ethAmount) private pure returns (uint160) {
    uint256 ratio = FullMath.mulDiv(tokenAmount, 1 << 192, ethAmount);
    // Babylonian sqrt.
    uint256 x = ratio;
    if (x == 0) return 0;
    ...
}
```

```solidity
// PoolOps.sol:460-467  (_greenCandle, the mandatory relaunch seed path)
uint256 totalTokens = activeTok + reserveTok;

uint256 ethActive = FullMath.mulDiv(ethAmt, activeTok, totalTokens);
if (ethActive > BUY_SETTLE_BUFFER) ethActive -= BUY_SETTLE_BUFFER;

// Deep-discount launch price = ALL tokens against only E_active.
uint160 sqrtPriceX96 = _sqrtPrice(totalTokens, ethActive);
poolManager.initialize(r.key, sqrtPriceX96);
```

#### Description

`FullMath.mulDiv(a, b, d)` computes a full 512-bit product and then **reverts**
unless the 256-bit quotient fits — and it reverts on `d == 0`. Here
`a = totalTokens`, `b = 2**192`, `d = ethActive`. The quotient fits only when:

```
ethActive  >  totalTokens * 2**192 / 2**256  ==  totalTokens / 2**64
```

On the relaunch path `totalTokens` is exactly `newActive + newReserve ==
CauldronToken.TOTAL_SUPPLY == 777_000_000e18` (`CauldronRegistry.sol:1074-1075`,
`CauldronToken.sol:29`), so the floor is a **fixed constant**:

```
777_000_000e18 / 2**64  ==  42_121_254 base units of the quote
```

That figure is in the quote's **own base units**, and nothing in the path
normalises it:

| Quote | 42,121,254 base units is… | Binding? |
|---|---|---|
| native ETH (18 dec) | 0.000000000042 ETH | never |
| USDG / USDC / USDT (6 dec) | **42.12 tokens** | routinely |

`_greenCandle` makes it worse by a further factor: it feeds `_sqrtPrice` the
*whole* supply but only `ethActive = ethAmt · activeTok / totalTokens` of the
quote. With a 50/50 active/reserve split the required `ethAmt` is
**≈ 84.24 USDG**.

The registry's only pre-seed solvency check is denomination-blind:

```solidity
// CauldronRegistry.sol:994-995
if (totalETH == 0) revert NoLiquidityToSeed();
governor.markConsumed(winId);
```

It validates against **zero**, not against the minimum the price arithmetic can
represent. And it is the *last* line on the safe side — the comment block
immediately above it says so explicitly: *"Reverting on the RIGHT is what must
never happen."* `_seedGeneration` → `createAndSeedWithBuy` → `_greenCandle` →
`_sqrtPrice` is entirely on the right.

`PoolOps.seedFunding` will happily return such an amount. Branch 1 returns on a
bare `p > 0`:

```solidity
// PoolOps.sol:1076-1079
if (wantQuote != address(0) && (recovered == 0 || oldQuote == wantQuote)) {
    uint256 p = (oldQuote == wantQuote ? recovered : 0) + _pullAsset(hookAddr, wantQuote);
    if (p > 0) return (wantQuote, p, 0);
}
```

`_pullAsset` drains `hook.releaseRelaunchAsset(wantQuote)`, which is credited
from whatever asset each swap fee arrived in. A guild that has traded a
USDG-quoted pair only lightly holds a small number of USDG base units there, and
`recovered == 0` is ordinary (a dead position whose liquidity is 0 makes
`removeAll` return `(0, 0)` at `PoolOps.sol:1145`).

#### Impact

**Permanent, unrecoverable brick of the entire protocol lifecycle**, identical in
shape to the B-05 walls and one layer beneath all of them. `markConsumed` is
rolled back with the revert, so the same proposal wins `_bestUnconsumed()` again,
and every subsequent `relaunch()` dies at the same line. There is no keeper, no
retry and no owner function that recovers it: the failing input is *derived* from
protocol state, so re-running produces the same input.

Secondary reach (same root cause, non-mandatory paths): `openOrAddPair` at
`PoolOps.sol:876` prices a rotation's new pair with `_sqrtPrice(tokenAmount,
quoteAmount)`, so a rotation slice smaller than the floor reverts the rotation;
and `createAndSeedProgressive`'s non-native degrade branch (`PoolOps.sol:297`)
has the same exposure on the summon path.

#### Exploit sequence

No attacker is required — this is a latent state-dependent freeze. The
deterministic version:

1. Governance allowlists a 6-decimal quote. **Already true on round 40:**
   `DeployLaunchpad.s.sol:625` deploys USDG with `6` decimals, `:668`
   allowlists it.
2. A generation runs with USDG as its quote (or the hook accrues any USDG fee
   reserve), so `hook.relaunchAsset[USDG]` is non-zero but small — tens of USDG.
3. A proposal naming USDG wins; the dying pool returns `recovered == 0`
   (drained/zero-liquidity position).
4. `seedFunding` takes branch 1 and returns `(USDG, p)` with `p < 84_242_637`.
5. `totalETH != 0`, so the guard passes; `markConsumed(winId)` fires.
6. `_greenCandle` → `_sqrtPrice(777_000_000e18, ~p/2)` → `FullMath.mulDiv`
   reverts with empty returndata.
7. The whole transaction unwinds, including `markConsumed`. Goto 4, forever.

An attacker who merely wants to *hasten* this can make step 2 cheap: a single
dust swap on a USDG-quoted registry pool credits `relaunchAsset[USDG]`.

#### PoC

`test/attacks/Z1_SeedPriceDenominationFloor.t.sol`, run against the **real
linked `PoolOps`** with a mock PoolManager whose fallback reverts
`REACHED_INITIALIZE`, so control flow is observable:

```
[PASS] test_Z1_threshold_is_42_million_base_units()        — floor == 42,121,254
[PASS] test_Z1_subThresholdSeed_revertsBeforeInitialize()  — ethAmount 84,242,636 → empty revert, never reaches initialize
[PASS] test_Z1_aboveThresholdSeed_reachesInitialize()      — ethAmount 84,242,638 → reverts REACHED_INITIALIZE
[PASS] test_Z1_oneUnitSeed_dividesByZero()                 — ethAmount 1 → ethActive 0 → mulDiv div-by-zero
Suite result: ok. 4 passed; 0 failed; 0 skipped
```

The boundary is pinned to **one base unit**: 84,242,636 dies in `_sqrtPrice`,
84,242,638 survives it. This is not a reimplementation of the helper — it calls
`PoolOps.createAndSeedWithBuy` on the deployed library.

#### Concrete fix

Clamp, do not revert — the same discipline this file already applies at
`_seedReserve` (`:793`), `deployTokenAbove` (`:718`) and the `nftSupply` bound.
Two changes, both in `PoolOps.sol`:

```solidity
    /// @dev The smallest quote amount `_sqrtPrice` can represent for a given token
    ///      amount: mulDiv(tokenAmount, 2**192, q) overflows uint256 unless
    ///      q > tokenAmount / 2**64. Stated as a helper so every caller shares it.
    function _minQuoteFor(uint256 tokenAmount) private pure returns (uint256) {
        return (tokenAmount >> 64) + 1;
    }

    function _sqrtPrice(uint256 tokenAmount, uint256 ethAmount) private pure returns (uint160) {
        //  REPRESENTABILITY FLOOR, NOT A REVERT. `ethAmount` arrives in the QUOTE's
        //  own base units; 42.1M of them is 42 gwei in ether but 42 tokens in a
        //  6-decimal quote. Reverting here would land behind `markConsumed`.
        uint256 minQ = _minQuoteFor(tokenAmount);
        if (ethAmount < minQ) ethAmount = minQ;
        uint256 ratio = FullMath.mulDiv(tokenAmount, 1 << 192, ethAmount);
        ...
    }
```

and, so the clamp cannot silently mis-price the active mint, hold the buffer
back only when there is room for it:

```solidity
    // _greenCandle, replacing :462-463
    uint256 ethActive = FullMath.mulDiv(ethAmt, activeTok, totalTokens);
    uint256 minQ = _minQuoteFor(totalTokens);
    if (ethActive > BUY_SETTLE_BUFFER + minQ) ethActive -= BUY_SETTLE_BUFFER;
    if (ethActive < minQ) ethActive = minQ;
```

**Belt and braces, strongly recommended alongside the clamp** — make the
registry's guard denomination-aware so the failure is caught on the *safe* side
of `markConsumed` instead of being papered over:

```solidity
    // CauldronRegistry.sol, replacing :994
    //  NOT `== 0`. The seed amount is in `specQuote`'s base units, and PoolOps'
    //  price helper cannot represent a launch price below TOTAL_SUPPLY / 2**64
    //  of them (~42.1e6). Ask the real question on the LEFT of markConsumed.
    if (totalETH <= (TOTAL_SUPPLY >> 64)) revert NoLiquidityToSeed();
```

Reverting *here* is safe and recoverable by design (the comment block at
`:988-993` says exactly that): the proposal stays live and a later call succeeds
once the machine holds enough.

---

### Z-02 — HIGH — A stranger's ether donation to a live floor vault permanently inflates the dead collection's entitlement, suppressing every future generation

**Tag:** VERIFIED for the mechanism (every link read and quoted); DERIVED for the
end-to-end profitability arithmetic (not executed).
**Location:** `CauldronVault.sol:72` (open `receive()`), `CauldronVault.sol:116-119`
(`close()`), `PoolOps.sol:1012-1014` + `:1082-1084` (`seedFunding` branch 2),
`PoolOps.sol:1374-1389` (`crystallizeCollection`), `CauldronRegistry.sol:1043-1064`,
`CollectionLedger.sol:145-161` (`crystallize`, one-shot, no downward adjuster).

#### The code

The vault takes ether from anyone:

```solidity
// CauldronVault.sol:72
receive() external payable {
```

and `close()` sweeps whatever is there:

```solidity
// CauldronVault.sol:116-119
function close() external nonReentrant returns (uint256 swept) {
    ...
    swept = address(this).balance;
```

`seedFunding` folds that sweep into the newborn's book and reports it:

```solidity
// PoolOps.sol:1012-1014
if (oldVault != address(0)) {
    try IVaultCloseOps(oldVault).close() returns (uint256 s) { vaultSwept = s; } catch {}
}
// PoolOps.sol:1082-1084  (branch 2, native)
if (recovered == 0 || oldQuote == address(0)) {
    uint256 n = (oldQuote == address(0) ? recovered : 0) + vaultSwept + _pullEth(hookAddr);
    if (n > 0) return (address(0), n, vaultSwept);
}
```

and the registry turns the ratio into a permanent entitlement:

```solidity
// PoolOps.sol:1378-1388
if (ledger == address(0) || collection == address(0) || totalETH == 0) return 0;
if (ILedgerOps(ledger).crystallized(gen)) return 0;
entitled = FullMath.mulDiv(swept, activeBase, totalETH);
...
ILedgerOps(ledger).crystallize(gen, nftCount, entitled);
```

```solidity
// CauldronRegistry.sol:1043-1064
PoolOps.crystallizeCollection(
    address(collectionLedger), generationCollection[oldGen], generationVault[oldGen],
    oldGen, vaultSwept, newActive, totalETH
);
uint256 legacy = collectionLedger.totalEntitled();
if (newActive > legacy) {
    newActive -= legacy;
} else {
    emit ReserveShortfall(newGen, legacy, newActive);
    newActive = 0;
}
if (newActive == 0) newActive = GEN1_ACTIVE_TOKENS;
```

#### Description

`entitled = swept · activeBase / totalETH`, and in branch 2 `totalETH` *contains*
`vaultSwept`. So with a legitimate funding level `L` and a donation `D`:

```
entitled  =  (V + D) / (L + D) · newActive        →  newActive   as D grows
```

A donation therefore drives the dead collection's crystallised entitlement toward
**100% of the newborn's entire active tranche**. The prior review's X5c fix
addressed the *denomination* of this value (it made only branch 2 report
`vaultSwept`, so numerator and denominator now share units — that part is
correct and is not being re-reported). It did not bound the *magnitude*, and the
magnitude is third-party controlled.

The damage does not expire:

- `CollectionLedger.crystallize` reverts `AlreadyCrystallized`
  (`CollectionLedger.sol:150`), so it cannot be re-run with a corrected figure.
- Nothing in `CollectionLedger` lowers `entitledTokens[gen]` or `totalEntitled`
  except `redeem` — which only fires when a *holder* chooses to recycle, and
  which itself reverts `NothingOutstanding` at zero outstanding.
- `legacy = collectionLedger.totalEntitled()` is the **global** sum across all
  generations, and `CauldronRegistry.sol:1057-1063` subtracts it from `newActive`
  at **every future relaunch**. Once `legacy ≥ newActive`, every future
  generation forever launches with `newActive = GEN1_ACTIVE_TOKENS`.

So one donation, at one death, permanently caps the active liquidity of every
generation that follows, and permanently over-claims the shared reserve LP that
also backs migration and genesis redemption (`Invariant R`). The protocol
*detects* this (`ReserveShortfall`) but has no way to undo it.

#### Impact

Permanent protocol-wide degradation: every future generation's tradeable tranche
collapses to the `GEN1_ACTIVE_TOKENS` fallback, and the shared reserve is
over-claimed, so migrating holders and genesis redeemers hit `"reserve short"`
(`PoolOps.sol:1281`, `:1437`) on a first-come-first-served basis. The dead
collection's holders gain a claim they did not earn.

Honest note on cost: the donation `D` is real ether the attacker gives up, and
the entitlement it buys is worth at most `D` back (and only to whoever holds the
dead collection's NFTs). This is therefore a **griefing amplifier, not a profit
engine** — the attacker pays roughly once and the protocol pays forever. That
asymmetry, plus the irreversibility, is why it is rated High rather than Medium.
A dying generation with a small `L` makes it cheap: to reach `entitled ≈
newActive/2` costs only `D ≈ L`.

#### Exploit sequence

1. Generation *N* is live; `generationVault[N]` exists. (Optionally, acquire
   generation *N*'s collection NFTs first, to capture the entitlement.)
2. Send `D` ether directly to `generationVault[N]` — `receive()` at
   `CauldronVault.sol:72` accepts it from anyone. Do **not** redeem it back out
   before death, or `close()` sweeps zero.
3. Wait for generation *N* to die (or trigger it normally).
4. `relaunch()` → `seedFunding` → `close()` returns `V + D`; branch 2 returns
   `totalETH = L + D` and `vaultSwept = V + D`.
5. `crystallizeCollection` writes `entitled = (V+D)/(L+D) · newActive` into the
   ledger. One-shot; irreversible.
6. `legacy ≥ newActive` → `ReserveShortfall` → `newActive = GEN1_ACTIVE_TOKENS`.
7. Every later relaunch repeats step 6, because `totalEntitled` never comes down.

#### Concrete fix

Two independent bounds; apply both.

**(a) Cap the entitlement at the share the sweep genuinely bought.** The sweep is
part of the newborn's own book, so it can never be worth more than its own
proportion — and the donation must not be allowed to dominate that proportion.
Pass the *pre-donation* denominator, i.e. exclude the sweep from the ratio:

```solidity
    // PoolOps.crystallizeCollection, replacing :1380
    //  `swept` is INSIDE `totalETH` (seedFunding branch 2 adds it), and anyone may
    //  donate to a live vault's open receive(). Ratioing swept against a denominator
    //  it inflates lets a third party drive `entitled` to the whole active tranche,
    //  one-shot and with no downward adjuster in CollectionLedger. Ratio it against
    //  the funding that did NOT come from the vault, and cap the result.
    if (swept >= totalETH) return 0;                 // degenerate: nothing else funded the book
    entitled = FullMath.mulDiv(swept, activeBase, totalETH);
    uint256 cap = activeBase / MAX_LEGACY_SHARE_DIV; // e.g. 4 → at most 25%
    if (entitled > cap) entitled = cap;
```

with

```solidity
    /// @dev A dead collection's crystallised entitlement may never exceed this
    ///      fraction of the newborn's active tranche. The sweep it is sized from
    ///      is third-party inflatable (CauldronVault.receive is open) and the
    ///      ledger has no downward adjuster, so the bound has to be structural.
    uint256 internal constant MAX_LEGACY_SHARE_DIV = 4; // 25%
```

**(b) Close the donation door.** The vault's `receive()` needs to accept value
only from the hook/registry:

```solidity
    // CauldronVault.sol:72
    receive() external payable {
        //  NOT OPEN. A donation here is swept into `vaultSwept` at death and
        //  ratioed into a permanent, one-shot collection entitlement
        //  (PoolOps.crystallizeCollection). Restrict it to the protocol.
        if (msg.sender != registry && msg.sender != hook) revert NotAuthorized();
```

`(b)` alone is insufficient — `selfdestruct` and coinbase payments can still move
the balance — which is why `(a)` is the load-bearing fix.

---

### Z-03 — LOW — `buyCollection` credits the ledger less than the buyer paid; the difference is stranded

**Tag:** VERIFIED
**Location:** `PoolOps.sol:1443-1461`

```solidity
    uint256 paid = 2 * ILedgerOps(ledger).floorPerNFT(gen, mintedNow);
    require(paid > 0, "no floor");
    require(IERC20(token).transferFrom(caller, address(this), paid), "pay");
    added = addToReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, paid);
    ILedgerOps(ledger).buyback(gen, mintedNow, added);
```

The buyer is charged `paid`, but the ledger is credited `added`, and `added < paid`
whenever `ReserveLib.liquidityForTokenOut` rounds down (it always rounds down —
`ReserveLib.sol:88-98`). The `paid - added` remainder stays as a loose registry
token balance that nothing in the normal cycle spends (only `migrateToSuccessor`
and the timelocked `emergencySweep`, per the comment at `PoolOps.sol:1030-1034`).
Per call the leak is dust; it accumulates monotonically and silently, and the
buyer's floor ratchet is correspondingly short-changed.

**Fix:** credit the amount actually paid and keep the remainder explicit.

```solidity
    added = addToReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, paid);
    //  Credit what the BUYER PAID, not what liquidity rounding absorbed. The
    //  `paid - added` remainder is still held by the registry and still backs the
    //  entitlement, so crediting `added` understates the floor and strands dust.
    require(added + CLAIM_DUST >= paid, "reserve rounding");
    ILedgerOps(ledger).buyback(gen, mintedNow, paid);
```

---

### Z-04 — LOW — `_approve` ignores the ERC20 return value and re-approves without zeroing

**Tag:** VERIFIED
**Location:** `PoolOps.sol:176-179`

```solidity
    function _approve(address token, address pm, uint256 amount) private {
        IERC20(token).approve(PERMIT2, amount);
        IPermit2Ops(PERMIT2).approve(token, pm, uint160(amount), uint48(block.timestamp + 300));
    }
```

Two hostile-token issues on a path that runs behind `markConsumed`:

1. The `approve` return value is unchecked. A quote that returns `false` instead
   of reverting (USDT-shaped, and most tokenised equities) approves nothing;
   the failure then surfaces far downstream inside the PositionManager's pull.
   Note this is the same token class that
   `executeBuy` explicitly hardens against at `PoolOps.sol:563-565` — this
   sibling was missed.
2. `approve` sets an absolute value rather than zeroing first. A token that
   requires allowance-to-zero before a non-zero re-approval (again USDT-shaped)
   reverts on the *second* seed in the same quote.

Both are gated in practice by the owner-curated `allowedQuote` list, which is
why this is Low rather than High. It is still the wrong default on the one path
that must never revert.

**Fix:**

```solidity
    function _approve(address token, address pm, uint256 amount) private {
        //  CHECKED, AND ZEROED FIRST. This sits behind `markConsumed`, and the
        //  false-returning / must-zero-first token class is the same one
        //  {executeBuy} already hardens against at :563.
        _forceApprove(token, PERMIT2, 0);
        _forceApprove(token, PERMIT2, amount);
        IPermit2Ops(PERMIT2).approve(token, pm, uint160(amount), uint48(block.timestamp + 300));
    }

    function _forceApprove(address token, address spender, uint256 amount) private {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve");
    }
```

(OpenZeppelin's `SafeERC20.forceApprove` is already a dependency and does exactly
this, if the EIP-170 budget allows the import.)

---

### Z-05 — LOW — While a collection is alive, its floor is computed over a supply that still counts vault-burned NFTs

**Tag:** VERIFIED
**Location:** `CollectionLedger.sol:86-90` and `:112-123`, fed by
`PoolOps.sol:1431` and `PoolOps.sol:1454`

```solidity
// CollectionLedger.sol:86-90
function outstanding(uint256 gen, uint256 mintedNow) public view returns (uint256) {
    uint256 supply = crystallized[gen] ? frozenSupply[gen] : mintedNow;
    uint256 r = retired[gen];
    return supply > r ? supply - r : 0;
}
```

`mintedNow` is `collection.totalMinted()` (`PoolOps.sol:1431`, `:1454`) — a
monotonic mint counter. NFTs burned by `CauldronVault.redeem` are *not* deducted
from it, and `retired[gen]` only counts NFTs recycled through the *ledger* path.
So while the collection is alive, `outstanding` over-counts by the vault-burned
population, `floorPerNFT` is understated, and each live recycler is paid less
than their true share. At crystallisation the count is corrected
(`PoolOps.sol:1387` passes `vault.outstanding()`, which *does* subtract
`redeemed`), so the residue is returned to the remaining holders rather than
lost. Unequal distribution, no value leak.

**Fix:** deduct the vault's redemption count on the live path too, so the live
and frozen supplies agree:

```solidity
    // PoolOps.recycleCollection :1431 and buyCollection :1454 — pass the vault's
    // own outstanding when a vault exists, so the live floor and the frozen floor
    // are computed over the SAME population.
    uint256 mintedNow = vault == address(0)
        ? IColMinted(collection).totalMinted()
        : IVaultRedeemedOps(vault).outstanding();
```

(both call sites already have the vault address in the registry's scope;
`recycleCollection`/`buyCollection` would each take one more argument.)

---

### Z-06 — INFO — Rounding dust accumulates permanently in `totalEntitled`

**Tag:** VERIFIED
**Location:** `CollectionLedger.sol:117` (`payout = entitledTokens[gen] / n`)

`redeem` rounds the payout down, deliberately ("round DOWN → Σ never drifts above
reserve"). The remainder stays in `entitledTokens[gen]`. Once the last NFT is
retired, `outstanding` is 0, `redeem` reverts `NothingOutstanding`, and the
residue is stranded in `totalEntitled` forever — where it is subtracted from
every future generation's `newActive` (`CauldronRegistry.sol:1057`). The amount
is sub-wei-per-NFT per redemption and is not exploitable; it is noted only because
`totalEntitled` has no downward adjuster and therefore ratchets.

---

### Z-07 — INFO — `creatureFor(0)` reverts on checked subtraction

**Tag:** VERIFIED
**Location:** `PoolOps.sol:153-154`

```solidity
function creatureFor(uint256 gen) external pure returns (string memory name, string memory symbol) {
    uint256 idx = (gen - 1) % 6;
```

`gen == 0` underflows and panics (`0x11`). No in-protocol caller passes 0
(generations are 1-indexed), and the function is `pure`, so this is cosmetic —
but it is a `public`-surface function on a linked library that anyone can call,
and an off-chain indexer or the frontend probing gen 0 gets an opaque panic
rather than a revert reason.

---

## Findings — Part II (NFT economy, dividend, genesis, and the small contracts)

IDs continue the Z-series. Each retains a pointer to the PoC that demonstrates
it, all of which were run and confirmed to contain executed assertions (a PoC
that early-returns passes vacuously; every one below was re-run with `-vv`).

### Z-08 — HIGH — The gacha reveal is grindable without limit; the holder picks their own rarity

**Tag:** VERIFIED (code read independently; PoC grinds tier 0 → tier 3)
**Location:** `cauldron/CauldronCollection.sol:247-273` (every per-brew
collection) and the identical code at `cauldron/MiFrensGenesis.sol:515-542`
**PoC:** `test/attacks/T9a_GenesisDividendHunt.t.sol`
(`test_B_ExpiryReanchorIsAnUnlimitedGachaReroll`, with
`test_A_HonestRevealIsFinal` as the positive control)

#### The code

```solidity
// CauldronCollection.sol:247-273
function _reveal(uint256 tokenId) private {
    if (ownerOf(tokenId) != msg.sender) revert OnlyMinter();
    if (!revealed[tokenId]) {
        uint256 mb = mintBlockOf[tokenId];
        if (block.number <= mb) revert NotReady(); // seed not known yet
        bytes32 bh = blockhash(mb);
        // EXPIRED SEED (audit M-03): ... Substituting a DETERMINISTIC fallback here
        // handed the holder a SECOND, fully-predictable draw ... so they could
        // simply wait out the window whenever the first roll was poor and take
        // the better of two. ...
        // Instead we RE-ANCHOR to a fresh future block: the token stays
        // revealable forever, but there is always exactly ONE unknowable draw.
        if (bh == 0) {
            mintBlockOf[tokenId] = uint48(block.number);
            emit ReAnchored(tokenId, uint48(block.number));
            return;
        }
        uint8 rarity = _rollRarity(uint256(keccak256(abi.encodePacked(bh, tokenId, address(this)))));
        rarityOf[tokenId] = rarity;
        revealed[tokenId] = true;
        emit Revealed(tokenId, rarity);
    }
}
```

#### Description

This is the clearest comment-vs-code contradiction in the sweep. The comment
claims the re-anchor preserves "exactly ONE unknowable draw". It does not, for
one reason the comment never considers: **the draw stops being unknowable the
moment block `mb` is mined, and nothing obliges the holder to reveal.**

The seed is `blockhash(mb)` and the tier is
`_rollRarity(keccak256(bh, tokenId, address(this))))` — every input is public at
block `mb + 1`. The holder computes the pending tier off-chain, and:

- if it is good, calls `reveal()` and commits it;
- if it is bad, does nothing for 256 blocks. `blockhash(mb)` then returns 0, the
  `bh == 0` branch re-anchors `mintBlockOf` to a fresh block, **commits no
  rarity**, and the holder is handed a brand-new draw at the cost of one
  transaction.

Repeat until the peek shows the tier they want. The re-anchor is unlimited:
nothing counts it, caps it, or degrades the outcome. `revealed[tokenId]` is only
ever set on the *committing* branch.

The M-03 fix reasoning was sound about the failure it was looking at
(a deterministic fallback = best-of-two, "P(≥ Rare) from 21% to ~37.6%") and
introduced a strictly worse one: **best-of-unlimited**, i.e. P(Ultra) = 1 for any
holder willing to wait.

#### Impact

The advertised 79/15/5/1 rarity distribution is not a distribution — it is a menu.
Every patient holder ends up holding a top-tier NFT, and rarity is the entire
value proposition of the gacha tranche. No protocol funds are drained (nothing
on-chain prices rarity), so the loss is borne by honest minters and by every
secondary buyer who paid a rarity premium. It also devalues the Liquidatoor/badge
tiering that the collection's own metadata exposes.

Note this affects **every generation**: `CauldronCollection` is deployed fresh per
brew (`CauldronFactory.deployBrew`), so the bug ships with each one.

#### Exploit sequence

1. Mint (or receive) any unrevealed token — for the volume tranche, ids above
   `GENESIS_SUPPLY`. `mintBlockOf[id] = mb` is set at mint
   (`MiFrensGenesis.sol:474-483`).
2. At block `mb + 1`, compute
   `_rollRarity(keccak256(abi.encodePacked(blockhash(mb), id, collection)))`
   off-chain. Do **not** call `reveal()`.
3. If the tier is unsatisfactory, wait until `block.number > mb + 256` so
   `blockhash(mb) == 0`.
4. Call `reveal(id)`. It takes the `bh == 0` branch, re-anchors to a fresh block,
   commits nothing, and returns successfully.
5. Goto 2. Commit only on the tier you want.

Cost per re-roll: one transaction (~21k + one warm `SSTORE`) plus a ~256-block
wait. Expected ~100 re-rolls to force the 100-bps Ultra tier.

#### Concrete fix

The property that must hold is *committing is not optional*. Three options; (a) is
the correct one.

**(a) Make the expiry draw one-shot and self-committing.** On expiry, roll
immediately from a seed the holder cannot decline, and commit:

```solidity
        if (bh == 0) {
            //  ONE-SHOT, AND IT COMMITS. Re-anchoring without committing let the
            //  holder peek at `blockhash(mb)` (public from mb+1, and they are under
            //  no obligation to reveal), wait out the 256-block window, and take a
            //  free fresh draw — unbounded. The M-03 note above reasoned about
            //  best-of-two and shipped best-of-unlimited. Binding the expiry draw to
            //  the PREVIOUS block and committing it here means declining the first
            //  draw costs the holder the draw rather than buying them another.
            uint8 expiredRarity = _rollRarity(uint256(keccak256(
                abi.encodePacked(blockhash(block.number - 1), tokenId, address(this))
            )));
            rarityOf[tokenId] = expiredRarity;
            revealed[tokenId] = true;
            emit Revealed(tokenId, expiredRarity);
            return;
        }
```

This is still one unknowable draw per token (`blockhash(block.number - 1)` is not
known when the reveal transaction is *built*, only when it is mined), and it is
now unavoidable. A holder who waits gains nothing.

**(b) Cap the re-anchor.** Minimal diff, weaker guarantee (it buys exactly one
extra draw rather than infinite):

```solidity
    /// @notice One re-anchor per token, ever. Without the cap the expiry branch is
    ///         an unlimited free re-roll — see the note in {_reveal}.
    mapping(uint256 => bool) public reanchored;
    ...
        if (bh == 0) {
            if (reanchored[tokenId]) revert AlreadyReanchored();
            reanchored[tokenId] = true;
            mintBlockOf[tokenId] = uint48(block.number);
            emit ReAnchored(tokenId, uint48(block.number));
            return;
        }
```

**(c) Commit at mint** from a source the holder never controls (a VRF, or a
protocol-driven batch reveal). Correct but the largest change.

Apply the same fix to `MiFrensGenesis.sol:532-536` — it is the same code.

---

### Z-09 — HIGH — `nftSupply` has no lower bound, and the immutable mint curve discards the per-generation ladder

**Tag:** VERIFIED (arithmetic and the discarded arguments); DERIVED (the
floor-capture economics)
**Location:** `cauldron/MintCurvePolicy.sol:95` and `:67`;
`CauldronGovernor.sol:316`; `CauldronRegistry.sol:925-926`, `:1098`;
`CauldronHook.sol:2177`
**PoC:** `test/attacks/Z9b_CurveSupplyMandate.t.sol`

#### The code

```solidity
// MintCurvePolicy.sol:95 — note the two DISCARDED arguments
function priceAt(uint256 k, uint256, uint256) external view returns (uint256) {
    return base + (spread * k * k) / (k + knee);
}
// MintCurvePolicy.sol:67
uint256 public immutable supply;
```

```solidity
// CauldronGovernor.sol:316 — an UPPER bound only
if (nftSupply > MAX_NFT_SUPPLY) revert SupplyOutOfRange();
```

```solidity
// CauldronRegistry.sol:925-926
if (spec.nftSupply > 0) {
    nftSupply = spec.nftSupply > MAX_NFT_SUPPLY ? MAX_NFT_SUPPLY : spec.nftSupply;
}
// CauldronRegistry.sol:1098
hook.setNftCurveFrom(volPerNFT);
// CauldronHook.sol:2177 — the policy is consulted, and ignores what was just set
try pol.priceAt(k, volumePerNFT, nftPriceStep) returns (uint256 c) {
```

#### Description

Two independent defects compound:

1. **`nftSupply` is bounded above but not below.** `CauldronGovernor.propose`
   rejects only `> MAX_NFT_SUPPLY` (`:316`); the registry clamps only the top
   (`:925-926`). `nftSupply = 1` is a valid, winnable proposal.
2. **`MintCurvePolicy` is immutable and supply-specific, and throws away the
   per-generation curve.** `priceAt` declares its second and third parameters
   *unnamed* — `volumePerNFT` and `nftPriceStep`, the very values
   `hook.setNftCurveFrom(volPerNFT)` writes at `CauldronRegistry.sol:1098`, are
   discarded. The ladder is fixed by the constructor's `base`/`spread`/`knee`,
   calibrated for the `supply` stored at `:67`, and that calibration silently
   voids whatever the winning proposal mandated.

So the mint-out cost does not scale with the collection it is pricing. Measured on
the shipped 2222-calibrated ladder: the first 100 rungs total **$80.36** against a
$20,000 target, with the first rung at $0.72.

The policy is wired whenever `QUOTE_ORACLE` is set, which is the shipped
configuration (`DeployLaunchpad.s.sol:319`).

#### Impact

Both directions are harmful and neither is recoverable without a timelocked
`setPolicies` redeploy, because `MintCurvePolicy` is immutable:

- **Small `nftSupply`:** the whole collection forges out for a rounding error of
  the intended volume. `CollectionLedger.floorPerNFT = entitledTokens /
  outstanding` (`CollectionLedger.sol:94`), so the attacker who holds all of a
  100-NFT collection owns 100% of the claim on a floor funded by `floorBps`
  (default `10_000`, `CauldronHook.sol:458`) of that generation's entire fee
  revenue.
- **Large `nftSupply`:** mint-out for 10,000 costs $444,083 (22×) and for 100,000
  costs $45.9M. The NFT forge is simply dead for that generation.

#### Exploit sequence

1. `propose(..., nftSupply = 100, volumePerNFT = <anything>)`; win the vote.
2. `relaunch()` deploys a 100-NFT collection;
   `hook.setNftCurveFrom(volPerNFT)` writes a curve `MintCurvePolicy.priceAt`
   ignores.
3. Trade through the pool to accrue ~$80 of weighted buy credit (≈$1.6 in swap
   fees and slippage).
4. Forge all 100 NFTs.
5. Hold the entire collection-floor entitlement for the generation's whole life.

#### Concrete fix

Any one of these closes it; (a) plus (c) is the recommendation.

**(a) Bound `nftSupply` on both sides and bind it to the wired policy:**

```solidity
    // CauldronGovernor.propose, replacing :316
    //  BOTH SIDES. MintCurvePolicy is an IMMUTABLE ladder calibrated for one
    //  `supply()`, and it discards the per-generation curve the registry writes,
    //  so an unbounded-below nftSupply lets a proposal mint a whole collection
    //  out for ~0.4% of the mandated volume.
    if (nftSupply != 0 && (nftSupply < MIN_NFT_SUPPLY || nftSupply > MAX_NFT_SUPPLY)) {
        revert SupplyOutOfRange();
    }
```

**(b) Make the policy honour its arguments** rather than silently discarding
them — rename the parameters and scale `base`/`spread` by
`volumePerNFT / self.volumePerNFTAtCalibration`, so the mandate is respected.

**(c) Fail loudly on the mismatch instead of silently:**

```solidity
    // CauldronHook.setPolicies (:1942)
    //  A curve policy is calibrated for ONE supply and cannot be re-calibrated
    //  (immutable). Refuse one that does not match the collection it will price,
    //  rather than discovering the 22x mispricing from the mint ladder.
    if (_curve != address(0)) {
        require(ICurvePolicy(_curve).supply() == nftSupply, "curve/supply");
    }
```

---

### Z-10 — MEDIUM — Any ERC20 pushed to `MiFrensDividend`, including its own royalties, is unrecoverable

**Tag:** VERIFIED (the no-exit half, by execution); DERIVED (the marketplace
trigger)
**Location:** `cauldron/MiFrensDividend.sol:273-289` (`fundToken`), `:319-343`
(the only ERC20 outflows); trigger at `deploy/DeployLaunchpad.s.sol:336`
**PoC:** `test/attacks/T9a_GenesisDividendHunt.t.sol`
(`test_C_PushedErc20RoyaltyIsPermanentlyStranded`)

```solidity
// MiFrensDividend.sol:278-287
if (msg.sender != funder) revert NotOwner();
...
_pull(asset, msg.sender, amount);
accPerShareOf[asset] += (amount * ACC) / activeShares;
```

`fundToken` is the **only** path that credits an ERC20, and it is both
`funder`-gated *and* pull-based — so it structurally cannot adopt a balance that
is already sitting in the contract. Meanwhile
`DeployLaunchpad.s.sol:336` makes the dividend contract the collection's EIP-2981
royalty receiver (`presale.setRoyalty(address(dividend), 500)`). A marketplace
settling a sale in WETH or USDC pays that royalty with a plain `transfer`.

The result: 5% of every non-native-denominated secondary sale lands in a contract
with no owner, no sweep, no rescue, and no crediting path. The PoC confirms
`accPerShareOf == 0`, `pendingToken == 0`, `assetCount == 0`, and that
`claimTokens` and `withdrawOwedToken` (holder *and* treasury) all leave the
balance untouched.

`RoyaltyRouter.sol:22-32` documents this exact hazard for its own ETH and solves
it by forwarding atomically; the dividend has no equivalent.

**Fix** — either route this collection's royalties through a forwarder as the
brew collections do, or add an adopt path with a per-asset accounted ledger:

```solidity
    /// @notice Credit an ERC20 that was PUSHED here (marketplace royalties arrive by
    ///         plain `transfer`, which `fundToken`'s pull cannot see). Without this
    ///         such a balance is credited to nobody and has no exit at any
    ///         privilege level.
    mapping(address => uint256) public accountedOf;

    function adopt(address asset) external returns (uint256 delta) {
        if (msg.sender != funder) revert NotOwner();
        if (activeShares == 0) revert NoShares();
        delta = IERC20(asset).balanceOf(address(this)) - accountedOf[asset];
        if (delta == 0) revert ZeroAmount();
        accountedOf[asset] += delta;
        accPerShareOf[asset] += (delta * ACC) / activeShares;
    }
```

(`accountedOf` must also be incremented in `fundToken` and decremented on every
payout, or the two accountings diverge.)

---

### Z-11 — MEDIUM — `DefaultFeeRouter` does not reproduce the hook's split, and silently diverts the whole collection floor share

**Tag:** VERIFIED
**Location:** `cauldron/DefaultFeeRouter.sol:28` against `CauldronHook.sol:1383`
and `:1433`; trigger condition at `CauldronRegistry.sol:1189`, `:1213`
**PoC:** `test/attacks/Z9_ScopeProbe.t.sol` (`test_Z9a…`)

```solidity
// DefaultFeeRouter.sol:28
toFloor = (vault != address(0) && floorBps > 0) ? (rem * floorBps) / BPS : 0;

// CauldronHook.sol:1383 — the split it claims to reproduce. NO vault test.
wantFloor = floorBps > 0 ? (rem * floorBps) / BPS : 0;
```

The router adds a `vault != address(0)` condition the hook does not have — and
both collection-deployment paths **always** set `hook.setVault(address(0))`
(`CauldronRegistry.sol:1189`, `:1213`). So under the shipped configuration the
router returns `toFloor == 0` always, the whole
`if (wantFloor > 0) { ... legacyBuffer += wantFloor; ... }` buy-pressure block at
`CauldronHook.sol:1433` is skipped, and 85% of every ETH fee is redirected from
the collection's token floor into the relaunch reserve.

The hook's own mismatch detector cannot catch it: the three returned amounts still
sum to `feeAmount`, so `routed = true` (`CauldronHook.sol:1373`). This directly
contradicts the assurance at `CauldronHook.sol:1952` that "a bad router can only
fall back, never misroute", and the router's own NatSpec claim (`:8`) that it
"reproduces the hook's BUILT-IN ETH fee split".

This is a **governance footgun, not an attack** — it requires an owner/timelock
`setFeeRouter` call. It is reachable precisely because the contract is presented
as the safe drop-in baseline. It is also currently dead code: zero in-protocol
callers, and no deploy script deploys it — which is why the divergence went
unnoticed.

**Fix** — delete the extra condition so it matches the hook exactly, or delete the
contract:

```solidity
    // DefaultFeeRouter.sol:28
    //  NO VAULT TEST. CauldronHook.sol:1383 does not have one, and both collection
    //  deploy paths set vault == 0 (CauldronRegistry.sol:1189, :1213) — so the extra
    //  condition zeroed the floor share on EVERY swap while still summing to
    //  feeAmount, which is exactly what the hook's mismatch check cannot see.
    toFloor = floorBps > 0 ? (rem * floorBps) / BPS : 0;
```

---

### Z-12 — LOW — `MAX_PER_WALLET` is a live-balance check, so one buyer can take the whole genesis tranche

**Tag:** VERIFIED
**Location:** `cauldron/MiFrensGenesis.sol:268`
**PoC:** `test/attacks/T9a_GenesisDividendHunt.t.sol`
(`test_D_PerWalletCapEvadedByParkingTokens`)

```solidity
if (balanceOf(msg.sender) + quantity > MAX_PER_WALLET) revert PerWalletCap();
```

The cap is checked against the caller's *current balance*, not against how much
they have ever minted. `loop { mint(MAX_PER_WALLET); transfer each id to a fresh
address }` takes the entire tranche at the ordinary presale price.

Consequences: one entity holds the whole OG dividend tranche and the entire
`ERC721Votes` electorate, and with `finalizer == address(0)` also picks the
ignition block. It is partly self-taxing — every parked id gets
`everMoved[id] = true` (`:711`), so re-enchanting costs `enchantFee` — and no
funds are lost, hence Low.

**Fix** — cap on cumulative mints rather than balance:

```solidity
    /// @notice Cumulative mints per address. A BALANCE check is not a cap: tokens
    ///         can be parked in fresh addresses between batches.
    mapping(address => uint256) public mintedBy;
    ...
    if (mintedBy[msg.sender] + quantity > MAX_PER_WALLET) revert PerWalletCap();
    mintedBy[msg.sender] += quantity;
```

(or accept the behaviour and drop the "anti-whale" claim at `:119`, which is the
honest alternative — a determined buyer can always use separate wallets).

---

### Z-13 — LOW — `_castSpell` mutates `activeShares` after two external calls, with no reentrancy guard

**Tag:** VERIFIED (mechanism and consequence, by PoC); requires a re-entering
registry or a callback-capable `currentToken`, both protocol-controlled
**Location:** `cauldron/MiFrensDividend.sol:390-397` and `:445-458`
**PoC:** `test/attacks/T9b_DividendConservation.t.sol`
(`test_F_CastSpellReentrancyDoubleCountsActiveShares`)

```solidity
        _collectEnchantFee(tokenId);
        activeShares += 1;
...
    if (!IERC20(tok).transferFrom(msg.sender, address(this), fee)) revert EnchantFeeUnpaid();
    reg.donateToReserve(fee);
```

`castSpell` carries no `nonReentrant`, and `_collectEnchantFee` makes two external
calls (an ERC20 pull and `registry.donateToReserve`) **before** `activeShares`
is incremented and before `enchantedBy` is written. A re-entrant path that reaches
the owner's code lets one token be counted as two shares. Only one decrement exists
(`:493`), so the phantom share persists forever, every later deposit is divided by
an inflated divisor, and the excess is stranded (ETH in `residual`; tokens lost
outright). Reported as defence-in-depth.

**Fix** — `nonReentrant` on `castSpell`/`castMany`, and CEI ordering:

```solidity
        //  STATE BEFORE CALLS. `_collectEnchantFee` reaches the registry and an
        //  ERC20; re-entering before `enchantedBy` is written double-counts one
        //  fren as two shares, and only one decrement exists (:493).
        enchantedBy[tokenId] = msg.sender;
        activeShares += 1;
        _collectEnchantFee(tokenId);
```

---

### Z-14 — LOW — `RoyaltyRouter.receive()` needs ~30k gas, so stipend-based royalty payers cannot pay it

**Tag:** VERIFIED
**Location:** `cauldron/RoyaltyRouter.sol:45`, against its own comment at `:28-29`
**PoC:** `test/attacks/Z9_ScopeProbe.t.sol` (`test_Z9b…`)

```solidity
if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
```

The forward `SSTORE`s `legacyBufferAsset` and `legacyBuffer`
(`CauldronHook.sol:1177-1178`), so it costs roughly 30k gas. A marketplace or
splitter paying EIP-2981 with `.transfer` (2300-gas stipend) reverts the whole
sale; one paying with `.send` gets `false` and silently skips the royalty. The
contract's own comment at `:28-29` asserts "It is moot now: the forward cannot
fail."

No ETH is stranded (the router's balance stays 0 either way).

**Fix** — accrue on receive and forward in a separate permissionless call, so a
stipend payment succeeds:

```solidity
    //  A STIPEND CANNOT AFFORD THE FORWARD. `fundLegacyBuffer` SSTOREs twice
    //  (~30k), so a `.transfer`-paying marketplace reverts the sale and a
    //  `.send`-paying one drops the royalty. Accrue here; forward separately.
    receive() external payable {}

    function flush() external returns (uint256 amt) {
        amt = address(this).balance;
        if (amt == 0) return 0;
        ILegacyBuffer(hook).fundLegacyBuffer{value: amt}();
    }
```

---

### Z-15 — LOW — `CauldronFactory.transferOwnership` has no zero-check, two-step, or event

**Tag:** VERIFIED
**Location:** `cauldron/CauldronFactory.sol:42-45`

```solidity
function transferOwnership(address to) external {
    if (msg.sender != owner) revert NotOwner();
    owner = to;
}
```

`transferOwnership(address(0))` permanently freezes `setLiquidatorRenderer` — the
one privilege the factory holds — so every *future* generation's collection loses
on-chain badge metadata. That is precisely the failure mode the comment at `:26-31`
says this contract exists to prevent. It is Low rather than Medium only because
`CauldronCollection.setLiquidatorRenderer:373` also accepts `deployer`, so the
registry can recover the right.

Noted alongside: `deployBrew` (`:63`) and `deployVault` (`:99`) are fully
permissionless. This could not be weaponised — nothing in the tree predicts a
factory `CREATE` address (only the token path uses `CREATE2`,
`CauldronRegistry.sol:1627`) and the collection's `deployer` is the caller-supplied
registry, which never enumerates collections — but gating `deployBrew` to the
registry would remove the question entirely.

**Fix:** zero-check, emit an event, and consider a two-step accept.

---

### Z-16 — INFO — `MiFrensDividend`'s token path has no `residual`, so per-deposit truncation is unrecoverable

**Tag:** VERIFIED
**Location:** `cauldron/MiFrensDividend.sol:287` against the ETH path at `:245-247`

The ETH path carries division truncation forward in `residual`. The token path has
no equivalent, so up to `activeShares - 1` raw units per deposit are permanently
unallocated with no sweep. Measured: 3 units of USDG across 4 deposits. Negligible
per deposit; noted only because, as with `totalEntitled` in Z-06, there is no exit.

---

## Findings — Part III (the progressive seeder)

### Z-17 — CRITICAL — `poke()` is permissionless and the treasury's prime buy has no slippage bound, so a stranger sets the price the protocol trades at

**Tag:** VERIFIED (gate and swap parameters read independently and confirmed;
exploit measured against a locally deployed real v4 `PoolManager`)
**Location:** `cauldron/CauldronSeeder.sol:231` (`poke()`), `:286-295`
(`_primeStep`), `:368` and `:376-378` (`_placeStep`), `:307` (`pokeInSwap`)
**PoC:** `test/attacks/T9b_SeederPokeSandwich.t.sol`

#### The code

The entry point has no authority gate at all:

```solidity
// CauldronSeeder.sol:227-241
/// @notice PERMISSIONLESS standalone nudge (self-`unlock`). No-op when complete,
///         throttled, or not seeding. Cannot be accelerated/over-deployed (the
///         target is a pure function of elapsed time).
function poke() external lock {
    uint256 step = _pendingStep();
    if (step > 0) {
        poolManager.unlock(abi.encode(ACT_PLACE, step));
        _advance(step);
    }
    ...
    uint256 want = primePending();
    if (want > 0) poolManager.unlock(abi.encode(ACT_PRIME, want));
}
```

The prime buy it drives is an unbounded market order:

```solidity
// CauldronSeeder.sol:286-295
BalanceDelta d = poolManager.swap(
    _key,
    SwapParams({
        zeroForOne: true,
        amountSpecified: -int256(ethIn),
        sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    }),
    abi.encode(address(this))
);
uint256 owed = uint256(uint128(-d.amount0()));
uint256 got = uint256(uint128(d.amount1()));
poolManager.settle{value: owed}();
if (got > 0) poolManager.take(_key.currency1, primeTo, got);
```

`TickMath.MIN_SQRT_PRICE + 1` is the *absolute* limit — it can never bind. `got`
is taken and forwarded without a single check. And the liquidity placement is
anchored to whatever spot happens to be:

```solidity
// CauldronSeeder.sol:368-378
(, int24 tick,,) = poolManager.getSlot0(_key.toId());
...
// ASK: token band just below current tick (pure token1).
(int24 aLo, int24 aHi) = SeedLib.askBand(0, 1, tick, _spacing, _bandWidth);
// BID: ETH band just above current tick (pure token0).
(int24 bLo, int24 bHi) = SeedLib.bidBand(0, 1, tick, _spacing, _bandWidth);
```

#### Description

The comment at `:227-229` is the trap. Its claim — "Cannot be
accelerated/over-deployed (the target is a pure function of elapsed time)" — is
**true and irrelevant**. It defends the *schedule*: no attacker can make the
seeder deploy more than the elapsed-time target. It says nothing about the
*price*, and price is what the permissionless caller actually controls.

Both of the seeder's actions read live spot and neither bounds it:

1. `_placeStep` places the pending ledger-A step as an ask band just *below* and a
   bid band just *above* the tick returned by `getSlot0`. An attacker who has just
   pushed the tick receives the protocol's liquidity donated right next to their
   own position.
2. `_primeStep` spends the treasury's prime budget as a market buy with the
   limit pinned to the end of the tick range and no `minAmountOut`. At a pushed
   price, that budget buys almost nothing.

So the attacker does not need to beat a keeper to a transaction — **they call the
function themselves**, in the middle of their own sandwich, atomically.

`pokeInSwap` (`:307`) makes it strictly worse: the hook invokes the placement from
*inside* the attacker's own push swap, so there is not even a block boundary to
work with.

#### Impact

Direct, attacker-profitable theft of protocol funds — not griefing. Measured with
a real v4 `PoolManager` and the **production** seed parameters (`bandWidth 2000`,
`minStep 0.02e18`, `floor 0.1e18`, matching `PoolOps.sol:137-145`), ledger A =
10 ETH / 100M tokens, prime budget = 5 ETH:

```
treasury tokens, honest  : 46,122,162.16
treasury tokens, attacked:         68,793.99      (−99.85%)
attacker net             : +12,157,455,696,195,385,360 wei  (= +12.157 ETH)
```

The treasury's 5 ETH buys 0.15% of what it should, and the remaining un-streamed
ledger-A ETH is extracted along with it. Attacker capital is ~40 ETH held for one
block — flash-loanable — and the profit figure above is already net of it and of
swap fees.

In production the only additional cost is the 3% base tax: the 9,600 bps
anti-sniper surtax expires after `snipeWindowBlocks = 30`
(`CauldronHook.sol:507-513`), which is far inside a launch window, so the attack
sits in the long unprotected tail of every progressive launch.

#### Exploit sequence

One transaction, one EOA:

1. Swap ETH→token to push spot far from its honest level.
2. Call `seeder.poke()`. The seeder places the pending ledger-A step as bands
   adjacent to *the attacker's* tick, then spends the prime budget buying at that
   tick with no slippage guard.
3. Swap back through the liquidity the protocol just donated.

Repeat once per throttle interval for the remainder of the launch window.

#### Concrete fix

Both halves need bounding; neither alone is sufficient.

**(a) Bound the prime buy.** It is a treasury market order and must carry the
protections any market order carries:

```solidity
    /// @dev Max deviation between live spot and the TWAP before the seeder refuses
    ///      to trade or place. `poke()` is PERMISSIONLESS, so the caller chooses the
    ///      block — every price this contract reads has to be treated as hostile.
    uint256 internal constant MAX_SPOT_DEV_BPS = 200; // 2%

    function _primeStep(uint256 ethIn) private {
        uint160 twap = _twapSqrtPrice();            // from the hook's existing oracle ring
        uint160 limit = uint160((uint256(twap) * (10_000 - MAX_SPOT_DEV_BPS)) / 10_000);
        BalanceDelta d = poolManager.swap(
            _key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(ethIn),
                sqrtPriceLimitX96: limit          // was MIN_SQRT_PRICE + 1: unbounded
            }),
            abi.encode(address(this))
        );
        uint256 owed = uint256(uint128(-d.amount0()));
        uint256 got = uint256(uint128(d.amount1()));
        //  MINOUT. Without it a pushed spot lets a sandwicher hand the treasury
        //  0.15% of the tokens its budget should buy (measured).
        require(got >= _minOutAtTwap(owed, twap), "prime slippage");
        poolManager.settle{value: owed}();
        if (got > 0) poolManager.take(_key.currency1, primeTo, got);
        primeSpent += owed;
    }
```

**(b) Refuse to place liquidity at a manipulated tick.** Anchor the bands to a
price the caller cannot choose:

```solidity
    function _placeStep(uint256 stepWad) private {
        ...
        (, int24 tick,,) = poolManager.getSlot0(_key.toId());
        //  DO NOT PLACE AT A TICK THE CALLER CHOSE. `poke()` is permissionless, so a
        //  sandwicher can move spot, have us donate both bands next to their own
        //  position, and sell back through them in the same tx.
        int24 ref = _twapTick();
        int24 dev = tick > ref ? tick - ref : ref - tick;
        if (dev > MAX_TICK_DEV) return;   // skip this step; the schedule is time-based
        ...
```

Returning (rather than reverting) is deliberate and consistent with this
contract's existing style: the deployment target is a pure function of elapsed
time, so a skipped step is caught up by the next honest poke and nothing strands.

**(c) Interim, deployable without a redeploy:** the surtax/exempt configuration
does not help here, but the attack requires a *progressive* generation. Until (a)
and (b) ship, launch atomically — do not arm the seeder — or fund
`primeBudget` to zero so `primePending()` is always 0 and only the (much smaller)
placement half remains exploitable.

---

### Z-18 — HIGH — The range cap plus ordinary upward price action permanently halts the stream

**Tag:** VERIFIED
**Location:** `cauldron/CauldronSeeder.sol:544-551` (the `MAX_RANGES` fallback),
`:388-392` (ask sizing), orientation documented at `SeedLib.sol:21-27`
**PoC:** `test/attacks/T9c_SeederRangeCapMisSide.t.sol`

At `MAX_RANGES` the seeder falls back to reusing `_lastAsk`, which records the
side the band was on **when it was tracked**, not when it is reused. Because a
token that appreciates makes the tick *fall* (`SeedLib.sol:21-27`), success drives
spot below every tracked ask band. The ask amount is still sized with
`getLiquidityForAmount1` (`:388-392`), so the pool settles it in **ETH the seeder
does not hold**, and `settle{value:}` fails.

Measured: 59 pokes of plain 200-tick drift fill `ranges` to exactly 64; the next
`poke()` reverts with empty revert data (out of funds), `placedWad` freezes at
`0.74275e18`, and 2.30 ETH plus the matching tokens never reach the pool.
`pokeInSwap` is swallowed by the hook (`CauldronHook.sol:1088`), so the stream
dies **silently** — no event, no revert anyone sees.

Attacker cost is **zero**: this is what ordinary upward price action does. A
griefer who wants it sooner can force it inside one window by tick-shopping ~32
slots. Recovery requires the token price to fall back, which is the opposite of
what a successful launch does.

**Fix** — validate the reused band against the *current* tick rather than trusting
the recorded side, and skip instead of stranding:

```solidity
    //  A TRACKED BAND'S SIDE IS NOT STABLE. `_lastAsk` records the side it was on
    //  when tracked; appreciation moves spot BELOW every tracked ask (SeedLib:21-27),
    //  and sizing it with getLiquidityForAmount1 then asks the pool for ETH we do
    //  not hold -> settle fails and the stream halts for good.
    if (aHi >= tick) return (0, 0);   // mis-sided: skip this step
```

or evict the furthest range instead of capping, so a live band is always available.

---

### Z-19 — MEDIUM — A fully-retired generation traps every later credit, and its treasury NFTs can never be bought back

**Tag:** VERIFIED
**Location:** `CollectionLedger.sol:86-90`, `:94-98`, `:106-111`, `:117-125`;
`PoolOps.sol:1455-1456`
**PoC:** `test/attacks/T9d_LedgerFullyRetiredTraps.t.sol`

Once every NFT of a generation has been recycled, `outstanding == 0`, so
`floorPerNFT == 0`, so `PoolOps.buyCollection`'s `require(paid > 0, "no floor")`
(`:1456`) can never pass again and `redeem` reverts `NothingOutstanding`. But
`credit` still raises `entitledTokens[gen]` and `totalEntitled`
**unconditionally** (`CollectionLedger.sol:105-111`).

PoC: a 3-NFT generation fully redeemed, then 500e18 credited — permanently
unclaimable, while the registry must keep the shared reserve sized to cover it
(Invariant R), and `CauldronRegistry.sol:1057` subtracts it from every future
generation's `newActive`. The comment at `PoolOps.sol:1415-1417` already
acknowledges that the only decrementer can never run in this state.

**Fix** — make `credit` refuse to accrue into a dead-end bucket, and price the
buyback off the pot rather than the per-NFT floor when the floor is zero:

```solidity
    // CollectionLedger.credit
    //  A FULLY-RETIRED GENERATION IS A DEAD END: outstanding == 0 makes redeem
    //  revert and buyCollection's `paid > 0` unsatisfiable, so anything credited
    //  here is unclaimable AND still sizes the shared reserve.
    function credit(uint256 gen, uint256 tokens) external onlyRegistry {
        if (tokens == 0) revert ZeroAmount();
        if (crystallized[gen] && frozenSupply[gen] <= retired[gen]) revert NothingOutstanding();
        ...
```

with the registry routing a rejected credit to the live generation instead.

---

### Z-20 — MEDIUM — `fundPrime` lets the seeder's deployer EOA redirect an already-funded prime budget

**Tag:** DERIVED (authority read in code; not executed)
**Location:** `cauldron/CauldronSeeder.sol:251-257`

```solidity
function fundPrime(address to) external payable {
    if (msg.sender != deployer && msg.sender != IRegistryOwner(registry).owner()) revert OnlyRegistry();
    if (to == address(0)) revert BadConfig();
    primeTo = to;
    primeBudget += msg.value;
```

`primeTo` is rewritten on **every** call, including a zero-value one, and
`deployer` is a plain EOA with no timelock and no renounce path. So after the
prime budget has been funded — by anyone, as a gift to the campaign — the deploy
EOA can call `fundPrime{value: 0}(attacker)` and redirect the entire token output
of that budget to itself. The NatSpec justifies the gate ("`primeTo` decides where
bought tokens land") without noticing that it is re-settable after funding.

**Fix** — separate the two concerns: let anyone add value, and make the recipient
set-once (or timelocked):

```solidity
    function fundPrime(address to) external payable {
        if (msg.sender != deployer && msg.sender != IRegistryOwner(registry).owner()) revert OnlyRegistry();
        if (to == address(0)) revert BadConfig();
        //  SET-ONCE. Re-setting `primeTo` after the budget is funded redirects value
        //  that is already committed, and `deployer` is an un-timelocked EOA.
        if (primeTo != address(0) && primeTo != to) revert BadConfig();
        primeTo = to;
        primeBudget += msg.value;
```

---

## Attacked and Found Clean

These are results, not omissions. Each was pursued to the point where a bug
would have shown.

### 1. The `public`/`external` library entrypoints — CLEAN, and the reason is verified, not assumed

`PoolOps` is a **linked external library**: every `public` and `external`
function is a real entrypoint on the deployed library address, callable by
anyone, with `address(this) == the library` rather than the registry. That is the
single most promising attack surface in this file, so all thirteen were
enumerated and each traced to the gate that stops it:

| Entry | Line | Why a direct call at the library address is inert |
|---|---|---|
| `claimFromReserve` (public) | 1179 | `DECREASE_LIQUIDITY` is `onlyIfApproved` in the v4 PositionManager; the library owns no position |
| `addToReserve` (public) | 1218 | `SETTLE_PAIR` must be paid from `address(this)` = the library, which holds nothing |
| `migrateOne` (public) | 1274 | `CauldronToken.burn` is `onlyRegistry` — **verified at `CauldronToken.sol:50,58`** |
| `doLegacyNote` (public) | 1325 | `CollectionLedger.credit` is `onlyRegistry` — **verified at `CollectionLedger.sol:78-81,105`** |
| `crystallizeCollection` | 1374 | `CollectionLedger.crystallize` is `onlyRegistry` (`:145-148`) |
| `recycleCollection` | 1395 | `CollectionLedger.redeem` is `onlyRegistry` (`:112`) |
| `buyCollection` | 1443 | `ownerOf(tokenId) != address(this)` → the library owns no NFT (`:1453`) |
| `materializeLegacy` | 1349 | hook's `sweepLegacyReserve` is registry-gated; `credit` is too |
| `removeAll` / `removePartial` | 1140 / 905 | position-manager ownership check |
| `seedFunding` | 1000 | both hook releases are registry-gated and both are `try/catch`'d, so it returns zeros |
| `executeBuy` | 498 | takes its `IPoolManager` from `msg.sender`, so a direct caller only drives its own contract |
| `sendAsset` | 1109 | spends `address(this)` = the library's zero balance |
| `deployTokenAbove` / `creatureFor` | 682 / 153 | deploys a token whose `registry` is the library; controls nothing |

`CollectionLedger` was read in full to confirm `onlyRegistry` sits on **all four**
mutators (`credit`, `redeem`, `buyback`, `crystallize`) and that `registry` is
`immutable` (`CollectionLedger.sol:38`). `CauldronToken` was read to confirm
`burn` is the only supply-changing function and it is `onlyRegistry`. This whole
surface is correctly defended, and the defence is structural rather than
incidental.

### 2. Reentrancy across the V4 unlock callback and the ERC721 receiver — CLEAN

- The registry's `unlockCallback` is doubly gated: `msg.sender` must be the
  PoolManager *and* `_seedBuyUnlocked` must be armed
  (`CauldronRegistry.sol:1764-1766`), and the flag is armed and cleared around
  each use (`:755-757`, `:1727-1740`).
- Both NFT-moving paths use `custodyTransfer`, which calls `_transfer`, **not**
  `_safeTransfer` — so no `onERC721Received` callback reaches an attacker
  (`CauldronCollection.sol:394-397`). This was checked specifically because
  `buyCollection` moves the NFT *last* (`PoolOps.sol:1460`), which would
  otherwise be a textbook reentrancy window.
- Both registry entries are `nonReentrant` (`CauldronRegistry.sol:1514-1515`,
  `:1535-1536`).
- `recycleCollection` follows checks-effects-interactions: ledger debit
  (`:1432`) precedes both the NFT move and the payout.

### 3. `autoMigrateBatch` — the only unbounded loop — CLEAN

`PoolOps.sol:1298-1314`. The `holders` array is caller-supplied and unbounded,
so it was checked against every failure mode:

- **Gas DoS:** the caller pays; no storage grows; nothing is appended by a
  stranger. The loop bound is the caller's own calldata.
- **Duplicate entries:** a repeated holder migrates once — the second pass reads
  `bal == 0` and `continue`s (`:1306`), because `migrateOne` burned the balance.
- **Grief via an uncoverable holder:** already fixed and correctly so. `cap` is
  re-read *inside* the loop (`:1308-1310`, "every migration drains the reserve")
  and `bal > cap` skips rather than reverts (`:1311`), so one oversized opted-in
  wallet can no longer kill the batch.
- **Forced migration:** only holders who set `autoMigrate` are touched
  (`:1304`), the flag is read per holder per call, and the vesting gate blocks
  the whole entry (`CauldronRegistry.sol:1352`).

### 4. `ReserveLib`'s rounding directions — CLEAN

`liquidityForTokenOut` (`ReserveLib.sol:88-98`) and its inverse
`tokenOutForLiquidity` (`:108-119`) **both round down**, so every round trip is a
conservative lower bound and no caller can round a claim upward in their favour.
`reserveTicks` aligns the floor *up* from `MIN_TICK` to avoid `InvalidTick`
(`:58-61`) and collapses to a one-spacing band rather than reverting when the
ceiling underflows past the floor (`:64-66`). `CLAIM_DUST = 1e12`
(`PoolOps.sol:1253`) is denominated in the brew token, which is always 18
decimals (`CauldronToken.sol:29`) — it is **not** quote-denominated, so unlike
Z-01 it does not misbehave under a 6-decimal quote. This was the first thing
checked after Z-01 surfaced.

### 5. The reserve-band breach at ~69× — ALREADY FOUND, not re-reported

The reserve-side operations all assume the band is strictly out of range and pure
`currency1`; once spot trades into it, `claimFromReserve` under-delivers and
`TAKE_PAIR` at `PoolOps.sol:1195` would additionally hand `currency0` to the
claimant. This was independently reached in this pass and then found to be
**already covered** by `test/attacks/Y01_ReserveCeilingBreach.t.sol` (and the
short-delivery half by `test/audit/AuditPoC2.t.sol`), so it is reported here only
as a confirmation, not as a new finding.

### 6. `deployTokenAbove` and the watermark invariant — CLEAN

`PoolOps.sol:682-719`. Plain-`CREATE` fallback cannot be front-run; the mined
`CREATE2` path asserts `token == predicted && token > floor` rather than trusting
the arithmetic (`:710`); the `SALT_TRIES` loop is bounded at 1024 and cannot
revert the relaunch (`:718` degrades to an unmined token against ETH). The
probability of 1024 consecutive misses against the `0xf000…` watermark
(93.75% of the address space) is `0.0625^1024` — not a reachable branch.

### 7. `executeBuy`'s settlement and delta casts — CLEAN

`PoolOps.sol:498-570`. The ERC20 settle path checks the transfer return value
(`:563-565`), which is correct and was the right call. The two casts were checked
for sign errors: on a `zeroForOne` swap the registry always *owes* `currency0`
and is *owed* `currency1`, so `-delta.amount0()` and `delta.amount1()` are both
non-negative and the `uint128` casts cannot wrap (`:519-520`). The
`sqrtPriceLimitX96 = MIN_SQRT_LIMIT` direction is correct for `zeroForOne`
(`:165`, `:514`).

### 8. Ledger accounting conservation — CLEAN

`totalEntitled == Σ entitledTokens[gen]` is preserved exactly by all four
mutators (`CollectionLedger.sol:105-161`); `retired[gen]` cannot exceed supply
because every increment requires a live NFT owned by the caller; the
`redeem`-then-`redeem` sequence pays each holder the same share
(`E/n`, then `(E − E/n)/(n−1) = E/n`), so there is no
last-holder-takes-all or first-holder-takes-all skew. The OG-tranche guard on
`recycleCollection` (`PoolOps.sol:1424-1429`) correctly self-configures via the
`GENESIS_SUPPLY()` staticcall and is inert for a plain brew collection.

### 9. Denomination survival of PoolOps' stored amounts — one bug, the rest CLEAN

Every constant and threshold in the file was re-read in both 6- and 18-decimal
terms. `BUY_SETTLE_BUFFER = 64` (`:625`) is correctly decimal-agnostic dust.
`MAX_ROTATION_BPS` (`:941`) and `SEED_*_WAD` (`:137-145`) are ratios. `CLAIM_DUST`
is token-side (see §4). The reserve tick math is price-space, not amount-space.
The **only** amount-space, quote-denominated threshold in the file that is wrong
in 6 decimals is the implicit one inside `_sqrtPrice` — which is Z-01.

### 10. Dividend basket conservation — CLEAN, and tested hard

`MiFrensDividend` was attacked for double-claim, late-joiner back-pay, and
denomination drift, with 6-decimal and 18-decimal assets interleaved across
transfers, casts, re-casts and repeated claims
(`test/attacks/T9b_DividendConservation.t.sol`,
`test_R1_BasketConservesAcrossTransfersAndDecimals`,
`test_R2_EthConservesAcrossTransfers`). Payout never exceeds funding; a second
claim pays zero; a late joiner draws no history. The property that closes it is
that the `debtOfAsset` marker is set on **both** branches of `_castSpell`
(`:435`, outside the `cur != 0` guard) — had it been inside, a re-cast would have
back-paid history.

`unchecked { activeShares -= 1 }` (`:493`) was checked for underflow: the
invariant `activeShares == #{id : enchantedBy[id] != 0}` holds because the
increment fires only on the `cur == address(0)` branch (`:397`), the decrement
only where `enchantedBy` is zeroed in the same call (`:493-494`), and the stale
branch (`:398-402`) touches neither.

Claim-for-someone-else was specifically hunted and does not exist: `_claim`
(`:530-541`) and `claimTokens` (`:307-309`) each require **both**
`ownerOf == msg.sender` and `enchantedBy == msg.sender`, and pay `msg.sender`
only. There is no `to` parameter anywhere in the contract.

### 11. `MAX_ASSETS` basket junk-fill / claim lockout — REFUTED

The hypothesis was that a stranger could fill the asset list and make the claim
loop unusable. `funder` is the hook
(`deploy/DeployLaunchpad.s.sol:348`), and the asset is the hook's `_feeAsset`,
adopted only in `_afterInitialize` behind the registry gate
(`CauldronHook.sol:1292`, `:2026`) — a stranger cannot choose what the loop walks.
A 4th quote makes `fundToken` revert `NotShare` (`:282`), and
`FeeRouteLib._fundGuild` (`:128-152`) swallows that and buffers the share to the
relaunch reserve. So: no brick and no loss, only a permanent forfeit of that
quote's guild share.

### 12. `CauldronVault.outstanding()` desync — REFUTED

A burn path that shrinks `totalMinted` while `redeemed` stays flat would inflate
`floorPerNFT` and let early redeemers drain the pool. There is none:
`CauldronCollection.burnFromVault:384-387` and `MiFrensGenesis.burnFromVault:545-548`
both call `_burn` only; `CauldronCollection.totalMinted` is written solely at
`:210` (`++totalMinted`) and `MiFrensGenesis.minted` solely at `:282`/`:478`; the
OG recycle path uses `custodyTransfer:394`, which is `_transfer` and never burns.
The `floorOffset` tranche split is enforced on **both** exits
(`CauldronVault.sol:96` and `PoolOps.recycleCollection:1427-1430`).

### 13. The `reserveTicks` degenerate-safety branch — unreachable, noted not reported

`ReserveLib.sol:63-65` collapses to a one-spacing band at the floor, which would
make `sqrtHi - sqrtLo` tiny and overflow the `uint128` cast in
`liquidityForTokenOut`. It needs `launchTick ≤ -844800`, and the launch tick comes
from `_sqrtPrice(totalTokens, ethActive)` over a fixed `TOTAL_SUPPLY`
(`PoolOps._greenCandle:466`), which is strongly positive. Recorded as a note so a
future change to the launch-price model does not walk into it.

### 14. `royaltyBps` overflow bricking every summon — REFUTED

If `royaltyBps` could exceed `setRoyalty`'s `bps <= 1000`, `deployBrew` would
revert and every summon would brick. `CauldronRegistry.setRoyalty:602` already
enforces `_bps > 1000 → TooHigh`, and the default is `500`
(`CauldronBase.sol:250`). Held.

### 15. `LaunchSniper` — CLEAN

`launch`/`sweep` are `onlyOwner`, `renounceOwnership` is sealed (`:120`),
`receive()` is open but `sweep` is a live exit so nothing strands. The unchecked
`IERC20.transfer` at `:96`/`:107` only ever touches the protocol's own token.

### 16. `CauldronSeeder.withdrawAll` / `rescue` — the registry side IS gated — CLEAN

The brief asked specifically whether the `onlyRegistry` on these is real or
whether the registry side is open. It is real, and tightly so.
`CauldronSeeder.sol:565` and `:597` are `onlyRegistry`; every registry-side
caller is `onlyEmergency timelocked nonReentrant` —
`CauldronRegistry.sol:339` (`rescueSeeder`), `:540` (`migrateToSuccessor`),
`:476` (`emergencyWithdrawLP`) — plus the internal relaunch path at `:858`.
There is no permissionless reach to either.

### 17. Seeder over-deploy / stream acceleration — REFUTED

This was attacked directly (repeated pokes within a block, and pokes straddling
the throttle boundary, trying to make `placedWad` outrun the schedule).
`_pendingStep` (`:316-323`) and `_advance` (`:327-335`) both snap to the same pure
`deployedTargetWad`, so the sum of all steps is bounded by `1e18` regardless of how
often or when `poke()` is called. The comment's acceleration claim holds — it is
only the *price* claim it does not make, which is Z-17.

### 18. Seeder unlock-callback reentrancy — CLEAN

`unlockCallback` (`:341`) is `poolManager`-only; `poke`, `pokeInSwap`, `startSeed`,
`withdrawAll` and `rescue` all carry `lock`. The hook's in-swap nudge is a
result-ignored low-level `.call` (`CauldronHook.sol:1088`), so a `Reentrancy()`
revert raised during a prime swap cannot bubble up and break the swap.

### 19. Seeder denomination (6 vs 18 decimals, live quote change) — CLEAN IN SCOPE, by construction

The seeder is native-only and structurally so: `PoolOps.sol:296-311` degrades a
non-native quote to the atomic path **before** `startSeed` is ever reached, and
`_settle` (`:488-503`) hard-codes `settle{value:}` on currency0. No ERC20-quote
value can reach these files, so there is no 6-decimal exposure to get wrong.
`CollectionLedger` is denominated in the brew token (`CauldronToken`, fixed 18
decimals), not the quote. Note this is the *opposite* posture from `PoolOps`,
where the same degrade path is exactly what makes Z-01 reachable — worth keeping
in mind when Z-01 is fixed, because widening the seeder to ERC20 quotes later
would open this surface.

### 20. Collection mint authority, supply cap and id collision — CLEAN

`mint` is `minter`-only and guarded by `totalMinted >= maxSupply`
(`CauldronCollection.sol:208-210`); the constructor forbids
`maxSupply >= LIQUIDATOR_ID_BASE` (`:148`), so volume ids can never collide with
the Liquidatoor badge range. `mint` uses `_mint`, not `_safeMint` (`:213`), so
there is no receiver callback on the mint path either.

---

## Open Leads (HYPOTHESIS — not findings; each carries the next step)

These are unresolved at the time of writing. They are recorded because each is
cheap to settle and one of them (L1) would be a brick if it lands.

- **L1 — could `castSpell` be permanently unusable for a whole generation?**
  `MiFrensDividend._collectEnchantFee:457` calls
  `RedemptionExt.donateToReserve` → `_pullGrow`, which reverts `NoBalance` when
  `added == 0` (`RedemptionExt.sol:181`) — a state its own comment attributes to
  `generationReservePositionId[g] == 0`. If a generation can hold
  `genesisReserveOutstanding > 0` (so `enchantFee() != 0`) while its reserve
  position id is 0, then every forged fren and every moved OG is permanently
  unable to `castSpell`, bricking the whole pay-to-earn tranche. **Next step:**
  from `CauldronRegistry.sol:1019` forward, determine whether relaunch can leave
  `generationReservePositionId[newGen] == 0` with `genesisReserveOutstanding > 0`.
  Note `PoolOps._seedReserve:793` returns 0 by design when the tranche is dust,
  which makes this look reachable.
- **L2 — `MiFrensGenesis.setDividend:343`** is `onlyDeployerOrRegistry` and
  re-settable, including to `address(0)`. Re-pointing it strands the entire live
  basket: every enchanted fren stays in `activeShares` forever and sellers keep
  collecting buyers' accrual. No caller outside deploy and tests. **Next step:**
  confirm no relaunch/continuation path calls it, then make it one-time and
  zero-rejecting.
- **L3 — `CauldronHook.setPolicies:1942`** overwrites all three module slots
  unconditionally, so changing one silently reverts the other two to built-in.
  **Next step:** audit every ops runbook / timelock payload that calls it with
  fewer than three live addresses.
- **L4 — `quoteOracle` can be set but never unset** (`CauldronHook.sol:1828-1829`
  only assigns inside `if (_oracle != address(0))`). **Next step:** confirm a
  permanently-reverting oracle can be repointed rather than only removed.
- **L5 — `GAS_DIVIDEND_MIN = 320_000`** (`MiFrensDividend.sol:111`) is enforced on
  every non-mint move of every id once `dividend != 0`, including badges,
  un-enchanted frens, `custodyTransfer` (`:414`) and `burnFromVault` (`:545`).
  **Next step:** measure whether a floor-redemption path that has already burned
  >70% of a block's gas can still clear 320k at `_update`.

---

## Redeploy Verdict

**Yes. Z-17 is a Critical that is live-exploitable for profit on any progressive
generation and must be fixed before the next progressive launch; Z-01 must be
fixed before any non-native rebirth. Neither should wait.**

### Z-17 first — it is the only finding here that pays an attacker

Z-17 is a different category from everything else in this report: it is not a
brick, not a griefing amplifier and not a fairness problem. It is **theft with a
measured profit** (+12.157 ETH in the PoC, from ~40 ETH of flash-loanable
one-block capital), reachable by any EOA, in one transaction, with no privilege
and no unusual state. It needs only that a generation was launched
*progressively* and that the 30-block surtax window has passed.

It is the one finding with a genuine operational mitigation that does **not**
require a redeploy, and that mitigation should be applied immediately:

- **Do not arm the seeder — launch atomically** until the fix ships. The atomic
  path (`createAndSeedWithBuy`) has no permissionless price-setting entry.
- If a progressive launch is already live, **drive `primeBudget` to zero** so
  `primePending()` returns 0. That removes the larger half of the loss (the
  unbounded treasury market buy); the placement half (Z-17b) remains exploitable
  but is bounded by the per-step size.

Note the interaction with Z-18: the same subsystem also halts permanently under
ordinary upward price action, so the progressive path is currently both
*exploitable* and *unreliable*. If the choice is between shipping a fix and
disabling the feature for a round, disabling it is defensible.

### Then Z-01 — the permanent brick

The reasoning, stated so the deploy decision can be made without re-reading the
findings:

- **Z-01 is reachable on round 40 as configured.** It needs a 6-decimal quote to
  be allowlisted, and `DeployLaunchpad.s.sol:625,668` deploys USDG with
  `decimals() == 6` and allowlists it. This is not a hypothetical future
  configuration.
- **Its consequence is the one outcome the architecture is explicitly built to
  prevent** — a revert on the right-hand side of `markConsumed`, which the
  registry's own comment block (`CauldronRegistry.sol:988-993`) identifies as
  "what must never happen". It is unrecoverable by any owner, keeper or timelock
  action, because the failing input is derived from protocol state and will be
  re-derived identically on every retry.
- **It cannot be mitigated operationally with confidence.** The obvious
  stopgap — `setAllowedQuote(usdg, false, …)` — removes the reachable path *for
  new proposals*, and is worth doing immediately as a holding action. But it does
  not help a generation that is *already* USDG-quoted, whose `oldQuote` feeds
  `seedFunding` branch 3 regardless of the allowlist, and it forfeits the
  multi-quote feature that the last several rounds of work existed to deliver.
- **The fix touches `PoolOps`, a linked library**, whose address is baked into the
  registry's bytecode. There is no way to patch it in place: `PoolOps` and
  `CauldronRegistry` both redeploy together. Since a registry redeploy is
  unavoidable, the recommended registry-side guard (the denomination-aware
  `NoLiquidityToSeed` bound) costs nothing extra and should ship in the same
  round — it moves the failure to the safe, recoverable side of `markConsumed`,
  which is strictly better than relying on the clamp alone.

**Z-02 can ride the same redeploy but should not be deferred past it.** It is not
reachable *today* in the sense that it needs a generation death to land, but its
effect is permanent and global once it does, and the fix is two small edits
(`PoolOps.crystallizeCollection` and `CauldronVault.receive`). Given that Z-01
already forces the round, there is no reason to leave it.

**Z-08 must ship in the same round, and it is the finding most likely to be
noticed by users first.** The reveal grind needs no privilege, no capital and no
unusual state — any holder of any unrevealed token can do it, on every
generation, and `CauldronCollection` is redeployed per brew so the bug ships
again with each one. It cannot be mitigated operationally at all: there is no
pause, no setter and no owner action that changes `_reveal`. If the round is being
cut for Z-01 anyway, this is the second thing in it. Note it also means any
rarity data already revealed on round 40 should be treated as untrustworthy.

**Z-09 should ship in the same round.** The `nftSupply` lower bound is a one-line
change in `CauldronGovernor`, and the alternative is relying on voters to reject a
malformed proposal. There *is* a partial operational mitigation — leaving
`curvePolicy` unwired (`setPolicies` with a zero curve) restores the hook's own
`setNftCurveFrom` ladder, which does scale per generation — and that is worth
doing as a holding action if the redeploy slips.

**Z-10 and Z-11 should ship in the same round but are not the reason for it.**
Z-10 is losing real money today at a slow rate (5% of any non-native secondary
sale) and the fix is additive. Z-11 is inert until someone calls `setFeeRouter`;
the zero-cost interim action is simply **do not call `setFeeRouter` with
`DefaultFeeRouter`**, and the cheapest permanent fix is to delete the contract,
which has no callers and is in no deploy script.

**Z-03 through Z-07 and Z-12 through Z-16 can wait** for whatever round comes
after. Z-03, Z-05, Z-06 and Z-16 are dust or distribution-fairness issues with no
value leaving the system; Z-04 is gated in practice by the curated `allowedQuote`
list; Z-12 is evadable-by-design rather than exploitable; Z-13 needs a hostile
protocol-controlled contract; Z-14, Z-15 and Z-07 are a payer-compatibility gap,
an owner footgun and a cosmetic panic respectively. None is reachable as a loss of
funds or a brick.

### Summary table for the deploy decision

| Finding | Sev | Needs redeploy? | Interim mitigation |
|---|---|---|---|
| **Z-17 seeder poke sandwich** | **Critical** | **Yes, blocking** | **launch atomically / zero `primeBudget` — effective** |
| Z-18 seeder range-cap halt | High | Yes, same round | same as Z-17 (don't use progressive) |
| Z-19 fully-retired ledger traps credit | Medium | Yes, same round | none |
| Z-20 `fundPrime` redirect | Medium | Yes, same round | keep `deployer` key cold |
| Z-01 seed price floor | High | **Yes, blocking** | `setAllowedQuote(usdg,false)` — partial only |
| Z-02 vault donation entitlement | High | Yes, same round | monitor `ReserveShortfall` |
| Z-08 grindable reveal | High | **Yes, same round** | none exists |
| Z-09 `nftSupply` vs mint curve | High | Yes, same round | unwire `curvePolicy` |
| Z-10 stranded pushed ERC20 | Medium | Yes, same round | none |
| Z-11 `DefaultFeeRouter` | Medium | No | never call `setFeeRouter` with it |
| Z-03..Z-07, Z-12..Z-16 | Low/Info | No | — |

### Suggested immediate holding action, before the redeploy lands

1. `setAllowedQuote(usdg, false, …)` and the same for any other quote with fewer
   than 18 decimals, so no *new* proposal can select one. (Partial mitigation
   only — see above.)
2. Monitor the `ReserveShortfall` event. It is the protocol's own alarm for the
   Z-02 end state and it already exists (`CauldronRegistry.sol:1060`).

---

## Artifacts Produced

| Path | Finding | Result |
|---|---|---|
| `test/attacks/Z1_SeedPriceDenominationFloor.t.sol` | Z-01 | 4/4 pass; boundary pinned to one quote base unit against the real linked `PoolOps` |
| `test/attacks/T9a_GenesisDividendHunt.t.sol` | Z-08, Z-10, Z-12 | 4/4 pass; includes the positive control `test_A_HonestRevealIsFinal` |
| `test/attacks/T9a_RevealRerollGrind.t.sol` | Z-08 (independent) | second, independently written PoC of the same grind |
| `test/attacks/T9b_DividendConservation.t.sol` | Z-13, plus the §10 conservation refutations | 3/3 pass |
| `test/attacks/Z9b_CurveSupplyMandate.t.sol` | Z-09 | 2/2 pass |
| `test/attacks/Z9_ScopeProbe.t.sol` | Z-11, Z-14 | 2/2 pass |
| `test/attacks/T9b_SeederPokeSandwich.t.sol` | **Z-17** | pass; real v4 `PoolManager`, production seed params, profit measured |
| `test/attacks/T9c_SeederRangeCapMisSide.t.sol` | Z-18 | pass; 59 pokes to the cap, then empty-revert halt |
| `test/attacks/T9d_LedgerFullyRetiredTraps.t.sol` | Z-19 | pass |

All PoCs were checked for **vacuous passes** — `grep` for `vm.skip` and bare
early `return;` returns nothing in any of them, so every reported pass executed
its assertions.

**Corroboration worth noting:** Z-08 (the grindable reveal) was found
*independently twice* in this sweep, by two reviewers working different files and
not sharing results — once from `MiFrensGenesis` and once from
`CauldronCollection`. Two separate PoCs exist. That is unusually strong evidence
for a finding whose in-code comment asserts the opposite property.

No contract was modified in the course of this audit. Only new test files were
added, all under `contracts/solidity/test/attacks/`.
