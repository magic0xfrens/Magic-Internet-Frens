# Fresh remediation ledger

## FS-surtax-01 — Medium policy fallback availability; candidate patch

Actual funded local-manager hook swap with owner-wired empty-return surtax
policy reverts; ordinary reverting-policy control succeeds. No outsider control
of policy selection or theft demonstrated; owner can replace/unset dependency.
Evidence: fee-policy-treasury-acceptance direct-library failure, then
surtax-hook-boundaries-corrected 1 fail/1 pass. First surtax-hook-boundaries
attempt was a test compile error (wrong setter name), not a protocol failure.

Patch claimed in SurtaxLib.surtaxBps only: single-word bounded STATICCALL,
minimum response length, same valid-value cap and built-in fallback. Scratch
memory [0,32) only, input allocated first, short reply cannot be accepted.
No storage/signature changes by source inspection; no gas-exhaustion guarantee.
surtax-policy-fix launched; inspect live session/result before claiming verified.
No other production files changed for this remediation.

SURTAX_SURFACE_CHECK.json passes: candidate hash
a83bfde89367484756b24f69fb6ce002c8491a4b5efc89f0a126b4e5d4b06aad,
same compiler, unchanged ABI/selectors/storage; fresh graph has 35 sensitive
sites and no unresolved references/selectors. Bytecode regression run 84542
still active, compiling 145 files; do not treat AST results as runtime validation.

## FS-feerouter-01 — Medium, reproduced, not patched

Faulty owner-configured fee router bypasses built-in fallback through empty
return decoding or overflowing returned sum. Actual funded swaps fail; ordinary
revert control passes. Evidence: fee-router-boundaries, 2 failed/1 passed;
source/caller analysis and planned validation in FEE_ROUTING_REVIEW.md.
Claim scope for next remediation: CauldronHook fee split validation and, only
if required for EIP-170 headroom, FeeRouteLib helper. No source edits yet.

Candidate implemented inline in CauldronHook: fixed three-word memory output,
STATICCALL matching IFeeRouter.view, minimum 96-byte length, and subtraction-
bounded equality rather than overflow-prone addition. Buffer allocation precedes
assembly; only allocated 96 bytes written; invalid/short output never accepted.
No state or ABI addition by source inspection. Baseline runtime 24,374 bytes
(202 headroom); candidate size must be measured before accepting placement.
Candidate SHA256 84c16c0b9967f183db6c25e99fbb82124976f9076e0c316b34bbc6cb5a40f8bf.
fee-router-fix is compiling 140 files, session 92250; results pending.

AST check completed separately: HOOK_SURFACE_CHECK.json confirms candidate
source hash, same compiler, unchanged ABI/selectors/storage, no unresolved
references/selectors. Fresh graph 1,096 declarations, 3,445 calls, 34 sensitive
sites and 168 surfaces. This does not establish runtime size or regression
results; session 92250 still active at last poll. Do not restart that job.

Prepared R23_FeeRouterAcceptance.t.sol for the next batch after that compilation:
wrong sum, 32-byte short reply, valid all-guild split, valid prefix plus trailing
word, and codeless router. Assertions check exact recipient balance, so always
falling back cannot masquerade as preserving custom routing. Explicit native
300-bps base tax, 1000-bps default guild share, no surtax/proposer/buyback carve.
These five cases are not executed yet. Earlier B03 surtax suite inspection also
shows it replicates a formula rather than calling current SurtaxLib; future
policy validation must test the implementation directly, not count that replica
as current-source coverage.

Latest continuation: same session 92250 still reports running without terminal
output; no replacement compilation launched. Prepared tests remain unexecuted.
Started partial TreasuryGovernor traversal in TREASURY_REVIEW.md; it is not
included in completed source-body traversal count.

fee-router-fix TERMINAL: exit 0 after 614.5 seconds; 3/3 fallback properties
pass. Candidate hook runtime 24,401 bytes vs 24,374 baseline (+27), 175 bytes
below EIP-170. Existing ABI/storage checks pass. Queued tests now running as
fee-policy-treasury-acceptance (session 95770); selected only new treasury
properties, excluding inherited duplicate tests. Do not conflate this combined
batch's expected lead failures with fee-router remediation results.

Acceptance batch TERMINAL: 9 pass, 3 fail. All FIVE fee-router exact-payout
cases pass, giving eight targeted fee-router passes overall. Surtax empty-return
fallback fails (ordinary revert and cap controls pass; direct 256-run curve fuzz
passes). Treasury lower-id tie and stale-cancel properties both fail against
the mock-votes fixture. No test job remains active. Next: severity assessment
and actual hook propagation for surtax; treasury issues likely bounded Low
behavior/specification mismatches, not unauthorized majority override.

## FS-ledger-01 — dead-end pre-freeze credit; candidate patch

Medium, bounded permanent unclaimable reserve allocation; not demonstrated theft.
CollectionLedger.crystallize rejects new extra credit at zero outstanding but
previously retained credit accrued while live after all shares retired. Local
failure logs/ledger-death-credit.* reproduces 500 tokens still booked after
all three shares retire and supply freezes. Registry source establishes the
ordering: _flushLegacyAtRelaunch -> PoolOps.materializeLegacy -> doLegacyNote ->
credit, then crystallizeCollection, then totalEntitled-based reserve sizing.
Treasury resale requires a positive floor and therefore cannot restore a share
once frozen outstanding is zero. Actual funded full-registry scenario remains
to be validated; the ledger fixture supplies registry authority, not an outsider
ability to credit arbitrary numbers.

Candidate change releases existing entitledTokens when mintedAtDeath <= retired,
subtracting exactly the same amount from totalEntitled and emitting the new
EntitlementReleased event. Existing live accrual and claimable frozen pots remain
unchanged. Storage and function signatures unchanged by inspection; event ABI
addition and compiled surface/size checks still require validation. No token
transfer: previously committed reserve becomes surplus accounting backing.
Baseline source cd9eb2589dcbb8dadbf80b8d6e4cc340d655ac0f05b8a175bf93dd56d0e16871;
candidate 2a3e82bc170445b8706fa4b83dbb10ff3e4ae094ce10267d665aeeb084b1ef23.
Regression command recorded as ledger-death-credit-fix; do not assume success
without its terminal result. Production file ownership is this audit patch;
snapshot remains unchanged. Previously deployed ledger state is not repaired.

Targeted verification: ledger-death-credit-fix completed with 26 passes and one
old ghost-model failure (accepted credits were not reduced by released liability).
The minimal failing handler sequence was credit then freeze without any mints.
Updated the exact invariant to accepted = outstanding + paid + released, with
release predicted from pre-call supply, retirement and entitlement (not inferred
from a post-call balance delta). ledger-release-conservation then passed all 27
tests across seven suites, zero failures/skips. No live test process remains.

Fresh compiler graph: 1,096 declarations, 3,445 calls, 33 sensitive sites,
168 surfaces, zero unresolved references/selectors. LEDGER_SURFACE_CHECK.json
confirms current hash/compiler, unchanged storage and selectors, and precisely
the expected new event ABI. Runtime/init bytecode 1,972/2,185 -> 2,092/2,305
bytes (+120 each); runtime headroom 22,484 bytes. git diff --check passes.
Same-reviewer source verification: release only after one-time freeze check,
no external calls, checked subtraction, exact global/per-generation debit, no
change to live credit acceptance or existing claimable pots. This remains
targeted verification; funded registry integration and full-scope checks pending.

Funded registry integration now passes: ledger-registry-reference-mature, one
test, zero failures/skips. Actual local V4 managers, registry, hook and ledger;
public buffer funded with 0.1 ETH, real swaps across two blocks acquire nonzero
pending tokens, collection outstanding asserted zero, actual relaunch reaches
generation two and clears pending buybacks with no dead-end entitlement.
No forced production storage or impersonated registry credit. Governor fixture
remains a mock; all-retired nonempty integration and baseline end-to-end
comparison are not established by this empty-collection case. Full scope pending.

## FS-oracle-01 — patch verified in targeted and neighboring suites

Severity: Medium. Confidence: VERIFIED for dropped volume after malformed feed;
false death classification DERIVED from isDead's threshold comparison. Status:
Fixed with targeted verification; full-scope final validation pending. Root
claimant: this audit agent; no delegated writers. See VERIFICATION.md: 42 focused
and 146 neighboring tests passed, no failures/skips; ABI/storage/size checked.

Claimed production file: contracts/solidity/cauldron/QuoteOracle.sol.
Functions: usdPerRawUnit, _sequencerOk, and internal read/validation helpers as
needed. Preserve external ABI, storage and normal rounding/caching policy.
Do not modify hook or registry for this remedy. Baseline snapshot stays unchanged.

Proof: logs/oracle-failure-boundaries.* (five unit failures) and
logs/oracle-hook-lifecycle.* (one control passes, one property fails).
The production-hook test executes a funded trade after 25 hours and sees zero
new volume under malformed data, versus positive volume and alive classification
under an ordinary reverting dependency. No target state is force-written.

Precondition: configured trusted feed returns invalid data (dependency incident
or bad privileged setup), nonzero death threshold and aged-out prior volume.
This is not an unprivileged ability to choose the feed. Blast radius: consumers
of that feed; volume/crystal accounting unavailable while malformed, and a
generation may satisfy death threshold despite current trading. Zero threshold
or sufficient other-pool volume defeats the death impact, not dropped volume.

Remediation hypothesis: validate low-level round/decimal return data before
decoding; refuse unrepresentable arithmetic as zero/unpriceable; preserve the
last-good cache and its truthful timestamp. Re-test ordinary valid feeds,
sequencer handling and live-price rotation refusal. No feed failure should be
turned into an invented price. Treat this remedy as unverified until tested.

Implemented in root QuoteOracle.sol: fixed-prefix STATICCALL helper (one/five
words), explicit short/malformed ABI checks, normalized arithmetic overflow
guards and shared safe round reader for sequencer checks. No external function
or state-variable added. Original snapshot remains unchanged; hash comparison
of all 4,304 baseline inputs shows only root QuoteOracle.sol differs.

Completed: logs/oracle-fix-regressions.* (session 11212, exit 0) and
logs/oracle-fix-neighbors.* (session 37311, exit 0). No live test command remains.

Compiler-surface verification passed via verify_oracle_surface.mjs:
ABI/selectors/storage unchanged, same compiler, current source hash matched,
zero unresolved compiler references/selectors. Evidence:
remediation/ORACLE_SURFACE_CHECK.json and remediation/COMPILER_GRAPH.json.
Candidate QuoteOracle SHA256:
753907d4c41ce9ac00cdba3dc814b0011bc632d55d930f21a7f43cb281078ffa.
This does not establish bytecode size, deployed parity or regression success.

Separate source review of the patch: fixed-prefix buffers are allocated before
STATICCALL; the return-length check precedes full-width ABI decode; uint80
round fields are validated explicitly; decimals above 95 are rejected before
exponentiation; quote decimals above 77 are rejected; both multiplications are
guarded before execution. No cached timestamp is refreshed on rejected data.
Only one/five-word private calls reach the buffer helper. Gas-burning dependency
calls can still exhaust available gas; no universal dependency-liveness claim.
This verification is by the same reviewer, not an independent human/agent.

Required verification: baseline failures retained; focused unit/integration,
neighbor oracle/cache/rotation tests, compiled ABI/storage comparison and size;
full applicable validation still pending. No push/deploy authorized.

## FS-vesting-01 — active remediation claim

Claim: root `contracts/solidity/cauldron/MigrationVesting.sol::_isInstant` and
`test/attacks/R23_VestingOracleBoundary.t.sol`. No dependency or owner files.
Medium, bounded migration availability: owner-configured malformed/code-less
policy blocks new migrations despite conservative fallback intent. Ordinary
reverts fall back. No permissionless policy control, theft, or permanent lock
demonstrated. Existing grants do not depend on this oracle; owner can unset it.
Before-fix evidence: `logs/vesting-oracle-boundaries.*`, exit 1, three failed
fallback properties and one passing ordinary-revert control. Use bounded
one-word STATICCALL decoding; preserve ABI, storage, valid true/false semantics.
After-fix regression, size and compiler surface validation remain required.

Focused verification completed: `vesting-policy-fix` exit 0, 29 passes including
nine inherited duplicate tests. Fresh compiler graph has 1,095 declarations,
3,442 calls, 32 sensitive sites, 168 surfaces, zero unresolved references or
selectors. `VESTING_SURFACE_CHECK.json` confirms unchanged ABI/storage/selectors
and source hash `5bcbfaebd8882ad9b2bd7f58705c9fb3a42faf795a12dca0167baeffaa2386b8`.
Runtime/init sizes are 4,740/5,187 bytes, each 17 bytes smaller than baseline.
Post-fix invariant session 37148 remains active at this checkpoint.

Second source pass (same reviewer): STATICCALL output uses Solidity scratch
space [0,32), never overwrites the free-memory pointer; the full input is
allocated beforehand. Short returns cannot grant instant status because valid
is false, even if scratch contains stale bytes. Only a successful response of
at least 32 bytes whose first word equals 1 grants instant status. Canonical
false and invalid words conservatively vest. No unbounded returndata copy.
Gas-burning policies remain a separate limitation; the patch does not promise
fallback after every possible gas exhaustion. Full-scope verification pending.

## FS-dividend-01 — active remediation claim

Claim MiFrensDividend.sol receive residual calculation and
R23_DividendResidual.t.sol. Confirmed Medium accounting/claim availability:
three actual genesis holders, one wei deposit, six public zero-value receipts
produce six wei aggregate pending versus one wei held. Evidence
dividend-residual-solvency exit 1; prior accumulator reproduction also fails.
Cost is gas per repeated call, additional funding zero; error grows at dust
scale, not evidence of profitable material theft. Proposed fix rounds the
already-credited aggregate UP when calculating whole-wei residual, so no part
of that credited wei can be redistributed. No ABI/storage change intended.

Implemented and targeted verified: dividend-residual-fix 13 passes, no skips
or failures; dividend-conservation-sequence 256 passing fuzz cases. Sessions
45070 and 26518 terminal. Fresh AST graph session 29791 terminal, zero unresolved
references/selectors. DIVIDEND_SURFACE_CHECK.json confirms unchanged ABI/storage/
selectors and hash 66424f6023d95bc4009e362d170f95f2213b6a80d4ec7e0b14a5e3bab217d229.
Runtime/init 8,078/8,783 bytes, +28 bytes each; runtime headroom 16,498 bytes.
Same-reviewer verification; full audit and deployed parity remain pending.

## FS-dividend-02 — active remediation claim

Claim MiFrensDividend._tryPush and new self-only payout helper, plus
R23_DividendMalformedPayout.t.sol. Medium dependency-failure availability:
authorized basket token returns malformed bool and blocks all claimTokens legs.
Before-fix log dividend-malformed-payout exits 1 on real dividend/collection
with synthetic funder-authorized token. Not permissionless asset registration.
Remediation needs a revert-isolated self-call so false/malformed responses also
roll back token-side movement before banked entitlement is created. This adds
one external selector, gated msg.sender==address(this); no new storage intended.

Targeted verification completed: 22 payout-isolation tests and two dedicated
atomicity/authority tests pass. Sessions 85028 and 91530 terminal. New compiler
graph 1,096 declarations, 3,444 calls, 33 sensitive sites, zero unresolved
references/selectors. DIVIDEND_SURFACE_CHECK.json allows exactly the documented
self-only helper (e184e3bb), preserves every baseline entry and storage layout,
and pins source b9c4157819c5ca9413dcb2f4d184a2bc076d40303996135afeb577ef94595944.
Runtime/init 8,194/8,899 bytes. Prior residual-only surface/size figures are
historical. Frontend uses selected public dividend ABI, not the self-only helper;
complete ABI consumer/deployment joins still pending. Same-reviewer verification.

## Terminal regression checkpoint — surtax and gacha/churn

Later active checkpoint: FS-badge-floor-01 reproduced an art-floor withdrawal
using a badge; see `badge-floor-impact` for exact raw amounts. Candidate PoolOps
SHA256 622266d2588da1d62a9426484df598e003277cd58b4dc517729a199607ea7b82;
CauldronVault b374dd5c5a645d9fc0cc61b96b6dcc37fed927e9d56b7d7976cf00f9105e0081.
Session 52920 (`badge-floor-fix`) was authoritatively polled and remains live.
Do not duplicate compilation. New standalone R23_BadgeLegacyVault test is queued
for the next batch; added after the current build began, so no execution claimed.
It covers rejected badge state preservation plus both legitimate art payouts.
`git diff --check` passes. PoolOps/Vault AST surface and bytecode size checks remain.

Session 84542 (`surtax-policy-fix`) completed: exit 0, 642.45s, seven selected
tests passing including 256 default-policy fuzz cases and funded malformed-policy
fallback. SurtaxLib runtime/init 723/753 -> 687/717 bytes. Seventh Medium patch
now has targeted evidence; not full-scope certification.

Session 25670 (`gacha-churn-review`) completed: exit 1, 15.10s, eight passes and
one failed earned-pity preservation property. Failure reproduces a conditional
library mechanism; production validator configuration reachability remains
unproven and historical registry impersonation is insufficient. Actual funded
three-loop native churn and impossible-minimum atomic rollback both passed.
No live test job remains at this checkpoint. Next work must distinguish this
conditional lead from confirmed production findings and continue remaining scope.

## Continuation checkpoint — badge verification and perp lead

`badge-floor-fix` is terminal: exit 0, 21 pass/0 fail/0 skip.
`badge-legacy-acceptance` matched no tests because the anchored name excluded
the signature suffix; its exit is not test evidence. Corrected selection in
`badge-legacy-and-earned-yield` executes two tests: badge legacy admission/state
conservation/art payouts PASS; earned-yield guard FAIL on mock engine.
Both commands are terminal. No production edits in this continuation.

Re-ran PoolOps/Vault source-matched surface checks: all pass. Recorded compiled
baseline/candidate sizes in remediation/BADGE_BYTECODE_SIZES.json:
PoolOps runtime 24,193 -> 24,465; vault runtime 2,402 -> 2,495.
Same reviewer; no deployed parity or full liquidation-to-badge proof claimed.
The perp failure is an unconfirmed-impact lead requiring funded production
engine reproduction before severity and remediation.

## Production earned-yield continuation

Added R23_VaultReplacementYield.t.sol (test only). Run
`perp-replacement-earned-yield` terminal exit 0: 1 pass/0 failures/0 skips.
Verified outage plus restoration control on production engine/vault.
FS-perpvault-01 Medium confirmed, unpatched. No production file claim yet;
remedy must handle write-offs/quote scaling and exclude orphan dust.
PerpVault source traversal complete; annotation table records remaining gaps.
Progress 24/66 traversed, 0/66 final sign-off. Goal remains active.

## FS-perpvault-01 remediation claim

Claim PerpVault.sol only: append private aggregate of settled current-epoch
reward units; maintain in _settleTok, _syncTokYield, claimTokYield; consult in
hasStakers after principal/queue checks. No engine production edit planned.
Unobserved write-off invalidates settled debts in the view exactly as in claim.
Orphan yield/accumulator rounding is never included. A positive internal debt
rounded to zero current quote may be cleared by its owner through claimTokYield
without sending zero to the engine; truly empty claims retain ZeroAmount.
This intentional zero-rounded-claim behavior avoids trapping attributable dust.
New appended storage requires fresh deployment; no live upgrade is authorized.
Tests: block replacement before payout, allow after; multiple users; orphan yield;
lazy write-off; quote scaling; failed payment rollback; neighboring vault suites.

## FS-perpvault-01 terminal verification checkpoint

perp-earned-yield-fix session 65156 terminal exit 0 after 138.4s: 32 passes,
0 failures/skips (25 distinct tests; 7 inherited repeats).
perp-reward-scale-and-mark-boundaries session 6377 terminal exit 0: five passes
(two vault scale cases, three mark boundary cases). perp-mark-existing session
70896 terminal exit 0: eleven passes. No live test job remains.

Fresh graph 1,096 declarations/3,453 calls/35 sensitive sites/168 surfaces,
zero unresolved compiler references/selectors. PERPVAULT_SURFACE_CHECK.json
permits only appended _settledTokYield and unchanged ABI/selectors. Recorded
bytecode sizes in PERPVAULT_BYTECODE_SIZES.json. Same-reviewer verification.

Next: resolve dust-clearing consumer flow; add stateful current-epoch aggregate
conservation checks; validate real requote paths; reproduce malformed mark
dependency boundary; continue PerpEngine and PerpSwapLib complete traversal.
25/66 source traversals and 0/66 final sign-offs.

## FS-perpmark-01 claim — production beforeSwap availability

perp-mark-before-swap-recipient terminal: one failing malformed-source funded
buy, one passing reverting-source buy; neither scenario calls public poke after
wiring the source. The initial run checked the payer instead of the recipient;
corrected recipient assertion passes control. Production hook + engine + local
managers, one healthy short; configurable source is faulty owner configuration,
not outsider source selection. _doSweep internally calls _pokeFunding before
liquidation, so keeperless pre-swap liquidation is the tested path.

Medium confirmed availability defect. Claim only PerpEngine._currentTick:
accept full word only within TickMath.MIN_TICK..MAX_TICK, otherwise existing
primary fallback. No ring reset, external keeper requirement, or hook edit.
Pending: boundary/valid-value preservation, funded hook regressions, source
surface/storage and bytecode-size verification. Existing polluted deployed
rings are not retroactively repaired by an undeployed source patch.

## Current continuation — source traversal and running verification

PerpSwapLib and PerpEngine executable source traversal documented, plus all four
shared interface/schema files: 31/66 read, 0/66 finally verified. Constructor,
asset, callback, setter and lifecycle gaps remain explicit in new worksheets.
Compiler-packed engine slots checked against current graph in
PERP_PACKED_SLOT_REVIEW.json; this is not a dynamic mutation-isolation test.

FS-perpmark-01 candidate source beaa831a370ec2bdd31bcc00fb0a20bafdd7b4a3f49602f27018e79434cbe9bf.
PERPENGINE_SURFACE_CHECK.json passes with no ABI/selector/storage change.
perp-mark-range-fix session 70859 is confirmed live by tool polling; do not
restart. Compile includes 104 files with 0.8.30 and 9 with 0.8.26; latter finished.
R23_MarkAcceptance and R23_VaultRewardSequence were added after that build began,
so they are queued for the next batch and no execution is claimed for them.
Draft PERP_RECOVERY_RUNBOOK.md records dust-claim consumer limitations and warns
that already-poisoned rings require independent recovery simulation. No keeper
requirement introduced; user-confirmed beforeSwap liquidation remains primary.

## Terminal checkpoint — mark fix and sequence acceptance

Session 70859 finished exit 0 after 506.18s, four tests executed/passed, no skips.
Session 87339 finished exit 0: five mark acceptance tests plus one vault
sequence fuzz property (256 runs x64 actions) pass. Session 85690 terminal
exit 0: 15 neighboring tests pass across two local suites, no skips.
Unmatched PerpEngineTest and other regex names are not counted as executions.

Both versioned engine compiler artifacts match current source metadata keccak;
runtime/init 24,207/26,229, 369 runtime headroom. Unversioned PerpEngine.json
is stale (old source hash/24,168 runtime); recorded explicitly in size report,
not accepted as deployment evidence. No artifact deletion or deployment made.

Source traversal now 35/66 after vendored BaseHook/HookMiner, shared CauldronBase,
and CauldronGovernor reviews. Registry/base/facet storage equality checked
recursively (61 entries), source hashes match current compiler graph.
Nine Medium patches have targeted evidence, zero full-file final sign-offs.
No live test process remains. Next: registry/redemption/PoolOps lifecycle,
governor bench reachability, token payout malformed/atomicity leads, remaining
consumer/deployment parity and full-scope invariants.

## Governor bench and launch helper continuation

## Bounded bench characterization

`governor-bench-continuation` failed the proposed stronger invariant that every
voted, unconsumed proposal remains discoverable. Nine contemporaneous proposals
with weights 1..9 leave proposal 1 unconsumed but undiscoverable after consuming
9..2. Source explicitly permits eviction by higher weight from an eight-slot
bench; this alone is not classified as a new security finding.

`governor-bench-recovery-snapshot` passes one characterization: winner reverts
NoProposals after that sequence, then a fresh proposal/vote becomes selectable
only after its voting period. No permanent governor freeze demonstrated.
The intermediate `governor-bench-recovery` run failed SnapshotNotReady; the
fixture now advances from the freshly stored proposal snapshot/deadline rather
than repeated compiler-cached block expressions. Both failures remain in logs.

Limits: mock historical voting weights, test contract as authorized registry;
no actual NFT checkpoints or registry relaunch execution in this fixture.
Potential stronger adversarial case (all eight slots already settled, new
higher-weight open candidates evicting them) remains to be characterized.
No production change; no final sign-off.

LaunchSniper full traversal added; launch-sniper-regressions: four passes, zero failures/skips, mock launch limitations in LAUNCH_SNIPER_REVIEW.md.

## Art/storage and settled governor continuation

Four full traversals documented in ART_STORAGE_REVIEW.md. art-renderer-regressions
executes five passing X9a tests only; FrenRendererTest excluded by profile.
check_art_bound.py and hashed ART_BUFFER_BOUND.json bound local assets only.
Unchecked renderer buffer under arbitrary owner uploads remains an open lead.
Governor settled-bench flood batch: two passes, zero failures/skips; seven
settled candidates survive eight higher-weight open proposals. See worksheet.


Latest terminal checkpoint: **41/66** traversed, **0/66** final sign-offs.
LiquidatoorRenderer full source worksheet added, ten local tests pass.
Five real-blob FrenRenderer tests now actually execute and pass via explicit
import under cauldron profile. Standalone render profile compile failure is
retained. Dense valid owner upload reproduces renderer panic: Low
FS-artbuffer-01, unpatched, failing property retained. No production edits;
no test process active. Full validation and all prior gaps remain open.

Latest checkpoint: **51/66** source traversals, **0/66** final sign-offs.
Five deployment helpers, three interfaces and two testnet mocks documented.
Two Low source-confirmed script workflow defects recorded; runtime reproductions
remain pending. No new runtime passes claimed and no scripts broadcast.

Latest terminal checkpoint: **55/66** traversed, **0/66** final sign-offs.
Four more deployment/art/probe files documented. Factory operation identity and
original-calldata recovery verified by one passing local test with actual
TimelockController/factories and stub registry target. No script broadcast.
Remaining script leads include zero upload batch and supplied mark ownership
handoff; no stronger severity asserted without impact verification. No live jobs.

Latest checkpoint: **59/66** traversed, **0/66** signed off.
Volume/rotation/venue files fully read, including deployed VenueSeeder helper.
Open leads: repeated seed overwrites only stored positionId; band tick formula
appears about tenfold wider than documented. Funded/runtime tests remain needed;
no production edits, broadcasts or new runtime passes in this continuation.

Latest checkpoint: **60/66** traversed, **0/66** final sign-offs.
Funded real-manager reproduction confirms Medium FS-venueseed-01: repeated seed
orphans prior LP NFT. Both seed entrypoints now reject a live stored position;
postpatch recover/reseed regression is RUNNING, session57962 / venue-reseed-guard.
No pass claimed until terminal evidence. Nine earlier Medium patches retain
prior targeted verification; new tenth Medium candidate pending verification.
DeployCauldron traversal identifies obsolete hook permission flags (beforeSwap
bits missing); source worksheet records pending reproduction/remediation.
No broadcasts; git diff --check passes.

Latest terminal checkpoint: **61/66** traversed, **0/66** final sign-offs.
Genesis source traversal complete. genesis-lifecycle-regressions: 48 test
executions across11 suites pass, zero failures/skips; inherited/repeated tests
are not 48 distinct security properties. Includes refunds, discount mint, caps,
cancelled ignition, genesis-only voting and three-asset dividend transfer paths.
Venue guard test passes both rejection paths plus recover/reseed/recover. Tenth
Medium now patched with targeted verification; full-scope validation remains.
No test jobs active, no broadcasts. Five large source files remain for traversal:
DeployLaunchpad, CauldronRegistry, CauldronHook, PoolOps and RedemptionExt.

Latest checkpoint: **62/66** traversed, **0/66** signed off.
Full Launchpad review found optional band mode intentionally double-seeded the
same helper. Guard alone would break this supported flow; candidate now uses
separate recoverable full-range/band helpers and logs both. Compatibility and
preflight tests RUNNING session49871 / launchpad-venue-compatibility.
Prior venue guard pass is not sufficient evidence for changed launchpad flow.
No broadcasts. Remaining four files: hook, registry, PoolOps, RedemptionExt.

Latest terminal checkpoint: **63/66** traversed, **0/66** final sign-offs.
RedemptionExt traversal and registry dispatcher boundary review documented.
launchpad-venue-compatibility finished6 passes/7 failures: venue two-helper
lifecycle passes, environment-mutating preflight tests raced. Fresh serial
launchpad-preflight-serial rerun passes all12 preflight tests, no skips. Retain
failed batch; use --threads1 for these shared-process environment tests during
final checks. No complete broadcast/script deployment success claimed.
No running jobs. Remaining traversal: CauldronHook, CauldronRegistry, PoolOps.

Latest checkpoint: **64/66** traversed, **0/66** signed off.
Complete PoolOps source traversal documents all linked-library functions and
host assumptions. Dust legacy sweep and small burn/zero payout remain open
leads, not new confirmed findings. No new tests/production edits this turn.
Remaining traversal: CauldronHook and CauldronRegistry. Full validation open.

Latest checkpoint: **65/66** complete source-body traversals, **0/66** sign-offs.
Registry full executable pass documented plus critical narrative inspected.
New unclassified leads: non-native emergency withdrawal denomination, incomplete
rotated-leg successor handoff, freshly flushed OG legacy share delayed by pending
fold order. None is counted as a confirmed finding without runtime impact proof.
No tests/production edits this continuation. CauldronHook traversal remains;
all semantic/final lifecycle gates remain open, regardless of reading count.

## FS-deployhook-01 — Low, constructor-verified deployment flag correction

DeployCauldron now includes both required beforeSwap permission bits. Internal
_hookFlags is the exact source consumed by run and exposed by test subclass.
Old-mask real constructor rejection and new-mask real constructor success each
pass (deploy-hook-permission-offline). Test uses local CREATE2 sender, not the
canonical broadcast factory, and placeholder manager; final deployment gate
remains open. First run crashed in Foundry network client and is retained.
Hook runtime source unchanged by this fix; script helper changes source graph.

## Earned liquidation badge — High remediation integration

R23_EarnedBadgeFloor earns one badge by liquidating an initially healthy short
through an ordinary45ETH buy. No public poke is used even for warmup. Existing
PoolOps admission rejects the owner's recycle with exact `not art`; asserts
unchanged badge owner, claimant tokens and real funded CollectionLedger backing.
`earned-badge-floor-wired` exits0, one pass, zero fail/skip. Local V4 managers,
real registry/hook/engine/collection/ledger. PLV token inventory and shared
manager native inventory are explicit fixture funding; art-mint role still
impersonated, NFT discount dependency mocked. No full deployed-state claim.
Previous fixture failures retained in earned-badge-floor, nextblock and trace.
No production changes in this continuation; funded art-draw acquisition and
remaining full-scope gates still open. Existing22 badge targeted/neighbor passes
plus this one distinct earned-badge property; do not add retries as passes.

## Paid art plus earned badge — expanded High integration

Previous art-role fixture replaced by paid untagged swap, native auto-commit,
two-ticket real resolver and pity win. Configured odds0/pity1 and blockhash
isolate admission from randomness; both NFT types now traverse real issuance.
`earned-art-and-badge-native` one pass, no public poke or mint-role prank.
An initial attempt wrongly attributed untagged credit to recipient (rather than
tx.origin); retained failure. This supersedes the art-acquisition gap for this
scenario, not the full graph/lifecycle gates. Full local profile suite now running
in candidate-cauldron-full-local, session44592; do not duplicate or claim pass.

## FS-gacha-01 — Medium, failed mint erases earned pity; claim (continuation 2026-09-23, Claude)

Reviewer change: Codex session ended on credit exhaustion; this continuation is
performed by a different model (Claude Opus 5.5) in the same working tree. Prior
evidence is re-read from logs, not re-asserted. Same-tree, single continuation
reviewer for this fix; no independent-review claim.

Evidence before edit: logs/genesis-paid-mint-failure.* (exit 1): actual hook,
registry, generation-2 Genesis continuation, paid swap crystals, deployer calls
production MiFrensGenesis.setTransferValidator; forced pity win reverts in
Genesis._update and pity falls 1 -> 0 while opened increments. Library-level
mechanism: R23_GachaFailedMint (8 -> 0).

Claimed production file: contracts/solidity/cauldron/GachaLib.sol, function
resolveTickets win branch only. Keep effects-before-interaction; snapshot the
streak and restore streak/opened in catch (the reverted call's writes, including
any re-entrant frame's, are already rolled back). No storage, ABI, event change.
Baseline SHA256 00db2e4316e93969aae40e311ab51aa055646878b098fe0ab534747bd445b9d2.

Result: logs/gacha-pity-fix.* exit 0 — 32 passed, 0 failed, 17 fork-only skips
(not counted). Candidate SHA256 1b6593e140b0cf28b74bd52c12f6458599278c90a55154f7185b80e0e00869a9.
Diff: +8 lines in the catch branch only (git diff --stat). Claim closed pending
final full-suite/artifact gates.

## FS-relaunch-01 — High, low-gas relaunch strands the perp book; claim

Evidence before edit: logs/registry-perp-leads.* — R23RelaunchGasSkip scan over
6.0M..26.0M relaunch caps (500k steps, state reverted between attempts): 41
completed relaunches, 5 of them (6.0M..8.0M) completed with both funded
positions open; afterwards syncGeneration, forceCloseAllDead and both traders'
close all revert, engine stays on generation 1. Control (full gas) drains book.
Claimed production file: contracts/solidity/CauldronRegistry.sol,
_perpHousekeep(false) branch only. Remove the silent `g > RELAUNCH_TAIL_RESERVE`
skip; always make the gas-capped, non-try call so an insufficient budget
reverts the whole rebirth (markConsumed included) instead of completing it.
Must not increase registry runtime (8 bytes headroom). No ABI/storage change.
Baseline SHA256 = snapshot hash printed above.

## FS-successor-01 — Medium, successor handoff strands rotated legs; claim

Evidence before edit: same run, R23SuccessorLegHandoff: after the documented
armed migrateToSuccessor, the rotated leg NFT stays owned by the old registry
with 31108410940295381152350 liquidity; recoverLegs(current) reverts
CannotClaimCurrentGen (0xbffafcbc) and emergencyWithdrawLP reverts.
Claimed production file: contracts/solidity/cauldron/RedemptionExt.sol,
recoverLegs + new private helpers only. When the live generation's primary NFT
is provably owned by `successor`, the already-forwarded recoverLegs(current)
completes the handoff by transferring each leg NFT to that successor (no
liquidity withdrawal, no price exposure, destination not caller-chosen). Past-
generation retry semantics unchanged. One new facet event. No registry bytes.

Result (both claims): logs/relaunch-successor-fix.* exit 0 — 46 passed, 0 failed,
0 skipped. CauldronRegistry 5831cab4bc5957e77e16453527a9c2ae07a057aab0be01f6de7f8f8b2773c96b; RedemptionExt 1dc4d83fa0d26552d9740f382d09b2ac47b60d9af6cd8e194baa0ebf4abf1d60. Registry diff removes
the skip branch only (comment added); facet adds recoverLegs handoff branch,
_handedOff, _handOffLegs and event LegHandedOff. Size/storage/ABI gates in
FINAL_GATES.json and VALIDATION.md.
