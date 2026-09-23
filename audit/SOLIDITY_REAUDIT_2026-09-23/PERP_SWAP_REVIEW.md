# PerpSwapLib — full source traversal, final verification pending

Read all 1,198 source lines, including Position, interfaces, Ring/Observation,
all external/private helpers and assembly. Linked-library delegatecalls operate
on engine custody/storage; direct library calls cannot establish engine safety.
No production edit. Historical narrative and claims in comments are not evidence.

| Paths | Source-derived behavior and required verification |
|---|---|
| unitOf/_unitOf; quoteFactor/_quoteFactor/_usdPerRawUnit | Configurable oracle/decimal reads, short/revert fallback, raw unit normalization. Dynamic returndata copying and mulDiv extreme ratios remain gaps. Fallback decimal count is not universally conservative for all quote valuations. |
| projectedSqrtPriceX96 | Exact-output cost ceiling, 15% slack, reserve cap, direction and caller price-limit clamp, TickMath bounds. Requires full-range liquidity/orientation invariants. int256 minimum negation/extreme arithmetic reverts need caller reachability review; partial fills and pool gaps need funded tests. |
| twapTick/writeObs | 32 observations, bounded binary search, timestamp/cumulative arithmetic, always refresh current tick. Ring chronological comparisons around uint32 rollover and negative-tick truncation need tests; observation window may extend to preceding sample. |
| sqrtPriceAtTick | TickMath enforces valid tick range. Configured malformed engine mark may reach this with invalid int24. |
| tryMintBadge | Code/gas gates, two bounded mint attempts, only bool success (no returned-id validation). Caller credits must not be consumed by a successful no-op dependency; mint rollback/reentrancy and actual earned badge lifecycle pending. |
| quoteAt/ethToToken/ethDepth | Two-stage floor arithmetic with quote-first convention; actual representability/rounding error at extreme price and size needs differential tests. ethDepth assumes valid sp <= SQRT_MAX. |
| tryTransferFrom/tryTransfer | Low-level calls then typed bool decode. Malformed nonempty returndata can revert instead of reporting false; mutation-before-false may persist unless caller reverts. Trace production payouts and isolate atomicity before finding classification. |
| swapLeg/_settle | Direction determines delta legs; input sign/exact-output mapping; native or sync-transfer-settle, output take. Assumes normal V4 delta signs and caller-bounded amounts. Malicious tokens, hook deltas, partial fill accounting and linked deployment need integration. |
| migrateInventory | Best-effort reserve-limited burn claim, emits shortfall; trusts uint return for diagnostic count. Existing old inventory may remain, engine rebooks new balance. Generation retry/reseeding custody obligations pending. |
| spendLimit/_spend; bandLimit/_band; closeLimit | Constant-liquidity budget and mark band; buy quote-first uses larger lower bound. Generic down=false branch in closeLimit also uses max, so validate no reachable quote-second caller. Extreme boundaries/zero budget and deeper-band spending need funded assertions. |
| _requoteBook/requoteBookAt | Registry-only check inside library before writes, generation equality/no-op, payout veto, old funding/queue sync, conversion, physical pots/positions and ring restatement, mark-source reset, remembered rotator, final vault callback. Outer engine nonReentrant; external callback ordering must be tested. |
| _factors/_factorStrict | Strict configured price requirement, but zero result after ratio truncation isn't explicitly rejected. Extreme zero/overflow scenarios require supported-decimal and price reachability proof. |
| _restatePots/_restatePositions/_shortBacking | Physical pot allocation at realized ratio, longs at oracle ratio with debt rounded up, remainders to PLV. Loops proportional to open positions, collateral uint128 bounds, checked arithmetic. Verify maximum book gas, no collateral dust lockout, exact reserve conservation. |
| syncQuoteChangeAt/_carryEmpty | Non-owner remembered-rotator conversion or owner treasury write-off; owed payout veto. Legacy no-rotator path checks quote-side stake, sweeps best-effort and resets pots. Privileged forfeiture intentional; failed treasury transfer leaves unbooked custody. Empty-book preconditions enforced in caller, not library. |
| _slot/_ld/_st/_ldAddr/_stAddr; _posAt/_idsAt/_obsAt/_ringAt | Packed 16-bit slot identifiers and byte offsets; address writes preserve slot mates. Verify compiler slot values, offsets, sizes, struct identity and reference mapping against engine; no storage assumption accepted from comments alone. |
| _convert/_held | Curated rotator venue, funds sent before swap, actual new-balance lower-bound check. Requires trusted rotator access/escrow wiring and oracle floor; return can underreport donated output leaving surplus. |
| _shiftRing | Fixed 32 loop, oracle log tick shift, unchecked cumulative math and checked lastTick range. Absolute timestamp shift and overflow/round-trip truncation require property tests. |
| _vaultHook | Calls configured vault and checks success; code-free address can succeed without executing hooks. Engine vault installation/wiring must be checked separately. |

No function is signed off on traversal alone. Priority leads are malformed mark
range validation and malformed token bool responses. Full engine solvency,
position-cap gas and real requote conservation remain open.
