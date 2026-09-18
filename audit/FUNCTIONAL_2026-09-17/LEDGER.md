# FUNCTIONAL_2026-09-17 — fix ledger

Byte table (EIP-170 limit 24,576):

| contract | free at P0 | free now | claimed by |
|---|---|---|---|
| PerpEngine | 1,333 | 1,194 (23,382 B) | perp-fixer (released) |

Rows:

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| perp-fixer | D-04 | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/D04_RebookErasesFundingAndPenalty.t.sol | _rebook | DONE 712c2b1 | a partial close now PRESERVES `collateral` (spends `principal` first); funding, penalty, keeper cut and badge bounty survive a rebook; `collateral + principal` unchanged |
| perp-fixer | D-05 | contracts/solidity/cauldron/PerpEngine.sol | _settle (comments only) | DONE 712c2b1 | comments only; the band is FLAT over one budget, the split band is explicitly marked unlanded |
| perp-fixer | D-08 | contracts/solidity/test/attacks/M1a_LiqGasBand.t.sol | test_gate_affords_only_one_kill_strands_the_rest | DONE 712c2b1 | ladder now runs to 4M and asserts `passes > 0`; 5 caps fill, so the dose-response assertions execute |

NOT MINE, left unstaged in the worktree (another agent, uncommitted): `PerpEngine.sol` hunks at the `_doSweep` kill-cap (`spec != 0 || kills < MAX_LIQ_PER_SWAP`) and the `_ownerFloor(ownerSlippage, 0, minOut)` added on the partial-close branch. My regressions were run WITH those hunks present and are green.
