# Baseline (real tree, pre-review) — 2026-09-11

- Branch at measurement time: fix/b05-b07-relaunch-totality
- HEAD: 3ee07ac
- Uncommitted paths at baseline: 73
- Snapshot commit (STEP 2): 1e98bb4 on branch redteam/2026-09-11

## Full suite (real tree, fork env)
`forge test --threads 2`: Ran 152 test suites in 574.22s (1300.74s CPU time):
718 passed, 13 failed, 1 skipped (732 total tests).

The only "429" hits in the log are the strings "429.00µs"/"429 CPU time" (timing
noise, not HTTP 429s) and one test literally named `..._OnFork`; no rate-limit
signal is present, so the conditional re-run rule does not apply and no re-run
was performed.

### Failed tests at P0 (13)
| file:contract | test | failure |
|---|---|---|
| test/attacks/T02_PartialFlipStrandsThePrimary.t.sol:T02_PartialFlipStrandsThePrimary | test_T02_POC_FullMandateFlipsWithAThirdLeftBehind | EvmError: Revert |
| test/attacks/T02_PartialFlipStrandsThePrimary.t.sol:T02_PartialFlipStrandsThePrimary | test_T02_POC_PrimaryLegIsUnrotatableAfterTheFlip | EvmError: Revert |
| test/attacks/T02_PerpAfterRotation.t.sol:T02_PerpAfterRotation | test_T02_POC_MarkSourceDoesNotFollowTheRotation | EvmError: Revert |
| test/attacks/T02_PerpAfterRotation.t.sol:T02_PerpAfterRotation | test_T02_POC_MinCollateralBricksOpensOnASixDecimalQuote | EvmError: Revert |
| test/attacks/T02_RotationDestinationSquat.t.sol:T02_RotationDestinationSquat | test_T02_CONTROL_UnsquattedRotationPricesItself | EvmError: Revert |
| test/attacks/T02_RotationDestinationSquat.t.sol:T02_RotationDestinationSquat | test_T02_RETRACTED_ForeignInitializeOnTheDestinationKeyReverts | EvmError: Revert |
| test/attacks/T02_StaleFloorSandwich.t.sol:T02_StaleFloorSandwich | test_T02_CONTROL_LiveFeedRejectsThePushedVenue | EvmError: Revert |
| test/attacks/T02_StaleFloorSandwich.t.sol:T02_StaleFloorSandwich | test_T02_POC_FrozenCacheLetsAPushedVenueFillTheSlice | EvmError: Revert |
| test/attacks/T03_InventoryWipe.t.sol:T03_InventoryWipe | test_Inventory_200M | InsufficientETH() |
| test/attacks/T03_RelaunchSurvivorBrick.t.sol:T03_RelaunchSurvivorBrick | test_SurvivorsCanNeverBeClosed | relaunch succeeded |
| test/attacks/T03_RelaunchSurvivorBrick.t.sol:T03_RelaunchSurvivorBrick | test_SurvivorsUnclosableEvenWhenTheGateOpens | relaunch ok |
| test/attacks/T03_RelaunchSurvivorBrick.t.sol:T03_RelaunchSurvivorBrick_BookSize | test_MinimumBookSizeAt12M | a brickable book size exists at 12M: 0 <= 0 |
| test/attacks/T02_EnvelopeBurnedOnADustLeg.t.sol:T02_EnvelopeBurnedOnADustLeg | test_T02_POC_DustLegBurnsTheWholeMigrationMandate | EvmError: Revert |

These are attack PoCs whose asserted attack no longer succeeds (e.g. "relaunch
succeeded", "relaunch ok", "a brickable book size exists at 12M: 0 <= 0" are
the PoC's own failure-message assertions firing because the attack it expected
to land did NOT land) — i.e. the exploit conditions the PoCs were written to
demonstrate are not currently reproducible, not infrastructure failures. Not
investigated further; out of scope for a runner pass.

## Env used
FOUNDRY_PROFILE=cauldron
FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com
POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4

## Sizes (runtime bytecode, real tree — non-test/non-lib/non-mock only)
CauldronBase has no row in `forge build --sizes` output (abstract contract,
no standalone deployed runtime bytecode) — omitted below for that reason.

| contract | runtime size (B) | runtime margin (B) |
|---|---|---|
| CauldronHook | 24,533 | 43 |
| CauldronRegistry | 24,561 | 15 |
| PerpEngine | 24,435 | 141 |
| PositionDescriptor | 24,110 | 466 |
| PoolOps | 23,845 | 731 |
| MiFrensGenesis | 20,261 | 4,315 |
| CauldronFactory | 18,159 | 6,417 |
| TreasuryGovernor | 6,266 | 18,310 |
| CauldronGovernor | 7,219 | 17,357 |
| MiFrensDividend | 7,364 | 17,212 |
| PerpVault | 7,901 | 16,675 |
| QuoteRotator | 8,435 | 16,141 |
| CauldronGachaRouter | 8,536 | 16,040 |
| CauldronCollection | 11,370 | 13,206 |
| RedemptionExt | 12,845 | 11,731 |
| CauldronSeeder | 12,974 | 11,602 |
| MigrationVesting | 4,640 | 19,936 |
| QuoteOracle | 3,691 | 20,885 |
| PerpMarkSource | 3,657 | 20,919 |
| CauldronToken | 2,033 | 22,543 |
| CauldronVault | 1,854 | 22,722 |
| LaunchSniper | 1,747 | 22,829 |
| CollectionLedger | 1,705 | 22,871 |
| MintCurvePolicy | 871 | 23,705 |
| PerpStakerOracle | 544 | 24,032 |
| DefaultFeeRouter | 355 | 24,221 |
| RoyaltyRouter | 293 | 24,283 |

PositionDescriptor is not on the named list but qualifies under "Runtime Margin
under 2000 B". The only other sub-2000-margin rows in the whole real-tree table
belong to lib/, test/, or Mock/Stub/Fake-named contracts and were excluded.
Four contracts are within 500 B of the EIP-170 runtime ceiling (24,576 B):
CauldronRegistry (15), CauldronHook (43), PerpEngine (141), PositionDescriptor (466).
