# Seeder range-cap loose-ledger review

Date: 2026-09-18

## Decision

**Current production classification: not a Medium-or-higher vulnerability.** The shipped path sets `PoolOps.SEED_BASE_WAD = 1e18` (PoolOps.sol:173). `createAndSeedProgressive` therefore assigns the whole active tranche to the atomic base at lines 400-406 and returns at line 412 before approving or calling `CauldronSeeder.startSeed` (lines 414-421). The launch script may deploy and wire a seeder, but it explicitly records that `startSeed` is not called under this configuration and that `poke` remains a no-op (DeployLaunchpad.s.sol:419-427).

**Dormant progressive-path classification: confirmed accounting/availability behavior with bounded custody impact; conditionally Medium if streaming is re-enabled without further work.** At the 64-range cap, the code can remove previously deployed principal into loose seeder balances while `placedWad` advances according only to time. No asset is lost: loose balances remain in the seeder and `withdrawAll` later sends both loose balances and all remaining position proceeds to the registry. The impact is reduced active depth and a misleading completion metric, not theft or permanent stranding.

This is a source-derived conclusion, not an executed PoC. No Forge or compiler command was run for this follow-up.

## Current code path

1. `_pendingStep` computes only the time-schedule delta, `target - placedWad` (CauldronSeeder.sol:515-521).
2. `_placeStep` converts that delta into `tokenStep` and `ethStep` from the original stream totals (lines 562-572). It does not inspect loose balances or recovered range principal.
3. Each step reserves an ask and bid range before minting (lines 592-600).
4. Below the cap, a new range is appended (lines 838-840). At `ranges.length >= MAX_RANGES`, `_reserveRange` instead selects the non-base range furthest from live spot, removes all of its liquidity, settles the positive proceeds into the seeder, and overwrites that tracked slot with the requested range (lines 815-835).
5. The new range is sized only from `tokenStep` or `ethStep` (lines 616-625). The proceeds recovered in step 4 are not added to those amounts.
6. After the PoolManager unlock succeeds, `poke` unconditionally calls `_advance` (lines 310-314). `_advance` sets `placedWad = target`, not an observed active-liquidity fraction (lines 526-533).
7. At teardown, `_teardown` removes every still-tracked position, then forwards the entire ERC20 and native balances—including cap-eviction proceeds—to the registry (lines 645-689). `withdrawAll` clears the range set and closes the campaign (lines 850-858).

Therefore the source proves the narrow claim: after an eviction, `placedWad` means “scheduled fraction successfully processed/ever placed,” not “fraction currently deployed.” It does not prove a loss of custody.

## Bound and impact

- `ranges.length` never exceeds 64, and `_teardown` remains bounded by that length. Eviction reuses a slot rather than growing the exit loop.
- The shipped progressive tuning—if the atomic-base constant were lowered—uses a 10% initial floor and a 2% minimum step (PoolOps.sol:142-144). With two distinct ranges per placement, 32 distinct placements fill 64 slots. In the simple no-trade case, the cap is reached around 72% scheduled progress: one 10% placement plus thirty-one 2% placements.
- Later 2% placements replace earlier positions rather than adding a 33rd pair. In a simple no-trade model, completion can consequently leave roughly 28% of the streamed tranche loose; if the furthest-range policy replaces the original 10% pair with a 2% pair, the illustrative loose fraction rises to roughly 36%. These percentages are a model, not measured evidence: swaps, fees, rounding, side checks, and which ranges are selected change the asset mix and exact value.
- An external trader can influence spot and therefore which range is “furthest,” but cannot redirect the recovered balances. The PoolManager callback is authenticated, seeder entrypoints are locked, and only the registry can perform teardown.
- The operational consequence, if progressive mode is restored, is lower live depth than `complete == true` / `placedWad == 1e18` suggests. That can weaken the intended anti-snipe and downstream depth assumptions. It does not bypass the reserve ledger because the seeder only holds ledger A.

## Intent and prior evidence

The eviction is an intentional Z-18 remediation. The prior verified bug reused a historically “ask” range after spot had crossed it, caused settlement in an asset the seeder lacked, and permanently halted the stream. The accepted fix deliberately chose eviction of the furthest non-base range so a side-correct replacement can be created while teardown stays bounded (`FINAL_AUDIT_FULLSWEEP.md`, Z-18; commit `9f04d9f`).

The current regression `T9c_SeederRangeCapMisSide.t.sol` establishes four properties after filling the cap: `poke` does not revert, `placedWad` advances, the range count stays at or below 64, and a side-correct ask exists. It logs the seeder ETH balance before and after the post-cap poke, but does not assert loose ETH/token bounds, conservation through teardown, or the relationship between `placedWad` and currently active liquidity.

The later scoped review `FINAL_BLIND_2026-09-13/hunt/H5_genesis_seed_deploy.md` independently recorded “`_reserveRange` eviction as a depth drain” as a hypothesis and prescribed essentially the missing measurement: fill 64 ranges, alternate price movement and pokes, then chart live PoolManager liquidity against seeder loose balances. No reviewed artifact upgrades that hypothesis to a measured PoC or records a resolution.

## Exact local regression assertions

Extend the existing local `T9c_SeederRangeCapMisSide` harness rather than creating a second fixture:

1. **Eviction actually creates loose ledger A:** immediately before the first post-cap poke, snapshot `address(seeder).balance` and `token.balanceOf(address(seeder))`; after a successful post-cap placement, assert that at least one loose balance increased beyond the known rounding tolerance. This demonstrates the source-derived behavior without claiming loss.
2. **Completion metric versus custody:** continue rolling blocks/warping and poking until `deployedWad() == 1e18`; assert `rangeCount() == 64`, then record loose native/token balances. Under a remediation whose invariant is “fully deployed,” assert both are no more than an explicit dust bound. Against the current implementation, make the expected-failure evidence precise by asserting that at least one is materially above dust.
3. **Tracked-position bound and existence:** scan all 64 public ranges and query `getPositionInfo`; assert no more than 64 entries exist and at least the newly requested side-correct bands have non-zero liquidity. Do not equate range count with active capital.
4. **Lifecycle conservation:** snapshot the registry recipient's native/token balances, call `withdrawAll`, and assert the returned amounts equal the recipient deltas; assert the seeder ends with zero native/token balance, `rangeCount() == 0`, `seeding() == false`, and `isComplete() == true`. This distinguishes reduced mid-life depth from stranded custody.
5. **Nominal active-depth comparison:** for a deterministic no-trade cap fixture, convert each tracked range's liquidity to currency amounts at the current square-root price using the same pinned v4 math library, sum those amounts, and compare them with `ethTotal`/`tokenTotal` and the loose balances. Assert conservation within rounding and separately assert the required minimum active fraction. This is the decisive product invariant missing from T9c.

Tests should roll one block per reference update, as T9c already does, and must use production values (`seedFloorWad = 0.1e18`, `minStepWad = 0.02e18`, `bandWidth = 2000`, spacing 200) for the quantitative case.

## Smallest remediation if progressive mode is restored

Do not merely stop `_advance`: that recreates a liveness failure at the cap. Preserve eviction, but recycle its proceeds into the replacement placement:

1. Have `_reserveRange` return the positive currency amounts recovered from the removed position in addition to the replacement ticks.
2. Aggregate recovered currency0 from both side reservations into `ethStep` and recovered currency1 into `tokenStep` before calculating the new ask/bid liquidity.
3. Net removal and addition deltas in the same unlock and settle once. The pinned `IPoolManager` documents that `callerDelta` already totals principal, fees, and hook deltas; the separately returned `feesAccrued` is informational and must not be added again.
4. Add explicit checked casts/sign checks because only positive removal proceeds may increase the replacement budgets.

This keeps the 64-range teardown bound, retains Z-18's live-side correctness, and makes `placedWad` materially track currently deployed principal instead of cumulative processed schedule. It is a localized Seeder change, but should not be shipped without the five assertions above because v4 removal returns, fees, and rounding must be reconciled exactly.

If the product accepts capped live depth as deliberate graceful degradation, the smaller non-security remediation is documentation/telemetry: rename or document `placedWad` as cumulative processed progress, expose loose ledger-A balances, and alert when eviction begins. Under the current 100% atomic-base production configuration, this documentation path is proportionate; no production-code change is required for Medium+ remediation.

## Limits

- No runtime trace was generated in this pass because the root build was already running and this task prohibited Forge/compiler use.
- The 28-36% figures are bounded illustrative accounting under deterministic no-trade assumptions, not measured mainnet or local-test results.
- Exact hook-adjusted v4 deltas and rounding must be confirmed in the remediation test before implementation; the pinned interface establishes that `callerDelta` already includes principal and accrued fees.
