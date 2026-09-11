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
| fixA | X1/X4a CRITICAL legacy buffer denomination | contracts/solidity/CauldronHook.sol | fundLegacyBuffer, _maybeLegacyBuyback, legacyBuyStep, _routeEthFee, legacyBufferAsset (new state) | CLAIMED | buffer denomination + drain + slippage + unchecked transfer |
| fixA | X1/X4a CRITICAL legacy buffer denomination | contracts/solidity/cauldron/LegacyBuyLib.sol | buyStep | CLAIMED | add slippage bound + checked transfer |
| fixA | X4c LOW codeless guild = success | contracts/solidity/cauldron/FeeRouteLib.sol | _fundGuild | CLAIMED | extcodesize/returndata check |
| fixA | X1b MEDIUM surtax jitter steerable | contracts/solidity/CauldronHook.sol | _snipeSurtaxBps (jitter) | CLAIMED | remove same-tx-movable tick from the jitter seed |
| fixA | tests | contracts/solidity/test/attacks/X1a_LegacyBufferDenomination.t.sol, contracts/solidity/test/attacks/X1b_SurtaxJitterSteerable.t.sol, contracts/solidity/test/attacks/X4a_LegacyBufferDenomination.t.sol, contracts/solidity/test/attacks/X4c_CodelessGuildSuccess.t.sol | all | CLAIMED | PoCs copied in, to be inverted to regressions |
| fixC | X2a HIGH voted migration mandate starved via secondary leg | contracts/solidity/cauldron/TreasuryGovernor.sol | consume | CLAIMED | refuse secondary-leg spend while a full migration mandate is outstanding |
| fixC | X2e HIGH primary frozen after migration (every fromLeg=0 slice reverts BadConfig) | contracts/solidity/cauldron/RedemptionExt.sol | rotateSliceFrom (fromLeg==0 source resolution) | CLAIMED | leg 0 resolves its quote from generationPoolKey.currency0, not generationQuote |
| fixC | X2b MEDIUM recoverLegs unreachable through the registry | contracts/solidity/CauldronRegistry.sol, contracts/solidity/cauldron/RedemptionExt.sol | recoverLegs forwarder stub + facet gate | CLAIMED | needs SPACE in CauldronRegistry first |
| fixC | X2d MEDIUM proposal spam erases a stockpiled mandate | contracts/solidity/cauldron/CauldronGovernor.sol | _recomputeLeader, MAX_LEADER_SCAN | CLAIMED | replace positional window with the sibling's non-positional shape |
| fixC | X2c LOW oracle floor fails OPEN on an unpriceable/stale pair | contracts/solidity/cauldron/QuoteRotator.sol, contracts/solidity/cauldron/QuoteOracle.sol | swapOnce, _oracleFloor, cachedUsdPerRawUnit | CLAIMED | permissionless rotation must refuse rather than rotate with no floor |
| fixC | X2f LOW guardian settable to zero | contracts/solidity/cauldron/TreasuryGovernor.sol | setGuardian | CLAIMED | zero check |
| fixC | X2g LOW dead completeRotation + codeless-address transfer | contracts/solidity/cauldron/RedemptionExt.sol, contracts/solidity/cauldron/QuoteRotator.sol | completeRotation, _safeTransfer | CLAIMED | decide wire-or-remove; extcodesize check |
| fixC | tests | contracts/solidity/test/attacks/X2a_MigrationMandateStarvation.t.sol, X2b_StrandedLegNoRetry.t.sol, X2c_OracleFloorFailsSafe.t.sol, X2d_MandateErasedBySpam.t.sol, X2e_FrozenResidualAfterMigration.t.sol | all | CLAIMED | PoCs copied in, to be inverted to regressions |
| fixB | H-1 rotation redenominates every counter but plv | contracts/solidity/cauldron/PerpEngine.sol | syncGeneration, _payOut, claimPayout, +payoutOwedTotal | CLAIMED | engine-side quote-denominated counters must all be zero before adopting a new quote |
| fixB | H-2 stale exit queue survives rotation; _haircut write-down rolled back | contracts/solidity/cauldron/PerpVault.sol, contracts/solidity/cauldron/PerpEngine.sol | claimPendingEth, +hasQuoteStake, syncGeneration | CLAIMED | vault ETH side must be drained before a quote flip; write-down must persist |
| fixB | H-3 _creditPerp missing _quoteIsNative check | contracts/solidity/cauldron/PerpEngine.sol | _creditPerp | CLAIMED | creditPerpFee/creditPerpFeeToken reject native value on an ERC20 book |
| fixB | H-4 ring reset collapses TWAP | contracts/solidity/cauldron/PerpEngine.sol | syncGeneration (ring reset), twapTick | CLAIMED | mark not ok until the ring has refilled after a reset |
| fixB | tests | contracts/solidity/test/attacks/X3a_QuoteRotationRedenominates.t.sol, contracts/solidity/test/attacks/X3b_NativeCreditIntoErc20Plv.t.sol, contracts/solidity/test/attacks/X3c_StaleQueueSurvivesRotation.t.sol, contracts/solidity/test/attacks/X3d_RingResetCollapsesTwap.t.sol | all | CLAIMED | PoCs -> regression tests |
| fixE | X4b MEDIUM churn confiscates a partial fill's refund | contracts/solidity/cauldron/CauldronGachaRouter.sol | _churn, rescueToken (new) | CLAIMED | debit what the swap consumed instead of zeroing ethBal; add onlyOwner ERC20 rescue for already-stranded quote |
| fixE | X4b regression test | contracts/solidity/test/attacks/X4b_ChurnConfiscatesRefund.t.sol | all | CLAIMED | PoC copied in, to be inverted to a regression |
| fixE | X4d LOW stale MAX_ASSETS comment | contracts/solidity/cauldron/MiFrensDividend.sol | comment only (near _settleBasket, ~:480) | CLAIMED | comment says "MAX_ASSETS is 4", constant at :124 is 3; comment-only, constant unchanged |
| fixD | X5a HIGH cancelled presale can still ignite | contracts/solidity/cauldron/MiFrensGenesis.sol | igniteCauldron | DONE 038e4d7 | `igniteCauldron` now reverts `AlreadyCancelled()` on a cancelled presale; the refund pot can never be forwarded to `summon`. Normal ignition unchanged. |
| fixD | X5c HIGH vault swept wei vs quote-denominated divisor | contracts/solidity/cauldron/PoolOps.sol | seedFunding (vaultSwept return only) | DONE 30b7d58 | `seedFunding`'s 3rd return is now non-zero ONLY on the native branch (the only one that folds it into the amount). Callers: a non-native rebirth reports swept==0, so `crystallizeCollection` credits 0 ETH-sized entitlement. Signature UNCHANGED, CauldronRegistry untouched. |
| fixD | X5b LOW sniper calls a nonexistent play() | contracts/solidity/cauldron/LaunchSniper.sol | IGachaPlay.play decl, launch | DONE 79a3fed | `IGachaPlay` now mirrors `CauldronGachaRouter.play` (5 args, 0x7fe7c4b6); call passes quoteIn=0/tokenIn=0/minTokenOut=minGnomeOut/minQuoteOut=0. `launch()` works. Router NOT edited. |
| fixD | X5d LOW three canonical deployment records | contracts/solidity/deployments/sepolia.json, contracts/solidity/deployments/sepolia-final.json, contracts/solidity/deployments/sepolia-launch.json | n/a | DONE a6a56f8 | ALL THREE marked `_status: SUPERSEDED` + `_canonical` -> REPO-ROOT deployments/sepolia.json (the file scripts/sync-deploy.mjs actually reads). fixF: root file unchanged by me, still the single source of truth. |
| fixD | X5e LOW deploy-script ordering assumption | contracts/solidity/deploy/DeployLaunchSniper.s.sol | run | DONE 834063c | script now reads GACHA and requires `hook.isOpener(gacha)` before broadcasting. NEW REQUIRED ENV VAR: GACHA. |
| fixD | tests | contracts/solidity/test/attacks/X5a_GenesisCancelledIgnite.t.sol, contracts/solidity/test/attacks/X5b_SniperSelectorDead.t.sol, contracts/solidity/test/attacks/X5c_VaultSweptDenomination.t.sol | all | DONE 038e4d7/30b7d58/79a3fed | all three inverted to regressions, 7/7 green. X5b was corrupt mid-session (python replace("",...) slip), rewritten from the pristine PoC; now 6,017 bytes and compiling. |
| fixF | F1+F4 HIGH perp UI encodes a non-existent selector; closes sign minOut=0 | src/config/perp.ts, src/hooks/usePerpEngine.ts, src/components/cauldron/PerpPanel.tsx | openLong, openShort, close, ABI | DONE 6a275c5 | 4-arg openLong/openShort selectors now match forge inspect (0x79588b97/0x9e4a4754); opens+closes sign a real minOut at PERP_SLIPPAGE_BPS |
| fixF | F2 HIGH unauthenticated brand rewrite | api/brand.ts, src/components/cauldron/TheCauldron.tsx | handler POST, BrewProfile.save | DONE b502cac | brand POST requires an EIP-191 sig from BRAND_SIGNERS bound to content+gen+ts; gen bounded, rows capped, no CORS on the write |
| fixF | F3 MEDIUM rotation panel signs a flat 1-token floor | src/components/cauldron/TreasuryRotation.tsx, src/hooks/useTreasuryRotation.ts | minOut computation | DONE 50839dc | minOut = simulated rotateSliceFrom output x (1-slip), re-quoted before signing; unquotable slice refuses to sign |
| fixF | F5 MEDIUM fren-ask fetches whatever x-forwarded-host names | api/fren-ask.ts | loadDocs | DONE 3c7d009 | doc origin pinned to CAULDRON_DOCS_ORIGIN/platform host; x-forwarded-host ignored; fetched text framed as untrusted data |
| fixF | F6 MEDIUM keeper binds addresses before sourcing env | scripts/keeper.sh | header | DONE d517e62 | .env.sepolia loads first and is mandatory; addresses come from round.json and a disagreeing override aborts |
| fixF | F7 LOW indexer subscribes to UnclaimedBurned which no contract emits | indexer/abis/RegistryAbi.ts, indexer/src/** | UnclaimedBurned handler | DONE 7890490 | UnclaimedBurned subscription removed; burned marked burnedIndexed:false so it is not served as live data |
| fixF | F8 LOW private keys in argv | scripts/*.sh, scripts/*.mjs | cast/forge invocations | DONE b8ec2b9 | scripts/lib/signer.sh: keystore account+password-file keeps keys off argv; raw-PRIVATE_KEY fallback announces its own exposure |
| fixF | F9 LOW x-token open unthrottled exchange | api/x-token.ts | handler | DONE fec94bf | redirect_uri allowlisted via X_REDIRECT_URIS + per-IP rate limit on the token exchange |
| fixF | F10 LOW liquidatoor reads any ?col= address | api/cauldron/liquidatoor.ts | handler | DONE b9e4583 | ?col= validated against the manifest collection + LIQUIDATOOR_COLLECTIONS before any read |
| fixE | BLOCKER (not mine) test/attacks/X5b_SniperSelectorDead.t.sol is corrupt | contracts/solidity/test/attacks/X5b_SniperSelectorDead.t.sol | n/a | RELEASED | fixD's file: 11.6 MB, the test body is duplicated between every character of the source (looks like a python `replace("", ...)` slip); it fails compilation project-wide ("Expected pragma... 37 | /    function test_Attack_SniperPlaySelectorDoesNotExistOnTheRouter"). NOT touched by fixE. fixE compiles with --skip around it; fixD must rewrite it from the pristine PoC |
| fixA | SPACE CauldronHook +213 over EIP-170 | contracts/solidity/CauldronHook.sol | _bestEffort (new private), _afterSwap liq sweep, native gacha, _maybeLegacyBuyback, _maybePoke | SPACE | 4 sites inline the identical gas-bounded result-ignored call block; folding them into one private helper. No ABI change, no gate weakened, thresholds passed through unchanged. |
| fixD | sizes after my 5 commits | n/a | n/a | DONE | MiFrensGenesis free 4,315 -> 4,304; PoolOps 731 -> 729; LaunchSniper 22,829 -> 22,823. All under EIP-170. NOT MINE: PerpEngine is -141 OVER (fixB) and CauldronHook is at 25 free (fixA). |
| fixD | X5f permissionless vestBatch + unpaginated _release; renounceOwnership live | contracts/solidity/cauldron/MigrationVesting.sol | vestBatch, _release, renounceOwnership | CLAIMED | coordinator-assigned follow-up; MigrationVesting ONLY (CauldronGovernor's renounce is fixC's - reporting, not editing) |
