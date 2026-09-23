# GachaLib source traversal

Current/frozen SHA256 both
00db2e4316e93969aae40e311ab51aa055646878b098fe0ab534747bd445b9d2.
All six implementation bodies read; no production edits, no final sign-off.

_reanchored/_markReanchored and _seed/_pinSeed access separate namespaced
per-batch slots under hook delegatecall. Correctness requires append-only batch
indices; verify commit/administration never reuse indices. _pinSeeds touches
at most four batches from final cursor, pins only nonzero available blockhash.
No guarantee of pinning every batch in a longer FIFO backlog within 256 blocks.

resolveTickets is bounded by maxCount and captured batches.length. Current-block
head stops FIFO. First expiry reanchors once; second expiry resolves base loss,
except previously earned pity can still win. Pinned seed avoids further expiry.
Counts/pending state and b.resolved update before mint. Both inspected hook
callers share nonReentrant; collection mint is plain _mint. Library alone must
not be presented as generally reentrancy-safe for arbitrary callback hosts.

Win path resets missStreak and increments opened BEFORE try mint; mint failure
records loss but leaves those updates. Determine intended successful-mint versus
attempt accounting, especially forced-pity failures. Collection totalMinted and
maxSupply reads are outside try; malformed dependency return/mint decoding can
still defeat broad 'queue never wedges' documentation. Production collections
are selected through factory/governance; reachability matters for severity.

Entropy depends on commit blockhash, player, batch index and draw index. Block
producer influence and the one permitted expiry redraw remain limitations, not
cryptographic unbiased randomness. Existing historical claims not re-certified.

Next selected suites: R2E_GachaSeedPin, R3A_GachaReRollGrind,
K4b_GachaReanchorGrind, plus actual hook/collection callback joins. None executed
in this traversal checkpoint. Surtax build session 84542 remains separate.

Follow-up fixture review: GACHA1_ResolveLoopExtraction uses real hook/collection
but grants credit through hardcoded vm.store slot 29 and a manager stub. Its
rejecting-validator checks prove queue progress, not preservation of earned
pity or accuracy of lifetime opened. Before relying on this legacy fixture,
reconcile that slot with fresh compiler layout and distinguish forced credit
from a funded acquisition. No fresh execution claimed.

Fresh compiler layout now confirms nftCredit slot 29, creditEpoch slot 30,
gacha slot 35, opened slot 38. The old helper's nested mapping key order
(epoch then player) matches current nftCredit type. This resolves the slot-drift
question only; vm.store credit remains synthetic and no fixture test has been
rerun at this checkpoint.

Subsequent executed evidence: `gacha-churn-review` completed in 15.10s, exit 1.
The failed-mint mechanism reproduces: processed=1, won=0, pending=0, but earned
pity falls from eight to zero. Production reachability qualification below still
applies; no production patch or severity promotion based on this harness alone.
Five R2E tests and the selected R3A/K4b tests passed. Historical test names are
not findings: interpret their assertions rather than their titles. The eighth
passing test is actual funded churn, documented in GACHA_ROUTER_REVIEW.md.

Prepared R23_GachaFailedMint using actual linked library and a small harness:
one ticket, already-earned eight-miss pity, rejecting collection, known mature
blockhash. Property requires queue progress but no pity reset without a mint.
Harness arranges counters directly; this is a mechanism test, not proof of a
permissionless production validator change. Await compilation completion before
running. Source comment identifies opened as lifetime creatures won, not attempts.

Production reachability follow-up: CauldronCollection.mint calls `_mint`, which
passes through `_update` and its configured view transfer validator. A rejecting
validator therefore really can revert mint without advancing totalMinted. However,
`setTransferValidator` requires the immutable `deployer`, explicitly set to the
registry by the factory (not the factory's own address). The historical GACHA1
fixture installs its validator with `vm.prank(address(registry))`; that is not
evidence of a callable production governance path. Direct searches of the registry
and RedemptionExt found no setTransferValidator forwarding call. Until an actual
reachable configuration path or another real mint-failure condition is established,
the pity-reset observation remains a conditional mechanism lead, not a confirmed
production Medium finding. Also check opened accounting independently: the catch
leaves its pre-mint increment in place despite reporting zero wins.

R2E pin-span test is characterization: resolve(0) pins indices 0..3 of eight
batches and deliberately asserts 4..7 remain unprotected. A pass must not be
reported as complete backlog expiry protection. It does not measure funded
user loss, keeper cadence, chain-specific timing, or impossibility of clearing
the backlog in time. Preserve those distinctions in the final limitation ledger.

Full-suite follow-up: failed-pity property reproduces again. Prior reachability
analysis covered CauldronCollection whose deployer is registry; it is insufficient
for iteration2. MiFrensGenesis.setTransferValidator is callable by its explicit
deployer, and Genesis._update validates mints too. Registry._continueMiFrens wires
Genesis as the hook collection. This provides a plausible ordinary privileged
configuration path for failed mint; requires actual Genesis/funded ticket
integration before severity/disposition. No synthetic counter pass claimed.

## Final disposition (2026-09-23)

Final: the failed-mint lead is FS-gacha-01 (Medium), reproduced on the production Genesis path and FIXED (logs/gacha-pity-fix.*, 32/0). Signed off; see SIGNOFF_CHECKLIST.md.
