# CollectionLedger source review

Current/frozen SHA256 both
`cd9eb2589dcbb8dadbf80b8d6e4cc340d655ac0f05b8a175bf93dd56d0e16871`.
All source bodies read; no production edits. Final verification pending.

| Body | Review |
|---|---|
| constructor / onlyRegistry | Nonzero immutable registry; all four mutations gated. No external calls in ledger. |
| outstanding | Frozen supply overrides caller-provided live count; saturating subtraction. Registry must provide correct eligible count. |
| floorPerNFT | Zero for no outstanding; floor rounding otherwise. |
| isDeadEnd | Frozen and retired >= supply. Depends on registry disallowing zero-floor treasury resale. |
| credit | Zero rejects; frozen dead-end credits rejected without reverting; live zero-outstanding credits retained. Checked arithmetic, per-gen/global increments identical. |
| redeem | Outstanding required; zero payout permitted; increments retirement and subtracts same payout from both liabilities. Registry must enforce NFT ownership/custody and reserve receipt. |
| buyback | Positive paid and nonzero retirement required; no intrinsic floor pricing or custody proof. Registry owns those checks. |
| crystallize | One-time freeze; rejects new extra entitlement if supply fully retired. Existing live credits are NOT released when freeze creates dead end: reproduced below. |

## Validation

`logs/ledger-review.*`: 24 tests pass, including unit, historical regressions,
three arithmetic fuzz tests and stateful invariants. The handler can mint after
crystallization (ignored by frozen accounting), directly buyback without the
production positive-floor price gate, and counts rejected credits in its ghost
upper bound. It tests internal arithmetic, not reserve backing or exit liveness.

## R23-L3: credit before dead-end crystallization

`logs/ledger-death-credit.*`: new local property fails. Real CollectionLedger,
fixture acting as registry: credit 300 tokens, redeem all three shares, credit
500 while alive, crystallize supply at three without another mint. Both floor
and outstanding are zero, redeem fails, but totalEntitled retains 500 tokens.
Existing T9d tests cover credit AFTER death and live credit followed by another
mint, not this sequence. Reproducer: R23_LedgerDeathCredit.t.sol.

Production call-site inspection: registry flushes legacy credit before
crystallization and then subtracts totalEntitled from new active supply.
PoolOps.buyCollection requires positive twice-floor payment, so its public
resale route cannot revive zero outstanding. This is a reproduced accounting
mechanism with a plausible production path, not yet a fully funded end-to-end
impact proof. Next: demonstrate reachable no-new-mint credit/flush sequence,
quantify impact and assign severity before remediation. Consider clearing only
unclaimable existing entitlement at freeze, preserving live accrual and global
sum, with an observable release event and conservation regressions.

Other open joins: reserve dust, offset versus ETH-burn count, zero-floor live
recycling and treasury custody uniqueness. No full lifecycle sign-off.

## Remediation checkpoint

Promoted to FS-ledger-01 (Medium bounded permanent reserve allocation), based on
the reproduced ledger behavior and inspected production flush-before-freeze
ordering. Candidate patch and limitations are in LEDGER.md. Added two controls
for other-generation balances/repeated freeze and new-mint-before-freeze.
`ledger-death-credit-fix` is compiling at this checkpoint (session 80118).
The older CollectionLedgerInvariant ghost only tracks paid-out and accepted-in;
it needs an explicit released-liability counter for the new transition, with
conservation expressed as accepted-in = outstanding + paid-out + released.
Do not weaken that equality to an upper bound. No completed regression claim yet.

Later checkpoint: initial run terminated 26 pass/1 old-model failure. The ghost
now explicitly predicts released liability from pre-call state, preserving the
exact equality. ledger-release-conservation completed 27/27 passes. Compiled
surface, hash and size checks passed; see LEDGER.md and LEDGER_SURFACE_CHECK.json.
Full-registry impact/validation still outstanding; no process remains running.

Funded integration follow-up: R23_LedgerRegistryLocal deploys actual local V4
managers, hook, registry and ledger, funds the public legacy buffer and swaps,
then attempts empty-collection relaunch. Initial ledger-registry-integration
and diagnostic ledger-registry-trace failed the nonvacuity assertion (zero
pending buyback). Trace shows LegacyBuyLib seeded its first-block reference and
returned (0,0), not a failed ledger property. Updated fixture executes a second
small swap in the next block, respecting the real reference warmup instead of
overwriting storage. ledger-registry-reference-mature session 40137 is active
at this checkpoint; inspect its terminal result before claiming integration pass.

Terminal result: ledger-registry-reference-mature passed (1/1). This proves the
funded empty-collection flush/freeze path completes with no dead-end liability
on the candidate. No live session remains. See LEDGER.md for fixture limits.
