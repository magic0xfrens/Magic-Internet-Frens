# RedemptionExt — full source traversal, final verification pending

All 1,082 source lines read, including shared interfaces and every body. Existing
recursive61-slot layout parity evidence remains applicable until source changes.
No production edit in this continuation. No final sign-off.

| Paths | Review and obligations |
|---|---|
| redeemOgFren | nonReentrant, emergency-aware exit gate, summoned/genesis-ID/owner checks. Floor computed before outstanding debit and treasury count increase; custody transfer then reserve pull, shortfall>1e12 reverts atomically. Saturating debit deserves reserve/outstanding invariant proof. Dust tolerance is raw token unit, not quote value. |
| buyTreasuryOgFren/donateToReserve/_pullGrow | only genesis-held NFT may buy,2x floor computed before count decrement, transferFrom/add reserve then custody. Positive added required; reported paid is credited liquidity amount rather than full raw pull. All holder/payment accounting must account for leftover dust. First-party exact token assumed. |
| materializeLegacyReserve | nonReentrant, PoolOps measured sweep/deposit, OG share credited immediately to outstanding. toReserve=false relaunch accounting is distinct. Requires asset/ledger invariant evidence, not narrative alone. |
| setRotationWiring | owner-only nonzero, replaceable rotator/governor. No code/type identity check; owner trusted. Direct facet owner initially zero so no public takeover via this setter. |
| rotateSlice/rotateSliceFrom | Permissionless approved envelope, destination allowlist, slice1..2500 capped by remaining. Source leg index bounds naturally panic; no explicit nonReentrant on facet OR registry wrapper. Trusted plain quote tokens/manager/rotator assumed; malicious callback scope remains a lead. Removes source share, converts and withdraws destination, unwinds existing destination/launch active positions before remint to retain one tracked NFT. Correct new key uses quote/token, not conversion venue. Consumes governance after success; full rollback on later failures. |
| rotation completion | fromPrimary identifies current denomination, not launch-origin index. Exhausted full mandate flips quote, hook live key, requotes book uncaught, then best-effort sync. PRIMARY_DRAINED_DUST declared but unused; no actual full drain predicate. Geometric percentage budget differs from percent original liquidity; documented residual semantics require UI/governance parity. Mark-source update/valuation across linked pools remains cross-contract gate. |
| floorClaimableNow | view computes floor and spot>reserve upper tick. Indicates reserve band geometry only; does not prove unpaused/configured/sufficient-backing claim succeeds. Registry explicit view-forwarder exists despite stale fallback comment. |
| claimByBurnUpTo | old nonzero generation only, claimGate allows gate or engine, caps by actual holder balance. PoolOps migration return emitted; no additional nonReentrant in wrapper/facet. Prior vesting integration evidence applies but adversarial callback/state accounting must be reconciled. |
| legCount/legAt/_legPosition/_recordLeg | Bound indexing, scan/upsert by quote. Returning launch quote replaces primary active ID and removes legacy duplicate. Existing leg updates ID but not key; safe only while immutable pool configuration implies same key. Source deletion can reorder indexes, so consumers must refresh. |
| recoverLegs/_bookLegProceeds | Public retry only past generations. Matched primary quote and old token become booked sweepable balances; must not double count teardown funding. |
| recoverLegsAtTeardown/_recoverLegs | No access modifier on facet entry: security depends on absent registry stub/fallback; inspected registry confirms explicit dispatcher and internal selector use. Direct facet own state empty, returns0. Per-leg external library failures caught, retain failed entries; successful reverse swap-pop handles full array. Only same primary-pool currency sums into quoteOut, others booked by asset. Gas/leg count cap must be proven at caller admission. |
| legProceedsOf/sweepLegProceeds | Getter lacks registry forwarding; consumer must use events/state reader. Owner-only nonzero sink, clears booking before asset send; failure should revert balance debit. Native callback cannot double spend cleared booking, but other reentrant entrypoints remain to analyze. |

Registry reachability inspected for public rotate, burn-up-to, retry, floor and
sweep stubs. No generic fallback; historical comment claiming fallback is wrong.
Residual obligations: funded multi-leg roundtrip/partial-failure recovery, quote
unit conservation, final open-perp migration, reserves/dust, donation/resale,
callback assumptions, compiler selector/storage and consumer ABI parity. Existing
tests and prior patches need final scope-wide reconciliation.

## Final disposition (2026-09-23)

Final: recoverLegs now completes a successor handoff (FS-successor-01 FIXED); rotateSlice reentrancy lead = FS-rotation-I01 Informational. Storage identical to baseline. Signed off.
