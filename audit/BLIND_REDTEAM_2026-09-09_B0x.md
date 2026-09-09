# Blind Red-Team — Magic Internet Frens / The Cauldron

**Date:** 2026-09-09
**Engagement:** blind (no prior audit material read before findings were written)
**Tree audited:** branch `fix/b01-perp-guild-strand` @ working tree (submodule `openzeppelin-contracts` dirty; no stash)
**Filename note:** `audit/BLIND_REDTEAM_2026-09-09.md` already existed from a prior pass; this file is written alongside it, unread, to avoid clobbering it. Comparison section deferred per protocol.

> **Remediation status (applied after the findings below were written):** B-02, B-03 and the arbStep lead have been FIXED in the working tree. Each finding's section carries a **FIX** subsection. All B0x tests are now green regressions (the invariants pass on the patched code and fail if the fix is reverted), and the full pre-existing suite still passes. Source touched: `cauldron/MiFrensGenesis.sol` (gas budget), `CauldronHook.sol` (surtax), `cauldron/QuoteRotator.sol` (arb cap). The `PerpMarkSource.weightedTick` lead was deliberately NOT changed — see §4.

---

## 1. Verdict (ten lines)

The money paths are, on the whole, carefully built: fee routing checks ERC20 return values, the perp mark is TWAP'd with a `MIN_TWAP` floor, liquidations are per-block-capped, the fee-take is fail-soft inside swaps, and the C-01 adoption gate genuinely stops foreign-pool poisoning. I could not drain the reserve, mint a free NFT, or liquidate a solvent position in one transaction.

But the freshest code in the tree — multi-quote fee distribution — carries a **High**: the genesis-dividend transfer hook no longer fits in the fixed 180k gas the NFT contract forwards to it, once the fee basket holds 3 assets. On an **ordinary, full-gas** transfer the hook silently OOGs, the sold fren stays in `activeShares` forever (diluting every holder, its cut permanently unclaimable), and — the exact states audits M-06 and F-09 were written to prevent — the seller is paid for the buyer's window and the buyer re-enchants free. It needs no attacker and activates on a **supported config change** (a 3rd non-ETH quote). The live manifest already runs 2.

Three things stand between this and "yes": (1) fix the dividend gas budget / basket bound; (2) restore the anti-sniper surtax's entropy (currently dead code — the surtax is fully predictable, B-03); (3) an independent re-review of the `_liveKey`-is-always-ETH assumption against the "park the LP in USDG" product claim, which I could confirm is internally consistent but sits one `setLiveKey` guard away from bricking a non-ETH relaunch.

**Would I put my own money in it today?** As a *trader/perp user*, cautiously yes. As a *genesis NFT holder* relying on the dividend, **not until B-02 is fixed** — a routine transfer can silently and permanently strand your share the moment a third quote is added.

---

## 2. Value map (built from source, not from any doc)

**Where value enters**
- Swap fees, taken on the **quote** side of any tracked pool, in whatever currency the quote is (`CauldronHook._takeEthFee`, :1303-1355). `_feeAsset` records the collected currency.
- Perp collateral / PLV deposits (`PerpEngine.openLong/openShort`), staker deposits (`PerpVault`).
- NFT mint proceeds (`MiFrensGenesis.mint`), re-enchant fees (`MiFrensDividend._collectEnchantFee` → reserve).
- Relaunch green-candle buy (registry), treasury rotations (`QuoteRotator`).

**Where value sits**
- `relaunchETH` / `relaunchAsset[asset]` in the hook — the self-funding reserve for the next generation.
- `MiFrensDividend`: `accPerShare` (ETH) + `accPerShareOf[asset]` (basket) + `owed`/`owedAsset` (settled-unclaimed).
- `PerpEngine`: `plv` (ETH), `plvToken`, `insuranceEth`, open-interest markers.
- `legacyBuffer` in the hook; `CauldronVault` floor.

**Where value leaves, and under whose authority**
| Sink | Mover | Authority | Rotatable? |
|---|---|---|---|
| `relaunchETH/Asset` | `releaseRelaunch*` | `registry` only | n/a |
| dividend claims | `claim*/withdrawOwed*` | NFT owner + enchanter | — |
| perp settlement/bounty | `_settle` | trader / permissionless keeper (capped) | — |
| legacy buyback | `legacyBuyStep` | permissionless, spends into `_liveKey` only (C-01b) | — |
| proposer flywheel | `claimProposerFees` | accrued to `activeProposer` (attacker-settable), pull-only | — |
| treasury rotation/arb | `rotateStep`/`arbStep` | permissionless, governed floor / oracle | — |
| policy/router/oracle swaps | `set*` | `owner`/`registry` (timelock on mainnet) | owner is multisig-behind-timelock |

**Key structural facts I relied on**
- `_liveKey` is **always ETH-quoted** — `setLiveKey` reverts unless `currency0 == address(0)` (:1631). The live/primary pool is native; USDG/xNVDA are for **sibling** pools and treasury denomination. This is what makes the Z-09 `currency1`-only credit gate (:791) safe: the token is the unique per-generation discriminator and it lives at currency1 of the (ETH) live key.
- The dividend basket holds **non-ETH assets only** (ETH has its own accumulator); `MAX_ASSETS = 3`. Live manifest → 2 today (USDG, xNVDA).
- `deathThreshold = 0` in the live manifest ⇒ `isDead` is always false ⇒ no permissionless relaunch is currently possible. Fails safe; owner-tunable later.

---

## 3. Findings

### B-02 — [HIGH] Dividend transfer hook exceeds its forwarded gas budget with a full basket → permanent share stranding + value misdirection on an ordinary transfer

**Location:** `cauldron/MiFrensGenesis.sol:671-675` (the `{gas: GAS_DIVIDEND_FWD=180_000}` forward, :97) vs `cauldron/MiFrensDividend.sol:459-468` (`onMiFrenTransfer` basket settle loop).
**PoC:** `test/attacks/B02_DividendGasBudgetOverrun.t.sol` (invariant fails on current code; PoCs pass).

**Mechanism.** `MiFrensGenesis._update` calls the dividend's `onMiFrenTransfer` with a hard 180k gas cap and swallows any failure in `catch {}`. The F-09 guard (`gasleft() < GAS_DIVIDEND_MIN=240_000 → revert`, :672) bounds what the *caller* supplies; it does nothing about what the *callee* costs. The in-code worst-case estimate ("~39k: one cold `owed` SSTORE plus three cold nonzero updates", :664-666) **predates the fee basket**. The settle loop now walks up to `MAX_ASSETS=3` assets, each costing — when `accPerShareOf[a] > debtOfAsset[id][a]` — two cold zero→nonzero SSTOREs (`owedAsset` 22,100 + `debtOfAsset` 20,000) plus cold SLOADs.

**Measured (cold storage, the real transfer condition):**

| basket assets | `onMiFrenTransfer` gas | vs 180k forwarded |
|---:|---:|---|
| 0 | 53,719 | fits |
| 1 | 103,092 | fits |
| 2 | 152,465 | fits (27.5k margin) |
| **3** | **201,838** | **exceeds by 21,838 → silent OOG** |

~49.4k marginal per asset; the cliff is exactly the 3rd asset.

**Exploit / failure scenario (no attacker needed).** Governance adds a 3rd non-ETH quote (fully supported; `MAX_ASSETS=3` and the D-3 comment explicitly anticipates it — "Three leaves one slot of headroom"). A genesis holder who enchanted before the fees accrued (`acc > d`, the normal lifecycle) transfers their NFT with an ordinary full-gas tx. The hook OOGs inside the catch. Result — precisely the M-06/F-09 states, now on the honest path:
- the sold fren stays in `activeShares`, diluting every honest holder, and its slice of every future deposit is unclaimable and **permanently locked** (PoC: 0.5 ETH locked from one dead share);
- `enchantedBy` still points at the seller, so accrual over the buyer's window is later paid to the **seller** via `_castSpell`'s stale branch (`MiFrensDividend.sol:398-402`; PoC: seller banks 1.05 ETH of the buyer's fees);
- that stale branch skips `_collectEnchantFee`, so the buyer **re-enchants free** and the reserve loses the moved-fren fee.

**Why existing tests miss it.** `F01_CustodyAndConsent._wireDividend` (:260-262) funds **ETH only**, so `assets.length == 0`; `test_F09_TheEntireGriefWindowIsClosed` sweeps a gas window against an **empty basket**. Both stay green (confirmed) — they bound a loop that never runs. `Q01`'s only real `transferFrom` runs from a fresh setUp with an empty basket too.

**Damage.** Permanent, unrecoverable loss of the dead share's dividend stream (no removal path); repeatable seller-takes-buyer's-fees + free re-enchant. Not a one-shot drain, but a standing tax on every holder plus a value-transfer primitive, triggered by a supported config and reachable with zero sophistication.

**Fix options considered.** (a) Raise `GAS_DIVIDEND_FWD`/`GAS_DIVIDEND_MIN` to cover `MAX_ASSETS` cold worst-case; **or** (b) make the settle loop O(1) — bank the leaver's basket entitlement lazily; **or** (c) lower `MAX_ASSETS` to 2 and gate a 3rd quote behind a dividend migration.

**FIX (applied — option a).** `cauldron/MiFrensGenesis.sol:97-98`: `GAS_DIVIDEND_FWD 180_000 → 260_000`, `GAS_DIVIDEND_MIN 240_000 → 320_000`. 260k covers the measured 202k worst case at MAX_ASSETS=3 with ~58k margin; the 60k MIN−FWD gap preserves the F-09 property (the parent still reserves enough to finish after the call, so a genuine child revert is still caught and a starved child now reverts cleanly with `InsufficientGas` rather than settling with broken accounting). Visible cost: transferring an *enchanted genesis* fren now needs ~320k gas — wallets estimate this correctly, and a clean revert beats a silent strand. The budget is now explicitly keyed to MAX_ASSETS with a comment tying the two; `test/attacks/B02_DividendGasBudgetOverrun.t.sol` is the regression that fails if the budget is lowered or MAX_ASSETS raised without it. Chose (a) over the durable (b) because it is a two-constant change that touches none of the sensitive accumulator accounting — lowest risk on the money contract. Recommend (b) as a follow-up if MAX_ASSETS is ever to grow.

**Post-fix verification:** `test_B02_INVARIANT_SettledTransferAlwaysBreaksTheSpell` and all four `B02_Basket{0,1,2,3}` now pass; the F-09 suite (`F01_CustodyAndConsent`, 9 tests) stays green.

---

### B-03 — [LOW] Anti-sniper surtax "entropy" is dead code; the surtax is fully predictable

**Location:** `CauldronHook._defaultSurtaxBps` :1288-1293.
**PoC:** `test/attacks/B03_SurtaxJitterDeadCode.t.sol` (fuzz + closed-form, both pass).

**Mechanism.** `decayed = maxBps*remaining/window`; `rnd = keccak256(…,tick) % (maxBps+1)` so `rnd ∈ [0,maxBps]`; `jitter = rnd*remaining/window`; return `max(decayed, jitter)`. Since `rnd ≤ maxBps` and both terms carry the identical `remaining/window` under the same floor division, `jitter ≤ decayed` **for all inputs** — proven over 256 fuzz runs. `max(decayed, jitter)` is therefore unconditionally `decayed`, and the `keccak256(blockhash, id, block.number, tick)` term — the entire L-02 manipulation-resistance argument, and the comment's claim that "the jitter can only ever RAISE the rate" — contributes nothing on any path.

**Impact.** The surtax collapses to a pure function of block number: `maxBps*(window-elapsed)/window`. A sniper computes the exact rate for any future block and schedules entry — the "no cleanly-predictable cheap block" property does not exist. **Low**, because the deterministic decay still charges a real surtax (defeated defense-in-depth, not a zero-fee bypass). Caveat: this is the built-in curve; a wired `surtaxPolicy` module overrides it (:1256), but the built-in is the documented default/fallback.

**FIX (applied).** `CauldronHook.sol:_defaultSurtaxBps` now returns `min(decayed + jitter, maxBps)` instead of `max(decayed, jitter)`. Because the jitter is *added* rather than compared, it genuinely raises the rate (as the comment always claimed), so a "cheap" late-window block can spike by an amount unknowable at submission (the live tick feeds the keccak). Clamped to `maxBps`; `snipeSurtaxBps` re-clamps to `MAX_SNIPE_BPS` and `_takeEthFee` clamps the *combined* rate to `MAX_TOTAL_FEE_BPS`, so a trade always leaves ≥1% to execute — the raise cannot be weaponised. Cost: +8 bytes of `CauldronHook` bytecode (headroom 30 → **22** bytes — see Blind spots; the hook is now extremely close to EIP-170). `test/attacks/B03_SurtaxJitterDeadCode.t.sol` now proves the jitter is bounded *and live* (there exist inputs where the result strictly exceeds `decayed`, impossible under the old `max`). I deliberately did **not** touch the entropy *source* (the tick's knowability to a first-in-block sniper is the pre-existing, documented L-02 tradeoff) — only made the existing jitter apply.

---

## 4. Leads (believed exploitable / suspicious; not demonstrated)

1. **`QuoteRotator.arbStep` — unbounded `amountIn` contradicted its own safety comment. [FIXED]** `arbStep` (:304) is permissionless and the header claimed "size is bounded per call, so repeated arbs cannot quietly re-allocate the treasury behind governance's back." No size bound existed — `amountIn` was only checked `!= 0` (:308), capped in practice only by the rotator's balance. A keeper could force a full inQuote→outQuote re-allocation of treasury holdings whenever an oracle-profitable spread existed, taking `arbKeeperBps` (≤20%) of the profit each time. Value stays net-positive at oracle prices, so not a drain, but exactly the ungoverned re-allocation the comment says is prevented.
   **FIX (applied):** added `maxArbNotionalUsd` (governance-tunable, default **$25k**, `0` = explicit opt-out) enforced in `arbStep` as `if (maxArbNotionalUsd != 0 && inUsd > maxArbNotionalUsd) revert ArbTooLarge()`, plus a dedicated `setMaxArbNotionalUsd` setter (so `setArbParams`'s signature and its callers are untouched). `test/attacks/B04_ArbNotionalCap.t.sol` pins the config surface.
   **Residual coverage gap:** the enforcement branch is after `poolManager.unlock`, so an end-to-end "over-cap arb reverts" PoC needs a PoolManager mock returning real swap deltas + an oracle; the rotator suite runs against a stub PM, so that PoC is deferred. Branch verified by inspection.

2. **`PerpMarkSource.weightedTick` weights by *current* `getLiquidity()` (:170-179). [NOT CHANGED — deliberate].** The safety claim ("cheapest-to-push pool has least weight") assumes liquidity is fixed, but JIT liquidity is not: push a thin sibling's tick, then add large liquidity to that same pool at that tick to dominate the weight. It feeds the engine's TWAP ring, so single-block manipulation averages away (`MIN_TWAP` floor) — which is why I could not land it. I left the logic untouched on purpose: I could not demonstrate an exploit, and changing the mark math (the input to every liquidation) on an unproven concern risks introducing a real, irreversible bug — the opposite of the fix's intent. **Next step (for the team):** multi-block scenario — hold manipulated JIT liquidity across ≥`twapWindow`, measure whether the weighted mark can be dragged far enough to flip a solvent position underwater before the per-block liq cap and `MIN_TWAP` neutralize it. Requires the mark source actually wired (`markSource`), which it may not be on the live deployment. If demonstrated, the safe fix is time-averaged (not spot) liquidity weights.

3. **`_afterSwap` Z-09 credit gate (:791) is `currency1`-only.** Safe *given* `_liveKey` is always ETH (token at currency1, unique per generation). If a future change ever relaxes `setLiveKey`'s ETH constraint (:1631) so the live pool can be non-ETH with the token at currency0, the gate would compare the *shared quote* instead of the *unique token*, re-opening Z-09 (a dead same-quote generation farming the live collection). **Next step:** treat as a regression tripwire — assert `setLiveKey` rejects non-ETH `currency0` in a test tied to the credit gate, so the two cannot drift apart.

---

## 5. Proven-safe (attacked hard, held)

- **C-01 adoption gate (`_afterInitialize` :575-604).** A third-party pool naming this hook is not tracked (`sender != registry`), so every hot path early-outs. Could not mint phantom `relaunchETH` or steer the buyback via a foreign pool.
- **Perp mark poisoning (A-02).** `_writeObs` always integrates the elapsed interval at the in-force tick and always refreshes `lastTick`; `twapTick` enforces `MIN_TWAP`. The crash-then-restore round-trip cannot freeze a stale tick into the mark. Held.
- **Fee-route return-value handling (`FeeRouteLib`, `MiFrensDividend._pull/_tryPush`).** USDT-style `return false` is checked on every pull/settle; a failed leg banks to `owed*` and the debt marker still advances (no double-count, no silent loss).
- **Gacha randomness (`_resolveTickets` :2097-2151).** Future-blockhash commit-reveal with FIFO re-anchor on expired seed (M-04); roll not grindable at commit and not re-rollable by reverting. `outstandingOf[col]` reservation prevents over-mint past `maxSupply`. No free mint found.
- **Dividend `fundToken` gating (D-1).** Funder-only; an attacker cannot fill the basket with junk to force the MAX_ASSETS wall (this is what keeps B-02 a config/latent issue rather than an attacker-triggerable one).
- **Q-01 / B-01 guild routing.** ERC20 guild share now goes through accounted `fundToken`; a full basket / nobody-enchanted correctly buffers to reserve rather than reverting the swap or stranding (Q01 regression suite green).

---

## 6. Coverage gaps (properties with no test, ranked by value behind them)

1. **[High] Dividend transfer under a full basket.** No test funds the basket to `MAX_ASSETS` with `acc > d` and then does a real `_update` transfer through the 180k cap. This is B-02; the F-09 suite's name promises "the entire grief window is closed" but its body only closes it for an **empty basket**.
2. **[Med] `QuoteRotator.arbStep` size bound.** The "bounded per call" property has no test; there is no bound to test.
3. **[Med] Surtax entropy.** No test asserts the surtax actually varies with the tick/seed; B-03 shows it never does.
4. **[Low] `setLiveKey` ETH invariant tied to the credit gate.** The two are coupled for safety but not co-tested.

---

## 7. Blind spots (stated honestly)

- **Fork suites:** ran with the provided Sepolia RPC + PoolManager/PositionManager; full baseline was **green, 0 skips**. I did not independently verify the live-chain state of `markSource`, `surtaxPolicy`, `feeRouter`, or `quoteOracle` wiring — several findings' blast radius depends on which pluggable modules are actually set on the live hook (`indexer/deployments/round.json` gives addresses, not module wiring).
- **I did not fully audit:** `PoolOps`/`SeedLib`/`ReserveLib` seeding math, `CauldronRegistry`'s claim accounting, the governor/timelock proposal lifecycle, the on-chain SVG renderers, or the TypeScript layers (indexer/API/frontend) — time went to the multi-quote seam where the tree was freshest.
- **EIP-170:** `CauldronHook` and `CauldronRegistry` (10 bytes) sit micro-margins under the limit; `PerpEngine` has 54. The B-03 surtax fix consumed 8 of the hook's 30 bytes, leaving it at **22** — these contracts are effectively frozen, and even a Low-severity fix now competes for single-digit-byte headroom. Strong recommendation to the team: move a chunk of `CauldronHook`/`CauldronRegistry` logic into a linked library (the pattern already used for `PoolOps`/`FeeRouteLib`) to buy back headroom before the next change is forced. I did not attempt to find an input that pushes either over via a compiler/settings change.
- **Assumed, not proven:** that the timelock genuinely gates `owner`/`registry` setters on mainnet (the comments assert it; I did not read the deploy wiring end-to-end).
- **Deleted contracts:** `MagicFrensPeg.sol` / `MagicFrensPresale.sol` are removed from the working tree but still referenced by deploy scripts (`DeployMagicFrensPeg.s.sol`, `DeployPresale.s.sol` — themselves also deleted), `MiFrensGenesis.cancelPresale`, the indexer's `Presale` handlers, and frontend ABIs. These are excluded from the `cauldron` build profile (`skip = [...]`), so they don't break compilation; the dangling references are dead deploy/indexer paths, not a contract-level break. Not pursued further as a security issue.

---

*Prior-audit comparison ("what they missed / what I missed") deferred until after this file is committed, per engagement protocol. Not yet read: `audit/**`, `docs/*.md`, `EXPLOIT_REPORT*`, commit messages.*
