# TreasuryGovernor — source traversal, final verification pending

Started while fee-router bytecode compilation (session 92250) remained active.
Initial whole-file read was truncated; inspected constructor/propose/vote/bench/
execute/cancel/guardian/winner sections separately. Remaining complete-file and
function-by-function reconciliation required; no complete traversal claim.

Observed: snapshots use previous block for ballots, but proposal threshold uses
current votes. Proposal concurrency is allowed; envelope activity/cooldown gate
both propose and execute. Executability includes quorum, expiry and flags.
Winner hint and eight-slot bench avoid unbounded proposal scans. Reusing voting
power across proposals is allowed; bounded bench coverage must be tested against
many independently viable proposals, not assumed safe because eight is large.

Leads (no severity yet, no production edit):
- Winner NatSpec says ties favor lower id. Hint updates on strictly greater
  votes, retaining whoever obtained the tied weight first; bench iteration also
  uses strict greater without an id comparison. Test later-filed proposal voted
  first, then equal support on earlier one.
- cancel(id) disables current envelope whenever that id was executed, without
  tying it to the currently installed envelope. Guardian already has broad
  cancellation authority, so this may be an operational targeting issue rather
  than a new privilege. Test stale-id cancellation after envelope replacement.
- constructor allows zero guardian/registry/votes; deployment configuration and
  intended no-guardian mode need reconciliation, not blanket severity escalation.
- conversionFor truncates fractional slices and fixed-point remainder at each
  step; UI approximation/error bounds and sliceBps > 10000 behavior need review.

No tests executed for this review yet. Existing TreasuryGovernor.t.sol provides
fixture and baseline cases, but does not by itself prove these transitions.

Prepared R23_TreasuryTargeting.t.sol with two explicit properties: equal support
voted in reverse proposal order must honor documented lower-id tie break;
cancelling an old consumed proposal must not clear a newer envelope. Uses the
existing mock votes/allowlist fixture; does not establish real ERC721 checkpoint
behavior. Tests are unexecuted while Foundry job 92250 remains active. Run only
these new test names when evaluating evidence to avoid counting inherited
TreasuryGovernorTest cases as additional independent coverage.

Severity boundary: the guardian already may cancel the current mandate, so a
stale-id targeting failure alone does not establish unauthorized cancellation.
Equal-support selection is a specification mismatch, not evidence that a
minority beats a majority. Assess impact before proposing any fixes; Low/Info
must remain unfixed under the audit scope.

## Later source checkpoint

All implementation bodies now inspected in bounded follow-up reads after the
initial truncated output. Current/frozen SHA256 both
dc61988b3c9fcd5af5566be54987a9278264e20df88507f21ab28f122ff9d636.
This completes source-body traversal, not semantic sign-off or lifecycle tests.

| Bodies | Observations / remaining obligations |
|---|---|
| constructor | Zero timing selects defaults; mainnet minimum timing enforced unless testnet flag; dependency addresses trusted. |
| conversionFor | Whole-slice approximation with per-step floor; uint16 domain permits invalid >10000 slice. No mutation. |
| propose | Current-vote threshold, asset/pricing checks, envelope/cooldown gates, previous-block snapshot. |
| vote | Historical weight, one ballot per address/proposal; hint and bench update on support. Cancelled proposal still accepts ballots while open; winner excludes it. |
| _benchRecord | Eight bounded slots; executable incumbents prioritized; finite candidate loss and cancelled ballot effects need adversarial sequences. |
| execute | Requires passed current winner, active/cooldown/allowlist/pricing checks; writes envelope atomically. External reads precede state, are view/static calls. |
| cancel / setGuardian | Guardian-only; stale executed id can target current envelope by source inspection. New guardian nonzero; no two-step acceptance. |
| winner / _executable / _dead | Hint then bounded bench; fixed eligibility window and monotonic death predicate. Tie rule needs test; hint maximality across cancellation/voting needs review. |
| allowance | Active/unexpired check; primary counter drives remaining budget, native-zero quote remains valid. |
| migrationMandateSpent | Pure counter/intent test, not current expiry/activity check or physical migration ratio. Caller gates must remain coupled. |
| stalled | Both spend counters zero plus cooldown; any secondary progress blocks replacement. Need evaluate unreachable-primary with usable-secondary route. |
| consume | Registry-only; primary and shared counters bounded differently. At most 2*30000 nominal shared bps, below uint16 max; zero bps allowed here, caller must reject pointless slices. |
| _passed / passing | Majority and floored snapshot quorum; trusted historical supply implementation. Unknown proposal fails zero-vote majority first. |
| _settled | Executed/cancelled/time predicate; inspect compiler call map for usage before claiming behavior depends on it. |
| _requirePriceable / setQuoteOracle | Native/unset exempt, other quotes require nonzero oracle read. Guardian sets oracle; a faulty configured oracle can block nonnative proposals/execution. |

RedemptionExt references inspected by location only: allowance at 329, consume
at 590, migrationMandateSpent at 657. Full callback/partial-completion accounting
across those joins remains pending. No treasury test result claimed yet.

## Rotation join follow-up

Read RedemptionExt allowance gate, zero/MAX_SLICE guard, consume-after-move,
and completion branch. `migrationMandateSpent()` is reached only after a live
allowance-gated successful slice, so its lack of its own expiry check is not
by itself a demonstrated expired-envelope bypass at this caller. Quoting flips
before setLiveKey/requoteBook; those failures roll the transaction back, while
syncGeneration alone is caught. Validate downstream adoption, not merely event.

Registry rotateSlice/rotateSliceFrom stubs forward without nonReentrant; facet
entrypoints also have none. Their external-call sequence therefore needs an
explicit callback audit (manager lock, rotator lock and admitted quote assets
may restrict reachability, but must not be assumed to protect the entire
registry state machine). This is a lead, not a confirmed reentrancy finding.
Inspect before adding guards because nested intended workflows and hook size
constraints are part of the compatibility requirements.

## Final disposition (2026-09-23)

Final: FS-treasury-L01/L02 Low retained as failing properties by policy. Signed off.
