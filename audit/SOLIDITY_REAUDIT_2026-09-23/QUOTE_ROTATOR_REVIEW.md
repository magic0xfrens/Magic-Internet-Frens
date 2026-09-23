# QuoteRotator source review — intermediate

Source: baseline cauldron/QuoteRotator.sol, unchanged by the oracle fix. All
32 implementation declarations read across this and preceding fresh-review
traversals. This worksheet does not close all callback, token and market-model
properties. Historical comments/test titles are not accepted as conclusions.

## Authority and entrypoints

| Node / line | Source-derived behavior | Test evidence or gap |
|---|---|---|
| constructor / 99 | Registry and manager immutable; deployer owns configuration | Fixtures deploy; zero-address deployment gap |
| onlyRegistry / 134 | Registry OR registry.hook().perpEngine() | Open-book rotation integration exercises engine path; malicious pointer/rotation gap |
| _liveEngine / 140 | Two static reads, zero on revert/short answer | Malformed full-length address response gap |
| onlyOwner / 150 | Exact msg.sender check | QuoteRotator and B12 stranger cases |
| transferOwnership / 155 | Single-step owner replacement, zero permitted | Explicit handover/zero-address gap |
| setVenue / 210 | Owner writes exact PoolId allowlist and latest pair route; revocation clears matching route | B12 curation, revoke and pair separation |
| _pairKey / 227 | Address-sorted keccak pair identity | Bidirectional/pair-cache edge gap |
| venueFor / 235 | Latest route only; spacing, allowlist and currency pair checked | Real-engine requote reaches route lookup; alternate remaining route gap |
| isVenueAllowed / 244 | Read-only exact PoolId lookup | B12 assertions |
| setPlan / 263 | Owner validates distinct assets, nonzero bounded amounts/rate and approved destination; replaces whole plan | QuoteRotator plan/invalid/authority tests |
| cancelPlan / 295 | Owner emits progress then clears plan; custody stays | QuoteRotator.test_PlanCanBeCancelled |
| setKeeperBps / 300 | Owner, max 100 bps | test_KeeperRewardIsCapped |
| nextSliceSize / 310 | Min(slice, remaining mandate, holdings); elapsed interval after first step | QuoteRotator holdings tests; completed-plan and exact-time boundaries gap |
| rotateStep / 331 | Permissionless; destination/pair/venue checks; done/time effects precede unlock; governed raw-unit floor; output ledger then keeper transfer | B12 success/refusal; partial-fill, callback and output-accounting boundaries gap |
| swapOnce / 382 | Registry/live engine; vetted pair/venue/destination, nonzero live oracle floor; max(user minimum, floor) | X2c and local production-manager rotation tests |
| setRotationSlipBps / 451 | Owner, max 2000 bps | Boundary/unauthorized-specific gap |
| _oracleFloor / 469 | Live USD ratios; floor haircut; zero if either input unpriceable | X2c refusal/control; extreme decimal/rounding gap |
| setArbParams / 529 | Owner sets oracle, min profit, keeper max 2000 bps | QuoteRotator authority/keeper tests |
| setMaxArbNotionalUsd / 539 | Owner changes cap; zero opts out | B04 default/setter/authority/independence tests |
| arbStep / 577 | Permissionless; same token/different quote, exact curated venues, allowed output, live preflight; unlock; realized spending cap per block; strict positive/minimum profit; keeper payout | S09 curation/destination/cap/profit splitting; X2m stale/live preflight |
| _usdLive / 666 | Static fresh oracle read; failed/short result zero; raw*factor/1e18 | X2c/X2m; overflow returns revert rather than zero gap |
| withdraw / 697 | Owner/registry arbitrary nonzero recipient; live engine only itself | QuoteRotator ordinary withdrawal/stranger/zero; engine integration |
| _swap / 715 | One manager unlock, direction derived from source currency | Local real-manager rotation |
| unlockCallback / 724 | Only immutable manager; tagged payload; exact-input swap; settle requested size; take returned output | Stranger rejection/local integration; partial-fill boundary gap |
| _arbCallback / 756 | One unlock, two swaps, sell first output, settle spent quote and take received quote | S09 uses mock manager; real-manager partial second-leg fill gap |
| _settle / 783 | Native settle or sync/ERC20 transfer/settle | Local quote-rotation integration; fee-on-transfer/rebasing gap |
| _send / 793 | Checked native call or checked ERC20 helper | Withdrawal tests; keeper callback re-entry gap |
| _safeTransfer / 806 | Requires code, call success and empty/true ABI return | Malformed/false/token-hook test coverage gap |
| _routeMatches / 819 | Exact currencies in either order | B12 wrong-pair |
| _balanceOf / 829 | Native balance or ERC20 balanceOf | nextSliceSize native coverage; hostile balanceOf gap |
| _allowed / 833 | Native always true; registry static allowedQuote otherwise | Destination refusal tests; malformed ABI gap |
| receive / 840 | Public native funding, no accounting write | Funded local integration |

## Custody, units and ordering

All assets remain contract balances, not per-depositor claims. Plan counters
are raw asset quantities: doneIn in source, gotOut in destination. minRate is
destination raw units per 1e18 source raw units; do not infer whole-token
normalization from test comments. rotateStep's gotOut is gross, before keeper
reward. swapOnce returns gross output for caller withdrawal. Arb profit and its
block budget use USD 1e18; reward is destination asset, proportional to profit.

Reverts in swap/floor/profit/cap/payment unwind the transaction. Manager callbacks
are caller-gated, but the manager and curated hooks remain trust boundaries.
Nested manager.unlock is subject to the manager's lock, not a rotator guard.
Keeper payment occurs after manager unlock returns and can invoke arbitrary
recipient code; re-entry ordering still needs a dedicated fixture. Plan effects
precede this payment; arb block spending is recorded before its payment.

No unbounded collection loop occurs in rotator source. _swap assumes a complete
exact-input fill: it settles requested size rather than actual delta. A partial
fill should leave nonzero manager deltas and revert, not silently donate; verify
that liveness behavior against production V4 rather than trusting mock fills.

## Executed batch and evidence limits

logs/rotation-gates-review.*: 24 passed, 0 failed, 0 skipped, exit 0.
Includes B12, B04, S09 and X2m. Combined with prior disjoint candidate batches:
212 selected tests passed. This is not full repository coverage.

S09_C proves same-block aggregate cap and atomic rollback with its mock fill.
S09_D does not prove planned funds are reserved: arbStep never reads plan and
nextSliceSize caps against the remaining shared balance. Its 10 ETH fixture leaves
2 ETH after an in-budget 8 ETH arb; smaller floats or later blocks can differ.
Do not infer an invariant of plan preservation from the passing test. Whether
arb should reserve scheduled capital is a design constraint to reconcile, not
permission to silently disable otherwise legitimate profitable arb routing.

X2m's healthy control merely proves the error is not NotPriceable; it does not
prove a profitable trade completed. Its stale refusal and cache timestamp
assertions are separate useful properties. Header claims that swapOnce is
owner-only, or that every path needs no oracle, are inconsistent with actual
gates; record as documentation limitations, not fresh asset-loss evidence.
