# Quarantined PoCs — 2026-09-12, before the r43 deploy

Moved out of `contracts/solidity/test/attacks/` so the suite compiles and runs.
All three were UNTRACKED (never committed), i.e. in-progress work by a hunter
that stopped mid-flight. None is refuted — they are OPEN LEADS.

| file | why it was moved | state |
|---|---|---|
| `S0a_LegacyRefWalk.t.sol` | broke WHOLE-PROJECT compilation — `pm.currencyDelta` needs `using TransientStateLibrary for IPoolManager` | unknown, never ran |
| `S0b_CurveBandDenomination.t.sol` | broke WHOLE-PROJECT compilation — invalid address checksum at :42 (correct: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`) | unknown, never ran |
| `S0x_OgTrancheBoughtAtForgedFloor.t.sol` | compiled but the ATTACK PATH reverts (`EvmError: Revert` at gas 350141) before reaching its first assertion | **does not currently demonstrate its claim** — that is NOT the same as refuted |

`S0x` is the one worth finishing: its claim is that a treasury-held OG fren can be
bought at a FORGED ledger floor rather than the genesis floor, which would be a
real loss of OG value. It never got far enough to show that. Pick it up after the
demo — a PoC that reverts in setup tells you nothing either way.
