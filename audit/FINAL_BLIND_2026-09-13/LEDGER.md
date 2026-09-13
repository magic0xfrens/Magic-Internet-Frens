# LEDGER — FINAL_BLIND_2026-09-13
Single source of truth for who touches what. Append-only except the status word.
Status: CLAIMED → DONE | RELEASED ; WAIT (blocked on another claim) ; SPACE (needs bytes: note says how many, from where).

## Byte table
| contract | runtime bytes at P0 | free at P0 | free now |
|---|---|---|---|
| CauldronCollection | 11,553 | 13,023 | 13,023 |
| CauldronGachaRouter | 8,580 | 15,996 | 15,996 |
| CauldronGovernor | 9,341 | 15,274 | 15,235 |
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
| TreasuryGovernor | 6,646 | 17,923 | 17,930 |

## Rows
| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixOFF | T6A | src/hooks/useCauldronSwap.ts, src/lib/quoteUnits.ts, scripts/test-quote-units.mjs, package.json | buy, quoteInForTypedAmount, scaleFloor | DONE 6504a11 | buy() now signs quoteIn = the TYPED amount in quote decimals (capped at zap delivery + balance), approval bounded to it, floor scaled proportionally. Overspend 400x -> 1x. New `npm test` key runs scripts/test-quote-units.mjs (10/10). |
| fixOFF | T6B | indexer/src/index.ts, indexer/src/quoteUnits.ts, indexer/ponder.schema.ts, indexer/deployments/round.json, src/components/cauldron/SwapWidget.tsx, src/lib/quoteUnits.ts | rawQuoteRatio, registerPool, PoolManager:Swap, minOutFor | DONE fe94a40 | SCHEMA CHANGE (no contract ABI): pool.quoteDecimals + pool.lastPriceRaw added; round.json schema cauldron_r44b -> cauldron_r44c (clean reindex required on redeploy). `lastPrice`/`spotPrice` is now decimals-normalised quote-per-token; volumeEth uses quote decimals. Widget divides by it in quote units and sizes sell floors in quote decimals. ERC20 buy floor now reachable (was 3.96e8x overshoot). |
| fixOFF | T6E | api/brand.ts | ensureBrandTable, GET handler | DONE d8ed3af | DDL hoisted to a module-flagged one-time ensureBrandTable; public GET now 400s on any query param other than `gen`, so the URL-keyed edge cache cannot be bypassed. |
| fixPERP | T3c | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/K3c_RotationStrandsPerpEngine.t.sol | syncGeneration, setVault | CLAIMED | dust quote-staker vetoes rotation adoption -> engine dead |
| fixPERP | T3d | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/K3d_ForceCloseDeadFloor.t.sol | forceCloseDead, _settle | CLAIMED | force close of solvent position at minOut 0 |
| fixPERP | T3b | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/K3b_TokYieldLockout.t.sol | syncGeneration, withdrawTokYieldTo | CLAIMED | rotation write-off bricks claimTokYield forever |
| fixPERP | T3a | contracts/solidity/cauldron/PerpVault.sol, contracts/solidity/test/attacks/K3a_StaleQueueEatsDeposit.t.sol | depositEth | CLAIMED | stale exit queue eats a fresh deposit |
| fixPERP | T3e | contracts/solidity/cauldron/PerpMarkSource.sol, contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/K3e_StaleMarkSource.t.sol | weightedTick, syncGeneration | CLAIMED | unarmed mark source returns tick 0; stale source survives relaunch |
| fixPERP | T3f | contracts/solidity/cauldron/PerpEngine.sol | _rebook | CLAIMED | rebook zeroes collateral -> no funding, no liq penalty |
| fixGOV | T2a | contracts/solidity/cauldron/TreasuryGovernor.sol, contracts/solidity/test/attacks/K2a_PartialEnvelopeStarve.t.sol | allowance, consume | DONE 5b2f2b5 | BEHAVIOUR: allowance()/consume() now meter and deactivate EVERY envelope on movedPrimaryBps (was movedBps for partial). A secondary-leg slice no longer reduces the reported remainder nor retires the envelope; it is still capped by movedBps <= maxTotalBps. No ABI change. 6,653 -> 6,646 B |
| fixGOV | T2b | contracts/solidity/cauldron/TreasuryGovernor.sol, contracts/solidity/test/attacks/K2b_MandateErasedAfterVoteCloses.t.sol | _benchRecord, winner (comment) | DONE 5b2f2b5 | BEHAVIOUR: bench eviction is lexicographic (unprotected before protected, then fewer votes); an _executable (settled+passed+in-window) slot is displaced only when ALL 8 slots are executable and only by strictly more votes. winner() is unchanged. No ABI change. 6,653 -> 6,646 B |
| fixGOV | T2c | contracts/solidity/cauldron/CauldronGovernor.sol, contracts/solidity/test/attacks/K2c_RelaunchStalledByOpenBrews.t.sol | _benchRecord | DONE c660538 | BEHAVIOUR: same eviction order in CauldronGovernor; a SETTLED unconsumed brew (the only kind _recomputeLeader elects) survives any number of open filings, so hasProposals()/winner() stay true for the registry at CauldronRegistry.sol:841. No ABI change. 9,302 -> 9,341 B (+39) |
| fixSEED | K5b-residual | contracts/solidity/cauldron/CauldronSeeder.sol, contracts/solidity/deploy/DeployLaunchpad.s.sol, contracts/solidity/test/attacks/K5b_ProgressiveSeederUnreachable.t.sol | fundPrime, refundPrime (NEW), rescue, NatSpec; deploy PRIME_BUY_ETH comment | CLAIMED | fundPrime ETH trapped forever while SEED_BASE_WAD=1e18; adding a pre-campaign exit (ABI CHANGE) |
| fixSEED | K5c | contracts/solidity/cauldron/CauldronSeeder.sol, contracts/solidity/test/attacks/K5b_ProgressiveSeederUnreachable.t.sol | rescue | CLAIMED | rescue() reverts pre-campaign on IERC20(address(0)).balanceOf |
| fixSEED | K5e | contracts/solidity/cauldron/MiFrensGenesis.sol | mint per-wallet cap | CLAIMED | balanceOf-based cap resets on transfer; append-only mintedBy slot if it fits |
| fixHOOK | K1a | contracts/solidity/CauldronHook.sol, contracts/solidity/test/attacks/K1a_StaleVolumeKeepsAlive.t.sol | _recordVolume, getVolume24h | CLAIMED | day-boundary off-by-one pins stale 24h volume, relaunch reverts TokenStillAlive forever |
| fixHOOK | H1-L3 | contracts/solidity/CauldronHook.sol, contracts/solidity/test/attacks/K1b_TenthSiblingBricksRotation.t.sol | linkVolume | CLAIMED | 10th distinct sibling reverts whole rotation, no unlink exists |
| fixHOOK | H1-L2 | contracts/solidity/CauldronHook.sol | _getHolderTaxRate | CLAIMED | uncapped NFT tax rate; dormant (nftContract == 0 on deployed path) |
| fixNFT | K4a+K4d | contracts/solidity/cauldron/RoyaltyRouter.sol, contracts/solidity/test/attacks/K4a_RoyaltyErc20Strand.t.sol | receive, sweep, erc20Sink | DONE 0503a09 | RoyaltyRouter CONSTRUCTOR CHANGED: `new RoyaltyRouter(hook, erc20Sink)`. New permissionless `sweep(address)` — address(0) = held ether to fundLegacyBuffer, an ERC20 to the immutable erc20Sink (the genesis dividend) + best-effort adopt. receive() no longer bubbles and skips the forward below a 40k gas floor, so a 2300-stipend marketplace can no longer revert the sale. 293 -> 1,295 bytes. |
| fixNFT | K4c | contracts/solidity/cauldron/CauldronGachaRouter.sol, contracts/solidity/test/attacks/K4c_ChurnNoFloor.t.sol, src/hooks/useCauldronSwap.ts, src/config/cauldron.ts, indexer/abis | playChurn, _churn | DONE 0c80fe9 | ABI CHANGE: `playChurn(quoteIn, loops, minTokenOut, openMax)` — selector changed. Floor enforced on the final tokBal in _churn, reverts Slippage(). Frontend ABI in src/config/cauldron.ts updated; useCauldronSwap.spin now REFUSES to sign a spin with no floor. No gacha ABI under indexer/abis. 8,580 -> 8,814 bytes. |
| fixNFT | K4c (cont) | contracts/solidity/test/attacks/X4b_ChurnConfiscatesRefund.t.sol, contracts/solidity/cauldron/CauldronFactory.sol | playChurn call sites, deployBrew | DONE 0c80fe9 / 0503a09 | X4b: 4 call sites take a 0 floor (prior behaviour preserved). CauldronFactory.deployBrew passes c.royaltyReceiver as the router's erc20Sink. |
| fixPERP | SPACE | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/cauldron/PerpSwapLib.sol | tier scan / mark math | SPACE | PerpEngine 24,687 after T3c+T3d+T3e (limit 24,576): need >=111 B. Sourcing from PerpEngine itself (fold the two death-band checks into one internal fn) and, if short, moving a pure math block into PerpSwapLib (18,266 B free). |
| fixNFT | K4a (cont) | contracts/solidity/test/attacks/X1e_RoyaltyRouterRevertsOnErc20Quote.t.sol, contracts/solidity/test/attacks/Z9_ScopeProbe.t.sol | RoyaltyRouter constructor | DONE 0503a09 | Both fixtures on `new RoyaltyRouter(hook, address(0))`; assertions untouched, both suites green. Tree compiles again. |
| fixPERP | BYTES | — | — | DONE | PerpEngine 24,460 -> 24,543 (free 116 -> 33). PerpVault 8,002 -> 8,339. PerpMarkSource 3,607 -> 3,603. PerpSwapLib unchanged 6,310. Bytes found IN PerpEngine, behaviour-neutral, in the same commit as the fixes: `_deathBand` folds the two dead-path band checks; `_deadPrep` folds the `!_isDead()->NotDead + _pokeFunding` preamble shared by forceCloseDead/forceCloseAllDead; `_utilGate` folds the identical vault util-cap + insurance-floor block out of openLong and openShort. Tried and REVERTED: moving the maxLeverage tier scan into PerpSwapLib COSTS 94 B (storage array -> memory ABI encode is bigger than the loop) - do not retry. |

