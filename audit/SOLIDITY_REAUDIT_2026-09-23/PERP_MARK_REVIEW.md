# PerpMarkSource — full source traversal, final verification pending

Read every declaration/body in PerpMarkSource.sol (constructor, ownership override,
setPrimary, addPool, removePool, poolCount, weightedTick and public getters).
No production change. The manager is immutable and externally trusted; source
ownership controls the registered pool set and all price-admission decisions.

| Declaration | Source-derived property and evidence gap |
|---|---|
| constructor | Ownable rejects zero owner; manager validity remains deployment obligation. |
| renounceOwnership | Always reverts; inherited transferOwnership remains available and must be included in authority/consumer coverage. |
| setPrimary | Owner-only, arms and clears siblings, emits id. Does not validate initialization/pair; owner misconfiguration can make an uninitialized primary return tick zero. Deployment and engine wiring are a gap. |
| addPool | Owner-only, armed, max four siblings, same ordered currencies, duplicate ids excluded. Fee/hooks/tickSpacing may differ; manager may report zero liquidity for uninitialized pools. |
| removePool | Owner-only bounded swap/pop, NotFound on missing id, cannot remove primary. Ordering changes are immaterial to exact sum. |
| poolCount and getters | Read-only config; pool indexed getters revert out of bounds. Consumer selector reconciliation pending. |
| weightedTick | Reverts unarmed; primary fallback without siblings/all-zero depth. Skips zero-depth siblings. Signed accumulator over max five uint128 weights is bounded within int256; sum weights within uint256. Division truncates negative means toward zero (sub-tick bias). Convex combination fits int24. Manager extsload is an external static read. |

Neighboring engine: _currentTick performs bounded one-word STATICCALL and requires
exactly 32 return bytes, then truncates to int24 without checking canonical sign
extension or valid TickMath range. This is a configurable-dependency lead, not a
confirmed exploit. Correct PerpMarkSource output stays in tick range for a real
V4 manager. Investigate malformed owner-configured source separately.

Tests inspected: Q07_WeightedMark asserts deep-pool weighting, thin-pool
attenuation, pair mismatch, empty/single fallback, cap, primary reset and addPool
authority against a mocked manager. K3e_UnarmedMarkTick checks revert and raw
staticcall failure. Their previous runs are not fresh evidence this continuation.
Missing: negative/boundary fuzz, remove/duplicate/owner-transfer paths, exact gas
at maximum set, funded local-manager multi-pool/TWAP attack including permissionless
liquidity changes. Current-liquidity weighting alone is not proof of manipulation
resistance; temporal sampling and liquidity changes must be analyzed together.

## Executed evidence

perp-reward-scale-and-mark-boundaries: three selected mark tests pass (including
256 fuzz cases covering negative ticks and uint128 weight boundaries); no
inherited Q07 repeats selected. Verified convex-hull result, remove preserving
remaining sibling, duplicate rejection, reset, transferred ownership and blocked
renunciation. perp-mark-existing: 11 passes, no failures/skips. Manager is mocked;
these establish source arithmetic/configuration properties, not funded market
manipulation resistance. No final sign-off.

## Intended hook execution path clarification

User confirms perps are intended to liquidate via hook beforeSwap, without an
external poke keeper. Inspected CauldronHook._beforeSwap -> _liqSweep ->
PerpEngine.sweepLiquidations -> _doSweep -> _pokeFunding -> _writeObs and
_quoteMark. The same observation/funding code runs automatically before the
sweep; public poke is not a prerequisite for normal operation.

perp-malformed-mark-boundary: malformed tick 887273 fails public mark calculation
with InvalidTick; ordinary revert control passes. The subsequent XL1 funded
fixture also fails while advancing its poke-based warm-up, before reaching its
close assertion. It therefore does NOT yet prove close itself was attempted.
Initial XL1 command had an incorrect close signature and compiled no tests;
corrected command is the runtime evidence. Neither substitutes for production
beforeSwap integration. R23_MarkBeforeSwap explicitly exercises two ordinary
buys separated by time with no external poke in the tested sequence.

Candidate range fix verified: four funded/local mark regressions pass and five
valid/malformed tick boundary tests pass. Production beforeSwap tests explicitly
omit public poke after configuration, matching intended keeperless operation.
Local neighboring partial-close and pre-sweep batch: 15 passes, no skips.
Versioned engine runtimes match current metadata source hash and fit EIP-170;
unversioned artifact is stale. Refer to FINDINGS.md for limitations.
