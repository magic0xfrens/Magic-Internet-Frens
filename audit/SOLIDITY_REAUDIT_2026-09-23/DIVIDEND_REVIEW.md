# Dividend source review — in progress

Read complete MiFrensDividend.sol. Native and token ledgers share activeShares
but have independent accumulators/debts; ERC20 list is lifetime-capped at three.
Collection transfer hook settles both ledgers into pull balances; current owner
must recast. Registry/funder are treasury-wired once to a nonzero value (setting
zero does not consume the one-time slot). No production edit in this checkpoint.

## R23-L3: residual accounting hypothesis

Native receive computes scaled inc=(amount*1e18)/activeShares, credits inc, then
stores residual=amount-floor(inc*activeShares/1e18) in whole wei. With three
shares and one wei, a fractional entitlement is already credited while residual
still equals one wei. Repeated zero-value receives could credit the same wei
again and create aggregate pending greater than custody. Must execute before
severity/remediation. Caller need not control treasury, registry, or token code;
the entry is public receive. Economic scale per repetition is small and must
not be confused with an immediate material treasury drain.

Added R23_DividendResidual.t.sol using the real genesis/dividend deployment from
the local T9b fixture: three minted/enchanting owners, one wei deposit, six
zero-value calls, unchanged-balance/accumulator/solvency assertions.
`dividend-residual-boundary` session 7197 pending. This property is separate
from T9b's two-share ETH test, which uses an exactly divisible deposit.

Other pending boundaries: _tryPush ABI decoding can itself revert despite its
failure-return contract; _pull accounts nominal rather than actual receipt;
fundToken/adopt and cast paths lack shared reentrancy protection. These are
leads requiring reachable trusted-token/registry/callback analysis, not findings.
The existing T9b reentrant-registry test uses a synthetic malicious privileged
registry, so its asserted double count alone does not establish permissionless
production reachability.

## Confirmed residual defect and candidate arithmetic

Second pre-fix run `dividend-residual-solvency` fails directly: pending sum 6
versus custody 1. Classified FS-dividend-01 Medium (dust-scale accounting and
claim availability; no material profitable drain shown). Candidate receive
computes credited=inc*shares, committedWei=ceil(credited/ACC), then retains only
amt-committedWei. Because credited<=amt*ACC, the subtraction is safe and each
whole wei retained is disjoint from scaled entitlements already allocated.
The multiplication bound is no larger than the existing amt*ACC computation.
For realistic shares<ACC, division leaves less than one wei of unallocated
fractional dust per receipt; more precisely <shares/ACC wei. Existing per-claim
flooring remains unchanged. No new storage or callable function added.

Focused/neighbor compilation session 45070 is still live (22 source files under
solc 0.8.30); do not restart it. Prepared separate
R23_DividendConservationSequence.t.sol with 24 deposit steps, two-to-three-to-two
active-share changes, actual NFT transfer, interleaved claims, and per-step
aggregate liability/custody assertions. This new sequence has not run yet.

Superseding pending results: residual-fix batch 13 passed (three inherited
duplicates); conservation sequence 256 cases passed. Fresh compiler surface
verified unchanged ABI/selectors/storage; runtime +28 bytes to 8,078. See
FINDINGS.md FS-dividend-01. Those commands are terminal.

## R23-L4 — malformed payout return boundary

Existing AuditPoC5 test_D2 models a trusted basket token turning hostile after
funding, but covers ordinary revert/false outcomes. `_tryPush` decodes nonempty
returndata as bool without validating length/canonical value; decoding can
revert the entire claimTokens loop rather than banking only that asset.
Added R23_DividendMalformedPayout.t.sol: authorized funder registers synthetic
token while healthy, token later returns invalid boolean before any transfer,
healthy second asset must still pay, failed first asset must remain owed and
recover after restoration. Session 21600, dividend-malformed-payout pending.
No permissionless basket registration is claimed. The synthetic token is a
dependency-failure model, not evidence that current configured tokens behave so.

Remediation analysis must also consider tokens that move balances and THEN
return failure/malformed data: simply treating invalid bytes as false can bank
an already-paid liability. Preserve atomicity of a failed individual payout
before claiming generalized hostile-token safety. Gas/return-data bounds and
trusted-asset assumptions remain explicit review items.

Malformed response run exited 1 as predicted; candidate FS-dividend-02 now
isolates each payout in self-only pushTokenIsolated. The helper bounds copied
return data to 32 bytes, accepts empty or canonical true, rejects no-code
targets and reverts on any invalid result. _tryPush catches that frame's revert,
so token movement is reverted before the outer call banks its liability.
No new storage; one intentional external selector. Prior residual-only ABI
report is stale for this newer candidate and must be regenerated.

Prepared R23_DividendPayoutAtomicity.t.sol (not yet executed): standard ERC20
subclass moves balance then returns false; test requires isolated rollback,
healthy second-asset delivery, retained accounted/owed balances, one successful
retry and no second payment. Separate test attempts direct helper access from
an NFT owner and requires NotOwner plus unchanged custody. Initial payout batch
session 85028 still compiling at last poll; serialize the new run behind it.
