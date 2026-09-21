# Native quote zap: input-budget and custody review

Status: source derivation plus **4/4 passing local tests**, including 256 fuzz
cases. This is not an entire zap/hook/token compatibility audit.

## Prior multi-tick hypothesis

`NativeQuoteZap.unlockCallback` settles `owed` before calculating a saturating
refund. Its comment claims exact-input tick-crossing fee rounding can make owed
exceed the input. The pinned V4 implementation does not support that explanation.

**DERIVED**, for ordinary V4 exact-input swaps without custom hook deltas:

- `lib/v4-periphery/lib/v4-core/src/libraries/SwapMath.sol:64-83` computes
  `available = floor(budget * (1e6-fee) / 1e6)`.
- When a tick target is reached, `input <= available` and fee is rounded up.
  Nevertheless `input + ceil(input*fee/(1e6-fee)) <= budget`: the sum equals
  `ceil(input*1e6/(1e6-fee))`, whose unrounded value is already <= the integer
  budget. Fee rounding therefore cannot independently overspend that budget.
- When the target is not reached, fee is exactly `budget-input`, so their sum
  equals budget. At 100% fee the target branch can only have zero input.
- `Pool.sol:376-384` advances the negative remaining amount by this bounded sum
  at each step, preserving the input bound across multiple ticks.

The comment in the first-party zap is not proof of an executable defect.
`test/audit_full_scope/NativeQuoteZapLocal.t.sol` adds three contiguous ranges
with a 0.3% fee and actual production PoolManager/zap to test full/partial input
consumption, multiple crossed ticks, output delivery, refund, slippage rollback,
unauthorized callback and zero-floor rejection. All four tests pass; the partial
fill explicitly reaches a tick below -1800, crossing all three ranges, returns
unused input, and leaves no ordinary native or quote residue in the zap. The
specific no-hook tick-fee rounding hypothesis is rejected; no production change
was made for it. The misleading comment remains informational.

## Custody and trust boundaries

The public entry rejects zero value, zero floor and a non-native currency0. The
callback checks the immutable manager. V4 unlock settlement is atomic; failing
the final `minOut` or output transfer reverts the swap and all associated token/
native balance movements. Refund callbacks can execute arbitrary caller code,
but a nested unlock remains subject to V4's lock. There is no owner, persistent
allowance or normal receive endpoint.

Unresolved properties: custom hook deltas, hostile/reentrant/nonstandard ERC20s,
forced pre-existing balances, rejecting refund recipients, exact gas bounds,
and service/UI venue choice. Do not generalize the no-hook math result to a
caller-selected malicious hook or price fairness. The caller's minimum remains
the execution protection.
