# Reserve and seed math — source traversal, caller review pending

Candidate batch `logs/reserve-math-review.*`: exit 0, 13 passed, zero failed or
skipped; eight fuzz tests with 256 cases each. No compilation needed. This is
pure math evidence, not stateful reserve conservation or deployed parity.

## ReserveLib: all five function bodies traversed

- `_alignDown`: signed truncation corrected for negative nonmultiples; positive
  spacing required by callers. Zero spacing reverts; no internal validation.
- `_alignUp`: positive nonmultiples increment; negative truncation already
  gives ceiling. Same caller spacing requirement.
- `reserveTicks`: lower bound is aligned MIN_TICK, upper is aligned
  launch-minus-offset; degenerate ranges become one spacing above the floor.
  Well-formedness test spans full ticks but orientation test excludes degenerate
  launches. A valid range is not proof it is below spot in that excluded domain.
- `liquidityForTokenOut`: dependency computes floor-rounded amount1 liquidity,
  with uint128 representability constraint. Existing round-trip fuzz covers
  launch ticks [-400000,600000], amounts [1e6,1e27], spacing 200, offset 42400.
  It does not establish these bounds for every quote denomination or caller.
- `tokenOutForLiquidity`: zero liquidity returns zero; otherwise FullMath
  computes floor(L*(sqrtHi-sqrtLo)/Q96). Requires ordered valid ticks. No reserve
  price/orientation check here; callers must ensure the position is token-only.

## SeedLib: all seven function bodies traversed

- Alignment helpers use the same signed convention as ReserveLib.
- `deployedTargetWad` clamps floor to WAD; zero-window/end-time => WAD;
  before-start => floor; intermediate elapsed < uint64 window. Multiplication
  is bounded by 1e18*(2^64-1), comfortably inside uint256; endpoint sum is
  widened before adding window. Read-only pure schedule with downward rounding.
- `askBand` and `bidBand` compute aligned width and indexed bands then clamp
  outer ticks. Narrowing index to int24 and subsequent arithmetic require
  caller bounds. Degenerate clamps can change orientation near global extrema.
- `_bandWidth` maps zero count to one, divides offset by narrowed count, and
  enforces minimum spacing. Huge counts can narrow to zero/negative; caller
  validation is required, not established by this library.
- `taperWeightWad` returns zero for zero count; otherwise descending fraction
  2*(n-i)*WAD/(n*(n+1)). Requires i<n and bounded n for checked arithmetic.
  Fuzz sums weights for n=1..64, but geometry only tests n=1..16 and interior
  launch ticks [-500000,500000]. Production caller joins remain pending.

## PoolOps migration boundary inspected

`claimFromReserve:1310` clamps requested liquidity to available position,
decreases with zero minimum amounts, takes BOTH currencies to recipient, and
returns only currency1 balance delta. Therefore its "zero ETH" comment relies
on out-of-range orientation; it is not an enforced postcondition here.
`addToReserve:1350` permits no currency0 input and measures actual currency1
consumption; arbitrary amount -> uint128 cast needs upstream supply bound.
`migrateOne:1412` burns nominal amount and reverts when actual token output plus
CLAIM_DUST (1e12) is insufficient. `migrateUpTo:1401` caps nominal amount using
liquidity's token-only capacity, then uses the same dust-tolerant primitive.
`autoMigrateBatch:1437` recomputes capacity per opted-in holder and skips a balance
above it. The normal vesting integration observed 739 raw units of tolerated
rounding; vesting records actual delivery rather than nominal burn.

Next: validate caller bounds/orientation across native/ERC20 quote rotation,
model tiny repeated migration losses and fee-bearing reserve outputs, and
execute failed-capacity/rollback cases. No new confirmed finding in this report.
