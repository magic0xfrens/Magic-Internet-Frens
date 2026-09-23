# LegacyBuyLib source review

Current/frozen SHA256:
`1ada6f0e4d0c95bb13aa4d9c726250103b6857a386f550ba646b829711cabce6`.
Both implementation bodies traversed. No production change; final verification
pending. Linked library executes in the hook's context.

## buyStep

Clamps requested amount to balance minus encumbered relaunch reserves. Zero free
balance returns before reference updates. Direction assumes quote currency0;
hook caller checks pool identity and denomination and sets self-buy flag.
Reference bootstrap skips the entire birth block; later limit uses the larger
of spot/reference sqrt prices, scaled by 9486/10000. An unreachable limit skips
without reverting, preserving reference catch-up. A real swap settles actual
debit, requires nonzero output, and checks a two-stage mulDiv output floor.
Native settles value; ERC20 uses sync/transfer/settle, then takes output to hook.

Dependencies and gaps: real V4 manager must supply correctly signed deltas;
extreme amount casts and boundary tick/min-limit behavior need explicit tests.
Malformed/false ERC20 responses revert the self-call and roll back its swap;
fee-on-transfer can leave unsettled deltas at outer unlock even with true return,
so admitted-quote constraints remain important. All external calls occur inside
the hook's nested buyback context; a self-call catch is not universal protection
against gas exhaustion or later outer-unlock failure.

## _syncRef

Namespaced slot per pool packs signed tick into low 24 bits, uint64 block into
next 64, virgin flag at bit 88. Tick-domain difference fits int24; movement
clamps to +/-1000 on a different block, independent of elapsed block count.
Same-block birth sample remains unusable; same-block established sample is reused.
Production monotonic block progression is assumed; uint64 block truncation is
not a practical present-day chain bound. The reference is rate-limited spot,
not an independent fair-price oracle or TWAP. Multi-block manipulation remains
an economic-analysis obligation; passing same-block tests cannot prove it absent.

## Executed evidence

logs/legacy-buy-review.*: 14 passes, zero failures/skips; no compilation.
Four local real-manager/library-harness cases cover birth-block deferral,
next-block spending, organic drift, and one same-transaction manipulated-price
scenario. Ten threshold cases include two inherited tests and two 256-run fuzz
tests. The gas-exhausting metadata test is a passing reproduction of bounded
setter failure/rollback, not evidence of universal liveness. Test PnL expressions
mix residual token and native units; only matched inventory or a consistent
valuation supports an economic profitability conclusion. No general economic
safety conclusion drawn from their PnL assertion.

The separate R23 ledger registry integration establishes actual hook invocation,
first-block reference deferral, second-block funded buyback, and relaunch flush.
Still missing: full quote-token callback matrix, cross-generation/pool reference
independence tests, minimum tick edges and multi-block economic stress.

## Informational — stale library documentation (leave unfixed)

Header claims the library holds no state and all reads/writes stay in the hook;
_syncRef now directly reads/writes namespaced hook storage through delegatecall.
This is documentation drift, not a demonstrated collision. Hook comments still
describe native-only settlement even though library supports ERC20 currency0.
Neither comment was changed, per instruction to leave Informational unfixed.
