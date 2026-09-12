# Smart Contract Security Audit Report
Magic Internet Frens — Cauldron (Uniswap V4 hook protocol)

## Executive Summary

**Project:** Magic Internet Frens / Cauldron
**Auditor:** Solidity security auditor (final pre-deploy blind pass)
**Date:** 2026-09-12
**Commit range:** `1e98bb4..6459b85` (38 commits touching `contracts/solidity`)
**Scope:** OWASP **SC-03** (Reentrancy), **SC-04** (Flash Loans), **SC-06** (Oracle Manipulation), **SC-07** (Unchecked External Calls) — restricted to code changed in that range.
**Solidity Version:** `^0.8.26`

### Overview

This pass audited only today's diff, and only along four axes: re-entry created by
the CEI re-orderings, the several places where a `revert` was converted into a
`return`, the oracle behaviour that was deliberately split into fail-open and
fail-closed halves, and every low-level call / ERC20 interaction added or moved.

The re-entrancy surface came out clean. The `_inSelfBuy` transient guard, the
result-ignored self-call pattern, and `rotateStep`'s explicit effects-before-swap
ordering all hold under adversarial reading, and each of the four
revert→continuation conversions was traced to every caller and every consumer of
the state it stops short of writing. Nothing was found there.

The oracle split is where the work was left half-done. `_oracleFloor` was moved
onto the uncached feed today with an explicit, correct rationale — "a price frozen
at whatever it was when the feed died is precisely what an attacker wants the
floor computed from" (`QuoteRotator.sol:429-438`). The *other* permissionless
treasury-spending path in the same contract, `arbStep`, still prices both of its
legs with the cached, fail-open reader, and those two numbers are its only guard
against loss, its only basis for the keeper's payout, and the unit its per-block
notional cap is denominated in. That is HIGH-01.

The second real finding is that `LegacyBuyLib.buyStep`'s new price bound names the
threat it does not stop. The commit message and the code comment both claim the
`SLIP_SQRT_BPS` limit protects against "a book drained or skewed **inside the same
transaction**"; the limit is computed from a `getSlot0` read taken *after* that
skew, in the same transaction, so it bounds only the buyback's own marginal move.

The third is an incomplete half of a fix shipped and regression-tested today:
`FeeRouteLib._deliver` got its codeless-recipient check placed correctly, before
both branches; `_fundGuild` got it only on the ERC20 branch, leaving the native
branch — the one whose own sibling comment says "the ether really left and sat at
a codeless address with no way back" — unguarded.

### Risk Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 1 |
| Medium   | 2 |
| Low      | 3 |
| Info     | 1 |

### Key Findings

- **HIGH-01** — `QuoteRotator.arbStep` judges profit, pays the keeper and meters
  its own notional cap from `QuoteOracle.cachedUsdPerRawUnit`, which pins the last
  good factor *indefinitely* when a feed stops answering. The fail-closed
  treatment applied to `_oracleFloor` today was not applied here.
- **MEDIUM-01** — `LegacyBuyLib.buyStep`'s ~10% sqrt bound is relative to a spot
  price read in the same transaction, so it does not bound a same-transaction
  skew; the buffer is spent at whatever price the triggering swap just created.
- **MEDIUM-02** — `FeeRouteLib._fundGuild`'s native branch still reports a
  codeless `guild` as funded; the ether leaves, `GuildFunded` is emitted, and the
  share is *not* rolled into the relaunch reserve.
- **LOW-01/02** — two unchecked `IERC20.transfer` return values on paths that
  debit a counter first.
- **LOW-03** — `TreasuryGovernor` snapshots at `block.number`, so voting power
  acquired later in the proposal's own block counts, contradicting the comment
  directly above it.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Scope](#scope)
3. [Methodology](#methodology)
4. [Findings](#findings)
5. [Categories Attacked And Found Clean](#categories-attacked-and-found-clean)
6. [Recommendations Summary](#recommendations-summary)

---

## Scope

### Contracts in Scope (changed in `1e98bb4..6459b85`)

| Contract | Lines | Relevance to this pass |
|----------|-------|------------------------|
| `CauldronHook.sol` | 2520 | in-swap fee/death/liquidation/seed/buyback; the `revert`→`return` in `fundLegacyBuffer`; `_creditFor` |
| `cauldron/LegacyBuyLib.sol` | 154 | the nested buyback swap: live price read, new sqrt bound, checked ERC20 settle |
| `cauldron/FeeRouteLib.sol` | 246 | `_fundGuild` / `_deliver` / `send` — every fee-path low-level call |
| `cauldron/QuoteRotator.sol` | 778 | `arbStep`, `rotateStep`, `swapOnce`, `_usd` vs `_usdLive`, `_send`, `_safeTransfer` |
| `cauldron/QuoteOracle.sol` | 344 | (unchanged today, read as the dependency) cache semantics behind both readers |
| `cauldron/PerpEngine.sol` | 1907 | `payoutOwedTotal`, `_pullIntoPlv`, `_vaultPaid`, `_creditPerp` native gate, `ringArmedAt` |
| `cauldron/PerpVault.sol` | 478 | `claimPendingEth` returning 0, `_haircut` |
| `cauldron/PerpSwapLib.sol` | 170 | `migrateInventory` shortfall event replacing a revert |
| `cauldron/RoyaltyRouter.sol` | 47 | the unconditional forward whose failure mode moved into the hook |
| `cauldron/CauldronGachaRouter.sol` | 595 | `_payQuote` / `_safeTransfer` / `_safeTransferFrom` / `rescueToken` |
| `cauldron/MigrationVesting.sol` | 361 | `_release` loop bound + payout call |
| `cauldron/TreasuryGovernor.sol` | 941 | vote-weight snapshot (SC-04) |
| `cauldron/PoolOps.sol` | 1462 | `sendAsset`, `_pullEth`, ERC20 settle path |
| `cauldron/SurtaxLib.sol` | 106 | new linked library; the removed `getSlot0` read |
| `CauldronRegistry.sol`, `cauldron/RedemptionExt.sol`, `cauldron/CauldronBase.sol`, `cauldron/CauldronGovernor.sol`, `cauldron/LaunchSniper.sol`, `cauldron/MiFrensDividend.sol`, `cauldron/MiFrensGenesis.sol`, `cauldron/PerpMarkSource.sol` | — | facet forwarders, renounce guards, selector fixes — read, nothing in category |

### Out of Scope
- Anything not in `git diff 1e98bb4..HEAD -- contracts/solidity`.
- The 20 items on the known-fixed list, except where a fix is incomplete or created
  something new (MEDIUM-02 is exactly that case).
- OpenZeppelin and v4-core dependencies.
- SC-01/02/05/08/09/10 except where they intersect the four assigned categories.

---

## Methodology

### Review Process
1. `git log --oneline 1e98bb4..HEAD -- contracts/solidity` → 38 commits; `git diff`
   per file for the 21 named contracts.
2. Every symbol cited below was re-grepped against the **current working-tree
   file** and the line numbers verified by `sed -n`. No finding rests on a comment.
3. Exhaustive grep for `.call{`, `.call(`, `.delegatecall`, `.transfer(`, `.send(`
   across all 14 changed contracts that contain any; each hit classified as
   checked / unchecked / intentionally-ignored, and each unchecked hit traced to
   whether a counter had already been debited.
4. For each of the four `revert`→`return`/`event` conversions, every caller was
   grepped (production callers separated from test callers) and asked: did anything
   rely on the revert to stop?
5. For the oracle split, both readers (`_usd`, `_usdLive`) were traced to every
   call site and the cache's write semantics read line by line.

---

## Findings

### [HIGH-01] `arbStep` prices permissionless treasury re-allocation off the fail-open cache — the same cache `_oracleFloor` was moved off today

**Severity:** High
**Status:** Open
**File:** `contracts/solidity/cauldron/QuoteRotator.sol`
**Lines:** 533-597 (`arbStep`), 615-624 (`_usd`), 602-613 (`_usdLive`), 425-445 (`_oracleFloor`)
**Dependency:** `contracts/solidity/cauldron/QuoteOracle.sol:305-312` (`cachedUsdPerRawUnit`), `:284` (`TTL`)
**Category:** SC-06 (Oracle Manipulation), SC-04 (value extraction with no capital)

#### Description

Commit `c2e3afa` split this contract's oracle behaviour on purpose, and wrote the
reasoning into the code. `_oracleFloor` now reads the **uncached** view and the
caller turns a `0` into a refusal:

```solidity
// QuoteRotator.sol:429-439 — the fix that shipped today
//  ── LIVE, NOT CACHED ────────────────────────────────────────────────
//  {_usd} reads `QuoteOracle.cachedUsdPerRawUnit`, which keeps its LAST
//  GOOD factor when a refresh comes back empty ... and wrong here, where
//  a price frozen at whatever it was when the feed died is precisely what an
//  attacker wants the floor computed from.
uint256 inUsd = _usdLive(from, amountIn);
```

`arbStep`, the other permissionless spending path in the same contract, was not
changed and still calls `_usd`:

```solidity
// QuoteRotator.sol:568-569 — CURRENT content, verified
uint256 inUsd  = _usd(inQuote,  spent);
uint256 outUsd = _usd(outQuote, received);
if (inUsd == 0 || outUsd == 0) revert NoRoute();
```

`_usd` → `QuoteOracle.cachedUsdPerRawUnit`, whose write rule is:

```solidity
// QuoteOracle.sol:305-312 — CURRENT content, verified
function cachedUsdPerRawUnit(address quote) external returns (uint256) {
    Cached storage c = cache[quote];
    if (block.timestamp <= c.at + TTL && c.factor != 0) return c.factor;
    uint256 fresh = this.usdPerRawUnit(quote);
    c.at = uint64(block.timestamp);          // <-- stamped even when fresh == 0
    if (fresh > 0) c.factor = fresh;         // <-- factor kept on failure
    return c.factor;
}
```

Two properties follow, and the second is the one that matters:

1. A cached factor is up to `TTL` = **15 minutes** old in the normal case.
2. When `usdPerRawUnit` returns `0` — a dead aggregator, `updatedAt` past the
   heartbeat (`QuoteOracle.sol:246`), an answer outside `[minUsd, maxUsd]`
   (`:267-268`), or `_sequencerOk()` false including the whole `gracePeriod` after
   an L2 sequencer restart — `c.at` is still stamped forward and `c.factor` is
   **kept**. The staleness is therefore **unbounded**, not 15 minutes: every read
   renews the TTL on a value that can never be corrected while the feed is down.

Those two USD numbers are everything `arbStep` has:

- they are the **only** loss guard. `_arbCallback` runs both legs with no price
  limit at all (`sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1` on leg 1,
  `MAX_SQRT_PRICE - 1` on leg 2, `QuoteRotator.sol:700-711`) and `arbStep` takes no
  `minOut` parameter. `if (outUsd <= inUsd) revert SlippageTooHigh();` (`:582`) is
  the entire protection;
- they set the **keeper's pay**: `keeperCut = (received * profitUsd * arbKeeperBps) / (outUsd * BPS)` (`:595`);
- they are the unit of the **per-block notional cap**: `arbUsdThisBlock + inUsd > maxArbNotionalUsd` (`:574-579`).

`arbStep` is `external` with no access control (only the venue allowlist and the
destination-quote allowlist, both of which a legitimate arb satisfies), and needs
no capital — both legs settle net inside one `unlock` against the treasury's own
balance.

#### Impact

Whenever a quote's feed is unusable — and for an L2 deployment the
`_sequencerOk()` grace window is the most likely trigger, because it coincides
exactly with the real price dislocation a restart produces — the cached factors
for both legs are frozen at pre-outage values while the pools trade at live
prices. A keeper can then:

- move the treasury from an accurately-cached asset into a stale-high-cached asset
  at up to `maxArbNotionalUsd` (default `$25,000`) of *fictitious* USD **per
  block**, repeatedly, for the whole outage;
- collect `arbKeeperBps` (default 10%) of a profit that does not exist, paid in
  real units of the received asset. With the received leg overvalued by a factor
  `k`, `profitUsd/outUsd → (k-1)/k`, so the cut approaches `10%` of the *entire*
  received notional rather than 10% of a real gain. At the default cap that is on
  the order of **$2.5k of real value per block, for free**, plus two pool fees and
  the price impact of an unwanted round trip, plus an ungoverned re-denomination
  of the treasury that no vote sanctioned.

Because `c.at` is renewed on every failed read, a permanently dead feed makes this
a permanent condition, not a 15-minute one. The `minArbProfitUsd` floor ($5) and
the `$25k` cap do not help: both are measured in the same broken unit.

#### Exploit sequence

1. A quote asset's Chainlink feed stops answering — heartbeat lapse, an answer
   outside the configured band, or (L2) the sequencer-uptime feed reporting down
   or still inside `gracePeriod`. `usdPerRawUnit` now returns 0 for it.
2. `cache[quote].factor` stays at its pre-outage value; every subsequent
   `cachedUsdPerRawUnit` call re-stamps `c.at`, so the TTL never expires.
3. Pools reprice to the live market. The keeper picks the ordered pair
   `(inQuote, outQuote)` for which the frozen cache most overstates `outQuote`
   relative to `inQuote` — both pools already on `allowedVenue`, `outQuote`
   already on the registry allowlist, so every gate in `arbStep` passes.
4. Keeper calls `arbStep(cheap, dear, amountIn)` with `amountIn` sized so
   `inUsd` lands just under `maxArbNotionalUsd`. Both legs fill at live pool
   prices with no slippage bound; `spent`/`received` are real, `inUsd`/`outUsd`
   are stale.
5. `outUsd > inUsd` passes, `profitUsd` clears `minArbProfitUsd`, and
   `_send(outQuote, msg.sender, keeperCut)` pays the keeper ~10% of `received` in
   real units. No capital was ever at risk.
6. Repeat every block until the feed recovers *and* the cache refreshes.

#### Recommendation

Apply the same fail-closed rule `_oracleFloor` got. The profit test is a
loss-prevention guard on treasury funds, which is the category the code's own
comment says must not use the cache:

```solidity
// QuoteRotator.sol — arbStep, replacing lines 568-569
//  ── LIVE, NOT CACHED (same rule as {_oracleFloor}) ──────────────────
//  These two figures are the ONLY guard against an arb that loses money,
//  the basis of the keeper's pay and the unit of the notional cap. A
//  factor frozen at whatever it was when the feed died turns every one of
//  those into a number an attacker chose the moment for.
uint256 inUsd  = _usdLive(inQuote,  spent);
uint256 outUsd = _usdLive(outQuote, received);
if (inUsd == 0 || outUsd == 0) revert NotPriceable();
```

`_usdLive` is already present, already `view`, already `staticcall`-based, and
already returns 0 on a refusing feed — no new code is needed, only the swap of
reader. Note that `arbStep` is not `view`-constrained, so this is a pure
substitution.

Additionally, and independently of which reader is used, stop the cache from
laundering a failed read into a fresh timestamp — it is what makes the staleness
unbounded rather than bounded by `TTL`:

```solidity
// QuoteOracle.sol:305-312
function cachedUsdPerRawUnit(address quote) external returns (uint256) {
    Cached storage c = cache[quote];
    if (block.timestamp <= c.at + TTL && c.factor != 0) return c.factor;
    uint256 fresh = this.usdPerRawUnit(quote);
    //  Only a SUCCESSFUL read may renew the TTL. Stamping `at` on a failure
    //  extends the life of the last good factor indefinitely, so "15 minutes
    //  stale" silently becomes "stale until the feed comes back". Volume
    //  accounting still fails OPEN — it keeps reading `c.factor` — it just
    //  stops pretending the value is fresh, so consumers that care can tell.
    if (fresh > 0) { c.factor = fresh; c.at = uint64(block.timestamp); }
    return c.factor;
}
```

This keeps the fail-open property the volume/death path depends on (the factor is
still returned) while making the age honest, so any future consumer that wants to
bound staleness can.

---

### [MEDIUM-01] `LegacyBuyLib.buyStep`'s price bound is measured against a spot price the same transaction just set

**Severity:** Medium (High if `legacyThreshold` is raised or royalties accumulate between live-pool swaps)
**Status:** Open
**File:** `contracts/solidity/cauldron/LegacyBuyLib.sol`
**Lines:** 44-50 (`SLIP_SQRT_BPS`), 91-108 (the read and the swap)
**Caller:** `contracts/solidity/CauldronHook.sol:1016-1058` (`_maybeLegacyBuyback`), `:1082-1121` (`legacyBuyStep`)
**Category:** SC-06 (Oracle Manipulation), SC-04 (flash-loanable sandwich)

#### Description

`MIN_SQRT_LIMIT` was replaced today by a relative bound, and the comment names
the exact threat it is meant to stop:

```solidity
// LegacyBuyLib.sol:91-108 — CURRENT content, verified
//  A REAL PRICE BOUND, NOT `MIN_SQRT_LIMIT`. The limit used to be the
//  absolute minimum tick price, i.e. "fill at any price at all": a book
//  drained or skewed inside the same transaction could take the whole
//  buffer for dust. Bound the move to a fixed fraction of the live sqrt
//  price ...
(uint160 sp,,,) = poolManager.getSlot0(key.toId());
uint256 lim = (uint256(sp) * SLIP_SQRT_BPS) / 10_000;
BalanceDelta d = poolManager.swap(
    key,
    SwapParams({
        zeroForOne: true,
        amountSpecified: -int256(amt),
        sqrtPriceLimitX96: lim > MIN_SQRT_LIMIT ? uint160(lim) : MIN_SQRT_LIMIT
    }),
    ""
);
```

`sp` is the **live** `slot0` price, read inside the attacker's own transaction,
after the attacker's own swap has already moved it. The bound is therefore purely
*marginal*: it caps how far this buy may push the pool from wherever the pool
already is. It says nothing about whether "wherever the pool already is" is a
price anybody should transact at — which is precisely the "skewed inside the same
transaction" case the comment claims to have closed.

The trigger is reachable by anyone. `_maybeLegacyBuyback` is called from both
`_beforeSwap` and `_afterSwap` (`CauldronHook.sol:799`, `:1001`) and fires on the
live pool (`if (PoolId.unwrap(id) != PoolId.unwrap(live.toId())) return;`,
`:1051`), i.e. on the *same* pool the triggering swap just moved. The buyback then
spends the whole buffer (`uint256 amt = legacyBuffer;`, `CauldronHook.sol:1085`)
with no per-trigger slice cap.

#### Impact

A sandwich converts the buffer into tokens at a price the attacker chose, and the
protocol receives a fraction of the tokens that buffer was worth. The shortfall is
the attacker's profit (net of their own round-trip pool fees and the hook fee on
their two swaps). Per event the loss is bounded by the buffer, which is
`legacyThreshold` = `0.02 ether` by default (`CauldronHook.sol:320`) — small — but:

- it is repeatable on every refill, permissionless, and atomic (no price risk);
- `legacyThreshold` is owner-tunable (`CauldronHook.sol:1898`), and a higher
  threshold directly multiplies the per-event loss;
- `fundLegacyBuffer` is permissionless and receives EIP-2981 royalties
  (`RoyaltyRouter.sol:44-46`), so on a collection with active secondary trading and
  a quiet live pool the buffer accumulates far above the threshold before any swap
  triggers it, and the first attacker swap takes all of it;
- `legacyOwedToReserve += got` (`:1119`) means the under-bought amount is what the
  genesis floor is credited with — the loss lands on the collection's floor, not
  on a discretionary pot.

#### Exploit sequence

1. Wait for `legacyBuffer >= legacyThreshold` with `legacyBufferAsset ==
   currency0` (both publicly readable getters).
2. In one transaction, from one contract: flash-borrow quote, swap a large
   quote→token buy on the live pool. This pushes the token price up sharply.
3. That swap's `_afterSwap` calls `_maybeLegacyBuyback` → `legacyBuyStep` →
   `buyStep`. `getSlot0` returns the *pushed* price; `lim` is 94.86% of that
   pushed sqrt price; the buyback buys the token at ~the top, spending up to the
   whole buffer.
4. Still in the same transaction, swap token→quote back, unwinding the push into
   the buyback's fresh buy pressure, and repay the flash loan. The delta between
   what the buffer bought and what it should have bought is the attacker's.

#### Recommendation

Anchor the limit to a price the triggering transaction cannot move, and cap the
spend per trigger. The protocol already maintains an in-house TWAP for exactly
this purpose (`PerpEngine.twapTick` / `markSqrtPriceX96`, fed by
`PerpMarkSource`), and the hook already holds a `perpEngine` address:

```solidity
// LegacyBuyLib.sol — replace lines 97-98
//  THE BOUND MUST NOT BE RELATIVE TO A PRICE THIS TRANSACTION SET. A
//  `getSlot0` read here is taken AFTER the triggering swap has already
//  skewed the book, so a fraction of it bounds only this buy's own
//  marginal move — not the absurdity of the level it starts from. Anchor
//  to the mark (a TWAP over `twapWindow`, which a single transaction
//  cannot move) and refuse rather than fill when the mark is unavailable:
//  a buyback that does not happen costs nothing, the buffer simply rolls
//  to the next trigger.
uint160 anchor = markSqrtPriceX96;          // passed in by the hook
if (anchor == 0) revert NoMark();
uint160 live; (live,,,) = poolManager.getSlot0(key.toId());
//  Never transact above the mark by more than the tolerance, and never
//  let the buy itself push more than SLIP_SQRT_BPS below wherever it is.
uint160 floorFromMark = uint160((uint256(anchor) * SLIP_SQRT_BPS) / 10_000);
if (live < floorFromMark) return (0, 0);    // book is skewed — skip, keep the buffer
uint256 lim = (uint256(live) * SLIP_SQRT_BPS) / 10_000;
```

and, in the caller, bound the per-trigger spend so a single manipulated block can
never reach the whole accumulated buffer:

```solidity
// CauldronHook.sol:1085 — legacyBuyStep
uint256 amt = legacyBuffer;
//  ONE TRIGGER MAY NOT SPEND AN ARBITRARILY LARGE ACCUMULATION. The buffer
//  grows permissionlessly (royalties), and the trigger is any swap on the
//  live pool — so an attacker chooses the block in which the whole balance
//  is committed. Cap the slice; the remainder rolls to the next trigger,
//  which the existing `spent < amt` refund path already handles.
uint256 slice = legacyThreshold * MAX_BUY_MULTIPLE;   // e.g. 4
if (amt > slice) amt = slice;
```

If wiring the mark into a linked library is too expensive against the EIP-170
ceiling, the per-trigger cap alone materially reduces the blast radius and is a
two-line change.

---

### [MEDIUM-02] `_fundGuild`'s native branch still reports a codeless guild as funded — the ether leaves and is not reserved

**Severity:** Medium
**Status:** Open (incomplete half of the X4c/X4e fix shipped today)
**File:** `contracts/solidity/cauldron/FeeRouteLib.sol`
**Lines:** 128-146 (`_fundGuild`), compare 148-175 (`_deliver`, fixed correctly — its check is at :162)
**Callers:** `contracts/solidity/cauldron/FeeRouteLib.sol:97` (`routeSplit`), `contracts/solidity/CauldronHook.sol:1431`, `:1507`
**Category:** SC-07 (Unchecked External Calls)

#### Description

Commits `02f4e8a` and `a3773fc` added a codeless-recipient check to both fee
delivery helpers. `_deliver` got it in the right place — **before** either branch:

```solidity
// FeeRouteLib.sol:148-163 — CURRENT content, correct (check at :162)
function _deliver(address asset, address to, uint256 amount, bytes4 nativeSel, bytes4 assetSel) private returns (bool ok) {
    //  ... and on the NATIVE branch it was worse than the ERC20 one: the
    //  ether really left and sat at a codeless address with no way back.
    //  Checking BEFORE either branch means the value never moves ...
    if (to.code.length == 0) return false;
    if (asset == address(0)) { ... }
```

`_fundGuild` got it only on the ERC20 branch, and only *after* the call:

```solidity
// FeeRouteLib.sol:128-146 — CURRENT content, verified
function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok) {
    if (asset == address(0)) { (ok, ) = guild.call{value: amount}(""); return ok; }   // <-- line 129: no check
    (bool approved, ) = asset.call(abi.encodeWithSignature("approve(address,uint256)", guild, amount));
    if (!approved) return false;
    bytes memory r;
    (ok, r) = guild.call(abi.encodeWithSignature("fundToken(address,uint256)", asset, amount));
    if (ok && guild.code.length == 0) ok = false;        // <-- ERC20 branch only, :142
    ...
}
```

Line 129 is the branch taken on every **native-quoted** generation, which is the
default configuration (iteration #1 is always native-quoted — see
`LaunchSniper.sol:84-91`). A `call{value:}` to an address with no code always
succeeds, so `ok` is `true`, the caller emits `GuildFunded`, and `leftover` is not
incremented:

```solidity
// FeeRouteLib.sol:97-98
if (guild != address(0) && _fundGuild(asset, guild, toGuild)) emit GuildFunded(guild, toGuild);
else leftover += toGuild;
```

#### Impact

If `guild` is ever set to an address with no code — a mistyped constructor
argument, an address on the wrong chain, a contract that was never deployed at a
counterfactual address, or a `selfdestruct`ed one — then on a native-quoted
generation every guild share of every swap fee is sent to that address and
**permanently lost**. It is not merely uncredited: the `else leftover += toGuild`
branch is skipped, so `_creditReserve` never books it into `relaunchETH` and there
is no exit at any privilege level. `CauldronHook.sol:1507` routes the anti-sniper
surtax through the same helper, so the surtax is lost the same way. The event log
reports every one of these as a successful `GuildFunded`, so monitoring will not
catch it. This is exactly the harm `_deliver`'s own comment describes, on the
sibling function, left in place.

#### Exploit sequence

Not attacker-triggered; it is an unrecoverable misconfiguration amplifier. Once
`setGuild` points at a codeless address on a native generation, the loss begins on
the very next swap and continues silently until someone notices the dividend
contract's balance is not growing. By then the ether is at an address with no
code, no owner and no sweep.

#### Recommendation

Move the check to where `_deliver` has it — before either branch — so the value
never moves and the share falls through to the reserve:

```solidity
// FeeRouteLib.sol:128
function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok) {
    //  A CODELESS RECIPIENT IS NOT A SUCCESSFUL PULL, ON EITHER BRANCH
    //  (red-team X4c — the native half). `call{value:}` to an account with
    //  no code ALWAYS succeeds, so the native branch reported funded while
    //  the ether left for an address with no code, no owner and no sweep —
    //  and because `routeSplit` only buffers the share when this returns
    //  false, it was not even reserved. Checking BEFORE either branch means
    //  the value never moves and the caller routes it to `relaunchETH`,
    //  which has an exit. Same placement as {_deliver}:162.
    if (guild.code.length == 0) return false;
    if (asset == address(0)) { (ok, ) = guild.call{value: amount}(""); return ok; }
    ...
}
```

Hoisting the check also lets the post-call `if (ok && guild.code.length == 0)` and
the unused `bytes memory r` be deleted, which returns a little EIP-170 headroom.

---

### [LOW-01] `sweepLegacyReserve` debits the counter and then ignores the transfer's return value

**Severity:** Low
**Status:** Open
**File:** `contracts/solidity/CauldronHook.sol`
**Lines:** 1178-1184
**Category:** SC-07

#### Description

```solidity
// CauldronHook.sol:1178-1184 — CURRENT content, verified
function sweepLegacyReserve(address token, address to) external returns (uint256 amt) {
    if (msg.sender != legacyRegistry) revert OnlySelf();
    uint256 owed = legacyOwedToReserve;
    uint256 bal = IERC20(token).balanceOf(address(this));
    amt = owed > bal ? bal : owed;
    legacyOwedToReserve = owed - amt;
    if (amt > 0) IERC20(token).transfer(to, amt);   // return value ignored
}
```

The CEI ordering is right (the counter is debited first — that was today's F-03
fix). The return value is not checked. Every other ERC20 write added today is
checked: `LegacyBuyLib.sol:146-148`, `QuoteRotator._safeTransfer` (`:741-754`),
`CauldronGachaRouter._safeTransfer` (`:553-556`), `PoolOps.sendAsset`
(`:1109-1119`), `FeeRouteLib._move` (`:105-111`). This is the one that is not.

#### Impact

A quote/iteration token that returns `false` instead of reverting (the USDT/most
tokenised-equity pattern this codebase explicitly guards against elsewhere) would
have `legacyOwedToReserve` debited while nothing moved, and the registry then
credits the genesis ledger for `amt` tokens the reserve never received — a floor
credit with no backing, which is the exact invariant `legacyBuyStep`'s own comment
says the deferred-credit design exists to preserve ("so a credit never out-runs
the reserve", `:1116-1118`). Today's iteration tokens are protocol-deployed and
revert on failure, so this is latent rather than live.

#### Recommendation

```solidity
if (amt > 0) {
    (bool ok, bytes memory r) =
        token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amt));
    //  A FALSE-RETURNING TOKEN MUST NOT LOOK LIKE A DELIVERED SWEEP: the
    //  registry credits exactly the `amt` returned here into the genesis
    //  ledger, so an unchecked transfer credits a floor the reserve never
    //  received. Reverting is safe — the only caller is the permissionless
    //  `materializeLegacyReserve`, and the revert rolls back the debit.
    if (!ok || (r.length != 0 && !abi.decode(r, (bool)))) revert SendFailed();
}
```

---

### [LOW-02] `MigrationVesting._release` marks a grant released before an unchecked transfer

**Severity:** Low
**Status:** Open
**File:** `contracts/solidity/cauldron/MigrationVesting.sol`
**Lines:** 263-283 (the loop), 272 (the transfer)
**Category:** SC-07

#### Description

```solidity
// MigrationVesting.sol:266-274 — CURRENT content, verified
uint256 due = vested - grt.released;
if (due > 0) {
    grt.released = vested;          // effect first — correct for reentrancy
    totalMoved += due;
    IERC20(grt.token).transfer(holder, due);   // return value ignored
    emit Claimed(holder, due, grt.token);
}
```

CEI is correct and `claim`/`claimFor` are `nonReentrant`. The return value is not
checked, and the grant is marked fully released beforehand, so a `false`-returning
token silently destroys the beneficiary's entitlement with a `Claimed` event
emitted. `grt.token` comes from `registry.generationToken(fromGen)`, so it is
protocol-controlled — latent, not live.

Separately noted as clean: the DoS half of this loop is genuinely fixed.
`MAX_GRANTS = 64` is enforced in the one push path (`:213`) and `vestBatch` is
sub-capped at `MAX_BATCH_GRANTS = 32` with a `continue` rather than a revert
(`:195`), so the loop is bounded by construction and a third party cannot consume
the holder's headroom.

#### Recommendation

Use a checked helper (the pattern already in `QuoteRotator._safeTransfer`), and
keep it reverting so the `grt.released = vested` write rolls back:

```solidity
if (due > 0) {
    grt.released = vested;
    totalMoved += due;
    //  CHECKED. `grt.released` is already advanced, so a false-returning
    //  token would destroy the entitlement and still emit `Claimed`.
    //  Reverting rolls the write back — the holder retries after the cause
    //  is fixed, rather than losing the grant.
    _safeTransfer(grt.token, holder, due);
    emit Claimed(holder, due, grt.token);
}
```

---

### [LOW-03] `TreasuryGovernor` snapshots at `block.number`, so power acquired later in the proposal's own block counts

**Severity:** Low
**Status:** Open
**File:** `contracts/solidity/cauldron/TreasuryGovernor.sol`
**Lines:** 444-448 (`snapshot: block.number`), 463 (`getPastVotes`), 879 (`getPastTotalSupply`)
**Category:** SC-04 (Flash Loan / governance weight)

#### Description

```solidity
// TreasuryGovernor.sol:444-448 — CURRENT content, verified
// Voting power is frozen at the PROPOSING block, so MiFrens bought
// or borrowed after reading this proposal carry no weight.
snapshot: block.number,
```

The comment overstates what the code delivers. OpenZeppelin `Votes` checkpoints
are keyed **by block number**, and `getPastVotes(account, N)` returns the last
checkpoint written at or before the end of block `N` — including transfers and
delegations that happen *later in block N itself*. A proposer who files at
transaction index `i` and then acquires + delegates at index `i+1` of the same
block is fully counted when they vote in a later block.

This is not flash-loanable (voting is a separate transaction, so the position must
survive one block boundary), which is why it is Low rather than High. But on a
fast L2 that is a ~1-2 second exposure that can be fully hedged, and the proposer
controls the ordering completely.

#### Impact

The cost of buying a mandate is reduced from "hold voting power through the voting
period" to "hold it across one block boundary". `QUORUM_BPS` is measured against
`getPastTotalSupply(p.snapshot)` with the same off-by-one-block, so the quorum
denominator is equally influenceable. Today's `e377594` fix (leader-scan /
overwrite hardening) does not touch the weight source.

#### Recommendation

```solidity
//  `block.number - 1`, NOT `block.number`. OZ checkpoints are keyed by
//  block, and `getPastVotes(a, N)` includes transfers made LATER IN BLOCK N —
//  so a proposer who files at tx index i and delegates at i+1 of the same
//  block is fully counted, which is exactly what the line below claims is
//  impossible. Snapshotting the previous block makes the comment true.
snapshot: block.number - 1,
```

(Guard the genesis case if this contract can be deployed and proposed against in
block 0 of a fresh chain; otherwise no other change is needed, since
`getPastVotes`/`getPastTotalSupply` already accept any past block.)

---

### [INFO-01] `QuoteRotator` has no reentrancy guard; two permissionless paths are safe only by hand-maintained CEI

**Severity:** Informational
**File:** `contracts/solidity/cauldron/QuoteRotator.sol`
**Lines:** 284-320 (`rotateStep`), 533-597 (`arbStep`), 730-737 (`_send`)

#### Description

`QuoteRotator` does not inherit `ReentrancyGuard`, and both `rotateStep` and
`arbStep` are permissionless and end with `_send(..., msg.sender, fee)` — a
full-gas `call{value:}` to an arbitrary keeper on a native quote.

Both are currently safe, and deliberately so. `rotateStep` writes
`p.lastStepAt = block.timestamp` and `p.doneIn += size` **before** `_swap`, with
the reason stated inline ("Effects BEFORE the external call: the swap re-enters
this contract via unlockCallback and pays an arbitrary keeper at the end"), so a
re-entrant call hits `nextSliceSize() == 0 → TooSoon`. `arbStep` commits
`arbBlock`/`arbUsdThisBlock` before `_send`, so a nested arb is metered against
the same per-block cap. `withdraw` is `registry`-or-`owner` gated and `swapOnce`
is `onlyRegistry`. I could not construct a re-entry that gains anything.

The exposure is to future edits: the safety is entirely a property of statement
order in two functions, with no structural backstop, in a contract that holds the
treasury mid-rotation.

#### Recommendation

Inherit `ReentrancyGuard` and mark `rotateStep`, `arbStep`, `swapOnce` and
`withdraw` `nonReentrant`. `unlockCallback` must **not** be guarded — it is
re-entered by the PoolManager inside the guarded frame (the same constraint
`CauldronRegistry.sol:1381-1384` documents for its facet forwarders). The
comments explaining the CEI ordering are worth keeping either way; they just stop
being the only thing standing between a keeper and the treasury.

---

## Categories Attacked And Found Clean

These were attacked deliberately and hard. Each is a result, not an omission.

**SC-03 Reentrancy — clean.** No finding.

- *The nested buyback.* `legacyBuyStep` sets the transient `_inSelfBuy` before the
  delegatecalled swap and clears it after (`CauldronHook.sol:1094`, `:1109`). Both
  callbacks early-return on it (`_afterSwap` at `:788`, `_beforeSwap` at `:1200`),
  so the nested swap accrues no fee, no volume, no death check, no liquidation
  scan, no gacha and no seeder poke, and cannot re-enter `_maybeLegacyBuyback`.
  The only call site is `address(this).call{gas:}` (`:1055`) and `legacyBuyStep`
  gates on `msg.sender != address(this)`, so there is no external door. I checked
  the failure path specifically: because the self-call is result-ignored, a revert
  inside `buyStep` rolls back both `legacyBuffer = 0` **and** `_inSelfBuy = true`
  — the flag cannot be left stuck on, which would have disabled all fee collection.
  `poolManager.take(currency1, ...)` moves a protocol-deployed token with no
  transfer hook.
- *`rotateStep` / `arbStep`.* See INFO-01 — safe, by explicit CEI, verified
  statement by statement rather than taken from the comment.
- *`claimProposerFees`* (`CauldronHook.sol:2118-2125`), *`releaseRelaunchETH`*
  (`:1688-1696`), *`PerpEngine.claimPayout`* (`:1482-1487`),
  *`PerpVault.claimPendingEth`* (`:313-336`) — all zero (or debit) the caller's
  entry before the send, all `nonReentrant`, all check the send's return. The
  `payoutOwedTotal` aggregate added today balances: incremented with
  `payoutOwed[to]` in `_pushQuote`'s failure branch (`:1477`) and decremented by
  the same amount in `claimPayout` (`:1486`), with the re-credit path on a failed
  re-push restoring both.
- *`PerpEngine._vaultPaid`* — the refactor that folded two vault-pull tails into
  one kept the counter debit at the call site, before the helper
  (`plv -= amount; _vaultPaid(...)`, `:1728-1737`), so CEI is byte-for-byte what
  it was. Both callers remain `onlyVault notNested nonReentrant`.

**SC-04 Flash Loans — one Low (LOW-03), otherwise clean.**

- `arbStep` requires no capital but is bounded per **block** now
  (`arbBlock`/`arbUsdThisBlock`, `:574-579`), so the "unlimited calls per block"
  hole is genuinely closed; I re-derived the accumulator and it cannot be reset
  within a block.
- `TreasuryGovernor` uses `getPastVotes` against a stored snapshot, not
  `balanceOf`, so it is not flash-loanable; the residual is the one-block
  off-by-one in LOW-03.
- The surtax is no longer steerable from inside the priced transaction: the live
  `tick` term was removed from the jitter seed (`SurtaxLib.sol:88-92`), leaving
  `blockhash(block.number - 1)`, `PoolId`, `block.number` and `prevrandao` — none
  of which a swapper can move with a probe swap. I checked for any other
  same-transaction-controllable input in the seed and found none. This also
  removed the hook's last direct `getSlot0`, which is what makes MEDIUM-01 the
  only live-pool-state read left in the hook's swap path.

**SC-06 Oracle Manipulation — HIGH-01 and MEDIUM-01; the rest of the split is correct.**

- The fail-**open** direction is right where it is used. `cachedUsdPerRawUnit`
  keeping the last good factor is correct for volume/death, because a `0` reads as
  "no trading" and pushes a live generation toward an irreversible death;
  `_sequencerOk` failing toward *alive* is consistent with that. I looked for a way
  to weaponise the fail-open direction against death detection and could not find
  one — a stale factor cannot make volume look *smaller* than it is unless the
  feed's last good value was itself low, which is not attacker-chosen.
- The fail-**closed** direction is right where it was applied:
  `rotateStep`'s `if (floor == 0 && quoteOracle != address(0)) revert NotPriceable();`
  (`:390`) with `_usdLive` behind it, and the `quoteOracle == address(0)` carve-out
  is correctly reasoned (a deployment with no oracle is bounded by `minOut` by
  design).
- The perp mark's cold-start hole is genuinely closed. `ringArmedAt` is written in
  the only place that wipes the ring (`PerpEngine.sol:1101-1108`: `delete
  observations` then `ringArmedAt = block.timestamp`), and `_guardOpen` re-arms off
  it for a full `twapWindow` (`:1355`). I grepped every write to `observations` and
  `obsIndex` (`:484-485`, `:653-654`, `:1101-1108`) to confirm there is no second
  wipe path that skips the re-arm. The constructor's `ringArmedAt == 0` default is
  correct because the 24h summon warmup covers the cold start.
- `PerpEngine._creditPerp`'s new `if (!_quoteIsNative()) revert BadParam();`
  (`:1691-1700`) closes the native-wei-into-an-ERC20-counter door, and the three
  siblings all route through `_pullQuote`, which refuses `msg.value` on an ERC20
  book. Consistent.

**SC-07 Unchecked External Calls — LOW-01 and LOW-02; everything else checked.**

Every `.call`, `.call{value:}`, `.delegatecall`, `.transfer` and `.send` in all 14
changed contracts that contain any was enumerated and classified:

- *Correctly checked:* `LegacyBuyLib.sol:146-148` (the new ERC20 settle, with the
  right `r.length != 0` handling for tokens that return nothing);
  `QuoteRotator._safeTransfer` (`:741-754`, including the `token.code.length == 0`
  guard); `QuoteRotator._send` (`:730-737`); `CauldronGachaRouter._payQuote` /
  `_safeTransfer` / `_safeTransferFrom` (`:542-562`); `PoolOps.sendAsset`
  (`:1109-1119`); `FeeRouteLib._move` (`:105-111`) and `_deliver` (`:148-175`, check at `:162`);
  `CauldronHook.sol:1693`, `:1991`, `:2122`; `CauldronRegistry.sol:474`, `:484`,
  `:566`, `:669`; `LaunchSniper.sol:104`; `MiFrensGenesis.sol:305`.
- *Intentionally ignored, and correctly so:* the four gas-capped best-effort
  self/side calls in the hook's swap path — `perpEngine.call{gas:}` (`:949`),
  the gacha self-call (`:966`), the legacy-buyback self-call (`:1055`) and
  `seeder.call{gas:}` (`:1072`). Each reserves gas, ignores the result by design,
  and any revert inside rolls back only the callee's own writes. This is the right
  pattern for a swap-path side effect and I confirmed none of them is the sole
  writer of state a later invariant depends on.
- *Fee-on-transfer / rebasing / gas-bombing:* `LegacyBuyLib` settles
  `spent = uint256(uint128(-d.amount0()))` — the realised debit, not the intended
  `amt` — so a price limit that binds cannot over-settle and strand a positive
  delta (which would revert the user's parent swap). A fee-on-transfer quote would
  break v4's `sync`/`transfer`/`settle` accounting, but that is a property of the
  allowlist (`_allowed`), not of today's diff. The `guild` and `perpEngine`
  recipients are governance-set, so an unbounded-gas callee is a trusted-party
  risk, not an attacker-reachable one.

**The four `revert`→continuation conversions — clean.** This was the sharpest
question in the brief and it produced nothing:

- *`fundLegacyBuffer` never reverts* (`CauldronHook.sol:1129-1163`). Its only
  production caller is `RoyaltyRouter.receive()` (`:44-46`), which forwards
  unconditionally and now genuinely cannot fail — so the marketplace-sale liveness
  break is real and fixed. I then checked whether the new continuation can corrupt
  the denomination invariant it was protecting, by enumerating all four writers of
  `legacyBuffer`/`legacyBufferAsset`: `:1156-1162` (native ingress),
  `:1388-1398` (fee carve), `:1414-1416` (no-vault floor fold) and `:1028-1035`
  (the stale-buffer drain). Every one either requires `legacyBuffer == 0` or
  requires `legacyBufferAsset` to already equal the asset being added, and
  `legacyBuyStep` re-asserts the match at the point of spending (`:1102`). Two
  denominations cannot coexist in the counter. The `else` branch credits
  `relaunchETH`, which `releaseRelaunchETH` really pays out, so nothing strands.
- *`claimPendingEth` returns 0* (`PerpVault.sol:313-336`). The early return sits
  **after** both write-downs (`pendingEth -= (owed - capped)` and
  `pendingEthOf[msg.sender] = capped`), which is the whole point — the zero is
  banked, not rolled back. No production caller relies on the revert: grep for
  `claimPendingEth` returns only `PerpVault.sol:71,99,262,313` and test files. The
  pro-rata `_haircut` rounds toward the vault and is monotone, so a worthless claim
  is recognised once and `pendingEth` can genuinely reach zero, which is what
  `syncGeneration`'s new `hasQuoteStake()` gate depends on.
- *`migrateInventory` emits instead of reverting* (`PerpSwapLib.sol:128-165`). The
  shortfall path advances no state the success path would have advanced — the
  unmigrated balance is still physically on the engine and `fundPlvToken` can
  re-seed it. Reverting genuinely is not an option here (the sync runs inside
  relaunch's try/catch, and a revert would leave the engine armed on a dead
  generation), so the event is the correct disposition. The `InventoryMigrationShortfall`
  event carries the raw revert data, which is what made today's
  `NotConfigured()`-from-a-missing-facet class of failure visible at all.
- *`PerpEngine.renounceOwnership` and the six siblings* — `revert`-only overrides;
  no continuation semantics to analyse.

---

## Recommendations Summary

### Immediate Actions (High)
1. **HIGH-01** — switch `arbStep`'s two valuations from `_usd` to `_usdLive` and
   revert `NotPriceable` on a `0`, matching `_oracleFloor`. Two-line change; the
   helper already exists.
2. **HIGH-01 (b)** — stop `QuoteOracle.cachedUsdPerRawUnit` from stamping `c.at`
   on a failed refresh, so cached staleness is bounded by `TTL` instead of by the
   feed's eventual recovery. Keeps the fail-open factor for volume/death.

### Short-term Improvements (Medium)
3. **MEDIUM-01** — anchor `LegacyBuyLib.buyStep`'s `sqrtPriceLimitX96` to the perp
   mark (a TWAP) rather than to a same-transaction `getSlot0`, and cap the
   per-trigger spend to a small multiple of `legacyThreshold`. Until then, do not
   raise `legacyThreshold`, and treat a large accumulated `legacyBuffer` as an
   exposed position.
4. **MEDIUM-02** — hoist `_fundGuild`'s codeless-recipient check above the native
   branch, matching `_deliver`. Also add a `guild.code.length != 0` assertion in
   `setGuild` as defence in depth.

### Best Practice Improvements (Low / Info)
5. **LOW-01 / LOW-02** — check the two remaining raw `IERC20.transfer` return
   values, using the checked-call pattern already standard in this codebase.
6. **LOW-03** — `snapshot: block.number - 1` in `TreasuryGovernor.propose`.
7. **INFO-01** — inherit `ReentrancyGuard` in `QuoteRotator` and guard
   `rotateStep` / `arbStep` / `swapOnce` / `withdraw` (never `unlockCallback`).

---

## Conclusion

The re-entrancy work in this diff is good: the transient self-buy flag, the
result-ignored gas-capped side calls, and the explicit effects-before-swap ordering
in `rotateStep` are each correct, and the four revert→continuation conversions were
each reasoned through to the invariant they could have broken and did not. I
attacked all four of those conversions specifically and found nothing.

The two real problems are both incompleteness rather than oversight. The oracle
split was applied to one of the two permissionless treasury-spending paths in
`QuoteRotator` and not the other, and the path that was missed is the one where the
oracle *is* the entire loss guard — that is HIGH-01, and the fix is a two-line
substitution using a helper that already exists. And `LegacyBuyLib`'s new price
bound solves the "fill at any price" half of its stated threat while leaving the
"skewed inside the same transaction" half exactly as it was, because the reference
price is read after the skew.

One fix shipped today is half-applied (`_fundGuild`'s native branch), and two raw
ERC20 transfers survive in a codebase that otherwise checks every one. None of the
four categories produced a Critical.

---

## Disclaimer

This audit report is not investment advice. The findings represent the auditor's
assessment of `1e98bb4..6459b85` at the time of review, restricted to OWASP SC-03,
SC-04, SC-06 and SC-07 within that diff. Smart contracts may contain undiscovered
vulnerabilities, and users should exercise their own due diligence.
