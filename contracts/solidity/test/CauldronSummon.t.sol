// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolOps} from "../cauldron/PoolOps.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../cauldron/ICauldron.sol";
import {CollectionLedger} from "../cauldron/CollectionLedger.sol";
import {IPositionManagerOps} from "../cauldron/PoolOps.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @notice Fork integration test for Cauldron genesis against LIVE Uniswap V4.
 *
 *  Deploying V4 in-process is impossible here: permit2 hard-pins solc =0.8.17
 *  while our contracts require ^0.8.26 (they can't share a compilation unit).
 *  So we fork a chain with V4 already deployed and drive the real PoolManager +
 *  PositionManager + canonical Permit2 through interfaces only.
 *
 *  Run:
 *    export FORK_RPC=https://...           # chain with V4 deployed
 *    export POOL_MANAGER=0x...
 *    export POSITION_MANAGER=0x...
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract CauldronSummonForkTest -vvv
 *
 *  Without FORK_RPC the tests no-op (so the suite still compiles and passes in CI).
 */
contract CauldronSummonForkTest is Test {
    CauldronHook hook;
    CauldronRegistry registry;
    IPoolManager pm;
    bool active;

    /// sqrtPrice floor for a zeroForOne (ETH→token) buy = TickMath.MIN_SQRT_PRICE + 1.
    uint160 constant MIN_SQRT_LIMIT = 4295128740;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return; // no fork configured -> skip
        active = true;

        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(
            IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this)
        );
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);

        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        // Wire the OG-redemption delegatecall facet (one-time). Without this the
        // redeemOgFren / buyTreasuryOgFren / donateToReserve / materializeLegacyReserve
        // forwarders revert NotConfigured.
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        // MANDATORY for the relaunch green-candle buy: the registry's own reserve
        // buy must skip the base tax + anti-sniper surtax, else its ETH is taxed
        // away mid-buy and the settle runs out of funds (see DeployLaunchpad).
        // Exemption is gated on BOTH isOpener[sender] (audit F-13) AND taxExempt —
        // the registry is the swap SENDER and tags itself as the player.
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 10 ether);
    }

    function test_Summon_CreatesGen1_OnFork() public {
        if (!active) return;

        (address token, ) = registry.summon{value: 1 ether}();

        assertEq(registry.currentGeneration(), 1, "gen 1");
        assertEq(registry.currentToken(), token, "current token");
        assertEq(CauldronToken(token).symbol(), "GNOME", "creature symbol");
        assertEq(CauldronToken(token).totalSupply(), registry.TOTAL_SUPPLY(), "supply minted");
        assertGt(registry.generationPositionId(1), 0, "active v4 position minted");

        // --- Reserve-LP model assertions (all supply in the LP) ---
        // 1. The RESERVE position exists (the ~90% migration/genesis supply).
        assertGt(registry.generationReservePositionId(1), 0, "reserve position minted");
        // 2. The reserve tick band is valid (lower < upper) — it sits below the
        //    launch tick so the position is pure token1 (verified in ReserveLib).
        assertLt(registry.reserveTickLower(1), registry.reserveTickUpper(1), "reserve band valid");
        // 3. The registry holds ~ZERO loose tokens — 100% is in the two LP
        //    positions (no whale-look wallet bag). Allow tiny rounding dust.
        uint256 loose = CauldronToken(token).balanceOf(address(registry));
        assertLt(loose, 1e18, "registry holds ~no loose tokens (all in LP)");
    }

    /// PRIME BUY: owner pre-funds personal ETH (fundPrimeBuy) → at genesis summon
    /// the registry does a REAL first-block market buy and sends the bought GNOME to
    /// the treasury (airdropWallet). NET demand (green candle) + ZERO dilution: the
    /// supply is unchanged and the treasury accumulates GNOME to airdrop OGs later.
    function test_Genesis_PrimeBuy_SendsGnomeToTreasury_OnFork() public {
        if (!active) return;

        address treasury = address(0xBEEF);
        registry.setPrimeFunder(address(this));
        registry.setAirdropReserve(treasury, 0); // set the treasury wallet, no carve

        // Fund the prime buy with 0.5 ETH of "personal" ETH (separate from the seed).
        registry.fundPrimeBuy{value: 0.5 ether}();
        assertEq(registry.primeBuyEth(), 0.5 ether, "prime ETH loaded");

        (address token, ) = registry.summon{value: 1 ether}();

        // The treasury received a NON-ZERO bag of freshly-bought GNOME.
        uint256 treGnome = CauldronToken(token).balanceOf(treasury);
        assertGt(treGnome, 0, "treasury got prime-bought GNOME");
        // The prime balance was fully spent.
        assertEq(registry.primeBuyEth(), 0, "prime ETH spent");
        // ZERO dilution: total supply is still exactly the fixed supply.
        assertEq(CauldronToken(token).totalSupply(), registry.TOTAL_SUPPLY(), "no dilution");
        // The buy really hit the market: the pool's spot tick is ABOVE the launch
        // tick (a green candle), i.e. price rose from the prime buy.
        (, int24 tickAfter,,) = StateLibrary.getSlot0(pm, registry.generationPoolId(1));
        // Reserve band sits below spot (pure token1) → its upper bound < spot tick.
        assertLt(registry.reserveTickUpper(1), tickAfter, "spot pumped above the reserve band");
    }

    /// Prime buy is gated: a non-funder can neither fund nor sweep.
    function test_PrimeBuy_OnlyFunder() public {
        if (!active) return;
        registry.setPrimeFunder(address(this));
        vm.deal(address(0xCAFE), 1 ether);
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        registry.fundPrimeBuy{value: 1 ether}();

        registry.fundPrimeBuy{value: 0.3 ether}();
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        registry.sweepPrimeBuy();
        // The funder can reclaim before summon.
        uint256 b = address(this).balance;
        registry.sweepPrimeBuy();
        assertEq(address(this).balance, b + 0.3 ether, "funder reclaimed");
        assertEq(registry.primeBuyEth(), 0, "swept");
    }

    /// RECYCLE: redeeming pays the holder the LIVE floor of the current token from
    /// the reserve and moves the NFT to the TREASURY (the registry) — NOT burned.
    /// Circulating supply is unchanged (a location move), and the recycled fren is
    /// now owned by the registry, ready for resale.
    function test_RedeemFren_RecyclesToTreasury_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4); // 10%, 4 shares
        mifrens.mint(address(this), 1);

        (address token, ) = registry.summon{value: 1 ether}();

        uint256 supplyBefore = CauldronToken(token).totalSupply();
        uint256 F = registry.floorPerFren();
        uint256 balBefore = CauldronToken(token).balanceOf(address(this));

        uint256 got = registry.redeemOgFren(1);
        uint256 delta = CauldronToken(token).balanceOf(address(this)) - balBefore;

        assertGt(got, 0, "redeemed a nonzero amount of the live token");
        assertApproxEqAbs(got, F, F / 1e6 + 1, "paid ~ the live floor");
        assertEq(delta, got, "received exactly the redeemed token from the reserve LP");
        assertEq(mifrens.ownerOf(1), address(registry), "fren moved to the TREASURY (not burned)");
        assertTrue(mifrens.everMoved(1), "fren marked moved");
        assertEq(CauldronToken(token).totalSupply(), supplyBefore, "circulating supply UNCHANGED");

        // Same fren can't be redeemed again by the old owner (registry owns it now).
        vm.expectRevert();
        registry.redeemOgFren(1);
    }

    /// BUYBACK grows the floor: buying a treasury-held fren for 2× floor adds the
    /// payment to the reserve → floorPerFren strictly increases and the buyer gets
    /// the (un-enchanted) NFT. Net of the redeem+buy cycle, the reserve grows.
    function test_BuyTreasuryFren_GrowsFloor_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4);
        mifrens.mint(address(this), 1);

        (address token, ) = registry.summon{value: 1 ether}();
        uint256 reserveStart = registry.genesisReserveOutstanding();

        // Recycle #1 → treasury holds it, we hold ~F tokens.
        registry.redeemOgFren(1);
        uint256 floorAfterRedeem = registry.floorPerFren();

        // Buy it back for 2× floor (approve the registry to pull the payment).
        uint256 price = 2 * registry.floorPerFren();
        // Top up so we definitely cover 2× (redeem only gave us 1×).
        deal(token, address(this), price);
        CauldronToken(token).approve(address(registry), price);
        uint256 paid = registry.buyTreasuryOgFren(1);

        assertApproxEqAbs(paid, price, price / 1e6 + 1, "paid ~2x floor");
        assertEq(mifrens.ownerOf(1), address(this), "buyer owns the fren");
        assertGt(registry.floorPerFren(), floorAfterRedeem, "floor RATCHETED up after buyback");
        assertGt(registry.genesisReserveOutstanding(), reserveStart, "reserve grew net of redeem+buy");
    }

    /// Floor RATCHETS across repeated recycle→buy cycles: each cycle nets the
    /// reserve up (buy adds 2F, redeem removed F), so floorPerFren only grows.
    function test_Floor_RatchetsUp_OverCycles_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4);
        mifrens.mint(address(this), 1);
        (address token, ) = registry.summon{value: 1 ether}();

        uint256 prevFloor = registry.floorPerFren();
        for (uint256 i = 0; i < 3; i++) {
            registry.redeemOgFren(1);
            uint256 price = 2 * registry.floorPerFren();
            deal(token, address(this), price);
            CauldronToken(token).approve(address(registry), price);
            registry.buyTreasuryOgFren(1);
            uint256 nowFloor = registry.floorPerFren();
            assertGt(nowFloor, prevFloor, "floor strictly increased each cycle");
            prevFloor = nowFloor;
        }
    }

    /// PROTECTION: the emergencyAdmin can pause redemption — redeemFren reverts
    /// while paused, works once cleared. It only disables a flow, never moves funds.
    function test_RedeemFren_PauseGuard_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4);
        mifrens.mint(address(this), 1);
        registry.summon{value: 1 ether}();

        registry.setRedemptionPaused(true);
        assertTrue(registry.redemptionPaused(), "paused");
        vm.expectRevert(); // RedemptionPaused
        registry.redeemOgFren(1);

        registry.setRedemptionPaused(false);
        uint256 got = registry.redeemOgFren(1);
        assertGt(got, 0, "redeem works after unpause");
        assertEq(mifrens.ownerOf(1), address(registry), "fren recycled to treasury after unpause");
    }

    /// A volume-minted fren (id > genesisShares) can never redeem a founder's
    /// reserve share, and only the owner may redeem their fren.
    function test_RedeemFren_Guards_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4); // 4 genesis shares
        mifrens.mint(address(this), 5); // id 5 > genesisShares (volume tranche)
        mifrens.mint(address(0xBEEF), 2); // someone else's genesis fren

        registry.summon{value: 1 ether}();

        vm.expectRevert(); // id out of the genesis tranche
        registry.redeemOgFren(5);
        vm.expectRevert(); // not the owner
        registry.redeemOgFren(2);
    }

    // NOTE: the seed-sqrtPrice overflow guard (FullMath.mulDiv over 512-bit
    // intermediate space) now lives in PoolOps._sqrtPrice and is exercised by the
    // fork integration path below. The old direct-call unit test was removed with
    // the registry's computeSqrtPriceX96 helper (moved into PoolOps).

    // Creature cycle is pure — runs with or without a fork.
    function test_CreatureCycle() public pure {
        // creature table lives in the linked PoolOps library now (registry EIP-170)
        (, string memory s1) = PoolOps.creatureFor(1);
        (, string memory s7) = PoolOps.creatureFor(7);
        assertEq(s1, "GNOME");
        assertEq(s7, "GNOME", "cycles every 6 generations");
    }

    /// RELAUNCH GREEN-CANDLE BUY: a new iteration funds its migration reserve with
    /// a REAL first-block market buy (visible volume) instead of a silent seed.
    /// We drive a full gen-1 → gen-2 rebirth on the live PoolManager and assert:
    ///   - gen-2 is seeded with a valid out-of-range reserve band,
    ///   - the registry holds ~no loose tokens (100% ended in the two LP positions),
    ///   - the newborn pool registered REAL volume from the candle (not a seed), and
    ///   - the reserve is funded (its position exists) so migration is covered.
    function test_Relaunch_GreenCandleBuy_FundsReserve_OnFork() public {
        if (!active) return;

        // Governor is mandatory for relaunch — wire a mock winner.
        MockGovernor gov = new MockGovernor();
        registry.setGovernor(address(gov));

        // gen-1
        (address token1, ) = registry.summon{value: 1 ether}();
        uint256 supply = registry.TOTAL_SUPPLY();

        // A real trader buys gen-1 → tokens leave the LP and become CIRCULATING.
        // This is exactly the supply the next iteration must migrate 1:1, so it
        // sizes the migration reserve the green-candle buy has to reproduce.
        // Tax-exempt so we get a clean fill (no ~99% launch surtax to reason about).
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        uint256 circulating = _buyGen1(0.25 ether);
        assertGt(circulating, 1e18, "trader acquired real circulating supply");

        // Age the pool past the 24h volume window (blocks, not just time) so it reads
        // dead, and clear the min-lifetime grace, then rebirth.
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen1 dead");

        (address token2, ) = registry.relaunch();

        // --- new-iteration assertions ---
        assertEq(registry.currentGeneration(), 2, "gen 2 born");
        assertEq(registry.currentToken(), token2, "current token = gen2");
        assertEq(CauldronToken(token2).totalSupply(), supply, "supply conserved");
        assertGt(registry.generationPositionId(2), 0, "gen2 active position minted");
        assertGt(registry.generationReservePositionId(2), 0, "gen2 reserve minted (bought)");
        assertLt(
            registry.reserveTickLower(2), registry.reserveTickUpper(2), "gen2 reserve band valid"
        );

        // 100% of supply is in the LP — the buy routed the reserve straight from the
        // active pool into the out-of-range position; nothing leaked to the registry.
        uint256 loose = CauldronToken(token2).balanceOf(address(registry));
        assertLt(loose, 1e18, "registry holds ~no loose gen2 tokens (all in LP)");

        // The candle is REAL: the newborn pool registered buy volume in block 0
        // (a silent seed would show zero) — this is the green candle.
        assertGt(hook.getVolume24h(registry.generationPoolId(2)), 0, "green-candle registered volume");

        // MIGRATION COVERAGE: the gen-1 holder migrates 1:1 out of the freshly
        // bought reserve — proof the candle bought ENOUGH supply for holders.
        CauldronToken(token1).approve(address(registry), circulating);
        uint256 got = registry.claimByBurn(1, circulating);
        assertApproxEqAbs(got, circulating, circulating / 1e6 + 1, "migrated 1:1 from candle reserve");
        assertEq(CauldronToken(token2).balanceOf(address(this)), got, "holder received gen2 1:1");
    }

    /// PROPOSER FLYWHEEL: a taxed swap streams a tiny slice of the ETH fee to the
    /// active proposer (whoever kicked the machine). Proves the carve pays out and
    /// is bounded (a fraction of the fee, not the swap).
    function test_ProposerIncentive_PaysProposer_OnFork() public {
        if (!active) return;

        registry.summon{value: 1 ether}();
        address proposer = address(0xC0FFEE);
        // Test owns the hook → can point the proposer slice directly.
        hook.setActiveProposer(proposer);
        assertEq(hook.activeProposer(), proposer, "proposer wired");

        // Roll past the launch surtax window so the fee is just the base tax
        // (predictable) and NOT the ~99% anti-sniper surtax (which routes 100% to
        // the guild, bypassing the proposer).
        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
        vm.warp(block.timestamp + 1);

        _buyGen1(0.2 ether); // address(this) is NOT tax-exempt → a real base fee

        // PULL pattern: the slice ACCRUES (no push in the swap path), then is claimed.
        uint256 owed = hook.proposerOwed(proposer);
        assertGt(owed, 0, "proposer accrued a slice of the fee");
        assertLt(owed, 0.2 ether / 100, "proposer slice is tiny (<1% of the swap)");

        uint256 before = proposer.balance;
        vm.prank(proposer);
        uint256 claimed = hook.claimProposerFees();
        assertEq(claimed, owed, "claimed the full accrual");
        assertEq(proposer.balance - before, owed, "proposer received the ETH");
        assertEq(hook.proposerOwed(proposer), 0, "balance zeroed after claim");
    }

    /// Relaunch records the winning author + repoints the hook's proposer slice at
    /// them, so each iteration's volume rewards ITS proposer.
    function test_Relaunch_RecordsProposer_OnFork() public {
        if (!active) return;

        MockGovernor gov = new MockGovernor();
        registry.setGovernor(address(gov));

        registry.summon{value: 1 ether}();
        // Genesis has no proposer (owner-summoned).
        assertEq(registry.generationProposer(1), address(0), "gen1 has no proposer");

        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        _buyGen1(0.25 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();

        // MockGovernor's winner.proposer == 0xBEEF → recorded + pushed to the hook.
        assertEq(registry.generationProposer(2), address(0xBEEF), "gen2 proposer recorded");
        assertEq(hook.activeProposer(), address(0xBEEF), "hook repointed to gen2 proposer");
    }

    /// EXIT GUARANTEE: while an emergency action is ARMED, the redemption pause is
    /// overridden — holders can always exit at floor before a custody move lands.
    /// A guardian veto re-closes it. (setUp uses emergencyAdmin = this, delay 0.)
    function test_ExitForcedOpenWhileArmed_AndGuardianVeto_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4);
        mifrens.mint(address(this), 1);
        mifrens.mint(address(this), 2);
        mifrens.mint(address(this), 3);
        registry.summon{value: 1 ether}();

        // Pause redemptions (fast circuit-breaker) → redeem is blocked.
        registry.setRedemptionPaused(true);
        vm.expectRevert();
        registry.redeemOgFren(1);

        // ARM an emergency action → the exit is FORCED OPEN despite the pause.
        registry.armEmergency();
        uint256 got = registry.redeemOgFren(1);
        assertGt(got, 0, "redeemed at floor while armed (pause overridden)");

        // GUARDIAN VETO cancels the armed action → pause bites again.
        registry.setGuardian(address(this));
        registry.vetoEmergency();
        assertEq(registry.emergencyReadyAt(), 0, "veto cleared the arm");
        vm.expectRevert();
        registry.redeemOgFren(2);

        // A non-guardian cannot veto.
        registry.armEmergency();
        registry.setGuardian(address(0xBEEF));
        vm.expectRevert();
        registry.vetoEmergency(); // this is no longer the guardian
    }

    /// V2 HANDOFF: migrateToSuccessor transfers the live position-NFTs' OWNERSHIP
    /// to the successor WITHOUT withdrawing liquidity — the pool price + position
    /// liquidity are byte-for-byte unchanged (no teardown, no candle). This is what
    /// makes a V2 controller a drop-in swap, not an emergency-withdraw + redeploy.
    function test_MigrateToSuccessor_MovesOwnership_NoTeardown_OnFork() public {
        if (!active) return;

        registry.summon{value: 1 ether}();
        PoolId pid = registry.generationPoolId(1);
        uint256 activeId = registry.generationPositionId(1);
        uint256 reserveId = registry.generationReservePositionId(1);
        address posm = address(registry.positionManager());

        // Snapshot price + liquidity BEFORE the handoff.
        (uint160 sqrtBefore, int24 tickBefore,,) = StateLibrary.getSlot0(pm, pid);
        uint128 activeLiqBefore = IPositionManagerOps(posm).getPositionLiquidity(activeId);
        uint128 reserveLiqBefore = IPositionManagerOps(posm).getPositionLiquidity(reserveId);
        assertEq(IERC721(posm).ownerOf(activeId), address(registry), "registry owns active pre");

        address succ = address(0xF00D);
        registry.setSuccessor(succ);
        registry.armEmergency();
        registry.migrateToSuccessor();

        // OWNERSHIP moved to the successor.
        assertEq(IERC721(posm).ownerOf(activeId), succ, "successor owns active");
        assertEq(IERC721(posm).ownerOf(reserveId), succ, "successor owns reserve");
        // LIQUIDITY + PRICE untouched — nothing was withdrawn, no teardown.
        (uint160 sqrtAfter, int24 tickAfter,,) = StateLibrary.getSlot0(pm, pid);
        assertEq(sqrtAfter, sqrtBefore, "price unchanged");
        assertEq(tickAfter, tickBefore, "tick unchanged");
        assertEq(IPositionManagerOps(posm).getPositionLiquidity(activeId), activeLiqBefore, "active liq intact");
        assertEq(IPositionManagerOps(posm).getPositionLiquidity(reserveId), reserveLiqBefore, "reserve liq intact");

        // Unset successor → migrate reverts (no accidental burn-to-zero).
        registry.setSuccessor(address(0));
        registry.armEmergency();
        vm.expectRevert();
        registry.migrateToSuccessor();
    }

    /// LEGACY FLOOR: a dead collection with an accrued floor (funded vault) is
    /// CRYSTALLIZED at relaunch into a token entitlement, the new reserve is sized
    /// to cover it ON TOP of migration + genesis, and — the solvency proof — a
    /// gen-1 holder still migrates 1:1 out of the freshly-bought reserve despite
    /// the extra legacy carve. Proves crystallize + reserve-sizing on live V4.
    function test_LegacyFloor_CrystallizeAndSolvency_OnFork() public {
        if (!active) return;

        MockGovernor gov = new MockGovernor();
        registry.setGovernor(address(gov));
        CollectionLedger ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));

        (address token1, ) = registry.summon{value: 1 ether}();

        // Fund gen-1's floor vault (simulate accrued swap fees) so its death
        // crystallizes a non-zero entitlement.
        address vault1 = registry.generationVault(1);
        assertTrue(vault1 != address(0), "gen1 vault deployed");
        (bool ok, ) = vault1.call{value: 0.1 ether}("");
        assertTrue(ok, "funded gen1 vault");

        // A trader takes real circulating supply (must migrate 1:1 later).
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        uint256 circulating = _buyGen1(0.25 ether);

        // Age → dead → rebirth.
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        (address token2, ) = registry.relaunch();

        // --- crystallize ran: gen-1 collection now holds a live entitlement ---
        assertTrue(ledger.crystallized(1), "gen1 collection crystallized at death");
        assertGt(ledger.totalEntitled(), 0, "legacy entitlement seeded from the funded vault");
        assertEq(CauldronToken(token2).totalSupply(), registry.TOTAL_SUPPLY(), "supply conserved");

        // --- SOLVENCY: the reserve was sized to cover migration + genesis + legacy,
        //     so the gen-1 holder still migrates 1:1 despite the legacy carve. ---
        CauldronToken(token1).approve(address(registry), circulating);
        uint256 got = registry.claimByBurn(1, circulating);
        assertApproxEqAbs(got, circulating, circulating / 1e6 + 1, "migrated 1:1 (reserve covers legacy too)");
    }

    /// LEGACY LIVE BUYBACK: with the buyback enabled, a REAL taxed swap feeds the
    /// buffer, and once it crosses the threshold the hook fires a nested self-buy
    /// (guarded, fee-free) that credits the live collection's pending entitlement —
    /// which then folds into its floor at death. Proves the in-hook buyback + the
    /// recursion guard on live V4 (the parent swap must NOT brick).
    function test_LegacyBuyback_FiresAndCredits_OnFork() public {
        if (!active) return;

        MockGovernor gov = new MockGovernor();
        registry.setGovernor(address(gov));
        CollectionLedger ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));

        registry.summon{value: 1 ether}();

        // Enable the buyback: 50% of the post-guild fee → buffer, tiny threshold so
        // one taxed buy triggers it.
        hook.setLegacyBuyback(address(registry), 5000, 1); // bps, 1 wei threshold
        hook.setOpener(address(this), true);

        // Roll past the anti-sniper window so a normal base fee applies (the surtax
        // routes 100% to genesis, bypassing the floor/buffer split).
        vm.roll(block.number + 40);

        // A REAL (non-exempt) buy → pays the base fee → feeds the buffer → the hook
        // fires its nested buyback in afterSwap. The parent buy must still succeed.
        uint256 got = _buyGen1(0.3 ether);
        assertGt(got, 0, "taxed buy succeeded (buyback did not brick the swap)");

        // P2: the buy HOLDS the bought tokens in the hook + DEFERS the credit — the
        // ledger is not yet credited (Invariant R: no credit without reserve backing).
        assertGt(hook.legacyOwedToReserve(), 0, "buyback tokens held, awaiting materialize");
        assertEq(ledger.entitledTokens(1), 0, "not credited until materialized");

        // Anyone materializes: sweep the hook's tokens INTO the reserve + credit the
        // ledger atomically → now it's redeemable AND solvently backed.
        uint256 addedReserve = registry.materializeLegacyReserve();
        assertGt(addedReserve, 0, "materialize deposited tokens into the reserve");
        assertGt(ledger.entitledTokens(1), 0, "credited once materialized (reserve-backed)");
        assertEq(hook.legacyOwedToReserve(), 0, "hold cleared after materialize");

        // At death, crystallize only FREEZES the supply + folds the final swept
        // sizing — it never reduces the already-credited live entitlement.
        (bool ok, ) = registry.generationVault(1).call{value: 0.02 ether}("");
        assertTrue(ok, "topped vault");
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        uint256 entitledBefore = ledger.entitledTokens(1);
        registry.relaunch();
        assertTrue(ledger.crystallized(1), "gen-1 crystallized");
        assertGe(ledger.entitledTokens(1), entitledBefore, "crystallize never reduces the entitlement");
    }

    /// @dev Minimal tax-exempt buy of gen-1 through the live PoolManager. Returns
    ///      the token amount received (now circulating outside the LP).
    function _buyGen1(uint256 ethIn) internal returns (uint256 got) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        bytes memory res = pm.unlock(abi.encode(key, ethIn));
        got = abi.decode(res, (uint256));
    }

    /// @dev Our own unlock body for `_buyGen1` (distinct from the registry's).
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        (PoolKey memory key, uint256 ethIn) = abi.decode(data, (PoolKey, uint256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            abi.encode(address(this))
        );
        uint256 ethOwed = uint256(uint128(-d.amount0()));
        uint256 got = uint256(uint128(d.amount1()));
        pm.settle{value: ethOwed}();
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }

    receive() external payable {}
}

/// Minimal governor: always has a winning proposal, so relaunch can proceed.
contract MockGovernor is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit",
            symbol: "SPIRIT",
            mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/",
            renderer: address(0),
            website: "spirit.xyz",
            socials: "x.com/spirit",
            quote: address(0),
            nftSupply: 1000,
            volumePerNFT: 0,
            proposer: address(0xBEEF)
        });
        id = 1;
    }
}

/// Minimal ERC-721 stand-in for genesis MiFrens — mirrors the recycle model:
/// registry-gated `custodyTransfer` (no burn) + an `everMoved` flag set on any
/// non-mint move (so paid re-enchant can be gated).
contract MockMiFrens {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => bool) public everMoved;
    address public registry;
    function setRegistry(address r) external { registry = r; }
    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        balanceOf[to] += 1;
    }
    /// @notice Mirrors MiFrensGenesis.custodyTransfer: registry-gated move, no
    ///         approval, marks the fren as moved (mint from==0 is not a move).
    function custodyTransfer(address from, address to, uint256 id) external {
        require(msg.sender == registry, "not registry");
        require(ownerOf[id] == from, "wrong from");
        balanceOf[from] -= 1;
        balanceOf[to] += 1;
        ownerOf[id] = to;
        everMoved[id] = true;
    }
}
