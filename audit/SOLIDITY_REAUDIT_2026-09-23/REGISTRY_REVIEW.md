# CauldronRegistry — complete executable source traversal

Read declarations and every executable body across all1,844 lines (comment-only
lines filtered for complete pass), then original emergency/successor and relaunch
reserve narrative. Base/facet reviewed separately. No final sign-off.

| Function group | Analysis and outstanding verification |
|---|---|
| constructor/setRedemptionExt | Manager/hook stored without code/interface checks, native quote enabled, immutable emergency admin/delay. Facet requires code and one-time nonzero slot; arbitrary trusted facet compatibility must be checked before wiring. |
| setReserveCeiling/setSeeder/setSeedWindow/setAllowedQuote | Owner bounds ceiling and window, propagates seeder to hook, native cannot be disallowed, watermark enforced, zero scale becomes1e18. Plain token semantics and role configuration trusted. Changing seeder may strand old campaigns unless checked by implementation/caller. |
| onlyEmergency/timelocked/_consumeTimelock/armEmergency/setGuardian/vetoEmergency/setRedemptionPaused | Shared one-action arm, guardian veto, emergency-ready resets before body but failure rolls back. Arm creates exit window through Base._redeemBlocked. Rearm can reset deadline; no per-action payload commitment. Owner/emergency admin can replace guardian. Distinguish governance timelock from this separate delay. |
| enchantFee/setEnchantFeeMult | Floor times bounded multiplier<=100x, overflow possible only extreme accounting values; established floor conservation required. |
| emergencyWithdrawLP/emergencySweep | Arm required; withdraw removes generation liquidity then sends returned quote amount as native ETH regardless of primary quote currency. Non-native recovery mismatch lead requires funded test. Sweep ignores ERC20 bool. Admin already has broad withdrawal power; no outsider theft claim. |
| setSuccessor/setClaimGate/migrateToSuccessor | Nonzero claim gate consumes arm; zero restores instantly. Successor transfer active+reserve NFTs, seeder assets, current tokens/native. Does not transfer generationLegs, foreign loose quotes or booked proceeds; pointers not cleared and no migrated flag. Lifecycle/post-handoff recovery lead. Comment says mifrens.setRegistry can rehome but Genesis setter is one-time, requiring explicit migration design verification. |
| receive/setGovernor/setMinLifetime/setFactory/setNftMaxSupply/setRoyalty/setGenesisMetadata/setCollectionMetadata | Persistent owner/admin powers; trusted address dependencies, bounded NFT supply/royalty. Collection metadata setter on Genesis accepts deployer only, so registry-call behavior differs for iteration2; test needed. |
| setGenesisBonus/setAirdropReserve/setPrimeFunder/fundPrimeBuy/sweepPrimeBuy | Genesis params pre-summon, bounds/shares nonzero. Prime fund/sweep remain reachable after summon, CEI before native callback. Need reserve solvency across bonus+airdrop choices: independent maxima do not automatically prove backing. |
| summon | Owner or igniter; payable/nonReentrant, once, positive value. Deploy token, genesis reserve entitlement, optional airdrop, green-candle seed, optional priming, deploy collection. All revert together in transaction. Constructor roles and factory must already be wired. Returned token minter context from linked library verified in source. |
| relaunch | nonReentrant dead/lifetime/governor gates. Force close before teardown, remove/burn old LP tokens, bounded ticket work, bump generation, resolve winning spec, mine token and pick funded quote. markConsumed atomic rollback; comments that only reverts after mark are dangerous are not a general EVM distinction. Quote record uses actual funding result. Fold genesisPending, compute active/reserve, flush legacy, crystallize and subtract entitlements, fallback/clamp, seed and deploy/continue collection, reset curve, sync perps. |
| reserve sizing | Existing shortfall events acknowledge undercoverage; they do not repair it. Fresh _flushLegacyAtRelaunch adds OG share to genesisPending AFTER outstanding fold/newActive sizing, potentially delaying this backing/claim increment one extra generation. Lead needs actual iteration2 funded test. Legacy>=active fallback uses80% active despite a comment saying maximize reserve. Must verify actual reachable shortfall policy and all claimant conservation. |
| _perpHousekeep | Before teardown calls hook force-close only if gas>8M; otherwise skips. After new generation sync catches failure. Need open-book/gas-dependent relaunch proof (not assume quote carry applies to generation replacement). User's normal liquidation remains hook beforeSwap. |
| _deployCollection/_continueMiFrens | Factory deploys collection/vault; hook floor vault deliberately zero for buyback funding. Iteration2 wires canonical Genesis minter/vault; clears neither automatically on later relaunch here. Verify old minter authority, dividend/custody/votes, badge wiring and role replacement. |
| claimByBurn/claimByBurnUpTo/enableAutoMigrate/disableAutoMigrate/autoMigrateBatch | Old generation, balances, gate except engine; individual paths unguarded by nonReentrant, batch guarded. Holder opt-in fee or any MiFrens NFT waiver (badges included). Excess fee retained, no refund. Capacity/dust effects in PoolOps worksheet; claimGate closes batch. |
| explicit facet forwarders/_forwardToExtView/_forwardToExt | Assembly exact calldata and return/revert bubbling, no fallback. So teardown selector inaccessible to outsiders through registry. 'View' wrappers ABI is nonpayable, code uses delegatecall; eth_call/staticcall works only when target path writes nothing. Consumer ABI may need view declaration override. Facet getter legProceedsOf still absent. |
| setCollectionLedger/_flushLegacyAtRelaunch/recycleCollectionNFT/buyCollectionNFT | Owner ledger pointer, burn-path legacy flush returns OG pending; recycle exit gate and nonReentrant, buy nonReentrant, current reserve pays old collection claims. Prior badge-floor fix applies at PoolOps. |
| _removeLiquidity | Remove main+reserve, optional currently configured seeder, best-effort facet leg teardown; sums primary quote in ethRecovered variable. No clearing main IDs; calls may revisit burned IDs. gen argument vs current seeder identity requires old-generation emergency test. Failed facet recovery tolerated; old legs retryable through separate guarded path. |
| _deployToken/_createPoolAndSeedWithBuy/_seedGeneration/_recordSeed/unlockCallback | Linked deployment/seed; bool armed across initialize/position/unlock, records full keys/IDs/ticks and hook live key. Callback verifies exact manager plus armed flag. Zero arbitrary callback admission; interaction nesting/transaction callback sequence still needs local invariant tests. |

Remaining final gates: confirmed fixes/previous invariant suite reconciliation,
new recovery/accounting leads, all current ABI/storage/size/source/deployment
parity, full launch-to-rotation-to-relaunch-to-successor and adverse callback
tests, consumer/static-view compatibility. No final sign-off from traversal.

## Funded emergency rotation check

`R23_EmergencyRotationRecovery.test_rotatedQuoteRequiresSeparateEmergencySweep`
uses real local V4/PositionManager/Permit2, registry/facet/governor/rotator,
a funded native launch and a voted 25% ERC20 rotation. No registry storage
writes or impersonated registry/manager callbacks. Emergency withdrawal removes
the foreign NFT liquidity, pays native quote to the admin, and leaves recovered
ERC20 quote in registry custody. A separately armed emergencySweep transfers
that entire balance to the admin. This is recoverable, not permanent fund loss.
Vote supply and quote token are fixtures. Logs:
`emergency-rotation-recovery-selected` — one pass, zero fail/skip, exit0.
Initial `emergency-rotation-recovery` selected no tests despite exit0; it is NOT
a passing runtime check (trailing anchored method regex excluded the signature).

This does not reach a generation initially SEEDED with non-native currency0;
the denomination-mismatch lead in that path remains open. Rotation changes the
active quote label but preserves launch key, so treating the tested rotated
native launch as an ERC20 launch would be invalid. _recoverLegs deliberately
books foreign proceeds separately. EmergencySweep does not clear that booking;
use sweepLegProceeds where applicable to keep its accounting synchronized, and
investigate post-emergency continuation before asserting it safe.

## Final disposition (2026-09-23)

Final dispositions: low-gas open-book relaunch = FS-relaunch-01 High FIXED; successor handoff = FS-successor-01 Medium FIXED (facet); non-native emergencyWithdrawLP = FS-registry-L01 Low; OG fold order = FS-registry-L02 Low. Relaunch fix confirmed on deployed bytecode in the local rehearsal. Signed off.
