# Blind Red-Team — Magic Internet Frens / The Cauldron

**Date:** 2026-09-09
**Scope:** the dirty working tree (uncommitted), not HEAD.
**Method:** blind. No prior audit doc, EXPLOIT_REPORT, design doc, or commit message was read before findings were written. Comments in source were treated as unverified author claims.

---

## 1. Verdict (ten lines)

The Cauldron is a genuinely hardened protocol. Four visible prior passes have closed the classic seams: the V4 adoption gate (C-01), TWAP mark poisoning (A-02), funding-as-non-closed-transfer (A-04), vault share inflation (V-02, 1e6 virtual offset), reserve-donate inflation (A-05), proposal-poison relaunch bricking (C-02), and the F-09 gas-starvation transfer guard all hold under direct attack. The fee-routing refactor and the dividend basket are careful and, for the ETH and organic paths, correct.

The value sinks that matter — the relaunch reserve, the perp vault, the migration reserve, the dividend — are not drainable by an unprivileged attacker on the **live ETH-only config**. I could not build a Critical or High that steals principal.

What I did find is one **Medium**: the Q-01 "stranded guild dividend" fix was applied to the organic swap path (`routeSplit`) but **missed on the perp swap path (`routePerp`)**, so a non-ETH-quoted perp generation permanently loses the OG-holders' 30% share of every perp fee to an unrecoverable balance. It is not attacker-*extractable* (it destroys value rather than routing it to a thief) and it is gated on a non-ETH perp generation — but that generation is exactly what this working tree exists to enable, and there is no rescue path. PoC included, red-on-current-code.

Two smaller regressions ride the same quote-agnostic change (stale wei constants; sell-side perp-fee misrouting). Would-it-hold: yes, against theft, today. The remaining risk is value *loss* on the not-yet-live multi-quote paths.

---

## 2. Value map (built independently)

**Where value enters**
- `summon()` — one-time genesis ETH (owner/igniter).
- Swap fees — taken on the quote side inside `beforeSwap`/`afterSwap`, in whatever asset the pool is quoted in (ETH/USDG/xNVDA). This is the machine's perpetual income.
- Perp collateral — `openLong`/`openShort` pull the generation's quote.
- Vault stakes — ETH/quote (`plv`) backing longs, iteration-token (`plvToken`) backing shorts.
- Enchant fees, auto-migrate fees, prime buy.

**Where value sits**
- `CauldronHook.relaunchETH` + `relaunchAsset[asset]` — the self-funding reserve for the next generation. **Registry-gated exit only.**
- `CauldronHook.legacyBuffer` — buyback pressure (native only).
- `MiFrensDividend` — per-asset MasterChef accumulators (`accPerShare`, `accPerShareOf[asset]`) + `owed`/`owedAsset` pull balances. Funded only through `receive()` (ETH) and `fundToken` (ERC20, funder-gated).
- `PerpEngine` — `plv`, `plvToken`, `insuranceEth`, `tokYieldEth`, per-position collateral/principal.
- Reserve LP position — single-sided token parked out of range (below launch tick); backs 1:1 migration.
- `CauldronVault` — per-generation ETH floor; redeemed by NFT burn.

**Where value leaves, and who can move it**
- `releaseRelaunchETH` / `releaseRelaunchAsset` — **registry only**.
- `MiFrensDividend.claim*` / `withdrawOwed*` — the enchanted NFT owner only.
- `PerpVault.withdraw*` / `claim*` — the staker, capped at free (un-lent) assets.
- `claimByBurn` / `claimByBurnUpTo` / `autoMigrateBatch` — burn old token 1:1 for new from the reserve; reverts if the reserve is short (no over-claim).
- Perp settlement `_payOut` — trader residual + keeper reward.
- `QuoteRotator.withdraw` / keeper cuts — owner-gated withdraw; permissionless `rotateStep`/`arbStep` pay bounded keeper cuts.

**Authorities**
- `owner` (timelock) — feeds, params, wiring. `registry` — reserve release, relaunch, force-close. `funder` (hook) — the only address that can `fundToken` the dividend basket. `emergencyAdmin` + `guardian` (timelocked, vetoable) — rescue/migrate/sweep. No unprivileged key reaches a sink directly.

---

## Remediation status (applied 2026-09-09)

- **B-01 — FIXED.** `FeeRouteLib.routePerp` guild leg switched from `_move` (bare transfer) to `_fundGuild` (the accounted path), mirroring `routeSplit`. Byte-neutral on all EIP-170-bound contracts (`_fundGuild` was already compiled in). Regression suite `B01_StrandedPerpGuildDividend.t.sol` rewritten to assert the fixed behaviour (4 tests, green).
- **B-03 — DOCUMENTED, deferred.** The engine and hook are both at the EIP-170 ceiling (54 B / 30 B spare); a correct buy/sell split for the ERC20 perp-fee path needs a second entrypoint neither can afford. It is a redistribution between staker classes (no loss, solvency intact), non-native-only, and in an area the author already deferred — so it is left with an accurate in-code note (`PerpEngine.creditPerpFeeAsset`) rather than shipped half-fitting. Fix path recorded there.
- **B-02 — DOCUMENTED, deferred.** Risk-constant denomination on a non-ETH quote; fails safe (DoS, not drain). Needs a design decision (restate constants on `syncGeneration`, or re-gate quote support), out of scope for a fee-accounting fix.

---

## 3. Findings

### B-01 — Medium — Perp guild dividend is stranded for non-ETH quotes (Q-01 un-fixed on the perp path) — **FIXED**

**Location:** `contracts/solidity/cauldron/FeeRouteLib.sol:89` (`routePerp` guild leg), reached from `contracts/solidity/CauldronHook.sol:1134` (`_routePerpFee` → `FeeRouteLib.routePerp`).

**Mechanism.** The multi-quote remediation fixed Q-01 (a bare `transfer` to the dividend lands unaccounted and unclaimable) by giving `routeSplit`'s guild leg the *accounted* primitive `_fundGuild` (`FeeRouteLib.sol:64`), which for an ERC20 does `approve` + `MiFrensDividend.fundToken`. Its comment (`FeeRouteLib.sol:56-63`) spells out the hazard verbatim: *"a plain ERC20 `transfer` lands there unaccounted and unclaimable with no exit."*

`routePerp` — the path every **perp** swap fee takes — was left on the old primitive `_move` (`FeeRouteLib.sol:89`, `_move` at `:97`), which for an ERC20 is exactly that bare `transfer`. So:

| Path | Guild leg (ERC20) | Result |
|---|---|---|
| `routeSplit` (organic swaps) | `_fundGuild` → `fundToken` | accounted, claimable ✓ |
| `routePerp` (perp swaps) | `_move` → `transfer` | **unaccounted, stranded ✗** |

`MiFrensDividend` has no function that can adopt a raw balance (`fundToken` pulls *new* tokens via `transferFrom`) and no rescue/sweep. So the 30% OG-dividend share of every perp fee on a USDG/xNVDA-quoted generation is transferred into the dividend and lost forever. ETH-quoted perps are unaffected (`_move(address(0), …)` hits the dividend's accounted `receive()`), which is why the live ETH-only config does not show it.

**Why it's reachable now.** This same working tree removes the `PerpEngine.QuoteNotSupported` guard and makes the engine quote-agnostic (`PerpEngine.sol` diff, ~line 332), and `syncGeneration` (permissionless) adopts `registry.generationQuote(gen)`. The feature that makes a non-ETH perp generation possible is precisely the change that arms this bug.

**Impact.** Permanent, unrecoverable loss of the genesis-holder dividend share (30%) of all perp trading fees, for any non-ETH perp generation. Breaks the dividend's core guarantee ("every ERC20 fee the hook routes to the guild becomes claimable") on the perp leg. Not attacker-extractable — it destroys OG-holder value rather than paying a thief — hence Medium, not High. Likelihood is conditional on a non-ETH perp generation (not live today).

**PoC.** `contracts/solidity/test/attacks/B01_StrandedPerpGuildDividend.t.sol`
- `test_Invariant_PerpGuildFeeIsClaimable_FAILS` — **RED on current code**: routes a 1000e6 USDG perp fee the way the hook does; the enchanted holder is owed `0` instead of `300e6`.
- `test_PoC_B01_PerpGuildFeeStrandedForever` — **PASS**: the 300e6 sits in the dividend, `accPerShareOf` never moves, `assetCount()==0`, holder claims 0.
- `test_PoC_B01_OrganicPathHandlesItButPerpDoesNot` — **PASS**: identical fee via `routeSplit` is credited; via `routePerp` it is stranded.

Verified the one-line fix flips the invariant green (and the stranding-PoCs then correctly fail): switch `routePerp`'s guild leg from `_move` to `_fundGuild` at `FeeRouteLib.sol:89`. Left the failing invariant in place as the regression.

**Fix.** `if (guild != address(0) && _fundGuild(asset, guild, toGuild)) emit GuildFunded(...)` — mirror `routeSplit`. `_fundGuild` already fails soft (buffers to reserve when nobody is enchanted / basket full), so the perp path keeps its "never revert a swap" property.

---

### B-02 — Medium/Low (fail-safe) — Quote-agnostic perp adopts a non-ETH quote with stale wei-denominated risk constants

**Location:** `PerpEngine.sol` — `syncGeneration` (~line 1015, `quote = newQuote`), against constants `minCollateral`, `tierDepthWei` (`maxLeverage`, ~line 663), `insuranceFloor` (~line 761/799).

**Mechanism.** The token↔quote math is correctly decimal-agnostic (it rides the pool's Q96 `sqrtPrice`). But the engine's *absolute* constants are wei-denominated and are **not** restated when `syncGeneration` (permissionless) adopts a new generation's quote. For a 6-decimal quote (USDG) they are off by 1e12:
- `minCollateral` (e.g. 1e16 for "0.01 ETH") reads as 1e10 USDG → every `open*` reverts `DustPosition`.
- `insuranceFloor` in wei vs `insuranceEth` in 6-dec → `InsurancePaused` effectively always → opens blocked.
- `tierDepthWei` in wei vs `activeEthDepth()` in 6-dec → always lowest leverage tier.

**Impact.** All three fail **safe** in the low-decimal direction (block opens / conservative leverage), so this is a usability/DoS regression on a non-ETH perp generation, not a drain. The removed `QuoteNotSupported` error was the thing that used to make the frontend say "perps are ETH-only for this brew"; now the engine silently adopts and bricks. xNVDA (18-dec) is less affected (right scale, wrong price magnitude). Owner must reconfigure every absolute constant as part of launching a non-ETH perp generation, and nothing enforces that.

**Next step / fix.** Either re-introduce a quote-support gate keyed on decimals, or store the constants as ratios / restate them in `syncGeneration` the way `setDeathThreshold` forces the curve restatement on the hook side (U-1). No PoC beyond code-reading; classified as a lead-grade Medium.

---

### B-03 — Low — Non-native perp sell-fee misroutes token-staker yield to ETH stakers; stale comment

**Location:** `PerpEngine.sol:1485` (`creditPerpFeeAsset` → always `plv += amount`) vs `:1495` (`_creditPerp` splits buy→`plv`, sell→`tokYieldEth`).

**Mechanism.** For native fees the hook splits perp fees by side: buys credit `plv` (ETH stakers), sells credit `tokYieldEth` (token stakers). For an ERC20 quote every perp fee goes through `creditPerpFeeAsset`, which unconditionally does `plv += amount`. So a non-native generation's sell-side perp fees are paid to ETH stakers instead of the token stakers who bear short-inventory risk.

**Impact.** Redistribution between two protocol staker classes, not theft or insolvency (the tokens genuinely arrive in `plv`). Low. Note also `_creditPerp`'s comment (`:1497-1500`) is stale — it claims a non-native pool "cannot deliver a perp fee at all," which `creditPerpFeeAsset` now contradicts.

---

## 4. Leads (believed exploitable-ish, not demonstrated)

- **`QuoteRotator.arbStep` is permissionless and accepts attacker-supplied PoolKeys** (`QuoteRotator.sol:304`) with no allowlist check on the two quotes (only a Chainlink-priceability check) and **no explicit size cap** despite the comment claiming one. I could not turn this into a drain: the `outUsd > inUsd` + `minArbProfitUsd` gate is Chainlink-priced (not flash-manipulable), so a hostile counterparty can only execute trades that *profit* the treasury, netting the attacker at most the ~10% keeper cut of a genuine arb. **Next step:** construct a pair of attacker-owned pools with a very high LP fee and check whether LP-fee capture on both legs can exceed the treasury's booked profit while the USD gate still passes — if so, the treasury is the losing counterparty in USD despite the gate. I believe it can't (the gate measures the treasury's own delta), but it wants a fuzz PoC.
- **`_playInCurveUnits` double-conversion surface** (`CauldronGachaRouter.sol`): the swap paths convert playWei→USD, the churn path deliberately does not. If a caller can reach `commitCrystals` with a play size that is ETH-notional on one path but already-USD on another, odds inflate ~(ETH price)×. All three call sites looked internally consistent, and `commitCrystals` is opener-gated, so I could not reach it — **next step:** audit any second opener the registry authorizes for the same unit discipline.

---

## 5. Proven-safe (attacked hard, held)

- **Dividend accounting under multi-asset + transfer/re-cast.** The "stale re-cast" branch (`MiFrensDividend.sol:398-402`) that settles ETH but not the basket is **dead code** given the F-09 guard: `MiFrensGenesis._update` (`:672`) reverts the transfer if it can't run `onMiFrenTransfer`, so `enchantedBy` is always reset and the stale branch is unreachable. Basket settlement on transfer (`onMiFrenTransfer` :459-468) is total and gas-bounded (180k forwarded, ~140k worst case at MAX_ASSETS=3).
- **F-09 gas starvation.** 240k floor / 180k forward survives the 63/64 rule; the child always gets its full 180k. Could not starve it.
- **Vault share inflation.** 1e6 virtual offset + CEI; first-depositor donation attack needs ~1e6× the victim deposit → reverts the victim's tx (griefing, not theft).
- **Volume/death manipulation inside a swap.** `_toUsd` reads a *Chainlink* factor (cached, last-good-on-stale), not pool state — a swap can't inflate its own recorded volume or force death. Death fails toward *alive* (0 = "cannot judge").
- **TWAP mark poisoning.** `_writeObs` always integrates the elapsed tail at the in-force tick and refreshes `lastTick`; a single-block round-trip contributes ~0 to the mark. Cold-start spot fallback is < MIN_TWAP only.
- **V4 adoption gate.** `_afterInitialize` tracks only `sender == registry` pools; a third-party pool naming the hook is inert on every hot path.
- **Migration 1:1.** `PoolOps.migrateOne` burns exactly `amount`, delivers ≤ `amount` (rounds down, CLAIM_DUST tolerance), reverts if the reserve is short — no over-claim, no silent partial.
- **Relaunch bricking.** A-05 clamp (donate-inflated recovery), C-02 clamp (poisoned proposal supply/quote), best-effort try/catch on perp force-close and ticket drain — I could not brick the rebirth.

---

## 6. Coverage gaps (property → value behind it)

1. **No test routes a perp fee in an ERC20 quote through the real hook end-to-end.** The Q-01 suite covers `routeSplit`; nothing covers `routePerp` with a non-native asset — which is exactly why B-01 survived. (High value: OG dividend on all perp volume.)
2. **No test adopts a 6-decimal quote in `PerpEngine.syncGeneration` and then opens a position.** The wei-constant staleness (B-02) has no assertion. (Medium: perp usability on multi-quote.)
3. **No test asserts `creditPerpFeeAsset` routes sell-side fees to the token-staker pot.** (Low: staker fairness.)
4. **`QuoteRotator.arbStep` has no test with attacker-owned pools / no size-cap assertion.** The comment promises a per-call size bound that the code does not implement. (Medium: treasury re-allocation.)
5. **`deathThresholdEth: 0` in the live manifest** means `isDead` is always false via the built-in rule (`vol < 0`) — so relaunch cannot fire unless a `deathChecker` module is wired. No test asserts the live-config relaunch story. Not a bug (owner config), but the "infinitely relaunching" property is currently *off* on-chain. (Observational.)

---

## 7. Blind spots (what I did not reach / had to assume)

- **Did not run the fork suites** (`QuoteOracleFork`, `RotatorSwapFork`, `RotationRoundTrip`) — no `FORK_RPC` exercised. The real multi-pool swap/settle deltas in `QuoteRotator._arbCallback` and `PerpSwapLib.swapLeg` are asserted only by reading; a settle/take imbalance there would be invisible to me.
- **Did not fully trace `PerpSwapLib`, `LegacyBuyLib`, `PoolOps.crystallizeCollection`, `CollectionLedger`, the governor's vote/quorum math, or the render layer.** The governor's `winner()`/`hasProposals()` gating of relaunch is assumed honest.
- **Off-chain (api/, indexer/, src/) not audited for authz/secrets** beyond noting the deleted `MagicFrensPeg`/`MagicFrensPresale` are superseded by `MiFrensGenesis` (the "presale receipts"); the indexer/api still read `round.contracts.presale` and expect `minted`/`soldOut`/`finalized`/`cancelPresale` on that address — confirm the deployed presale address exposes them or the homepage hero shows stale state.
- **Assumed the deploy wiring is correct** (hook is the dividend's `funder`, dividend is the hook's `guild`, feeds ↔ allowlist are the same set). If `funder != hook`, even the organic guild dividend silently rolls to reserve.
- **Trusted-component assumption:** a compromised `quoteOracle`, `feeRouter`, `deathChecker`, `surtaxPolicy`, or `markSource` is out of scope by the code's own trust model (all timelock-set). I did not attack them as hostile.

---

## Would I put my own money in this contract today?

**As an ETH-quoted holder / LP: yes, cautiously** — the live ETH-only config is well-defended and I could not steal from it. **As a staker or OG holder on the first non-ETH generation: not until B-01 is fixed** — you would silently forfeit your perp-fee dividend to a dead balance, and B-02 would likely brick opens on a 6-decimal quote. The protocol is close, and the gap is entirely on the multi-quote paths it is in the middle of shipping.

---

## 8. What the prior passes missed, and what I missed that they caught

*(written only after findings were locked; prior docs read at this point)*

**The bullseye — B-01 is an incompletely-applied remediation of a known High.** Pass-4's own Q-01 writeup (`EXPLOIT_REPORT_PASS4.md`) enumerated **three** stranding sites and named them explicitly: *"the base share (`CauldronHook.sol:1233`), the anti-snipe surtax (`:1339`), and **the perp fee via `routePerp` (`:1134`)** … `routeSplit`/`routePerp` deliver an ERC20 with `_move` → a plain `transfer` (`FeeRouteLib.sol:89-95`)."* The fix reached `routeSplit` (base + surtax) but **not `routePerp`** — one of the three sites the finding itself listed. The Q-01 regression (`Q01_StrandedGuildDividend.t.sol`) only ever calls `routeSplit`, so it went green while the third site stayed broken. Running blind is what surfaced it: I traced `routePerp` from the code without the "Q-01 → FIXED" label steering my attention away from it. This is precisely the failure mode the engagement was designed to catch — *"a reviewer who reads FIXED allocates no attention there, which is exactly where a defect survives."*

**What the prior pass got that I under-rated.** Pass-4 flagged (Q-03) that the removed `QuoteNotSupported` guard leaves a *money* PoC on the table — perp insolvency/mis-denomination on a non-ETH quote — and correctly noted it "needs a two-currency fork" to demonstrate. My B-02 is the same territory arrived at independently, but I stopped at "fails safe / DoS" because I did not build the fork PoC. Their instinct that there is a real two-currency perp hazard deserves more weight than my Medium/Low framing gives it; the honest status is "unproven, needs the fork I didn't run." They also already caught and fixed the gacha odds unit mismatch (Q-02) that my §4 lead only gestures at, and the off-chain byte-cap / throttle bypasses (Q-05/Q-06) which I explicitly did not audit.

**Net.** Blind review paid for itself on exactly one thing — the surviving `routePerp` site — and that one thing is a real, PoC'd, permanent value-loss bug that a fifth anchored pass would most likely have skipped as "Q-01, fixed, has a regression test."
