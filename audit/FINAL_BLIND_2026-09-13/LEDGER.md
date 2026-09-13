# LEDGER — FINAL_BLIND_2026-09-13
Single source of truth for who touches what. Append-only except the status word.
Status: CLAIMED → DONE | RELEASED ; WAIT (blocked on another claim) ; SPACE (needs bytes: note says how many, from where).

## Byte table
| contract | runtime bytes at P0 | free at P0 | free now |
|---|---|---|---|
| CauldronCollection | 11,553 | 13,023 | 13,023 |
| CauldronGachaRouter | 8,580 | 15,996 | 15,996 |
| CauldronGovernor | 9,302 | 15,274 | 15,274 |
| CauldronHook | 24,530 | 46 | 46 |
| CauldronRegistry | 24,492 | 84 | 84 |
| CauldronSeeder (cauldron/CauldronSeeder.sol) | 15,260 | 9,316 | 9,316 |
| CauldronToken (CauldronToken.sol) | 2,033 | 22,543 | 22,543 |
| CauldronVault | 2,241 | 22,335 | 22,335 |
| CollectionLedger | 1,972 | 22,604 | 22,604 |
| DefaultFeeRouter | 349 | 24,227 | 24,227 |
| FeeRouteLib | 1,957 | 22,619 | 22,619 |
| LaunchSniper | 1,703 | 22,873 | 22,873 |
| MiFrensDividend | 8,050 | 16,526 | 16,526 |
| MiFrensGenesis | 20,470 | 4,106 | 4,106 |
| MigrationVesting | 4,757 | 19,819 | 19,819 |
| MintCurvePolicy | 871 | 23,705 | 23,705 |
| PerpMarkSource | 3,607 | 20,969 | 20,969 |
| PerpSwapLib (cauldron/PerpSwapLib.sol) | 6,310 | 18,266 | 18,266 |
| PerpVault | 8,002 | 16,574 | 16,574 |
| PoolOps | 24,006 | 570 | 570 |
| QuoteOracle | 3,821 | 20,755 | 20,755 |
| QuoteRotator | 8,531 | 16,045 | 16,045 |
| RedemptionExt | 13,973 | 10,603 | 10,603 |
| RoyaltyRouter | 293 | 24,283 | 24,283 |
| SurtaxLib | 723 | 23,853 | 23,853 |
| TreasuryGovernor | 6,653 | 17,923 | 17,923 |

## Rows
| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixOFF | T6A | src/hooks/useCauldronSwap.ts, src/lib/quoteUnits.ts, scripts/test-quote-units.mjs, package.json | buy, quoteInForTypedAmount, scaleFloor | DONE 6504a11 | buy() now signs quoteIn = the TYPED amount in quote decimals (capped at zap delivery + balance), approval bounded to it, floor scaled proportionally. Overspend 400x -> 1x. New `npm test` key runs scripts/test-quote-units.mjs (10/10). |
| fixOFF | T6B | indexer/src/index.ts, indexer/src/quoteUnits.ts, indexer/ponder.schema.ts, indexer/deployments/round.json, src/components/cauldron/SwapWidget.tsx, src/lib/quoteUnits.ts | rawQuoteRatio, registerPool, PoolManager:Swap, minOutFor | DONE fe94a40 | SCHEMA CHANGE (no contract ABI): pool.quoteDecimals + pool.lastPriceRaw added; round.json schema cauldron_r44b -> cauldron_r44c (clean reindex required on redeploy). `lastPrice`/`spotPrice` is now decimals-normalised quote-per-token; volumeEth uses quote decimals. Widget divides by it in quote units and sizes sell floors in quote decimals. ERC20 buy floor now reachable (was 3.96e8x overshoot). |
| fixOFF | T6E | api/brand.ts | ensureBrandTable, GET handler | DONE d8ed3af | DDL hoisted to a module-flagged one-time ensureBrandTable; public GET now 400s on any query param other than `gen`, so the URL-keyed edge cache cannot be bypassed. |
