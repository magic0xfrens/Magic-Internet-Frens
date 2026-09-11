# Ledger

Row format, append-only except the status word: | agent | finding | files (comma-separated) | functions | status | note |  — statuses CLAIMED → DONE | RELEASED | WAIT | SPACE

| contract | free at P0 | free now | claimed by |
|---|---|---|---|
| CauldronHook | 43 | 43 | |
| CauldronRegistry | 15 | 15 | |
| PerpEngine | 141 | 141 | |
| PositionDescriptor | 466 | 466 | |
| PoolOps | 731 | 731 | |
| MiFrensGenesis | 4,315 | 4,315 | |
| CauldronFactory | 6,417 | 6,417 | |
| TreasuryGovernor | 18,310 | 18,310 | |
| CauldronGovernor | 17,357 | 17,357 | |
| MiFrensDividend | 17,212 | 17,212 | |
| PerpVault | 16,675 | 16,675 | |
| QuoteRotator | 16,141 | 16,141 | |
| CauldronGachaRouter | 16,040 | 16,040 | |
| CauldronCollection | 13,206 | 13,206 | |
| RedemptionExt | 11,731 | 11,731 | |
| CauldronSeeder | 11,602 | 11,602 | |
| MigrationVesting | 19,936 | 19,936 | |
| QuoteOracle | 20,885 | 20,885 | |
| PerpMarkSource | 20,919 | 20,919 | |
| CauldronToken | 22,543 | 22,543 | |
| CauldronVault | 22,722 | 22,722 | |
| LaunchSniper | 22,829 | 22,829 | |
| CollectionLedger | 22,871 | 22,871 | |
| MintCurvePolicy | 23,705 | 23,705 | |
| PerpStakerOracle | 24,032 | 24,032 | |
| DefaultFeeRouter | 24,221 | 24,221 | |
| RoyaltyRouter | 24,283 | 24,283 | |

(CauldronBase has no row in `forge build --sizes` — abstract contract, no
standalone runtime bytecode. QuoteOracle/PerpMarkSource/etc. margins are large
free space, not close to EIP-170; listed for completeness since the brief asks
for one row per baseline contract.)

| agent | finding | files | functions | status | note |
|---|---|---|---|---|---|
