# Blind Red-Team — Magic Internet Frens / The Cauldron (session 2: B-05, B-06)

**Date:** 2026-09-09
**Engagement:** blind (no prior audit material read before findings were written)
**Tree audited:** branch `fix/b01-perp-guild-strand` @ working tree
**Baseline suite:** 524 pass / 1 fail / 1 skip before my tests; the single pre-existing failure is my own B-05 invariant.

**Filename note.** `audit/BLIND_REDTEAM_2026-09-09.md` and `audit/BLIND_REDTEAM_2026-09-09_B0x.md` both already existed. This file is written alongside them, unread, to avoid clobbering. The comparison section is deferred to the end per protocol.

---

> ## REMEDIATION STATUS — applied after §1–§8 were written
>
> **Both findings are FIXED, plus lead L-3.** The goal set for the fix pass was a single property: **`relaunch()` must never revert in a way that rolls back `markConsumed`** — because that rollback is what turns any failed step into a permanent, unrecoverable freeze.
>
> | Layer | Change | File |
> |---|---|---|
> | Proposal boundary | `propose()` refuses a non-native quote — a revert here is free | `cauldron/CauldronGovernor.sol` |
> | Consumption | `specQuote` clamped to `address(0)`; the governor is swappable so it cannot be the only defence | `CauldronRegistry.sol` |
> | Landmine removal | `setLiveKey` no longer asserts a native currency0 | `CauldronHook.sol` |
> | B-06 root | proposer carve is native-only; the skipped slice falls to `relaunchAsset[]` | `CauldronHook.sol` |
> | L-3 | `hook.releaseRelaunchETH()` and `vault.close()` wrapped in try/catch | `CauldronRegistry.sol` |
>
> **EIP-170 headroom went UP** despite two added try/catch blocks — registry **10 → 107 B**, hook **22 → 31 B**, governor **+198 B** — because the clamp and the landmine removal are both byte-negative.
>
> **Suite: 536 pass / 0 fail / 1 skip** (537 total). No pre-existing test was weakened or removed; none regressed. Every fix was verified **load-bearing** by reverting it individually and confirming the matching regression goes red with the original failure signature (`TRANSFER_FROM_FAILED`, `SendFailed()`, `vault: no`, `315000000000000000 > 300000000000000000`).
>
> **Scope, stated honestly:** this does **not** implement a non-ETH rebirth. It converts an unimplemented path from *bricking* to *degrading*. See §9 for exactly what remains unbuilt.

**Scope correction, stated up front.** The engagement brief describes "roughly 50 modified files, 2 deleted contracts, and several untracked ones." The actual working tree is 3 modified `.sol` files, 1 dirty submodule pointer, and 4 untracked files. There are **no deleted contracts** — I searched for dangling references and found none. `test/attacks/` already contained `A0x`/`Y0x`/`Z0x`/`Q0x`/`B01`–`B04` suites plus a partial report. This is a **continuation** of a blind engagement, not a cold start. I treated B-01…B-04 as spent ground, audited the three uncommitted diffs as unreviewed code, and hunted from B-05 forward.

---

## 1. Verdict (ten lines)

The core money paths are carefully built and I could not break them: I failed to drain the fee reserve, failed to mint a free NFT, failed to liquidate a solvent position, and failed to poison the perp mark. `FeeRouteLib` checks ERC20 return values and clears stray allowances; the TWAP has a `MIN_TWAP` floor and a flood-proof ring; the C-01 adoption gate genuinely holds; the F-13 exemption gate genuinely holds.

The failure is not in the money math — it is in the **multi-quote generalisation, which is half-built and unguarded**. The protocol advertises three quote assets in its live manifest and can survive exactly one of them. A relaunch naming any non-ETH quote hits three consecutive unimplemented steps, each an unguarded revert sitting *behind* `governor.markConsumed`, so the failed proposal keeps winning and the machine is bricked **permanently** (B-05, Critical). Separately, the proposer fee slice accrues in the fee's asset and pays out in native wei, which both overpays the proposer and eats the ether backing `relaunchETH` — reaching the same permanent brick from a second direction (B-06, High).

One honest qualifier, which I credit to the prior pass rather than to myself (see §8): the live manifest ships `deathThresholdEth: 0`, so `isDead` is permanently false and `relaunch()` cannot fire on-chain **today**. B-05 is therefore "Critical on the first day the protocol actually operates" rather than "Critical this minute." It must be rated Critical regardless, because setting a working death threshold is not an optional configuration change — it is the protocol's core loop.

Three things stand between this and mainnet: **(1)** make every step of `relaunch()` total — either implement the quote conversion + non-native seed + non-native `setLiveKey`, or refuse a non-ETH quote at *proposal* time where a revert is harmless; **(2)** denominate `proposerOwed` per-asset like every other sink in the same function already is; **(3)** get a fork test that drives a full relaunch against an ERC20 quote — its absence is why both findings survived four prior passes.

**Would I put my own money in this contract today?** See the final line.

---

## 2. The value map

### Sinks — where value rests

| Sink | Contract | Denomination | Exit | Who can trigger |
|---|---|---|---|---|
| `relaunchETH` | `CauldronHook:255` | native wei, **counter-tracked** | `releaseRelaunchETH` | registry only |
| `relaunchAsset[a]` | `CauldronHook:2263` | per-asset, counter-tracked | `releaseRelaunchAsset` | registry only — **no caller exists** (§4) |
| `legacyBuffer` | `CauldronHook:287` | native only (guarded `:1208`,`:1230`) | `legacyBuyStep` self-call | in-swap, threshold-gated |
| `proposerOwed[p]` | `CauldronHook:463` | **mixed — B-06** | `claimProposerFees` | the proposer |
| `legacyOwedToReserve` | `CauldronHook:301` | iteration token | `sweepLegacyReserve` | `legacyRegistry` |
| dividend pot (ETH) | `MiFrensDividend:accPerShare` | native | `claim` / `withdrawOwed` | enchanted genesis holders |
| dividend basket | `MiFrensDividend:accPerShareOf` | per-asset, ≤3 assets | `claimTokens` / `withdrawOwedToken` | enchanted genesis holders |
| PLV (ETH + token) | `PerpEngine:280,281` | generation quote | vault withdraw / settlement | vault, traders |
| `insuranceEth` | `PerpEngine:210` | quote | absorbs bad debt; `skimInsurance` | owner |
| floor vault | `CauldronVault` | native | `redeem` | NFT holders — **dormant**, `setVault(0)` |
| reserve LP band | out-of-range V4 position | iteration token | `redeemOgFren`, `claimByBurn` | OG holders, migrants |

### Flows — fee in, value out

```
swap ──▶ _takeEthFee (CauldronHook:1316)
          │  poolManager.take(feeCur)      feeCur = quote side, ANY asset
          │  _feeAsset := quote            :1349
          ├── base fee
          │     ├─ sender == perpEngine ──▶ _routePerpFee   30% guild / 70% stakers
          │     └─ else ─────────────────▶ _routeEthFee
          │            ├─ proposerBps off the TOP  :1164   ◀── B-06: NO asset check
          │            ├─ IFeeRouter (fallback-guarded)
          │            ├─ guildBps  ──▶ FeeRouteLib.routeSplit   (asset-aware)
          │            ├─ floorBps  ──▶ vault, or folded to reserve if non-native
          │            └─ residual  ──▶ _creditReserve            (asset-aware)
          └── surtax ──▶ 100% guild, else _routeEthFee
```

Every branch below the proposer carve is asset-aware. The proposer carve is not.

### Authorities

| Role | Reaches | Constraint |
|---|---|---|
| hook `owner` | tax/odds/curve/weights, `setSnipeParams`, policies, `proposeRegistryOverride` | `setRegistry` one-shot; override has 7-day announce (`REGISTRY_SWAP_DELAY`) |
| `registry` (on hook) | `setCollection`, `setVault`, `setLiveKey`, `setOpener`, `setTaxExempt`, `linkVolume`, both release paths | the registry contract itself |
| registry `owner` | `setAllowedQuote`, `setGovernor`, `setFactory`, `setGenesisBonus` | quote must sort below `QUOTE_WATERMARK` |
| `governor` | names the next brew: name, symbol, supply, renderer, **quote**, proposer | supply clamped `:821`; quote re-checked `:811` — **but see B-05** |
| `treasuryGovernor` | approves a rotation envelope (destination + bps) | `rotateSlice` execution is **permissionless** within it |
| perp `owner` | fees, risk, tiers, routing, `skimInsurance` | `MAX_OPEN_POSITIONS` is `constant`, deliberately unconfigurable |
| **anyone** | `relaunch`, `resolveTickets`, `materializeLegacyReserve`, `rotateSlice`, `arbStep`, `poke`, `forceCloseDead`, liquidation sweep via any swap | the lifecycle attack surface |

---

## 3. Findings

### B-05 — CRITICAL — Any non-ETH relaunch permanently bricks the machine

**PoC:** `contracts/solidity/test/attacks/B05_NonEthRelaunchBrick.t.sol` — 1 failing invariant, 5 passing (2 attack, 1 control, 1 recovery, 1 isolation).

**Locations:** `CauldronRegistry.sol:787`, `:920`, `:1503`; `CauldronHook.sol:1642-1646`; `PoolOps.sol:194`,`:504-541`.

**Mechanism.** The multi-quote relaunch path is unimplemented, and every way it fails is an unguarded revert. Three independent walls; clearing one only advances to the next.

*Wall 1 — the value is never converted, and never rescaled.* `relaunch()` accumulates the dead generation's value as native wei:

```solidity
uint256 totalETH = ethFromLP + ethFromHook + vaultSwept;              // :787
poolId = _seedGeneration(token, newActive, totalETH, newReserve, newGen); // :920
```

That figure is handed to the seeder as the **quote** amount. Nothing converts ETH into the new quote — `QuoteRotator` exists for exactly this job and `relaunch()` never calls it — and nothing rescales units. Measured on the fork:

```
ERC20InsufficientBalance(registry, 0, 19999999999999987150)
```

`19999999999999987150` is the 20 ETH recovered from the dead pool, requested verbatim as USDG. Note the decimals hazard riding along: live USDG is 6 decimals, so a registry that *did* hold the balance would request 20 trillion USDG **and price the newborn pool from it**.

*Wall 1b — the green candle settles native ether into an ERC20 pool.* Fund the registry and the pull succeeds; `PoolOps.createAndSeedWithBuy` then runs the first-block buy, which settles native ether while `currency0` is an ERC20. A currency delta is left open → `CurrencyNotSettled()`. The hook guards this exact limitation on its own buyback with an early return (`CauldronHook.sol:950-960`, "ETH-LAYOUT ONLY, for now"); the seeder does not guard it at all.

*Wall 2 — the hook refuses to record a non-native live key.*

```solidity
function setLiveKey(PoolKey calldata k) external {          // CauldronHook.sol:1642
    if (msg.sender != registry) revert OnlyRegistry();
    if (Currency.unwrap(k.currency0) != address(0)) revert ZeroAddress();
```

But `PoolOps` puts the quote at `currency0` by construction (`:194/250/324`) and mines the token to sort above it (`deployTokenAbove`), so for any ERC20-quoted generation `currency0` is the quote and this always reverts.

**Why it is permanent.** All three walls sit behind `governor.markConsumed(winId)` (`:825`). The revert rolls consumption back, so the proposal stays unconsumed, keeps winning `CauldronGovernor._bestUnconsumed()`, and every future `relaunch()` hits the same wall. Proven across four attempts separated by warps and rolls.

**Exploit scenario.** No attacker required — this is the *advertised* path. `indexer/deployments/round.json` ships USDG (`0xeDFd2eA3…`) and xNVDA (`0x4F3Df1F4…`) as live `quoteAssets` with UI copy inviting it ("Park the LP here when the guild wants out of ETH volatility"). A proposer selecting an offered option freezes the protocol. An attacker's job is only to get such a proposal to win — which costs a proposal and votes, not capital.

**Damage.** Total and permanent: no rebirth, no migration, the reserve never redeploys, every holder stranded. Attacker cost ≈ one winning proposal. No capital at risk.

**Recovery** exists but is privileged and timelocked: `setAllowedQuote(q, false, …)` makes `:811` downgrade the spec to native ETH and the rebirth completes. Proven in `test_Recovery_OwnerMustDelistTheQuote`. So the multi-quote feature is **unreachable, not merely risky** — every non-ETH outcome is either a brick or a silent downgrade to ETH the voters did not choose.

**The bitter part.** The surrounding code guards this exact failure class four times, each citing audit C-02: `:803-811` (de-listed quote falls back rather than reverting), `:817-820` (clamp `nftSupply`, "never revert"), `:902-910` (clamp `newActive` against underflow, which would "permanently brick `relaunch()`"), `PoolOps.sol:493-496` (mining failure returns ETH because "a failed relaunch would roll back `markConsumed` and permanently brick the machine"). Every one hardens a path that then hands off to three unguarded reverts.

**Recommended fix.** Two acceptable shapes, in preference order:

1. **Make the path total.** Convert `totalETH` through `QuoteRotator` before seeding; give `PoolOps` a non-native settle branch; generalise `setLiveKey` to accept a quote-at-currency0 key (it already stores the whole key — only the assertion is wrong).
2. **Refuse early, where a revert is harmless.** Reject a non-ETH `spec.quote` in `CauldronGovernor.propose()`, and keep the `:811` downgrade as the belt-and-braces. This is a two-line change that converts a permanent brick into a rejected proposal, and is the correct *immediate* mitigation regardless of whether (1) is ever built.

Whichever is chosen, `_recordSeed`'s `hook.setLiveKey` should be `try/catch`'d like its neighbours — it is the last unguarded call on the most important function in the protocol.

---

### B-06 — HIGH — `proposerOwed` mixes denominations and pays out in ether

**PoC:** `contracts/solidity/test/attacks/B06_ProposerOwedDenomination.t.sol` — 1 failing invariant, 2 passing attacks.

**Locations:** `CauldronHook.sol:1162-1170` (accrual), `:1882-1889` (payout), `:1348-1350` (the take that sets the unit).

**Mechanism.** `_routeEthFee` carves the proposer slice off the top of every fee **before any `_feeAsset` check**:

```solidity
address prop = activeProposer;
if (prop != address(0) && proposerBps > 0) {
    uint256 wantProp = (feeAmount * proposerBps) / BPS;
    proposerOwed[prop] += wantProp;        // units of _feeAsset
```

`feeAmount` is denominated in whatever the fee was taken in — `poolManager.take(feeCur, …)` at `:1350`, where `feeCur` is the pool's quote. The claim is unconditionally native:

```solidity
(bool ok, ) = msg.sender.call{value: amount}("");   // :1886 — WEI
```

Measured: **16500000000000000 xNVDA base units credited → 16500000000000000 wei of real ether paid out.**

Every other sink in the same function was generalised for exactly this reason — guild via `FeeRouteLib.routeSplit` (`:1244`), floor explicitly folded into the per-asset reserve (`:1232-1241`, citing Q-01), residual via `_creditReserve` (`:1146-1151`, citing R-1). The proposer carve sits above all of them and was missed.

**Two harms.**

1. **Overpayment.** For an 18-decimal quote worth less than ether, the proposer is paid `ETH_price / quote_price` times what they earned, in real ether. The live manifest ships xNVDA at 18 decimals. A 6-decimal quote errs the other way (~1e12× *under*pay), so this is unbounded in both directions, not small in one.
2. **Bricks relaunch.** `relaunchETH` is counter-tracked, not balance-tracked — `:249-255` is explicit that "a figure booked here must be ether the hook actually holds". A non-native fee credits `proposerOwed` without adding a wei, so claiming it drains ether backing `relaunchETH`. Once balance < counter, `releaseRelaunchETH()` fails its send and reverts `SendFailed` — and `relaunch()` calls it **unguarded**:

```solidity
if (hook.relaunchETH() > 0) { ethFromHook = hook.releaseRelaunchETH(); }  // :782-784
```

That rolls back `markConsumed` → the same permanent brick as B-05, reached by a second road. Proven in `test_POC_UnbackedReserveBricksTheNativeRelease`, which also asserts the counter is unchanged afterwards, so the state is identical on every retry.

**Reachability.** Does **not** depend on the bricked non-ETH relaunch path. `RedemptionExt.rotateSlice` is permissionless within the treasury governor's approved envelope and calls `PoolOps.openOrAddPair` + `hook.linkVolume` directly (`RedemptionExt.sol:264-278`). Because `PoolOps` is delegatecalled from the registry, `_afterInitialize` sees `sender == registry` and **adopts** the sibling pool, so its fees are collected in the rotation's quote. `activeProposer` is attacker-reachable by construction: anyone may propose, and the winner is pushed to the hook at `CauldronRegistry.sol:844`.

**Profit / damage.** Direct extraction is bounded by `proposerBps` (default 50 = 0.5% of the fee, hard-capped at 500) times the overpayment ratio, and by the hook's ether balance. The larger damage is the brick, which is unbounded.

**Recommended fix.** Mirror `_creditReserve`: key the accrual per asset (`proposerOwedAsset[asset][prop]`) and pay through `FeeRouteLib.send`. If bytecode headroom forbids a second mapping, the cheap correct alternative is to skip the proposer carve entirely when `_feeAsset != address(0)` and let the slice fall through to `_creditReserve` — under-paying the proposer on non-native volume is a rounding-level unfairness; paying them out of the reserve's backing is a brick.

---

## 4. Leads (believed exploitable, not demonstrated)

**L-1 — `releaseRelaunchAsset` has no caller in the entire codebase.** `CauldronHook.sol:1549` is `registry`-gated, and I grepped every `.sol`, the frontend, the indexer and the API: nothing calls it. So a non-native reserve accrues with a door that only a contract lacking the key can open. Combined with B-05 this means fees collected by a rotated (USDG/xNVDA) sibling pool are, in practice, stranded today. *Next step:* confirm no registry function reaches it (I read `CauldronRegistry.sol` and found none), then add a registry entry point and a test that rotates, accrues, and releases.

**L-2 — `QuoteOracle` freezes the last good price forever.** `cachedUsdPerRawUnit` (`:192-199`) refreshes `c.at` on every attempt but only overwrites `c.factor` when the fresh read is non-zero. A permanently broken feed therefore serves the last good factor indefinitely. Documented as deliberate and correct for death detection (fails toward alive) — but volume also drives **NFT mint credit**, so a frozen-high price after a real price crash inflates every trader's credit against a fixed ladder and over-issues the collection. *Next step:* add a hard staleness ceiling (e.g. 24h) past which the factor is zeroed for the *credit* path while death detection keeps failing-alive; assert both directions in a test.

**L-3 — Unguarded external calls remaining on `relaunch()`.** Beyond B-05/B-06: `_removeLiquidity` (`:751`), `IVaultClose(oldVault).close()` (`:777`), `PoolOps.crystallizeCollection` (`:881`), `_deployCollection`/`_continueMiFrens` (`:927-931`). The author clearly knows this class — `_perpHousekeep` and `resolveTickets` are both `try/catch` + gas-capped, citing Z-07. `close()` is currently safe only because the vault is dormant and the registry has a `receive()` (`:501`); a donation to the vault re-arms the send. *Next step:* fuzz each with a hostile stand-in and assert `relaunch()` still completes.

**L-4 — `MAX_ASSETS` comment/code disagreement.** `MiFrensDividend.sol:124` sets `MAX_ASSETS = 3`; the comment at `:457` says "why MAX_ASSETS is 4". The uncommitted `MiFrensGenesis` diff re-sizes the gas budget explicitly "keyed to MAX_ASSETS = 3". A stale comment here is the kind that gets trusted during a later change. Informational, but it sits on the B-02 coupling.

**L-5 — serverless rate limits are per-warm-instance.** `fren-ask.ts:109` and `fren-teach.ts:45` both use an in-memory `Map`, which resets per cold start and is not shared across instances. `fren-teach.ts` is honest about this in its own comment ("real distributed limiting belongs in the WAF"). Cost amplification on `fren-ask` is bounded by the 800-char question and 6-message history, so this is Low. *Next step:* move both to a shared store or a WAF rule before the LLM routes carry real spend.

---

## 5. Proven-safe — what I attacked and could not break

| Target | How hard I hit it | Result |
|---|---|---|
| **Fee-exemption forgery (F-13)** | Traced `_isExemptPlayer`/`_taxedPlayer` (`:2205-2217`) and read `CauldronGachaRouter` end to end looking for a path that forwards caller-controlled `hookData` | **Held.** The router always sets `d.player = msg.sender` (`:325`, `:367`); exemption additionally requires `isOpener[sender]`. No path lets a direct swapper name another player. |
| **`FeeRouteLib` value routing** | Read every send path for unchecked returns, stranded allowances, and reverts-into-swap | **Held.** Return values checked (`:110`,`:178`), allowances cleared on failure (`:134`,`:150`,`:211`), nothing reverts. Genuinely good code. |
| **Perp mark poisoning (A-02)** | Read `_writeObs`/`twapTick` for the stale-`lastTick` round-trip; checked ring flood-resistance and the `MIN_TWAP` floor | **Held.** `lastTick` is refreshed unconditionally (`:580`); ring appends throttle on a separate clock (`lastRingTs`), so the ring cannot be evicted. `uint32` deltas are `unchecked` per F-10. |
| **Dividend basket poisoning (D-1/D-2/D-3)** | Looked for an unbounded/attacker-chosen asset list and a single-token claim brick | **Held.** `fundToken` is `funder`-gated (`:278`), list capped at `MAX_ASSETS`, failed legs bank to `owedAsset` instead of reverting the whole claim (`:319-328`). The absence of `removeAsset` is correctly argued at `:206-230`. |
| **Free NFT via pity counter** | Worked the `missStreak`/`pityThreshold` math in `_resolveTickets` (`:2140-2159`) for a cheap guaranteed mint | **Held.** Pity is per-player and every crystal costs curve credit; 9 crystals-per-guaranteed-NFT is *worse* than a large play's ~1.1. Sybils gain nothing — credit is bought with volume and fees. |
| **Secrets in the client bundle** | `grep` over `dist/` for key patterns; checked `.gitignore` coverage of every `.env*` | **Clean.** The only match is a third-party analytics lib's runtime `Bearer ${jwt}` template, not a baked credential. `.env.local` and `.env.vercel-backup` are both ignored by `.gitignore:61`. |
| **Admin secret comparison** | Checked `fren-teach.ts` for length leaks / non-constant-time compare | **Held.** sha256-then-`timingSafeEqual` (`:31-35`), fail-closed when unset (`:86`). |
| **Native reserve solvency on a pure-ETH deployment** | Enumerated every native inflow/outflow against `relaunchETH + legacyBuffer + Σ proposerOwed` | **Held.** Every native outflow is counter-backed. B-06 needs a non-ETH pool to break it — which is why I stated that reachability constraint rather than claiming it on the live config. |

---

## 6. Coverage gaps, ranked by the value behind each

1. **No test drives a relaunch with a non-ETH quote.** Both fork governors hardcode `quote: address(0)` (`YBase.YGov:306`, `ZAuditBase.ZMockGovernor:225`). `test/QuoteAllowlist.t.sol` covers only the setter — its own header says *"Phase 1 … Nothing reads"* it. **This single gap hides B-05, which is total protocol loss.** A governor stub with a settable quote is ~20 lines and would have caught it in the first pass that added the feature.
2. **No test sets `activeProposer` on a non-native fee.** `test/audit/AuditPoC6_QuoteReserve.t.sol` is the only test driving a non-native fee and never sets `activeProposer` or `guild`, so `wantProp` is always 0. Its closing assertion `relaunchAsset[USDG] == held` passes *because* the proposer slice is absent — a test that is green for the wrong reason. Hides B-06.
3. **`releaseRelaunchAsset` is tested only by calling it directly as a fake registry.** `AuditPoC6` makes the *test contract* the registry, so it proves the function works but not that anything reaches it. Hides L-1.
4. **`rotateSlice` has no adversarial test.** It is permissionless, creates an adopted pool, and links volume — the entry point for B-06's reachability — and I found no attack suite against it.
5. **Names that promise more than the body delivers.** `Y03_RelaunchGasBrick.test_FIXED_Z07_FullBookRelaunchSurvivesAGasCap` asserts the rebirth survives a *gas* constraint; nothing in the file constrains any other relaunch failure mode, so "relaunch survives" is much narrower than the suite name suggests. `QuoteWatermarkInvariant.t.sol` pins the address-ordering invariant but not that an ordered pool can actually be *launched*.

---

## 7. Blind spots — what I could not reach

- **I did not read any prior audit material before writing §1–§6.** I did read Solidity comments citing findings by ID, which I treated as unverified author claims. Two of them (`:803-811` and `PoolOps:493-496`, both citing C-02) turned out to be *correct in isolation and defeated downstream* — which is how B-05 survived.
- **Fork tests ran against Sepolia only**, at an unpinned head for `YBase` (`ZAuditBase` pins; `YBase` does not). Timing-sensitive results could differ. I did not test on an Arbitrum/Orbit fork, so the L2 clock and `block.number` behaviour behind Z-05 is unverified by me.
- **I did not run the indexer, the frontend, or Cypress.** I read `round.json` and grepped the built bundle, but I never observed the UI under a stale/lying/unreachable indexer, which the brief explicitly asks about. That surface is unaudited by this pass.
- **I did not audit `render/*.sol`, `MigrationVesting`, `CollectionLedger`, `TreasuryGovernor`, or the `deploy/*.s.sol` wiring order** beyond what B-05/B-06 forced me through. Deployment wiring order is named as attack surface in the brief and I did not reach it.
- **`PerpEngine` got a structural read, not an adversarial one.** I verified the TWAP/mark hardening and the funding cap, but did not attempt a full solvency attack on the two-sided PLV, the `maxUtilBps` accounting, or a cross-block liquidation cascade. The largest single value sink in the protocol is therefore under-attacked by me. `A02_PerpAttacks` and `Z02_PerpStaleMark` cover part of this; I did not independently re-derive their claims.
- **I did not attempt formal invariant fuzzing.** The existing `test/invariants/` suites pass; I read their assertions but did not extend them.
- **B-06's overpayment magnitude is asserted structurally, not priced.** I proved the unit confusion and the resulting brick with exact numbers; I did not model a real xNVDA/ETH price to put a dollar figure on the extraction.

---

## 8. What the prior passes missed, and what I missed that they caught

*(Written only after §1–§7 were locked. Prior docs read at this point.)*

### The bullseye: the previous pass documented B-05's mechanism and read its sign backwards

This is the sharpest result of the engagement, and it is not "they missed it." The immediately-prior blind pass (`BLIND_REDTEAM_2026-09-09_B0x.md`) **found the exact line** and recorded it in its value map as an established fact:

> `_liveKey` is **always ETH-quoted** — `setLiveKey` reverts unless `currency0 == address(0)` (:1631). The live/primary pool is native; USDG/xNVDA are for **sibling** pools and treasury denomination.

It then filed the constraint as a **safety property to preserve**, as its finding #4 (Low) and lead #3:

> **Next step:** treat as a regression tripwire — assert `setLiveKey` rejects non-ETH `currency0` in a test tied to the credit gate.

That recommendation, if implemented, would have **pinned the brick in place with a passing test**. The revert is not a guard protecting the credit gate; it is an unimplemented branch on the mandatory path, and `CauldronRegistry.sol:811/837` contradicts the "sibling pools only" premise directly — `spec.quote` becomes `generationQuote[newGen]`, which is the **primary** pool's quote, fed straight into `_seedGeneration`.

To its real credit, that pass's verdict line hedged precisely: *"sits one `setLiveKey` guard away from bricking a non-ETH relaunch"* — and flagged it for "independent re-review." It named the risk and declined to price it. I ran the fork test it did not, and the answer is that it bricks three ways, not one, and permanently. The difference between us is not insight; it is that I wrote the governor stub with a settable `quote`.

**A correction I owe them, in their favour.** Their tripwire worried that relaxing `setLiveKey` would re-open Z-09, because a non-ETH live pool might put "the token at currency0" and make the credit gate compare the shared quote instead of the unique token. That specific hazard does not exist: `PoolOps` places the token at `currency1` in all four pool constructors (`:195`, `:251`, `:325`, `:672`), and `deployTokenAbove` mines it above `QUOTE_WATERMARK` so the ordering is invariant. So the gate at `:791` stays correct under my fix recommendation #1. The coupling they identified is real and worth a test; the failure direction they feared is closed by the watermark.

### What the prior passes caught that I did not

- **The live config currently has relaunch switched off entirely.** Their coverage gap #5 notes `deathThresholdEth: 0` in `round.json`, which makes the built-in rule `vol < 0` permanently false, so `isDead` never returns true and `relaunch()` always reverts `TokenStillAlive` unless a `deathChecker` module is wired. I read that same manifest for B-05's reachability argument and did not connect it. **This is a genuine moderating factor on B-05's severity that I should have surfaced myself**: today, on-chain, the brick is not reachable because the machine cannot relaunch at all. It becomes live the instant the threshold is set to any working value — which it must be for the protocol to function — so I keep the Critical rating, but the honest framing is "Critical on the first day the protocol actually operates," not "Critical right now." B-06's direct overpayment is unaffected and remains reachable via `rotateSlice` today.
- **B-01 (`routePerp` stranding)** — a real, PoC'd permanent value loss I would not have found, since I read `FeeRouteLib` after their fix had landed and correctly judged the post-fix code sound. My "Proven-safe: FeeRouteLib" entry is only true *because of* their pass.
- **B-02 (dividend gas budget)** — the 180k→260k re-sizing in the working tree. I read `MiFrensGenesis`'s diff as context and did not independently re-derive the measurement.
- **Q-02 (gacha odds unit mismatch)** and **Q-05/Q-06 (off-chain byte-cap / throttle bypasses)** — I noted the `_playInCurveUnits` discipline looked internally consistent and moved on; they found and fixed the underlying unit bug.
- **A-02, A-04, C-01, C-02, V-02, F-09, Z-05, Z-07** — the hardening I verified and listed under Proven-safe is theirs. I attacked those seams and they held *because four passes closed them.*

### What I contributed that anchored review would likely not have

Both of my findings live in the same blind spot, and it is a structural one: **every prior pass tested the multi-quote feature at the level of a single function, and none tested it at the level of the lifecycle.** `AuditPoC6` proves a non-native fee is booked to the right counter. `Q01`/`B01` prove the guild leg is accounted. `QuoteAllowlist` proves the setter validates. Each is green, each is correct, and the composition of all three — *actually launching a generation against the asset the allowlist blesses* — was never executed. Both B-05 and B-06 fall precisely in that seam.

The prior pass's own closing line was that blind review "paid for itself on exactly one thing." This one paid for itself on the inverse of that pass's conclusion: the property it recorded as safe and recommended locking down is the one that ends the protocol.

**Net.** Four anchored passes plus one blind pass closed the exploit surface thoroughly enough that I could not steal a wei. The remaining risk is not theft; it is that the protocol's advertised configuration cannot execute its own core loop, and the last reviewer to look at that line read the revert as a feature.

---

## 9. What the fix does NOT do

Stating this plainly, because a remediation section that overclaims is worse than none.

**A non-ETH REBIRTH is still not implemented.** All three legs remain unbuilt: `relaunch()` still does not convert its recovered ether into a named quote, `PoolOps.createAndSeedWithBuy` still has no non-native settle branch, and the reserve/green-candle sizing is still written for one orientation. What changed is the *failure mode*: an unseedable quote is now refused at proposal time and clamped at consumption, instead of reverting behind `markConsumed` and freezing the protocol forever.

**A generation can still be quoted in another asset** — that is `RedemptionExt.rotateSlice`, which is deliberate, governed, reversible, and untouched by this pass. What is no longer possible is staking the machine's ability to be *reborn* on a code path that was never written.

**To re-enable a non-native rebirth**, in order: build the conversion (route `totalETH` through `QuoteRotator` with slippage bounds and a native fallback on failure), give `PoolOps` a non-native settle, then relax the governor refusal and the registry clamp — in that order, with `B07_RelaunchTotality` green at every step. The clamp is one line and is deliberately the last thing to remove.

**Still unguarded on the relaunch path** (accepted, documented, not fixed): `_removeLiquidity` (`:751`), `PoolOps.crystallizeCollection` (`:881`), `_deployCollection`/`_continueMiFrens` (`:927-931`). Each calls a protocol-controlled component and I could not construct a hostile input that reverts them, so guarding them would have cost registry bytes for no demonstrated gain. They are named here so the next reviewer does not have to rediscover the list. `B07_RelaunchTotality` is the place to add a case if one is ever found.

**L-1, L-2, L-4, L-5 are untouched.** In particular L-1 — `releaseRelaunchAsset` still has no caller anywhere in the codebase — is now *more* relevant, not less: with the proposer carve skipped on non-native fees, more value accrues to `relaunchAsset[]`, and that reserve still has no reachable exit. That is the highest-value item remaining and it is a missing registry entry point, not a vulnerability.

---

## Final line

**Would I put my own money in this contract today?**

As a **trader or perp user on the current ETH-only generation**: yes, cautiously. The fee math, the mark, and the liquidation bounds are the work of someone who has thought hard about them, and I attacked them and failed.

As a **holder relying on the machine to relaunch**: before this pass, no — the protocol shipped a three-asset quote menu it could only survive one of, and the failure was not a refund but a permanent freeze with every holder's value locked in a dead generation.

**After the fix: yes, on that specific question.** The freeze is closed at three independent layers, the guarantee is now a named property with a suite that asserts it against hostile components, and every guard was verified load-bearing by reverting it. The machine relaunches when a vault refuses to close, when the reserve cannot be paid, when a swapped governor names an asset that cannot be seeded, and four times consecutively.

I would still hold two reservations, and they are the honest ones: the multi-quote *product* is advertised but not built — it now degrades to ETH rather than bricking, which is safe but is not what the manifest promises — and the perp engine, the largest single value sink here, got a structural read from me rather than a full adversarial one. Those are features to finish and a review to commission, not landmines. The landmine is gone.
