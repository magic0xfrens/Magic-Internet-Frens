# FUNCTIONAL_2026-09-17 — fix ledger

Byte table (EIP-170 limit 24,576):

| contract | free at P0 | free now | claimed by |
|---|---|---|---|
| PerpEngine | 1,333 | — | perp-fixer |

Rows:

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| perp-fixer | D-04 | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/D04_RebookErasesFundingAndPenalty.t.sol | _rebook | CLAIMED | preserve `collateral` across a partial close; spend `principal` first |
| perp-fixer | D-05 | contracts/solidity/cauldron/PerpEngine.sol | _settle (comments only) | CLAIMED | the two band comments contradict each other |
| perp-fixer | D-08 | contracts/solidity/test/attacks/M1a_LiqGasBand.t.sol | test_gate_affords_only_one_kill_strands_the_rest | CLAIMED | ladder tops out below the 2.4M fill point, dose-response asserts nothing |
