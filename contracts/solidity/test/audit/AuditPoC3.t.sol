// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/// A trader contract that refuses ETH. Perfectly legal on-chain behaviour.
contract RejectEthTrader {
    PerpEngine public perp;
    constructor(PerpEngine p) payable { perp = p; }
    function open(uint8 lev) external payable returns (uint256) {
        return perp.openLong{value: msg.value}(lev, 0, 0, msg.value);
    }
    receive() external payable { revert("no eth"); }
}

contract MockGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://s/", renderer: address(0), website: "", socials: "",
            nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}

contract NoFrens2 {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 11 / REGRESSION — PerpEngine._settle used to pay the trader with a REVERTING
//          `_sendEth`, so a trader contract that rejects ETH made its own position
//          permanently unsettleable. That cascaded: `forceCloseAllDead` reverted
//          wholesale, `openCount` never reached 0, and `syncGeneration` reverted
//          `PositionsOpen` forever — stranding the engine (and the entire short
//          inventory) on a DEAD token.                            (audit H-04)
//          FIXED: settlement payouts to attacker-controlled recipients use a PULL
//          pattern — a failed push is credited to `payoutOwed` and claimed later
//          via `claimPayout()`, so nothing can block a settlement.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_PerpGriefStuckEngine is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook hook;
    CauldronRegistry registry;
    PerpEngine perp;
    IPoolManager pm;
    address token;
    bool active;

    address dividend = address(0xD1D1);
    address treasury = address(0x7E7E);

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970341;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(poolManager), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 200 ether);
        (token,) = registry.summon{value: 2 ether}();

        perp = new PerpEngine(
            IPoolManager(poolManager), address(hook), address(registry),
            address(new NoFrens2()), dividend, treasury, address(this)
        );
        perp.fundPlv{value: 5 ether}(5 ether);
        uint256 seed = 50_000_000 ether;
        deal(token, address(this), seed);
        IERC20Minimal(token).approve(address(perp), seed);
        perp.fundPlvToken(seed);

        hook.setDeathThreshold(0);
        hook.setPerpEngine(address(perp));
        registry.setGovernor(address(new MockGov()));

        vm.warp(vm.getBlockTimestamp() + 25 hours);
        vm.roll(block.number + 40);
        perp.poke();
    }

    function test_Fixed_RejectingTraderCannotFreezeTheEngine() public {
        if (!active) return;

        RejectEthTrader griefer = new RejectEthTrader(perp);
        vm.deal(address(griefer), 1 ether);
        uint256 id = griefer.open{value: 0.05 ether}(2);
        assertEq(perp.openCount(), 1, "grief position open");

        // A normal trader also opens (so we can show they are NOT the problem).
        uint256 healthyId = perp.openLong{value: 0.05 ether}(2, 0, 0, 0.05 ether);
        assertEq(perp.openCount(), 2, "two positions open");

        // Kill the generation.
        hook.setDeathThreshold(1 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen-1 dead");

        // The honest position closes fine.
        perp.forceCloseDead(healthyId);

        // FIXED: the griefer's position settles too — the push fails, the payout is
        // CREDITED instead of reverting.
        perp.forceCloseDead(id);
        assertEq(perp.openCount(), 0, "FIXED: the hostile position settled");
        uint256 owed = perp.payoutOwed(address(griefer));
        console2.log("credited to the rejecting trader:", owed);
        assertGt(owed, 0, "FIXED: their equity is owed, not lost");

        // Their funds are fully recoverable once they can accept ETH.
        vm.prank(address(griefer));
        vm.expectRevert(); // still rejects -> the inner send fails, nothing is lost
        perp.claimPayout();

        // Relaunch + re-arm now work, which is the whole point.
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "gen 2 born");
        assertEq(perp.syncedGeneration(), 2, "FIXED: engine re-armed on the new generation");
        assertEq(perp.syncedToken(), registry.currentToken(), "FIXED: token side follows the live gen");
        console2.log("engine syncedToken   :", perp.syncedToken());
        console2.log("registry currentToken:", registry.currentToken());
    }

    /// The batch path the registry drives at relaunch must also survive a hostile
    /// trader: `forceCloseAllDead` closes EVERY position, hostile ones included.
    function test_Fixed_ForceCloseAllDeadSurvivesHostileTrader() public {
        if (!active) return;

        RejectEthTrader griefer = new RejectEthTrader(perp);
        vm.deal(address(griefer), 1 ether);
        griefer.open{value: 0.05 ether}(2);
        perp.openLong{value: 0.05 ether}(2, 0, 0, 0.05 ether);
        assertEq(perp.openCount(), 2, "two positions open");

        hook.setDeathThreshold(1 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)

        perp.forceCloseAllDead();
        assertEq(perp.openCount(), 0, "FIXED: the whole book cleared");
        assertGt(perp.payoutOwed(address(griefer)), 0, "hostile trader's equity is claimable");
    }

    function unlockCallback(bytes calldata) external pure returns (bytes memory) { return ""; }
    receive() external payable {}
}
