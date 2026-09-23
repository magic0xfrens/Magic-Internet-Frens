# CauldronGachaRouter source traversal

Current/frozen SHA256 both
13a0bda56a00898026025e4bb5ef74d1e4b0dd8ea428a63b60142f1fef6cbc7d.
All implementation bodies read, no production edit, no final sign-off.

| Bodies | Review and remaining obligations |
|---|---|
| constructor / nonReentrant | Immutable manager/hook/registry, owner from Ownable; transaction entry guard, dependency wiring trusted. |
| setOracle / playInCurveUnits / _playInCurveUnits | Owner oracle config; public view delegates quote-specific conversion. Empty typed return and product overflow can escape fallback. Raw-unit fallback under a still-USD hook does not restore unit consistency; impact depends on asset decimals/price and credit acquisition. |
| _quote / _key | Live generation reads each time; callback rebuilds key rather than receiving captured key. Test quote/generation changes across token callbacks; registry rotation gates matter. |
| play / playLiq / _play | Guarded entry, pull inputs, manager unlock, derive realized notional, commit/resolve, refund unused inputs. Buy output transfers inside callback, before gacha, despite high-level 'sends last' comment. Router guard protects own entries, not every registry action. |
| _pullQuote | Rejects mixed native/ERC20 inputs; ERC20 return is nominal amount, not actual balance delta despite comment. Fee-on-transfer/admitted-token constraints need validation. |
| openReady | Capped 30, derives notional from curve cost and buy weight, deliberately no double oracle conversion. Dependency errors revert atomically. |
| playChurn / _churn | 1..10 loops, keeps partially unspent balances on both sides, checks final token output, returns residual quote. Intermediate legs have extreme price limits; user final minimum is essential. |
| unlockCallback | Only immutable manager allowed, tag 1 churn otherwise play. No explicit in-flight commitment, relies on manager calling only its unlock requester. Real-manager semantics required, not generic malicious manager assumption. |
| _limit / _settle / _take | Extreme valid price limits; native value or ERC20 sync-transfer-settle; takes positive output. Signed delta casts rely on valid V4 direction/input bounds. |
| _payQuote / _safeTransfer / _safeTransferFrom | Reject failed/false token transfer, malformed bool reverts atomically. Codeless token appears successful; configuration/token assumptions remain relevant. Refund-rejecting caller reverts entire play. |
| rescueETH / rescueToken | Owner-only; no entry lock. Owner chosen as callback-capable contract can act during play; privileged trust, not outsider bypass by itself. |
| renounceOwnership / receive | Renounce disabled, inherited transferOwnership retained; open native receipt permits donations, rescued by owner. |

New tests not run during this traversal; surtax compilation session 84542 is
still active. Candidate suites: F21_GachaQuoteAgnostic, Q02_GachaOddsUnitMismatch,
churn partial-fill/slippage tests (discover before selecting). Required joins:
trusted opener identity, liquidation hints and keeper recipient, oracle outage
units, registry generation changes during callbacks, queue/reveal rollback.

Informational stale documentation (leave unfixed): header says ETH always
currency0 despite implemented ERC20 quote support; _pullQuote says actual held
amount but returns nominal transferFrom amount. Broad 'fails safe, never more'
oracle-fallback claim is not justified for every possible quote denomination.

Fixture selection checkpoint: F21 explicitly uses stub registry/oracle and
codeless manager/hook that its view-only tests never reach. Its quote-following
passes cannot establish actual rotated-pool settlement or funded play liveness.
Use alongside, not instead of, funded manager integration. Churn regressions
located at K4c_ChurnNoFloor and X4b_ChurnConfiscatesRefund; inspect harnesses
before assigning real-manager evidence. No new test execution in this checkpoint.

Inspected X4b/K4c: both use synthetic managers returning chosen deltas and
minting output rather than enforcing V4 liquidity/delta conservation. Useful
router arithmetic tests, not full AMM integration. Prepared R23_ChurnLocal
using actual local managers/hook/registry, funded three-loop native churn,
zero-residue assertions, and snapshot-replayed impossible minimum proving
transaction rollback. No forced token balances/credit. Not yet run while
surtax compilation 84542 is active; native test does not establish ERC20 or
exhausted-liquidity partial-fill coverage.

Subsequent execution: `gacha-churn-review` ran R23ChurnLocal successfully.
Actual funded three-loop native churn returned positive tokens, left no router
native/token residue, and the snapshot-replayed impossible minimum reverted
without changing player balances. This closes that specific execution gap only;
ERC20 quote, rotation during lifecycle, and liquidity-exhaustion cases remain.

## Final disposition (2026-09-23)

Final: oracle malformed-reply escape = FS-router-L01 Low. Router buys exercised in the local rehearsal. Signed off.
