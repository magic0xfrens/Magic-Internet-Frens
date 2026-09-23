# Per-file final sign-off checklist

Current: **0/66 signed off**. Each row is pending substantive closure, not merely
paperwork. Source hashes and future sign-off evidence slots are in
SIGNOFF_CHECKLIST.json. PROGRESS.md records completed work; worksheets contain
specific leads, assertion limits and cross-contract dependencies.

A file can be signed off only after its relevant function/authority/asset/callback
review and lifecycle obligations are resolved, confirmed Critical/High/Medium
findings are fixed and verified, applicable regressions/invariants/integration
and consumer/build/deployment checks are satisfied, and the reviewer records a
source-bound conclusion with residual Low/Informational issues and limitations.
Reading, artifact freshness and passing test totals alone do not close a row.
Unavailable or failing checks remain explicitly unavailable or failing.

Priority order: remaining High/Medium or severity-unknown leads; shared custody/
solvency lifecycles; remediation compatibility; full build/deployment/consumer
gates; then source-bound per-file conclusions. Shared evidence may close several
rows, but one passing test does not automatically close its dependencies.

| File | Next substantive verification | Review evidence | Final sign-off |
|---|---|---|---|
| CauldronHook.sol | Close pre/post-swap solvency and callback/fee-asset conservation; verify configuration recovery and supported swap quadrants. | [HOOK_REVIEW.md](HOOK_REVIEW.md) | Pending |
| CauldronRegistry.sol | Reproduce non-native launch emergency recovery, successor handoff, pending-OG fold order and low-gas open-book relaunch leads. | [REGISTRY_REVIEW.md](REGISTRY_REVIEW.md) | Pending |
| CauldronToken.sol | Finish authority/callback and launch/continuation/role-transfer reconciliation with deployment consumers. | [TOKEN_FACTORY_REVIEW.md](TOKEN_FACTORY_REVIEW.md) | Pending |
| cauldron/CauldronArtAdapter.sol | Disposition dense-render failure; verify upload/lookup/freeze and renderer dependencies with supported build profiles. | [ART_STORAGE_REVIEW.md](ART_STORAGE_REVIEW.md) | Pending |
| cauldron/CauldronBase.sol | Reconcile all delegatecall state consumers and final compiler storage layout after remaining fixes. | [REGISTRY_BASE_REVIEW.md](REGISTRY_BASE_REVIEW.md) | Pending |
| cauldron/CauldronCollection.sol | Close art/badge issuance-to-redemption joins, validator authority and old-collection ticket resolution. | [COLLECTION_REVIEW.md](COLLECTION_REVIEW.md) | Pending |
| cauldron/CauldronFactory.sol | Finish authority/callback and launch/continuation/role-transfer reconciliation with deployment consumers. | [TOKEN_FACTORY_REVIEW.md](TOKEN_FACTORY_REVIEW.md) | Pending |
| cauldron/CauldronGachaRouter.sol | Close paid swap/credit/ticket attribution, refunds and callback/expiry behavior. | [GACHA_ROUTER_REVIEW.md](GACHA_ROUTER_REVIEW.md) | Pending |
| cauldron/CauldronGovernor.sol | Close bench eviction/candidate liveness and actual registry winner-consumption joins. | [GOVERNOR_REVIEW.md](GOVERNOR_REVIEW.md) | Pending |
| cauldron/CauldronSeeder.sol | Finish configured campaign replacement/recovery, range tracking and funded production reachability. | [SEEDER_REVIEW.md](SEEDER_REVIEW.md) | Pending |
| cauldron/CauldronVault.sol | Finish art/badge and OG-offset lifecycle evidence, teardown and claimant conservation. | [VAULT_REVIEW.md](VAULT_REVIEW.md) | Pending |
| cauldron/CollectionLedger.sol | Reconcile live/dead entitlement and retirement conservation across funded reserve and relaunch sequences. | [COLLECTION_LEDGER_REVIEW.md](COLLECTION_LEDGER_REVIEW.md) | Pending |
| cauldron/DefaultFeeRouter.sol | Close fee split conservation and fallback behavior across hook/perp/asset consumers. | [FEE_ROUTING_REVIEW.md](FEE_ROUTING_REVIEW.md) | Pending |
| cauldron/FeeRouteLib.sol | Close fee split conservation and fallback behavior across hook/perp/asset consumers. | [FEE_ROUTING_REVIEW.md](FEE_ROUTING_REVIEW.md) | Pending |
| cauldron/GachaLib.sol | Reproduce validator-rejected mint through Genesis continuation; resolve pity/opened accounting and backlog-expiry disposition. | [GACHA_LIB_REVIEW.md](GACHA_LIB_REVIEW.md) | Pending |
| cauldron/ICauldron.sol | Reconcile every declaration against implementations, dynamic callers, selector/return semantics and trust assumptions. | [INTERFACE_REVIEW.md](INTERFACE_REVIEW.md) | Pending |
| cauldron/ICreatorToken.sol | Finish per-declaration implementation/caller or deployment-mock role and token-behavior compatibility. | [REMAINING_INTERFACES_MOCKS_REVIEW.md](REMAINING_INTERFACES_MOCKS_REVIEW.md) | Pending |
| cauldron/IDeathChecker.sol | Reconcile every declaration against implementations, dynamic callers, selector/return semantics and trust assumptions. | [INTERFACE_REVIEW.md](INTERFACE_REVIEW.md) | Pending |
| cauldron/ILiquidatorMintable.sol | Reconcile every declaration against implementations, dynamic callers, selector/return semantics and trust assumptions. | [INTERFACE_REVIEW.md](INTERFACE_REVIEW.md) | Pending |
| cauldron/IPolicies.sol | Reconcile every declaration against implementations, dynamic callers, selector/return semantics and trust assumptions. | [INTERFACE_REVIEW.md](INTERFACE_REVIEW.md) | Pending |
| cauldron/ISeeder.sol | Finish per-declaration implementation/caller or deployment-mock role and token-behavior compatibility. | [REMAINING_INTERFACES_MOCKS_REVIEW.md](REMAINING_INTERFACES_MOCKS_REVIEW.md) | Pending |
| cauldron/LaunchSniper.sol | Close launch timing, approvals, refunds/slippage and owner recovery against supported pool/quote paths. | [LAUNCH_SNIPER_REVIEW.md](LAUNCH_SNIPER_REVIEW.md) | Pending |
| cauldron/LegacyBuyLib.sol | Resolve threshold/dust/backing and quote/generation transition conservation. | [LEGACY_BUY_REVIEW.md](LEGACY_BUY_REVIEW.md) | Pending |
| cauldron/MiFrensDividend.sol | Close payout/transfer/reentrancy and multi-asset conservation with final source/consumer compatibility. | [DIVIDEND_REVIEW.md](DIVIDEND_REVIEW.md) | Pending |
| cauldron/MiFrensGenesis.sol | Verify validator/gacha continuation and admin/minter handoff; reconcile redemption, voting and dividend lifecycle evidence. | [GENESIS_REVIEW.md](GENESIS_REVIEW.md) | Pending |
| cauldron/MigrationVesting.sol | Finish claim-gate/oracle/instant-tier integration and final migration entitlement conservation. | [VESTING_REVIEW.md](VESTING_REVIEW.md) | Pending |
| cauldron/MintCurvePolicy.sol | Reconcile arithmetic boundaries and policy fallbacks with current hook configuration consumers. | [POLICY_MATH_REVIEW.md](POLICY_MATH_REVIEW.md) | Pending |
| cauldron/MockAggregator.sol | Finish per-declaration implementation/caller or deployment-mock role and token-behavior compatibility. | [REMAINING_INTERFACES_MOCKS_REVIEW.md](REMAINING_INTERFACES_MOCKS_REVIEW.md) | Pending |
| cauldron/MockQuoteToken.sol | Finish per-declaration implementation/caller or deployment-mock role and token-behavior compatibility. | [REMAINING_INTERFACES_MOCKS_REVIEW.md](REMAINING_INTERFACES_MOCKS_REVIEW.md) | Pending |
| cauldron/NativeQuoteZap.sol | Close quote admission, refund/slippage and actual router-consumer configuration compatibility. | [NATIVE_ZAP_REVIEW.md](NATIVE_ZAP_REVIEW.md) | Pending |
| cauldron/PerpEngine.sol | Close open-book rotation/relaunch, settlement/funding conservation and poisoned-observation recovery; classify fork-only assertions. | [PERP_ENGINE_REVIEW.md](PERP_ENGINE_REVIEW.md) | Pending |
| cauldron/PerpMarkSource.sol | Finish mark observation/recovery lifecycle and source/deployed dependency compatibility. | [PERP_MARK_REVIEW.md](PERP_MARK_REVIEW.md) | Pending |
| cauldron/PerpStakerOracle.sol | Finish claim-gate/oracle/instant-tier integration and final migration entitlement conservation. | [VESTING_REVIEW.md](VESTING_REVIEW.md) | Pending |
| cauldron/PerpSwapLib.sol | Close projection/limit and settlement conservation boundaries across liquidity bands and quote changes. | [PERP_SWAP_REVIEW.md](PERP_SWAP_REVIEW.md) | Pending |
| cauldron/PerpVault.sol | Verify real-engine scaled rewards, queue/writeoff/replacement sequences and claim-consumer recovery. | [PERP_VAULT_REVIEW.md](PERP_VAULT_REVIEW.md) | Pending |
| cauldron/PoolOps.sol | Resolve dust sweep/burn and zero-liquidity leads; prove reserve backing across legacy, rotation and relaunch. | [POOL_OPS_REVIEW.md](POOL_OPS_REVIEW.md) | Pending |
| cauldron/QuoteOracle.sol | Close all worksheet oracle boundaries and consumer normalization; revalidate current surface evidence. | [QUOTE_ORACLE_REVIEW.md](QUOTE_ORACLE_REVIEW.md) | Pending |
| cauldron/QuoteRotator.sol | Complete admitted-asset callback and plan/arb integration with custody and atomicity checks. | [QUOTE_ROTATOR_REVIEW.md](QUOTE_ROTATOR_REVIEW.md) | Pending |
| cauldron/RedemptionExt.sol | Close multi-quote custody, emergency/successor and proceeds accounting; reconcile static-view consumers. | [REDEMPTION_FACET_REVIEW.md](REDEMPTION_FACET_REVIEW.md) | Pending |
| cauldron/ReserveLib.sol | Close reachable math/rounding boundaries against actual launch and reserve funding configurations. | [RESERVE_SEED_MATH_REVIEW.md](RESERVE_SEED_MATH_REVIEW.md) | Pending |
| cauldron/RoyaltyRouter.sol | Close royalty denomination, forwarding failures and collection/deployment wiring lifecycle. | [ROYALTY_ROUTER_REVIEW.md](ROYALTY_ROUTER_REVIEW.md) | Pending |
| cauldron/SeedLib.sol | Close reachable math/rounding boundaries against actual launch and reserve funding configurations. | [RESERVE_SEED_MATH_REVIEW.md](RESERVE_SEED_MATH_REVIEW.md) | Pending |
| cauldron/SurtaxLib.sol | Reconcile arithmetic boundaries and policy fallbacks with current hook configuration consumers. | [POLICY_MATH_REVIEW.md](POLICY_MATH_REVIEW.md) | Pending |
| cauldron/TreasuryGovernor.sol | Disposition known Low findings; finish bounded candidate selection and rotation-envelope lifecycle checks. | [TREASURY_REVIEW.md](TREASURY_REVIEW.md) | Pending |
| deploy/BadgeArtLib.sol | Resolve mark-source handoff/upload batching leads and complete script configuration/consumer checks. | [DEPLOY_PERP_ART_PROBE_REVIEW.md](DEPLOY_PERP_ART_PROBE_REVIEW.md) | Pending |
| deploy/DeployCauldron.s.sol | Extend constructor flag pass to full local factory/wiring/summon simulation. | [DEPLOY_CAULDRON_REVIEW.md](DEPLOY_CAULDRON_REVIEW.md) | Pending |
| deploy/DeployLaunchSniper.s.sol | Resolve documented deployment leads and verify each script supported configuration, ownership and operation identity. | [DEPLOY_HELPERS_REVIEW.md](DEPLOY_HELPERS_REVIEW.md) | Pending |
| deploy/DeployLaunchpad.s.sol | Complete local full deployment/wiring/summon and optional venue paths; verify exact deployable sizes and consumers. | [LAUNCHPAD_REVIEW.md](LAUNCHPAD_REVIEW.md) | Pending |
| deploy/DeployMigrationVesting.s.sol | Resolve documented deployment leads and verify each script supported configuration, ownership and operation identity. | [DEPLOY_HELPERS_REVIEW.md](DEPLOY_HELPERS_REVIEW.md) | Pending |
| deploy/DeployPerp.s.sol | Resolve mark-source handoff/upload batching leads and complete script configuration/consumer checks. | [DEPLOY_PERP_ART_PROBE_REVIEW.md](DEPLOY_PERP_ART_PROBE_REVIEW.md) | Pending |
| deploy/DeployQuoteAssets.s.sol | Resolve documented deployment leads and verify each script supported configuration, ownership and operation identity. | [DEPLOY_HELPERS_REVIEW.md](DEPLOY_HELPERS_REVIEW.md) | Pending |
| deploy/DeployRenderer.s.sol | Resolve mark-source handoff/upload batching leads and complete script configuration/consumer checks. | [DEPLOY_PERP_ART_PROBE_REVIEW.md](DEPLOY_PERP_ART_PROBE_REVIEW.md) | Pending |
| deploy/DeployRotationStack.s.sol | Complete two-helper deployment/consumer recovery; resolve band-width and supported volume-script configuration leads. | [VENUE_VOLUME_REVIEW.md](VENUE_VOLUME_REVIEW.md) | Pending |
| deploy/DeployV4Core.s.sol | Resolve documented deployment leads and verify each script supported configuration, ownership and operation identity. | [DEPLOY_HELPERS_REVIEW.md](DEPLOY_HELPERS_REVIEW.md) | Pending |
| deploy/FixFactoryWiring.s.sol | Resolve documented deployment leads and verify each script supported configuration, ownership and operation identity. | [DEPLOY_HELPERS_REVIEW.md](DEPLOY_HELPERS_REVIEW.md) | Pending |
| deploy/SellVolume.s.sol | Complete two-helper deployment/consumer recovery; resolve band-width and supported volume-script configuration leads. | [VENUE_VOLUME_REVIEW.md](VENUE_VOLUME_REVIEW.md) | Pending |
| deploy/SnipeBuy.s.sol | Resolve mark-source handoff/upload batching leads and complete script configuration/consumer checks. | [DEPLOY_PERP_ART_PROBE_REVIEW.md](DEPLOY_PERP_ART_PROBE_REVIEW.md) | Pending |
| deploy/SwapVolume.s.sol | Complete two-helper deployment/consumer recovery; resolve band-width and supported volume-script configuration leads. | [VENUE_VOLUME_REVIEW.md](VENUE_VOLUME_REVIEW.md) | Pending |
| deploy/TopUpVenue.s.sol | Complete two-helper deployment/consumer recovery; resolve band-width and supported volume-script configuration leads. | [VENUE_VOLUME_REVIEW.md](VENUE_VOLUME_REVIEW.md) | Pending |
| interfaces/INFTContract.sol | Finish per-declaration implementation/caller or deployment-mock role and token-behavior compatibility. | [REMAINING_INTERFACES_MOCKS_REVIEW.md](REMAINING_INTERFACES_MOCKS_REVIEW.md) | Pending |
| render/FrenRenderer.sol | Disposition dense-render failure; verify upload/lookup/freeze and renderer dependencies with supported build profiles. | [ART_STORAGE_REVIEW.md](ART_STORAGE_REVIEW.md) | Pending |
| render/LiquidatoorRenderer.sol | Finish source-matched build, badge data/collection callers and bounded rendering coverage. | [BADGE_RENDERER_REVIEW.md](BADGE_RENDERER_REVIEW.md) | Pending |
| render/SSTORE2.sol | Disposition dense-render failure; verify upload/lookup/freeze and renderer dependencies with supported build profiles. | [ART_STORAGE_REVIEW.md](ART_STORAGE_REVIEW.md) | Pending |
| render/TraitStorage.sol | Disposition dense-render failure; verify upload/lookup/freeze and renderer dependencies with supported build profiles. | [ART_STORAGE_REVIEW.md](ART_STORAGE_REVIEW.md) | Pending |
| vendor/BaseHook.sol | Verify callback authority/permission and CREATE2 consumers, including all current deployment masks. | [HOOK_BASE_REVIEW.md](HOOK_BASE_REVIEW.md) | Pending |
| vendor/HookMiner.sol | Verify callback authority/permission and CREATE2 consumers, including all current deployment masks. | [HOOK_BASE_REVIEW.md](HOOK_BASE_REVIEW.md) | Pending |
