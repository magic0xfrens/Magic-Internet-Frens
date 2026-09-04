// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";

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
    bool active;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return; // no fork configured -> skip
        active = true;

        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");

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
        hook.setRegistry(address(registry));
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

    /// Genesis claim releases the gift from the out-of-range RESERVE position:
    /// pure token to the OG, zero ETH, and the registry never held it loose.
    function test_GenesisClaim_FromReserve_OnFork() public {
        if (!active) return;

        // Wire a genesis bonus (10% of supply over 4 shares) via a mock MiFrens.
        MockMiFrens mifrens = new MockMiFrens();
        registry.setGenesisBonus(address(mifrens), 1000, 4); // 10%, 4 shares
        mifrens.mint(address(this), 1); // own genesis id #1

        (address token, ) = registry.summon{value: 1 ether}();

        uint256 before = CauldronToken(token).balanceOf(address(this));
        uint256 got = registry.claimGenesis(1);
        uint256 delta = CauldronToken(token).balanceOf(address(this)) - before;

        assertGt(got, 0, "claimed a nonzero bonus");
        assertEq(delta, got, "received exactly the claimed token, from the reserve LP");
        assertEq(registry.genesisClaimed(1), true, "marked claimed");
    }

    /// Batch claim: a holder of several frens claims ALL in ONE reserve removal,
    /// receiving the combined bonus and marking every id claimed.
    function test_ClaimGenesisMany_OneRemoval_OnFork() public {
        if (!active) return;

        MockMiFrens mifrens = new MockMiFrens();
        registry.setGenesisBonus(address(mifrens), 1000, 8); // 10% over 8 shares
        mifrens.mint(address(this), 1);
        mifrens.mint(address(this), 2);
        mifrens.mint(address(this), 3); // own ids 1,2,3

        (address token, ) = registry.summon{value: 1 ether}();
        uint256 perFren = registry.genesisSharePerFren();

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1; ids[1] = 2; ids[2] = 3;

        uint256 before = CauldronToken(token).balanceOf(address(this));
        uint256 total = registry.claimGenesisMany(ids);
        uint256 delta = CauldronToken(token).balanceOf(address(this)) - before;

        assertApproxEqRel(total, perFren * 3, 1e12, "combined 3x bonus in one call");
        assertEq(delta, total, "received the combined token in one removal");
        assertTrue(registry.genesisClaimed(1) && registry.genesisClaimed(2) && registry.genesisClaimed(3), "all 3 marked");

        // Re-claiming the same ids is idempotent (all skipped → reverts AlreadyClaimed).
        vm.expectRevert();
        registry.claimGenesisMany(ids);
    }

    // NOTE: the seed-sqrtPrice overflow guard (FullMath.mulDiv over 512-bit
    // intermediate space) now lives in PoolOps._sqrtPrice and is exercised by the
    // fork integration path below. The old direct-call unit test was removed with
    // the registry's computeSqrtPriceX96 helper (moved into PoolOps).

    // Creature cycle is pure — runs with or without a fork.
    function test_CreatureCycle() public {
        CauldronRegistry r = new CauldronRegistry(address(1), address(2), address(3), address(0), 0);
        (, string memory s1) = r.getCreatureForGeneration(1);
        (, string memory s7) = r.getCreatureForGeneration(7);
        assertEq(s1, "GNOME");
        assertEq(s7, "GNOME", "cycles every 6 generations");
    }

    receive() external payable {}
}

/// Minimal ERC-721 stand-in for genesis MiFrens (only what claimGenesis reads).
contract MockMiFrens {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        balanceOf[to] += 1;
    }
}
