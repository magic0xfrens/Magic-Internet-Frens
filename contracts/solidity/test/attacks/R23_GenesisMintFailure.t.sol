// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";
import {YBase, YGov} from "./YBase.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

contract R23MintValidator {
    function validateTransfer(address, address, address, uint256) external pure {
        revert("mint rejected by policy");
    }
}
contract R23GenesisMintFailure is YBase {
    MiFrensGenesis internal genesis;
    function setUp() public {
        address poolManager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        posm = deployCode("out/PositionManager.sol/PositionManager.json",
            abi.encode(poolManager, permit, uint256(100_000), address(0), address(0)));
        pm = IPoolManager(poolManager);
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));
        registry.setGovernor(address(new YGov()));


        vm.deal(address(this), 1000 ether);
        genesis = new MiFrensGenesis("Frens", "FREN", 1, 100, 20 ether, 1, "ipfs://test/");
        genesis.setRegistry(address(registry));
        registry.setGenesisBonus(address(genesis), 2000, 1);
        registry.setIgniter(address(genesis));
        genesis.mint{value: 20 ether}(uint256(1));
        token = genesis.igniteCauldron();
        _warp(25 hours);
        registry.relaunch();
        token = registry.currentToken();
        assertEq(registry.currentGeneration(), 2);
        assertEq(hook.collection(), address(genesis));
        assertEq(genesis.minter(), address(hook));
        hook.setNftCurve(0.01 ether, 0);
        hook.setMaxOdds(0);
        hook.setOddsParams(1 ether, 1);
        vm.roll(vm.getBlockNumber() + 40);
    }
    function _resolveOne() internal returns (uint256 won) {
        uint256 b = vm.getBlockNumber();
        vm.roll(b + 1);
        vm.setBlockhash(b, bytes32(uint256(123)));
        (uint256 processed, uint256 wins) = hook.resolveTickets(1);
        assertEq(processed, 1);
        return wins;
    }
    function test_rejectedGenesisMintPreservesPaidPity() public {
        address player = tx.origin;
        _buy(0.009 ether, player);
        assertEq(hook.pendingOf(player), 1);
        assertEq(_resolveOne(), 0);
        assertEq(hook.missStreak(player), 1, "pity earned from paid losing ticket");
        _buy(0.006 ether, player);
        assertEq(hook.pendingOf(player), 1);
        // Actual deployer calls an available production setter; no role prank.
        genesis.setTransferValidator(address(new R23MintValidator()));
        uint256 mintedBefore = genesis.totalMinted();
        uint256 openedBefore = hook.opened(player);
        assertEq(_resolveOne(), 0);
        assertEq(genesis.totalMinted(), mintedBefore, "rejected mint delivered no art");
        assertEq(hook.pendingOf(player), 0, "failed ticket cannot wedge queue");
        assertEq(hook.missStreak(player), 1, "undelivered win cannot erase earned pity");
        assertEq(hook.opened(player), openedBefore, "undelivered win cannot count as opened art");
    }
}
