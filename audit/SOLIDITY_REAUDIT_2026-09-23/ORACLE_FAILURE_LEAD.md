# R23-O1 — oracle refusal contract is incomplete

Confidence: VERIFIED at oracle boundary; downstream impact HYPOTHESIS.
Severity: not assigned. Status: open investigation, not a confirmed Medium+.

Baseline production source: BASELINE.json, QuoteOracle.sol:202–282 and :334–343.
Test: contracts/solidity/test/attacks/R23_OracleFailureBoundaries.t.sol, retained
in root and as an additive snapshot test. No production source edited.

Command: run.py oracle-failure-boundaries forge test --offline --threads 1
--match-path test/attacks/R23_OracleFailureBoundaries.t.sol -vv

Evidence: logs/oracle-failure-boundaries.json/.log, exit 1, 5 failed, 0 passed,
0 skipped. This supersedes any suggestion that all selected fresh tests pass:
the current selected aggregate is 156 passed and 5 failed.

## Observations

1. Empty successful latestRoundData return causes a caller-side decode revert.
2. Empty successful decimals return also reverts.
3. A fresh int256.max answer overflows normalization before bounds can refuse it.
4. With a previously valid cached price, case 1 after TTL reverts the refresh;
   the cached getter does not return its last usable factor.
5. An owner-configured codeless, nonzero feed address reverts rather than returning 0.

Every test establishes a normal 3000 USD price first; cache failure establishes
a usable cached factor and verifies elapsed time using vm.getBlockTimestamp.
Malformed return is simulated by the configured dependency, not by force-writing
oracle state. This proves robustness failure, NOT permissionless feed control.

## Trust and impact checks still required

Feed choice is owner-only. The failure model requires a bad/migrated dependency,
its changed behavior, or bad privileged configuration. Do not label it an
unprivileged price-manipulation finding without further evidence.

CauldronHook._toUsd:790–798 returns 0 on failed cached getter. The afterSwap
volume conversion at :982 consumes this result; isDead:1867–1887 judges rolling
volume against the configured threshold. Source suggests a malformed feed could
erase fresh volume contributions while an ordinary reverting feed uses retained
cache, but a local lifecycle control must establish that distinction and any
actual death/relaunch effect. Check threshold-zero and sibling-volume refutations.
Rotator uses a live static read and refuses unusable prices: no rotation drain
has been demonstrated here.

Next: production-hook/local-manager control comparing ordinary feed revert with
malformed response after warming cache and aging volume. Establish caller,
configuration, dollar-volume and lifecycle deltas before severity/remediation.
