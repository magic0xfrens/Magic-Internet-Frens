# CauldronGovernor — executable source traversal complete, verification pending

Read all declarations/state and executable bodies, plus voting/bench/curve
narrative. Pure interface helpers, both propose overloads and getters included.
No production edit. This governor is separate from TreasuryGovernor.

| Paths | Behavior and open verification obligations |
|---|---|
| constructor/renounceOwnership/setRegistry | Nonzero voting source, default three-day period or >=60 seconds; owner registry assignment is nonzero and one-time, code/wiring not checked here. Owner cannot renounce, can transfer. Registry bootstrap must be validated. |
| _liveHook/_calibratedSupply/_liveCurveBase | Optional static reads fall back on missing/short replies, but malformed address decoding can still revert. Typed uint values may overflow downstream live*CURVE_BAND. Trusted dependencies and specific production reachability need validation. |
| propose overloads/_propose | Requires current getVotes>0, bounded UTF-8 byte lengths (not semantic sanitization), URI or code-bearing renderer, optional NFT supply calibration, curve-cost band, quote allowlist. Snapshot at creation block; votes must be later block. No proposal deposit or per-user count cap; storage growth and bench policy reviewed separately. |
| vote | Existing/unconsumed/open-time, once per user, snapshot-past-block, historical voting weight, state update then cached leaders/bench. No token transfers; IVotes is external view. Same-block flash vote duplication blocked by past snapshot, but real delegation/checkpoint semantics need integration. Vote allowed exactly at end time; winner eligible strictly later. |
| _benchRecord | Eight slots; already tracked ids stay; unconsumed mature entries protected preferentially, then weakest vote count. More than eight simultaneous mandates can become untracked; mature evictions cannot receive a new vote to re-enter. Availability/specification and winner-order evidence required before severity. |
| _bestUnconsumed/_recomputeLeader | Cached eligible leader is returned directly, otherwise scans only eight bench entries. MAX_LEADER_SCAN=64 is declared but not used by recompute. No fresh claim that all historic proposals remain discoverable. Tie depends on leader/bench order, not an explicit lower-id ordering. |
| winner/hasProposals | Read selection and exact BrewSpec tuple. No quorum condition in this governor; this may be intentional and must not be confused with treasury policy. Quote/renderer/supply validity may change between proposal and consumption. Registry must enforce safe launch fallbacks. |
| markConsumed | Registry-only, existing/not consumed, marks before leader promotion/recompute; registry can consume any id it names, not intrinsically only winner. Trust/access boundary is caller registry implementation. Atomic relaunch rollback and bench preservation require tests. |
| getProposal/displayName/public getters | Existence gate and fixed suffix; byte-bounded user strings still need UI escaping/safe URI handling. ABI overload and dynamic tuple consumer joins pending. |

Existing governance test files are leads, not current passing evidence. Prior
TreasuryGovernor tie/cancel findings are not automatically findings here.
Full lifecycle tests should cover >8 mature mandates, consume/promote ordering,
new high-vote open candidates against settled candidates, snapshots and quote/
curve configuration changes. No final sign-off.

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

Stronger settled-bench case now characterized: governor-settled-bench-flood
passes both tests. Eight fresh higher-weight open proposals displace only the
weakest of eight settled entries: remaining seven are selectable in order.
Fresh candidates replace the unprotected slot preferentially. After seven
consumptions there is a temporary wait until fresh votes settle, then id16 wins.
This fixture does not demonstrate wholesale eviction of settled mandates.
