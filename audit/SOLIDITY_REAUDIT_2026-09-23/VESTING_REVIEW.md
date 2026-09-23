# Migration vesting review — in progress

## Snapshot reconciliation

Current HEAD observed during this pass: `20640d02c6a678881b451faf14ee3aa345f84a4d`.
`git diff --stat 31b753546c0e39efb7ae3c28efe9ee4d7fa67df5 HEAD -- contracts/solidity`
returned no changes. This reconciles committed Solidity changes only, not all
consumer files or dirty dependency contents. Root QuoteOracle remediation and
new regression files remain uncommitted; preserve them.

## Executable lane

`logs/vesting-local-review.json` records the candidate-tree batch covering
MigrationVesting, X5i transfer-return handling, X5g grant headroom, and
VestingInvariants. Execution was started in session 53887; consult its terminal
result before counting passes. MigrationVestingGate is deliberately excluded
from this local batch: its seven fork tests explicitly skip without an active
fork. Their integration properties remain pending, not passed.

## Evidence limitations identified from test source

- `VestingInvariants.t.sol:MockMigrationRegistry.claimByBurn` mints live tokens;
  despite the finite-reserve comment, it does not model reserve exhaustion or
  actual registry migration gates. Conservation assertions concern the escrow
  under this mock, not the full protocol reserve.
- Handler `claim` and `claimFor` swallow all reverts. Conservation can therefore
  pass even if claims become unavailable. A separate successful-claim liveness
  property is required.
- `invariant_claimableWithinGrant` actually checks only `released <= total`;
  it does not directly assert its named claimable bound or monotonicity.
- Existing time-dependent tests lack explicit `vm.getBlockTimestamp()` warp
  checks required by this audit. Passing results must not be overstated.

## Dependency boundary pending reproduction

`MigrationVesting._isInstant` uses a typed external boolean call inside
try/catch. Test ordinary reverts versus successful malformed return data and
code-less configured addresses before asserting fallback totality or severity.
The owner can replace/unset this optional oracle; existing grants snapshot
their window and claims do not consult it. No permissionless oracle-control
claim is established.

`PerpStakerOracle.isInstant` derives membership from either positive vault share
balance. Its immutable vault address has no update path; deployment wiring and
the economic meaning of minimal shares require cross-contract verification.

No vesting production changes or confirmed new findings in this checkpoint.

## Next regression prepared

`test/attacks/R23_VestingOracleBoundary.t.sol` adds four isolated dependency
boundary tests: ordinary revert (control), empty successful return,
non-canonical boolean, and code-less configured address. Each requires a
successful conservative migration, actual escrow funding, a recorded grant,
and no instant payout. These are pending execution, not findings or passes.
The existing batch finished with exit 0 in 101.19 seconds: 22 tests passed,
zero failed, zero skipped across four suites. The two fuzz tests each executed
256 cases. Invariant limitations above still apply. Session 53887 is terminal.
The boundary-only run is now recorded separately in
`logs/vesting-oracle-boundaries.json`; its result is still pending.

## Remediation and integration checkpoint

Superseding the pending statuses above: boundary run reproduced three failures
and one passing control; FS-vesting-01 is now recorded in FINDINGS.md and patched.
Focused/neighbour candidate run passed 29 tests (nine inherited duplicates).
Post-fix invariant run `vesting-fixed-invariants` exited 0 in 100.74 seconds,
six tests passed, no failures/skips; session 37148 is terminal. Its mock and
handler limitations remain as described above.

Added `R23_VestingRegistryLocal.t.sol` to exercise actual local managers,
hook, registry, relaunch, claim gate, funded escrow and beneficiary payout
under an empty-response policy. This fixture does not add ambient manager ETH.
`vesting-registry-integration` is pending execution; do not count it as passed.

That initial integration run exited 1: actual escrow receipt was
31,078,446,077,696,115,317,808 versus nominal burn
31,078,446,077,696,115,318,547 (739 raw units short). Source reinspection:
`PoolOps.sol:1393` defines `CLAIM_DUST = 1e12`; `migrateOne:1412` burns nominal
input but accepts reserve output within this bound. The failed test incorrectly
required exact nominal 1:1. Revised test explicitly checks the dust ceiling and
exact escrow-receipt-to-beneficiary conservation. This is a test-model correction,
not a changed production invariant; the original failed log is retained.
The economic adequacy of this absolute dust bound for tiny repeated migrations
remains a separate PoolOps review item. `vesting-registry-conservation` pending.

Corrected integration completed: exit 0, one passed, no failures/skips, 14.68s.
Session 83446 is terminal. The test includes fixture deployment and the whole
lifecycle in its gas total; that total is NOT a migration transaction gas
measurement. This demonstrates real local reserve funding and gate enforcement,
not deployed/fork parity or every batch/partial-claim path.

## Source traversal worksheet

Locations below are candidate MigrationVesting.sol unless specified. This is a
source/property worksheet, not complete machine-readable graph annotation.
External token/registry calls rely on protocol-owned CauldronTokens and registry
wiring. NonReentrant covers all four state-changing user entry points.

| Function / line | Authority and effects | Evidence / remaining gap |
|---|---|---|
| constructor / 147 | Deploy caller supplies immutable registry, owner, bounded window, optional policy | Unit fixture succeeds; zero registry/wrong registry deployment rejection absent; constructor boundary tests GAP |
| startVest / 168 | Caller funds own grant; amount nonzero; pulls/migrates then releases matured grants atomically | R23 real registry conservation and ordinary/instant unit tests; max grants X5g |
| vestBatch / 191 | Anyone may consume holder allowance up to balance; skips zero and 32-grant sub-cap; no automatic payout | Unit skip and X5g spam tests; repeated-holder, reserve-short batch rollback and real instant-policy batch GAP |
| _pullAndVest / 208 | Registry token lookup, 64-grant hard cap, checked transferFrom, burn migration, min(returned,actual receipt), snapshot policy/window/token | R23 local integration; hostile registry under-reporting and generation change during call GAP; immutable registry assumed trusted |
| claim / 249 | Caller-only beneficiary; no payable amount reverts | Linear/stack unit tests and X5i payout rollback |
| claimFor / 256 | Permissionless, payout remains beneficiary | R23 local integration exact recipient payout; X5i failed transfer preserves grant |
| _release / 264 | Loops max 64 grants, effects before transfer, false return reverts, swap-pop drained grants | X5g full-array claim, X5i recovery; mixed-generation ordering and callback tests GAP |
| _vestedOf / 301 | Linear raw-token units; floors partial release, full amount at deadline, zero-window immediate | 256-case linear fuzz plus units; supply-times-window overflow bound and timestamp narrowing proof GAP |
| _isInstant / 308 | Optional owner-selected read dependency; valid canonical true only; no state writes | Four R23 boundary regressions plus true/false units; gas-burning policy liveness remains unproven |
| claimable / 330 | Public sum of vested-minus-released across <=64 grants | Unit + invariants; sums raw quantities across different generation tokens, not an economic valuation |
| locked / 338 | Public sum of total-minus-vested across <=64 grants | Unit + invariants; same mixed-token interpretation limitation |
| grantCount / 346 | Public array length | X5g hard/sub-cap and pruning assertions |
| grantAt / 351 | Public indexed grant; Solidity bounds checks | X5i total/released assertions; invalid index explicit test GAP |
| setVestWindow / 361 | Owner-only, [1h,14d], affects future grants only | Unit ownership/bounds/snapshot tests; exact endpoint tests GAP |
| setStakerOracle / 368 | Owner-only, zero allowed, future grants only | Unit ownership/unset plus R23 configurations; ownership handover GAP |
| renounceOwnership / 381 | Always reverts | X5g confirms owner retained and setter still callable |

PerpStakerOracle.sol:24 constructor pins immutable vault without code validation;
:29 isInstant reads positive ETH shares, otherwise token shares, using short
circuit OR. Interfaces declare ethShareOf/tokShareOf only. No state writes,
asset transfers, or loops. Direct real-vault tier entry/exit tests and dust-share
economics remain GAP. Inherited Ownable transferOwnership and generated getters
need compiler-node/consumer joins; they are not silently counted as closed.
