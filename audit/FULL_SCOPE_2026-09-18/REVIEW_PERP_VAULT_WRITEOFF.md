# Independent review — repeated token-yield write-offs

Date: 2026-09-18  
Scope: `PerpVault._syncTokYield`, `_settleTok`, `claimTokYield`, `pendingTokYield`; the engine's token-yield credit, rotation write-off, and vault pull paths; and `test/audit_full_scope/PerpVaultRepeatedWriteoff.t.sol`. No Forge run was performed in this lane because the root build was already running.

## Conclusion

The change from `totalTokYieldPulled = cum` to `totalTokYieldPulled = pulled + lost` is correct for the reviewed accounting model and closes a real Medium repeated-write-off defect. I found no remedy-induced fault. The new tests exercise the previously missing second-write-off sequence, preserve a healthy-path control, reverse claim order, and fuzz two through eight write-off cycles. Test execution results remain owned by the root run; this report does not independently claim they passed.

## Independent derivation

Define:

- `C = engine.tokYieldCumulative()`: monotonic token-side reward credits.
- `P = engine.tokYieldEth()`: presently backed reward pot.
- `W = totalTokYieldPulled`: amounts removed from the pot by successful vault claims plus amounts explicitly written off.

At a synchronized boundary the conservation watermark must be `P + W = C`.

1. A token-side credit increments both `P` and `C` by `x`, preserving the equality. Production does this in `_routeFee` and `_creditPerp` (`PerpEngine.sol:2202-2220,2594-2618`).
2. A successful claim decrements `P` and increments `W` by the same `x`. The vault increments `totalTokYieldPulled` before calling the engine, and a failed external call reverts both effects (`PerpVault.sol:650-659`; `PerpEngine.sol:2643-2647`).
3. Rotation writes the entire `P` off while deliberately leaving `C` monotonic (`PerpEngine.sol:1470-1495`). Therefore the newly unbacked amount is exactly `lost = C - (P + W)` (`PerpVault.sol:547-552`). Advancing `W` by `lost` restores the equality without counting any still-backed pot.

The accumulator split is consistent with the same boundary. `cut = W_old + lost` is the cumulative level through which backing disappeared; it is clamped into `[lastTokYieldCum,C]`, folded to `epochAcc`, and only `C-cut` is retained as post-write-off backed yield (`PerpVault.sol:552-595`). `_settleTok` forfeits an old epoch's nominal, rebases debt at `epochAcc`, and then accrues only the amount above that line (`PerpVault.sol:598-618`). `pendingTokYield` mirrors the detector, split, epoch bump, and rebase without mutating storage (`PerpVault.sol:786-829`).

## Why the former assignment failed

Take a synchronized state with `W = 0`, then credit 5, write it off, and credit 1 before the next sync:

- Actual state at sync: `C=6`, `P=1`, `W=0`, hence `lost=5` and `cut=5`.
- Former code set `W=C=6`. That treated the backed `P=1` as if it had already been pulled/written off, producing `P+W=7>C`.
- If the one-ether pot was then written off, the detector saw `backed=P+W=6` against `C=6`, calculated `lost=0`, and failed to create a new epoch. The stale one-ether entitlement could then overhang or consume later rewards.
- Patched code sets `W=W_old+lost=5`, so `P+W=C`. After the second write-off `P=0`, the detector calculates exactly one ether lost and advances the epoch once.

This generalizes. If multiple write-offs occur before any sync, `C-(P+W)` aggregates exactly all pot reductions since the last observation; one epoch forfeits that unavailable interval, while the final still-backed `P` remains above the cut. No iteration is required.

## Strongest cheap refutations attempted

- **Backed post-write-off credit accidentally forfeited:** rejected. It remains in `P`; `lost` excludes it and `cut=W+lost` ends immediately before it.
- **Claim mistaken for a write-off:** rejected. `claimTokYield` increases `W` by the exact amount the engine then removes from `P`; CEI and transaction rollback preserve the detector invariant.
- **Same write-off counted repeatedly:** rejected. Adding `lost` closes `C-(P+W)` to zero, so the next sync is idempotent until a new pot reduction occurs.
- **Two write-offs before synchronization:** rejected. Their unavailable pots are additive in the single observed shortfall. A single epoch is sufficient because there is no backed interval between them that must remain separately attributable; any final backed interval is `P` and is excluded.
- **View/write divergence:** rejected for the reviewed formulas. `pendingTokYield` uses the same `backed`, `lost`, `cut`, clamping, accumulator split, and prospective epoch bump as `_syncTokYield`.
- **Watermark overflow introduced by the patch:** rejected under the established invariant. After recognition `W=C-P<=C`; between recognitions `P+W<=C`. The patch removes, rather than creates, the old `P+W>C` state.

## Severity and impact

**Medium — token-side reward accounting/liveness.** A second rotation write-off could be masked by the overstated watermark. Claims could retain an unbacked nominal, revert against the smaller pot, or consume yield belonging to later epochs/stakers. The affected asset is accrued token-side reward, not token principal: rotation intentionally preserves `plvToken`, and the reviewed patch does not touch principal/share accounting.

## Regression assessment and limits

`PerpVaultRepeatedWriteoff.t.sol` uses the production vault and a mock engine whose relevant accounting transitions match production: credits increase pot and cumulative, rotation zeroes only the pot, and withdrawal decrements the pot with an insufficient-pot check (`K3b_TokYieldLockout.t.sol:146-178`). It does not reproduce production `syncGeneration` authorization, treasury transfer behavior, quote units, or reentrancy modifiers; those are not needed to test this arithmetic but remain outside what the fixture proves.

The suite checks:

- the post-sync watermark equality while a backed post-rotation pot remains;
- two write-offs with two stakers and bounded aggregate claims;
- a no-write-off control;
- two to eight repeated cycles, non-contiguous claim timing, both claim orders, and `sum(pending) <= backed reward` within explicit rounding tolerance.

Useful additional assertion, not required to validate this patch: after every successful individual claim inside the fuzz loop, assert `totalTokYieldPulled + tokYieldEth == tokYieldCumulative` before initiating the next write-off. The final test already asserts this after both claims.

## Directly reviewed properties and residual gaps

- Verified from source: credits are paired `P/C` increments; vault claims are paired `W/P` movements; the reviewed rotation path zeroes `P` without decreasing `C`; patched loss recognition restores the conservation watermark.
- Verified from source: stateful and view accumulator paths use the same write-off boundary and epoch semantics.
- Not certified: all `PerpVault` share/queue solvency, full production rotation reachability, quote redenomination economics, or behavior of engine paths outside the named credit/write-off/pull callers.
- Execution gap: this lane did not run Forge. Compilation and runtime results must be taken from the root-owned test run.
