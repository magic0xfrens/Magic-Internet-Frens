# Cauldron Perp Engine — Design Spec (v0)

Hook-native, real-price-impact, overcollateralized perps on the eternal token.
**Status: design for review — not yet built.** Perps are the highest-risk
addition to the protocol; this spec is the gate before any money-code.

---

## 0. Architecture (confirmed)

- **One hook, one pool, all iterations.** Every iteration's V4 pool is created
  with the *same* `CauldronHook` address, so the hook already owns fees, NFT
  volume-minting, the crystal gacha, and death detection. Perps become another
  faculty of that same hook — automatically live for **every future iteration**.
- **Satellite contract.** The hook is at 16.2 KB / 24.6 KB. A full perp engine
  won't fit, so it lives in **`PerpEngine.sol`**, a dedicated contract the hook
  (and traders) call. The hook exposes the price/volume it already tracks; the
  engine holds all position state + collateral. (Same pattern as `PoolOps`.)
- **No external oracle.** The hook *is* the price authority. The engine reads a
  short **TWAP of the pool's own price** for liquidation triggers (see §4).

---

## 1. Core principle: perps are REAL, not synthetic

Every open / close / liquidation executes an **actual swap through the pool**, so
positions move the real price. This is the headline feature:

- **Open long** → engine buys token from the pool → **price up**.
- **Open short** → engine sells token to the pool → **price down**.
- **Liquidate a short** → engine buys the token back → **price UP** → the chart
  *pumps* (a real short squeeze). Cascading short liquidations = a real green
  candle, which is on-brand degen energy and rewards holders/longs.
- Every perp swap also pays the **hook fee + anti-snipe surtax**, so perps feed
  the floor vault / genesis dividend just like spot trades.

Trade-off: real swaps cost gas + slippage. Accepted — it's what makes it "real."

---

## 2. Position model (overcollateralized, capped)

A position = `{ trader, isLong, collateralETH, debt, sizeToken, entryMark, openedAt }`.

- **Collateral** is posted in **ETH**.
- **Leverage** capped at **3×** (config, `MAX_LEVERAGE`).
- **Overcollateralized / no bad debt (the safety core):** a position is liquidated
  at a **maintenance margin that is set ABOVE zero equity by enough to cover the
  liquidation swap's own price impact.** Because the liquidating swap moves price
  *against* the position, the margin buffer must exceed the worst-case slippage of
  closing that size. Result: even after the liquidation trade, collateral always
  covers the debt → **the engine can never accrue bad debt.** This is what
  "overcollateralize to avoid any exploit" means in practice — not leverage ≤ 1×,
  but *liquidate early enough, accounting for slippage, that solvency is
  guaranteed.*

### Where the leverage capital comes from — the Perp Liquidity Vault (PLV)
- A long borrows `(L−1)·C` **ETH** from the PLV to buy `L·C` of token.
- A short borrows **token** from the PLV to sell it.
- The PLV is seeded + grown by: **opening fees, liquidation penalties, funding
  payments**, and (optionally) a treasury seed. It holds both ETH and token.
- **Open interest is capped to what the PLV can fund.** Early in an iteration the
  PLV is small → OI is tiny → perps are effectively throttled at launch (this
  dovetails with the warmup in §5). As fees accumulate, OI capacity grows. The
  system can never lend more than it holds → no insolvency from over-lending.

---

## 3. Fees & revenue routing (per your spec)

- **Opening fee** — deliberately *expensive* (`OPEN_FEE_BPS`, e.g. 1–2% of
  notional) to make leverage a considered choice, not a spam toy. Discourages
  open/close churn manipulation.
- **Liquidation penalty** — a % of the liquidated collateral.
- **Both route to: OG MiFrens dividend + treasury**, split by a config bps
  (e.g. 60% dividend / 40% treasury). Funding payments net between traders; any
  house edge also flows to dividend + treasury.

So OGs earn from perp fees + liquidations on top of spot fees, forever.

---

## 4. Liquidation trigger — the hook is the oracle (your insight)

You were right: no external oracle. The distinction that matters:

- **Legitimate liquidation** (real order flow pushes price past your maintenance
  mark) → liquidate. The hook's own price handles this natively.
- **Flash-manipulation** (a whale moves the shallow pool for one block, then
  reverts, purely to farm liquidations) → **must be ignored.**

Defense = read a **short TWAP** (time-weighted average over N blocks/minutes) of
the pool's *own* price as the **liquidation mark**. A one-block flash-move barely
dents a TWAP, so it can't trigger a liquidation; a *sustained* real move does.
Layered defenses already present: every manipulation swap pays the hook fee twice
(both legs) + the anti-snipe surtax, raising the attack cost on top of the TWAP.

**Anti-cascade:** liquidations execute real swaps that move price, which could
chain (short squeeze). This is desirable but must be *bounded* — cap the token
volume liquidated per block (`MAX_LIQ_PER_BLOCK`) so an attacker can't engineer an
unbounded single-tx cascade. Cascades still happen across blocks (exciting), just
not weaponizable in one atomic tx.

---

## 5. Warmup — no perps the second a token goes live (your spec)

A brand-new iteration has: no TWAP history, minimal PLV, and a price that only
moves up (launch buys) — max-long "can't fail," which is exactly the unsafe
setup. So:

- **`PERP_WARMUP`** — perps cannot open until `block.timestamp ≥ summonAt +
  WARMUP` (e.g. 24–72h), AND until a **minimum TWAP window + PLV size** exist.
- This guarantees a real price is established, the pool has depth, and the PLV has
  fee-funded capacity before any leverage is allowed.

---

## 6. Death cycle — force-close, no migration (your spec: "super not exploitable")

When `relaunch()` fires (the token dies → next iteration summoned):

1. **All open positions are force-closed at the final TWAP mark.** No migration —
   carrying positions across iterations is complex and exploitable (open a giant
   position right before death to game the rebirth), so we simply **don't**.
2. Because positions are overcollateralized (§2), force-close is always solvent:
   each trader's `collateral ± realized PnL − fees` is computed and made
   claimable. No one is left with bad debt.
3. **Residual sweep:** the PLV's leftover balance for the dead iteration (house
   edge, unclaimed dust, funding residue) sweeps to **treasury + dividend**, and
   any un-withdrawn settled balances after a deadline → treasury. This is the
   "treasury absorbs" behaviour you wanted — the safe, no-loose-ends version.
4. **New iteration starts fresh:** PLV resets, warmup restarts, no positions carry
   over. A trader who wants exposure to the new brew opens a new position after
   its warmup. Clean slate every death.

Guard: positions **cannot be opened once the token is dead / dying** (block opens
when `hook.isDead()` or within a pre-death window), so nobody can open into a
death to grief the settlement.

---

## 7. Safety invariants (must all hold)

1. **No bad debt:** `Σ debts ≤ Σ (collateral + PLV)` at all times — enforced by
   slippage-aware early liquidation. The engine can never owe more than it holds.
2. **OI ≤ PLV capacity:** cannot lend what it doesn't have.
3. **Liquidation is permissionless + incentivized** (keeper reward from penalty),
   so underwater positions always get closed.
4. **TWAP-marked triggers** — no single-block price can liquidate.
5. **Per-block liquidation cap** — no atomic cascade weaponization.
6. **Warmup + not-dead gates** — no leverage at launch or into a death.
7. **Reentrancy:** all state settled before any external ETH/token send (CEI +
   nonReentrant); perp swaps go through the pool lock.
8. **The migration reserve is never touched** — perps use the PLV, not the
   reserve owed to migrators.

---

## 8. Attack analysis (the ones that kill perp DEXs)

| Attack | Defense |
|---|---|
| Flash-move price to farm liquidations | TWAP mark + swap fees on both legs |
| Open→cascade-liquidate own counter-side in one tx | per-block liquidation cap |
| Over-lever a thin launch pool | warmup + PLV-capacity OI cap |
| Open huge position right before death | opens blocked pre/at-death; force-close at mark |
| Drain via bad debt | slippage-aware early liquidation → provable solvency |
| Use reserve tokens as leverage source | reserve is off-limits; PLV only |
| Funding-rate gaming | funding nets between traders, capped rate |

---

## 9. What this costs to build (honest)

This is, effectively, a mini perp-DEX: position accounting, a lending vault,
funding accrual, a slippage-aware liquidation engine, TWAP maintenance, and the
death-settlement lifecycle. It is **larger + riskier than everything else in the
Cauldron combined**, needs its **own audit**, and should ship in phases:

- **Phase 1 ✅ (commit 9d9e99a)** — `PerpEngine` skeleton: position storage,
  open/close **longs only**, real swaps, opening fee → dividend/treasury, tiered
  leverage by active-ETH depth, per-position notional cap, liquidation guard.
  4 fork tests on live V4.
- **Phase 2 ✅** — **SHORTS** (reflexive squeeze: sell on open → price down; buy
  back EXACTLY the borrowed token on close → price up + inventory made whole) +
  a **two-sided PLV** (`plv` ETH for longs, `plvToken` inventory for shorts,
  seeded by a supply allocation via `fundPlvToken`) + **per-side OI caps**
  (`maxOiBps` of depth, plus long OI ≤ PLV ETH / short OI ≤ PLV token — can't
  lend what it doesn't hold) + a **funding index** (`fundingIndex` accrues on the
  net long/short imbalance × elapsed; the crowded side pays, accruing to the PLV
  to tether OI toward balance). 5 fork tests on live V4 (adds
  `test_OpenShort_MovesPriceDown_AndCloses`, proving inventory conservation).
- **Phase 3 ✅ (hardening)** — **TWAP MARK**: an on-chain observation ring
  (`observations[64]`, `poke()` + auto-writes on every action) → `twapTick()` /
  `markSqrtPriceX96()`; liquidations trigger off the TWAP (spot fallback during
  the cold-start window), so a single-block flash-move can't farm liquidations
  (execution still swaps at spot). **PER-BLOCK LIQUIDATION CAP** (`maxLiqBps` of
  depth per block) blocks an unbounded atomic cascade. **DEATH FORCE-CLOSE**:
  opens revert `TokenDead` once `hook.isDead()`, and `forceCloseDead(id)` lets
  anyone solvently, penalty-free close any position so nothing is trapped across
  a relaunch. Frontend views `stats()` + `positionHealth(id)` + `isLiquidatable`.
  **Also fixed a latent price-orientation bug** (`_quoteEth`/`_ethToToken` were
  inverted — `size×price` instead of `size/price`; Phase-1/2 tests only checked
  conservation + direction so didn't catch it). **9 fork tests on live V4**
  (adds flash-crash-ignored, sustained-crash→liquidate→PLV-solvent+keeper-paid,
  death-blocks-open+force-close, per-block-cap-throttles).
- **Phase 3 leftovers ✅ (fixed)** — (1) **Funding is now a real transfer** via
  the PLV: the crowded side PAYS in, the underweight side RECEIVES out, bounded to
  ±`maxFundingBps` of collateral (default 50%) and notional pinned to entry so it
  can't be gamed by moving spot; solvent because the crowded (larger) side always
  pays ≥ what the underweight side draws. (2) **Death force-close is incentivized**
  — `forceCloseDead` pays the caller a keeper reward, so bots clear every position
  the instant a token dies, before a relaunch can strand it. (3) **TWAP oracle
  hardened against ring-flooding** — observation writes are time-throttled
  (`OBS_INTERVAL` 30s, ring `OBS_CARDINALITY` 128), so filling the ring takes
  ~68 min regardless of block time; plus an oldest-observation fallback that still
  requires ≥ `MIN_TWAP` (5 min) of span — a flash-move can NEVER become the mark.
  `poke()` now also accrues funding so keepers keep everything fresh.
- **Still deferred (non-blocking):** PLV `plvTarget`/overflow-to-60-40 economics;
  a fully registry-integrated pre-relaunch force-close (the incentivized
  death-window close covers it in practice — the ETH backing longs physically
  sits in the pool, so a post-liquidity-removal settle needs registry cooperation).
- **Phase 4** — dedicated security audit + LaTeX, then mainnet.

### Manipulation-resistance summary ("not worth it")
- **Flash-move → farm liquidations:** blocked — TWAP mark (≥5 min), spot only for
  execution; both swap legs pay hook fee + anti-snipe surtax.
- **Flood the oracle ring → force spot fallback:** blocked — 30s write throttle +
  128-slot ring + 5-min oldest-fallback floor (test: `test_Twap_ResistsRingFlood`).
- **Atomic liquidation cascade:** blocked — per-block ETH-notional cap (`maxLiqBps`).
- **Move price with a big position:** bounded — per-position notional ≤ 5% of depth
  and per-side OI ≤ 30% of depth, so round-trip slippage < the 6.9% open fee.
- **Game funding:** bounded — accrues over time (dt), notional pinned to entry,
  capped at ±50% collateral, and the 6.9% open fee dwarfs any realistic harvest.
- **Over-lever a thin/young pool:** blocked — 24h warmup + depth-tiered leverage +
  opens revert once dead.
- **Bad debt / vault drain:** blocked — long OI ≤ PLV ETH, short OI ≤ PLV token,
  slippage-aware early liquidation (proven solvent + keeper-paid on a real crash).

Each phase is independently testable against live V4 on Sepolia (as we've done).

---

## 10. Parameters — LOCKED (all tunable by deployer post-deploy)

- **Leverage:** NOT a fixed cap — a **tiered auto-cap by active-ETH depth (TWAP)
  × a deployer ceiling**; effective = `min(autoTier, deployerCeiling)`, both must
  agree. Tiers are **config/tunable** (deployer sets the ETH thresholds).
  Starting tiers: `<25Ξ→2×, 25–100Ξ→3×, 100–300Ξ→4×, 300+Ξ→5×`; deployer
  ceiling starts at **3×**. Safe because the active LP is protocol-owned (users
  can't add/remove liquidity to inflate the depth) and the depth is read via TWAP.
- **Open fee:** **6.9% of COLLATERAL** (usable, keeps the 69 meme — 6.9% of
  notional would start a 3× position ~20% underwater and kill the feature).
  **Halved for genesis MiFren holders** (tunable discount). → 60/40 OG/treasury.
- **Liquidation penalty:** **6.9%** of the liquidated position → 60/40
  OG/treasury (a slice retained in the PLV until the tank is full — see below).
- **Fee split:** **60% OG dividend / 40% treasury.**
- **PLV bootstrapping:** seed **~3% of the raise** (~0.7 Ξ on a 24.66 Ξ launch)
  so leverage is alive at warmup; it then self-funds from the **house edge**
  (liquidation penalties + funding residue + losers' residual) up to a
  **`plvTarget` ≈ 10% of active-ETH depth**; overflow above target flows to the
  60/40 split. The PLV only needs to cover the **net long/short imbalance**, not
  total OI, and the funding rate pushes OI toward balance. Never topped up again.
- **Warmup:** `PERP_WARMUP` (24–72h, tunable) + min TWAP window + min PLV before
  any open.
- TWAP window (~30 min), `MAX_LIQ_PER_BLOCK`, slippage-aware maintenance margin
  — set in Phase 2.

## 11. The PLV in one sentence
Leverage means fronting the capital *beyond* your collateral (a 3× on 1 Ξ needs
2 Ξ fronted to buy 3 Ξ of token); the PLV is the shared pot that fronts it, only
has to cover the *net* long/short imbalance (funding balances the rest), is
seeded small from the raise, and self-fills from the house edge — so perps are
revenue-positive AND self-collateralizing, they just need a starter tank.
