"""Write per-file final sign-off records (SIGNOFF_CHECKLIST.json/.md).

Every row is a reviewer conclusion bound to the CURRENT source hash. A row is
SIGNED OFF only when its worksheet leads are dispositioned, no open Critical/
High/Medium touches it, and its evidence is recorded; limitations are listed,
never omitted. Common limitations apply to every row and are stated once.
"""
import hashlib
import json
from pathlib import Path

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parent.parent
GATES = json.loads((REPORT / "remediation/FINAL_GATES.json").read_text())
SIGNED = "SIGNED OFF (local scope, with limitations)"
BLOCKED = "BLOCKED"

COMMON = [
    "LC-FORK: no approved public RPC; the pinned public-chain fork lane was not run. The fork-dependent "
    "suites were executed against a LOCAL anvil node carrying freshly deployed V4 core (see VALIDATION.md); "
    "tests needing real-chain state are classified there, never counted as passes.",
    "LC-DEPLOYED: deployed bytecode, manifests and on-chain wiring were not compared (no RPC). Every fix here "
    "is source-only; already-deployed contracts are NOT repaired.",
    "LC-REVIEWER: reproduction and verification by the same review lineage (Codex, then Claude on the same "
    "tree); no independent second verifier.",
    "LC-GRAPH: the per-node machine-readable semantic graph (brief section 6.2) was not produced; coverage is "
    "per-file worksheets plus executed tests. Compiler graph resolution (0 unresolved) is mechanical only.",
    "LC-OFFCHAIN: frontend/indexer/API resilience drills (brief section 13) are outside this Solidity sign-off.",
]

ROWS = {
 "CauldronHook.sol": dict(ws="HOOK_REVIEW.md",
  concl="Swap path: beforeSwap sweep precedes fee processing and fails closed; fee split now validates the router's 96-byte STATICCALL reply before accepting a custom split (FS-feerouter-01); surtax and oracle dependency failures fall back instead of reverting (FS-surtax-01, FS-oracle-01); malformed mark answers no longer poison the pre-trade sweep (FS-perpmark-01, engine side); gacha resolution preserves earned pity on failed mints via the linked GachaLib (FS-gacha-01). Native in-swap gacha is an isolated self-call whose failure cannot revert a trade.",
  findings=["FS-feerouter-01 Medium FIXED", "FS-oracle-01 Medium FIXED (consumer path)", "FS-surtax-01 Medium FIXED (SurtaxLib)", "FS-perpmark-01 Medium FIXED (engine)", "FS-gacha-01 Medium FIXED (GachaLib)"],
  residual=["FS-hook-L01 Low: malformed curve-policy reply blocks commits/cost views until owner repair (swaps unaffected)", "Info: tagged credit may be assigned to any player (a gift, not theft); untagged attribution is tx.origin", "Info: engine replacement has no independent open-book guard (owner trust)"],
  evidence=["fee-router-fix", "fee-policy-treasury-acceptance (5/5 exact payouts)", "surtax-policy-fix", "oracle-fix-regressions", "oracle-fix-neighbors", "perp-mark-range-fix", "perp-mark-neighbor-regressions", "earned-art-and-badge-native", "gacha-pity-fix", "final full local suite"],
  limits=["Configured policies/death checker/engine/oracle are trusted owner dependencies; gas-burning dependencies are not proven tolerated."]),
 "CauldronRegistry.sol": dict(ws="REGISTRY_REVIEW.md",
  concl="Relaunch now either force-closes the whole perp book or reverts (FS-relaunch-01): the silent low-gas skip is removed and success is monotonic in gas. Quote requests are clamped before value moves; markConsumed follows the funding check; emergency actions are armed/timelocked with guardian veto and the exit guarantee holds while armed. Rotated-leg custody now follows a successor handoff through the facet (FS-successor-01). Explicit selector forwarders only; no fallback.",
  findings=["FS-relaunch-01 High FIXED", "FS-successor-01 Medium FIXED (facet)", "FS-ledger-01 Medium FIXED (ordering verified in registry integration)"],
  residual=["FS-registry-L01 Low: emergencyWithdrawLP pays currency0 amount as native (ERC20 generations)", "FS-registry-L02 Low: OG share of relaunch-flushed buybacks folded one generation late", "Info: Genesis setRegistry is one-time, so the migrateToSuccessor comment that governance can re-home it is stale; a V2 must use approval-based custody", "Info: facet 'view' wrappers are nonpayable in ABI; consumers must eth_call"],
  evidence=["registry-perp-leads (pre-fix failures)", "relaunch-successor-fix", "emergency-rotation-recovery-selected", "ledger-registry-reference-mature", "vesting-registry-conservation", "genesis-paid-mint-failure / gacha-pity-fix (iteration-2 relaunch)", "REGISTRY_FACET_STORAGE_CHECK.json", "final full local suite"],
  limits=["Registry runtime headroom is single-digit bytes; any future edit must be size-checked.", "Relaunch minimum gas now includes the 8M reserve even with an empty book."]),
 "CauldronToken.sol": dict(ws="TOKEN_FACTORY_REVIEW.md",
  concl="No mint entry point; registry-only burn without allowance (consent is enforced by each registry caller, which were reviewed); supply fixed by registry creation arguments.",
  findings=[], residual=["Info: TOTAL_SUPPLY is a constant, not a constructor cap"],
  evidence=["token-factory-review-corrected (R23_TokenAuthority executes the missing-mint call)", "final full local suite"], limits=[]),
 "cauldron/CauldronArtAdapter.sol": dict(ws="ART_STORAGE_REVIEW.md",
  concl="Stateless metadata adapter; caller-as-collection design cannot alter other state; trait derivation is visual, not a security RNG.",
  findings=[], residual=["Info: header overstates pre-reveal unpredictability", "Info: API deriveTraits counts come from generated assets; deployed-upload parity unverified"],
  evidence=["art-renderer-regressions", "renderer-real-blobs", "renderer-standalone-artifacts"], limits=["Immutable renderer dependency must be validated at deployment."]),
 "cauldron/CauldronBase.sol": dict(ws="REGISTRY_BASE_REVIEW.md",
  concl="Shared storage for registry and facet; recursive 61-entry layout parity holds; exit guarantee (_redeemBlocked) cannot suppress exits once an emergency is armed; renounce disabled. This continuation adds no storage.",
  findings=[], residual=[], evidence=["REGISTRY_FACET_STORAGE_CHECK.json", "final storage-layout recheck (FINAL_GATES / VALIDATION.md)"], limits=[]),
 "cauldron/CauldronCollection.sol": dict(ws="COLLECTION_REVIEW.md",
  concl="Art mint is minter-only, capped and sequential with plain _mint; badges live in a separate ID space and are excluded from totalMinted. The transfer-validator setter is registry-deployer-only with no registry forwarder, so FS-gacha-01's validator path is not reachable through brew collections.",
  findings=["FS-badge-floor-01 High FIXED at consumers (PoolOps/Vault)"],
  residual=["Info: stale header (immutable/no-admin claims)", "Info: badge revealed mapping defaults false; consumers must classify badges"],
  evidence=["collection-review (19)", "earned-art-and-badge-native", "final full local suite"], limits=[]),
 "cauldron/CauldronFactory.sol": dict(ws="TOKEN_FACTORY_REVIEW.md",
  concl="Permissionless deployBrew/deployVault create NEW instances only and cannot mutate registry pointers; owner-only badge renderer applies at creation.",
  findings=[], residual=["Info: transferOwnership accepts zero, emits no event"],
  evidence=["token-factory-review-corrected", "factory-operation-identity", "final full local suite (FactoryBadgeWiring)"], limits=[]),
 "cauldron/CauldronGachaRouter.sol": dict(ws="GACHA_ROUTER_REVIEW.md",
  concl="Guarded entries, manager-only callback, refunds of unused inputs, final-output minimum on churn; failed payments revert atomically.",
  findings=[], residual=["FS-router-L01 Low (DERIVED): malformed owner-configured oracle reply escapes playInCurveUnits fallback and reverts router plays; hook swaps unaffected", "Info: _pullQuote returns nominal amount; header says ETH is always currency0"],
  evidence=["gacha-churn-review (R23ChurnLocal funded churn)", "gacha-pity-fix (Q02, K4c, X4b)", "final full local suite"], limits=["ERC20-quote churn and liquidity-exhaustion partial fills not executed on real managers."]),
 "cauldron/CauldronGovernor.sol": dict(ws="GOVERNOR_REVIEW.md",
  concl="Snapshot voting with past-block weights; bounded eight-slot bench; registry-only consumption. More than eight simultaneous mandates can be evicted by design, with no permanent freeze.",
  findings=[], residual=["Info: bench eviction of weakest unconsumed proposals (characterized)", "Info: no quorum in brew governor (distinct from treasury policy)"],
  evidence=["governor-bench-recovery-snapshot", "governor-settled-bench-flood", "final full local suite"], limits=["Mock historical votes in characterizations."]),
 "cauldron/CauldronSeeder.sol": dict(ws="SEEDER_REVIEW.md",
  concl="Registry-only campaign control, manager-only callback, bounded range tracking. Production launches do not start streaming campaigns (PoolOps SEED_BASE_WAD = 1e18), so this component is dormant in the shipped registry path.",
  findings=[], residual=["R23-L2 not reproduced (seeder-range-tracking-nonvacuous)", "Info: immutable deployer remains a refundPrime authority pre-campaign"],
  evidence=["seeder-local-review (20)", "seeder-range-tracking-nonvacuous", "seeder-prime-refund (3)"], limits=["Re-open if SEED_BASE_WAD changes; fork-only CauldronSeeder.t.sol classified in VALIDATION.md."]),
 "cauldron/CauldronVault.sol": dict(ws="VAULT_REVIEW.md",
  concl="Legacy redemption rejects IDs above totalMinted (badge IDs) before any state change (FS-badge-floor-01); increments before burn/payment, all revert together. Both registry creation paths disable legacy mode (hook.setVault(0)).",
  findings=["FS-badge-floor-01 High FIXED"], residual=["Info: accountedDeposits is cumulative (legacy mode disabled in shipped wiring)"],
  evidence=["badge-floor-fix (21)", "badge-legacy-and-earned-yield (legacy vault property passes)", "vault-floor-review-offline (11)", "VAULT_SURFACE_CHECK.json"], limits=[]),
 "cauldron/CollectionLedger.sol": dict(ws="COLLECTION_LEDGER_REVIEW.md",
  concl="Registry-only ledger with no external calls; dead-end pre-freeze credit is now released with an exact equal debit and an event (FS-ledger-01); conservation holds as accepted = outstanding + paid + released.",
  findings=["FS-ledger-01 Medium FIXED"], residual=[],
  evidence=["ledger-release-conservation (27)", "ledger-registry-reference-mature", "LEDGER_SURFACE_CHECK.json"], limits=["All-retired nonempty full-registry scenario not separately executed; deployed frozen state not repaired."]),
 "cauldron/DefaultFeeRouter.sol": dict(ws="FEE_ROUTING_REVIEW.md",
  concl="Pure split with checked arithmetic; the hook now validates any router reply and falls back on malformed or overflowing results (FS-feerouter-01).",
  findings=["FS-feerouter-01 Medium FIXED (caller)"], residual=["Info: a custom router can change economics within a valid sum (owner choice)"],
  evidence=["fee-routing-review (20)", "fee-router-fix", "fee-policy-treasury-acceptance"], limits=[]),
 "cauldron/FeeRouteLib.sol": dict(ws="FEE_ROUTING_REVIEW.md",
  concl="Linked library routing guild/floor/staker shares from caller custody; codeless recipients refused; shipped hook folds non-native vault share into reserve rather than an ERC20 _move.",
  findings=[], residual=["Info: malformed ERC20 bool can revert _move/send for configured non-native routes", "Info: deliver() reports a partial pull as success; allowance reset attempted"],
  evidence=["fee-routing-review (20)"], limits=[]),
 "cauldron/GachaLib.sol": dict(ws="GACHA_LIB_REVIEW.md",
  concl="Queue resolution is bounded and FIFO, effects precede the only external call, a reverting mint cannot wedge the queue, and a failed mint now restores the pre-roll pity streak and opened count (FS-gacha-01).",
  findings=["FS-gacha-01 Medium FIXED"], residual=["Info: blockhash entropy with one expiry redraw; producer influence not excluded", "Info: seed pinning covers four batches from the cursor; deep backlogs can still expire (characterized by R2E)"],
  evidence=["genesis-paid-mint-failure (pre-fix failure)", "gacha-pity-fix (32 pass)", "gacha-churn-review"], limits=["New library bytecode requires relinking the hook at deployment."]),
 "cauldron/ICauldron.sol": dict(ws="INTERFACE_REVIEW.md", concl="Schema/interface declarations only; tuple orders match implementations in the compiler graph; enforcement belongs to implementations reviewed elsewhere.", findings=[], residual=["Info: no bounds/sanitization in BrewSpec schema; governor/UI must enforce"], evidence=["COMPILER_GRAPH.json (0 unresolved)"], limits=[]),
 "cauldron/ICreatorToken.sol": dict(ws="REMAINING_INTERFACES_MOCKS_REVIEW.md", concl="Validator interface declared view (STATICCALL), which is what keeps validator calls from re-entering mint paths.", findings=[], residual=[], evidence=["COMPILER_GRAPH.json"], limits=["Marketplace ERC-721C compatibility not tested."]),
 "cauldron/IDeathChecker.sol": dict(ws="INTERFACE_REVIEW.md", concl="Read-only policy declaration; hook handles revert/fallback.", findings=[], residual=["Info: comment says currency0 volume; hook supplies oracle-normalized volume"], evidence=["COMPILER_GRAPH.json"], limits=[]),
 "cauldron/ILiquidatorMintable.sol": dict(ws="INTERFACE_REVIEW.md", concl="Badge mint/stats interface; access control and art-supply exclusion enforced in implementations; consumer-side badge admission fixed (FS-badge-floor-01).", findings=[], residual=["Info: ETH-named stat fields on non-native generations are display units only"], evidence=["COMPILER_GRAPH.json", "earned-art-and-badge-native"], limits=[]),
 "cauldron/IPolicies.sol": dict(ws="INTERFACE_REVIEW.md", concl="Policy declarations; callers now validate surtax/router replies; odds/curve fallbacks documented.", findings=[], residual=["Info: 'a reverting module can never brick execution' wording is broader than the implementations guarantee"], evidence=["COMPILER_GRAPH.json"], limits=[]),
 "cauldron/ISeeder.sol": dict(ws="REMAINING_INTERFACES_MOCKS_REVIEW.md", concl="Seeder interface; constraints enforced by implementation and PoolOps.", findings=[], residual=[], evidence=["COMPILER_GRAPH.json"], limits=[]),
 "cauldron/LaunchSniper.sol": dict(ws="LAUNCH_SNIPER_REVIEW.md", concl="Owner-only launch/sweep helper; any downstream revert rolls back ignition atomically; renounce disabled.", findings=[], residual=["Info: ERC20 sweep ignores transfer bool; event reports whole balance including donations"], evidence=["launch-sniper-regressions (4)"], limits=["Real presale-to-pool-to-gacha launch not executed (mocks)."]),
 "cauldron/LegacyBuyLib.sol": dict(ws="LEGACY_BUY_REVIEW.md", concl="Bounded self-buy with rate-limited reference, birth-block deferral and output floor; failures roll back the self-call.", findings=[], residual=["Info: header says stateless; _syncRef writes namespaced hook storage"], evidence=["legacy-buy-review (14)", "ledger-registry-reference-mature (real hook buyback)"], limits=["Multi-block economic manipulation not modelled."]),
 "cauldron/MiFrensDividend.sol": dict(ws="DIVIDEND_REVIEW.md", concl="Native residual no longer re-credits allocated fractions (FS-dividend-01); each ERC20 payout is isolated in a self-only frame so a malformed token cannot block healthy assets or bank a moved balance (FS-dividend-02).", findings=["FS-dividend-01 Medium FIXED", "FS-dividend-02 Medium FIXED"], residual=[], evidence=["dividend-residual-fix (13)", "dividend-conservation-sequence (256)", "dividend-payout-isolation (22)", "dividend-payout-atomicity (2)", "genesis-lifecycle-regressions (48)", "DIVIDEND_SURFACE_CHECK.json"], limits=["Gas-burning token callbacks not proven tolerated; new self-only selector pushTokenIsolated is not a consumer call."]),
 "cauldron/MiFrensGenesis.sol": dict(ws="GENESIS_REVIEW.md", concl="Presale/discount/refund paths are exact-value, capped and nonReentrant; only genesis IDs carry votes; deployer-set transfer validator applies to hook mints, which is the reachable trigger for FS-gacha-01 (fixed in GachaLib).", findings=["FS-gacha-01 Medium FIXED (reachability here)"], residual=["Info: onlyDeployerOrRegistry setters stay live after ignition", "Info: discount price truncates price/10", "Info: refunds go to payer, not current holder"], evidence=["genesis-lifecycle-regressions (48)", "gacha-pity-fix (R23GenesisMintFailure passes)"], limits=["setRegistry is one-time: a V2 successor cannot take registry custody authority."]),
 "cauldron/MigrationVesting.sol": dict(ws="VESTING_REVIEW.md", concl="Instant-tier policy read is bounded and only canonical true grants instant tier, so a malformed policy falls back to vesting (FS-vesting-01); escrow receipt, not nominal burn, is vested.", findings=["FS-vesting-01 Medium FIXED"], residual=[], evidence=["vesting-policy-fix (29)", "vesting-fixed-invariants (6)", "vesting-registry-conservation", "VESTING_SURFACE_CHECK.json"], limits=["Invariant handler swallows claim reverts (liveness shown separately); MigrationVestingGate is fork-dependent."]),
 "cauldron/MintCurvePolicy.sol": dict(ws="POLICY_MATH_REVIEW.md", concl="Pure pricing curve with checked arithmetic; not on the swap path.", findings=[], residual=["Info: integer rounding plateaus for tiny calibrations", "Info: totalToMintOut loops supply (view)"], evidence=["final full local suite (F13, R23_PolicyBoundaries)"], limits=[]),
 "cauldron/MockAggregator.sol": dict(ws="REMAINING_INTERFACES_MOCKS_REVIEW.md", concl="Testnet price mock; the launchpad refuses mock quote stacks off Sepolia (DeployLaunchpad chain guard).", findings=[], residual=["Info: must never back production collateral"], evidence=["launchpad-preflight-serial (12)"], limits=[]),
 "cauldron/MockQuoteToken.sol": dict(ws="REMAINING_INTERFACES_MOCKS_REVIEW.md", concl="Freely mintable testnet quote; Sepolia-only via launchpad guard.", findings=[], residual=["Info: unrestricted mint by design"], evidence=["launchpad-preflight-serial (12)"], limits=[]),
 "cauldron/NativeQuoteZap.sol": dict(ws="NATIVE_ZAP_REVIEW.md", concl="Stateless zap: manager-only callback, refund of unspent input before return, caller-supplied output floor; nested zap refused by manager lock.", findings=[], residual=["Info: output transfer trusts empty/true token return"], evidence=["oracle-fix-neighbors (NativeQuoteZapLocal 4)", "zap-refund-callbacks (2)"], limits=[]),
 "cauldron/PerpEngine.sol": dict(ws="PERP_ENGINE_REVIEW.md", concl="Mark answers are range-checked before use (FS-perpmark-01); vault replacement now respects earned rewards (FS-perpvault-01 via hasStakers); relaunch can no longer strand the book (FS-relaunch-01 at the registry). Cascade exit condition (R23-L1) dispositioned in VALIDATION.md with mixed-leverage evidence.",
  findings=["FS-perpmark-01 Medium FIXED", "FS-perpvault-01 Medium FIXED (vault side)", "FS-relaunch-01 High FIXED (registry side)"], residual=["R23-L1 see VALIDATION.md", "Info: _book narrows collateral to uint128 (bounded by caps)", "Info: token pull ignores bool (first-party token only)"],
  evidence=["perp-mark-range-fix", "perp-mark-neighbor-regressions (15)", "cascade-ordering-64", "registry-perp-leads / relaunch-successor-fix (R23CascadeMixedLeverage)", "PERPENGINE_BYTECODE_SIZES.json"], limits=["Deployed poisoned-ring recovery not simulated; see PERP_RECOVERY_RUNBOOK.md."]),
 "cauldron/PerpMarkSource.sol": dict(ws="PERP_MARK_REVIEW.md", concl="Owner-curated weighted tick over at most five pools; convex combination stays in int24; engine now validates the reply range.", findings=[], residual=["Info: negative means truncate toward zero (sub-tick bias)"], evidence=["perp-mark-existing (11)", "perp-reward-scale-and-mark-boundaries"], limits=["Funded multi-pool TWAP manipulation not modelled (mocked manager)."]),
 "cauldron/PerpStakerOracle.sol": dict(ws="VESTING_REVIEW.md", concl="Read-only tier oracle over an immutable vault's share balances.", findings=[], residual=["Info: any positive share qualifies (dust-share tier economics)"], evidence=["vesting-policy-fix"], limits=[]),
 "cauldron/PerpSwapLib.sol": dict(ws="PERP_SWAP_REVIEW.md", concl="Linked library for projection, swaps, requote conversion and ring maintenance; packed slot identities match compiler layout; invalid ticks are now filtered before sqrtPriceAtTick by the engine.", findings=["FS-perpmark-01 Medium FIXED (caller)"], residual=["Info: tryTransfer decodes nonempty returndata and can revert on malformed tokens (first-party tokens only)"], evidence=["PERP_PACKED_SLOT_REVIEW.json", "requote-local-regressions (10)", "open-book-local-regressions (2)"], limits=["Full-book requote gas and extreme-decimal conversions not exhaustively tested."]),
 "cauldron/PerpVault.sol": dict(ws="PERP_VAULT_REVIEW.md", concl="Replacement guard now counts settled attributed rewards (FS-perpvault-01); aggregate equals the sum of current-epoch user debts; claims and write-offs keep it exact.", findings=["FS-perpvault-01 Medium FIXED"], residual=["Consumer: StakePanel hides the zero-display claim needed to clear dust-rounded rewards (direct call works)"], evidence=["perp-earned-yield-fix (32)", "perp-mark-acceptance-and-reward-sequence (256x64)", "PERPVAULT_SURFACE_CHECK.json"], limits=["Actual quote-conversion requote with live positions modelled, not swapped."]),
 "cauldron/PoolOps.sol": dict(ws="POOL_OPS_REVIEW.md", concl="Linked library executing in registry custody; badge IDs rejected before ledger/payment/custody on recycle and buy (FS-badge-floor-01); measured-delta accounting on reserve claims and additions.", findings=["FS-badge-floor-01 High FIXED"], residual=["Info: CLAIM_DUST tolerance of 1e12 raw units per migration (bounded; vesting records actual receipt)", "Info: zero-liquidity reserve add after sweep can leave loose uncredited tokens"], evidence=["badge-floor-fix (21)", "og-floor-admission-fixture (13)", "POOLOPS_SURFACE_CHECK.json", "BADGE_BYTECODE_SIZES.json"], limits=["Headroom ~111 runtime bytes."]),
 "cauldron/QuoteOracle.sol": dict(ws="QUOTE_ORACLE_REVIEW.md", concl="Bounded STATICCALL reads with field validation; unusable answers return zero so the retained cache is used for volume while strict consumers fail closed (FS-oracle-01).", findings=["FS-oracle-01 Medium FIXED"], residual=["Info: pegged assets bypass feed/sequencer checks by construction"], evidence=["oracle-fix-regressions (42)", "oracle-fix-neighbors (146)", "ORACLE_SURFACE_CHECK.json"], limits=["Real feed configuration not verified (no RPC)."]),
 "cauldron/QuoteRotator.sol": dict(ws="QUOTE_ROTATOR_REVIEW.md", concl="Registry/live-engine gated swaps over exact-PoolId curated venues with a live oracle floor; permissionless plan/arb steps bounded by per-block caps and profit checks.", findings=[], residual=["Info: arbStep does not reserve planned capital (design)", "Info: keeper payment after unlock may call recipient code (effects already written)"], evidence=["rotation-gates-review (24)", "RotationLifecycleLocal / QuoteRotationLocalIntegration"], limits=["Real-manager partial second-leg arb fill not executed."]),
 "cauldron/RedemptionExt.sol": dict(ws="REDEMPTION_FACET_REVIEW.md", concl="OG redemption/resale, legacy materialization, rotation slices and leg recovery under shared storage; a live generation handed to the successor now passes its leg NFTs to that successor (FS-successor-01) while live-generation protection and past-generation retry are unchanged.", findings=["FS-successor-01 Medium FIXED"], residual=["FS-rotation-I01 Info: rotateSlice/rotateSliceFrom lack nonReentrant; all callbacks owner-curated", "Info: legProceedsOf is not forwarded by the registry"], evidence=["relaunch-successor-fix (R23SuccessorLegHandoff)", "emergency-rotation-recovery-selected", "RotationLifecycleLocal", "REGISTRY_FACET_STORAGE_CHECK.json"], limits=[]),
 "cauldron/ReserveLib.sol": dict(ws="RESERVE_SEED_MATH_REVIEW.md", concl="Pure tick/liquidity math with floor rounding; callers supply positive spacing and ordered ticks.", findings=[], residual=[], evidence=["reserve-math-review (13, 8x256 fuzz)"], limits=[]),
 "cauldron/RoyaltyRouter.sol": dict(ws="ROYALTY_ROUTER_REVIEW.md", concl="Immutable hook/sink; native forwarded with stipend retention, permissionless sweep to fixed destinations only.", findings=[], residual=["Info: malformed adopt() reply can revert an ERC20 sweep (sink is configured)"], evidence=["royalty-routing-review (5)"], limits=[]),
 "cauldron/SeedLib.sol": dict(ws="RESERVE_SEED_MATH_REVIEW.md", concl="Pure schedule/band math; production callers use index 0/count 1.", findings=[], residual=[], evidence=["reserve-math-review", "seeder-local-review"], limits=[]),
 "cauldron/SurtaxLib.sol": dict(ws="POLICY_MATH_REVIEW.md", concl="Policy reply read as one bounded word with length check and hard cap; ordinary and malformed failures take the default curve (FS-surtax-01).", findings=["FS-surtax-01 Medium FIXED"], residual=["Info: default branch relies on configured maxBps"], evidence=["surtax-policy-fix (7)", "SURTAX_SURFACE_CHECK.json"], limits=[]),
 "cauldron/TreasuryGovernor.sol": dict(ws="TREASURY_REVIEW.md", concl="Majority plus snapshot quorum over historical votes; bounded bench; registry-only consumption; guardian cancellation.", findings=[], residual=["FS-treasury-L01 Low: equal-support ties follow vote order, not documented lower id (failing property retained)", "FS-treasury-L02 Low: cancelling a stale executed id clears the current envelope (failing property retained)"], evidence=["fee-policy-treasury-acceptance", "final full local suite (R23TreasuryTargeting expected failures)"], limits=["Mock votes; real ERC721 checkpoint integration not executed here."]),
 "deploy/BadgeArtLib.sol": dict(ws="DEPLOY_PERP_ART_PROBE_REVIEW.md", concl="Chunked SSTORE2 upload with hash check; atomic only within a single call.", findings=[], residual=["Info: interrupted multi-transaction upload can leave partial art"], evidence=["badge-renderer-regressions (10)"], limits=[]),
 "deploy/DeployCauldron.s.sol": dict(ws="DEPLOY_CAULDRON_REVIEW.md", concl="Minimal legacy deployment; hook mask now includes beforeSwap and beforeSwapReturnDelta (FS-deployhook-01).", findings=["FS-deployhook-01 Low FIXED"], residual=[], evidence=["deploy-hook-permission-offline (2)"], limits=["Not the production path (DeployLaunchpad)."]),
 "deploy/DeployLaunchSniper.s.sol": dict(ws="DEPLOY_HELPERS_REVIEW.md", concl="Checks opener role before broadcast; wires exemption and finalizer.", findings=[], residual=["Info: non-atomic multi-transaction wiring"], evidence=["source review"], limits=[]),
 "deploy/DeployLaunchpad.s.sol": dict(ws="LAUNCHPAD_REVIEW.md", concl="Production deployment script; optional band venue now uses separate recoverable helpers (FS-venueseed-01 caller compatibility); mock quote stack refused off Sepolia.", findings=["FS-venueseed-01 Medium FIXED (caller)"], residual=["Info: several env values narrow to smaller integers without prior bound checks", "Info: role handoffs beyond registry are manual"], evidence=["launchpad-preflight-serial (12)", "launchpad-venue-compatibility (two-helper lifecycle)", "local anvil rehearsal (VALIDATION.md)"], limits=["Rehearsal is local anvil, not the target chain."]),
 "deploy/DeployMigrationVesting.s.sol": dict(ws="DEPLOY_HELPERS_REVIEW.md", concl="Deploys oracle/escrow and optionally sets the claim gate.", findings=[], residual=["FS-deployvesting-01 Low: script ignores the emergency delay that setClaimGate(nonzero) consumes"], evidence=["source review", "vesting-registry-conservation"], limits=[]),
 "deploy/DeployPerp.s.sol": dict(ws="DEPLOY_PERP_ART_PROBE_REVIEW.md", concl="Deploys and wires engine/vault, optional mark source, then hands ownership to the timelock.", findings=[], residual=["FS-deployperp-I01 Info: mark-source handoff keyed on the env flag", "Info: TWAP_WINDOW narrows to uint32"], evidence=["local anvil rehearsal (VALIDATION.md)"], limits=[]),
 "deploy/DeployQuoteAssets.s.sol": dict(ws="DEPLOY_HELPERS_REVIEW.md", concl="Testnet mock asset/rotator deployment; does not wire the rotator.", findings=[], residual=["Info: no chain guard in this script (launchpad has one)"], evidence=["source review"], limits=[]),
 "deploy/DeployRenderer.s.sol": dict(ws="DEPLOY_PERP_ART_PROBE_REVIEW.md", concl="Deploys storage/renderer, batched uploads, optional irreversible freeze.", findings=[], residual=["FS-deployrender-I01 Info: BATCH=0 never advances (fails in simulation)", "Info: freeze does not validate art completeness", "Info: dedicated render profile fails to compile (transient syntax); explicit-path build under cauldron settings succeeds"], evidence=["renderer-standalone-artifacts", "renderer-profile-tests (failure retained)"], limits=[]),
 "deploy/DeployRotationStack.s.sol": dict(ws="VENUE_VOLUME_REVIEW.md", concl="Rotation stack deployment incl. VenueSeeder helper; both seed entrypoints now refuse to overwrite a live position (FS-venueseed-01).", findings=["FS-venueseed-01 Medium FIXED"], residual=["FS-venueband-L01 Low: seedBand width 10x the documented band", "Info: partial reuse of rotator/governor silently discarded"], evidence=["venue-repeated-seed-recovery (pre-fix)", "venue-reseed-guard", "launchpad-venue-compatibility"], limits=["Testnet mock venue support only."]),
 "deploy/DeployV4Core.s.sol": dict(ws="DEPLOY_HELPERS_REVIEW.md", concl="Deploys PoolManager/PositionManager after requiring Permit2 code.", findings=[], residual=["Info: checks Permit2 code presence, not implementation"], evidence=["local anvil rehearsal (VALIDATION.md)"], limits=[]),
 "deploy/FixFactoryWiring.s.sol": dict(ws="DEPLOY_HELPERS_REVIEW.md", concl="Timelocked factory rewiring helper.", findings=[], residual=["FS-deployfactory-01 Low: rerun encodes a new factory, so EXECUTE cannot match the scheduled operation"], evidence=["factory-operation-identity"], limits=[]),
 "deploy/SellVolume.s.sol": dict(ws="VENUE_VOLUME_REVIEW.md", concl="Operator volume probe; no user funds.", findings=[], residual=["Info: no min-output; hardcoded pool key"], evidence=["source review"], limits=[]),
 "deploy/SnipeBuy.s.sol": dict(ws="DEPLOY_PERP_ART_PROBE_REVIEW.md", concl="Operator buy probe; no user funds.", findings=[], residual=["Info: no min-output; reported spend is requested budget"], evidence=["source review"], limits=[]),
 "deploy/SwapVolume.s.sol": dict(ws="VENUE_VOLUME_REVIEW.md", concl="Operator volume probe; no user funds.", findings=[], residual=["Info: no min-output; hardcoded pool key"], evidence=["source review"], limits=[]),
 "deploy/TopUpVenue.s.sol": dict(ws="VENUE_VOLUME_REVIEW.md", concl="Mock venue top-up/recovery helper script.", findings=[], residual=["Info: slippage env narrows to uint16"], evidence=["source review"], limits=[]),
 "interfaces/INFTContract.sol": dict(ws="REMAINING_INTERFACES_MOCKS_REVIEW.md", concl="Holder-tax interface; hook clips values.", findings=[], residual=[], evidence=["COMPILER_GRAPH.json"], limits=[]),
 "render/FrenRenderer.sol": dict(ws="ART_STORAGE_REVIEW.md", concl="On-chain SVG renderer over owner-uploaded trait blobs; shipped art fits a 118,476-byte bound.", findings=[], residual=["FS-artbuffer-01 Low: dense valid owner uploads overflow the fixed 200,000-byte buffer (failing property retained)", "Info: appendUint comment claims 65535 capacity"], evidence=["renderer-real-blobs (5)", "renderer-dense-upload (failure retained)", "ART_BUFFER_BOUND.json"], limits=["Dedicated render profile build fails (tooling)."]),
 "render/LiquidatoorRenderer.sol": dict(ws="BADGE_RENDERER_REVIEW.md", concl="Badge SVG renderer interpolating only numbers, addresses and owner art.", findings=[], residual=["Info: price/bounty labels assume 18-decimal native units", "Info: one-step ownership, zero allowed"], evidence=["badge-renderer-regressions (10)"], limits=[]),
 "render/SSTORE2.sol": dict(ws="ART_STORAGE_REVIEW.md", concl="Write-once code storage with STOP prefix; no mutation path.", findings=[], residual=[], evidence=["renderer-real-blobs"], limits=[]),
 "render/TraitStorage.sol": dict(ws="ART_STORAGE_REVIEW.md", concl="Owner-only uploads until irreversible freeze.", findings=[], residual=["Info: freeze does not validate completeness"], evidence=["renderer-real-blobs"], limits=[]),
 "vendor/BaseHook.sol": dict(ws="HOOK_BASE_REVIEW.md", concl="Manager-only wrappers; permission bits validated against the address at construction.", findings=[], residual=[], evidence=["deploy-hook-permission-offline (address validation executed)"], limits=[]),
 "vendor/HookMiner.sol": dict(ws="HOOK_BASE_REVIEW.md", concl="Deterministic CREATE2 salt search over the lower 14 permission bits.", findings=[], residual=["Info: bounded search may not find a salt for every initcode"], evidence=["deploy-hook-permission-offline"], limits=[]),
}


def build(verdicts, extra_evidence=None):
    cur = GATES["tree_vs_baseline"]["first_party_current_sha256"]
    files = []
    for rel, r in ROWS.items():
        path = f"contracts/solidity/{rel}"
        v = verdicts.get(rel, SIGNED)
        ev = list(r["evidence"]) + (extra_evidence or {}).get(rel, [])
        files.append({
            "file": path, "source_sha256": cur[path], "worksheet": r["ws"],
            "body_traversal": "documented", "final_signoff": v,
            "conclusion": r["concl"], "findings_touching": r["findings"],
            "residual_low_info": r["residual"], "evidence": ev,
            "file_limitations": r["limits"],
        })
    assert len(files) == 66 and len({f["file"] for f in files}) == 66
    signed = sum(f["final_signoff"] == SIGNED for f in files)
    out = {"final_signoffs": signed, "scope_files": 66, "standard": __doc__.strip(),
           "common_limitations": COMMON, "files": files}
    (REPORT / "SIGNOFF_CHECKLIST.json").write_text(json.dumps(out, indent=2) + "\n")
    md = [f"# Per-file final sign-off\n\n**{signed}/66 signed off** (local scope, with the limitations below).\n",
          "A row is SIGNED OFF only when its worksheet leads are dispositioned, no open Critical/High/Medium touches it, "
          "and its evidence is recorded. It is not a claim that the file is bug-free or that the system is deploy-ready; "
          "see FINAL_REPORT.md for the deploy verdict.\n", "## Common limitations (apply to every row)\n"]
    md += [f"- {c}" for c in COMMON]
    md.append("\n## Rows\n")
    for f in files:
        md.append(f"### {f['file'].removeprefix('contracts/solidity/')} — {f['final_signoff']}\n")
        md.append(f"- Source SHA256: `{f['source_sha256']}` · Worksheet: [{f['worksheet']}]({f['worksheet']})")
        md.append(f"- Conclusion: {f['conclusion']}")
        if f["findings_touching"]:
            md.append("- Findings: " + "; ".join(f["findings_touching"]))
        if f["residual_low_info"]:
            md.append("- Residual (unfixed, documented): " + "; ".join(f["residual_low_info"]))
        md.append("- Evidence: " + "; ".join(f["evidence"]))
        if f["file_limitations"]:
            md.append("- File limitations: " + "; ".join(f["file_limitations"]))
        md.append("")
    (REPORT / "SIGNOFF_CHECKLIST.md").write_text("\n".join(md).rstrip("\n") + "\n")
    return signed


if __name__ == "__main__":
    import sys
    verdicts = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    print(build(verdicts), "/66 signed off")
