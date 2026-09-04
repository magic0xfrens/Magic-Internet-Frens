// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";

/**
 * @title DeployCauldron
 * @notice Deploys the eternal Cauldron protocol and performs genesis (summon).
 *
 *  V4 hooks must live at an address whose low bits encode their permission
 *  flags, so the hook is CREATE2-deployed to a mined address via {HookMiner}.
 *
 *  Flow:
 *    1. Mine a hook address with the required permission flags.
 *    2. CREATE2-deploy CauldronHook to that address.
 *    3. Deploy CauldronRegistry(poolManager, positionManager, hook).
 *    4. hook.setRegistry(registry).
 *    5. registry.summon{value: GENESIS_ETH}()  — Gen 1 token + V4 pool.
 *
 *  Env:
 *    PRIVATE_KEY       deployer key (required)
 *    POOL_MANAGER      V4 PoolManager address (required, per chain)
 *    POSITION_MANAGER  V4 PositionManager address (required, per chain)
 *    NFT_CONTRACT      MagicFrensPeg / NFT address for tiered tax (optional, 0 ok)
 *    TREASURY          fee treasury (optional, defaults to deployer)
 *    DEATH_THRESHOLD   24h volume (wei of currency0) below which pool is "dead"
 *                      (optional, default 1 ether)
 *    GENESIS_ETH       ETH to seed Gen 1 liquidity (optional, default 0.1 ether)
 *
 *  Run (from contracts/solidity):
 *    forge script deploy/DeployCauldron.s.sol \
 *      --rpc-url $ETH_RPC --broadcast -vvv
 */
contract DeployCauldron is Script {
    // Canonical deterministic CREATE2 factory (same on every EVM chain).
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address nft = vm.envOr("NFT_CONTRACT", address(0));
        address treasury = vm.envOr("TREASURY", vm.addr(pk));
        uint256 deathThreshold = vm.envOr("DEATH_THRESHOLD", uint256(1 ether));
        uint256 genesisETH = vm.envOr("GENESIS_ETH", uint256(0.1 ether));

        // Permissions must match CauldronHook.getHookPermissions().
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Owner must be the deployer EOA — the hook is CREATE2-deployed via the
        // canonical factory during broadcast, so msg.sender in the constructor
        // would otherwise be the factory, locking us out of setRegistry().
        address owner = vm.addr(pk);

        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), deathThreshold, nft, treasury, owner);

        (address hookAddr, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(CauldronHook).creationCode,
            ctorArgs
        );
        console2.log("mined hook address:", hookAddr);

        vm.startBroadcast(pk);

        // CREATE2-deploy the hook to the mined address.
        CauldronHook hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager),
            deathThreshold,
            nft,
            treasury,
            owner
        );
        require(address(hook) == hookAddr, "hook address mismatch");
        console2.log("CauldronHook:", address(hook));

        CauldronRegistry registry = new CauldronRegistry(
            poolManager,
            positionManager,
            address(hook),
            address(0), // emergencyAdmin = deployer
            0 // emergencyDelay: instant
        );
        console2.log("CauldronRegistry:", address(registry));

        // Only the registry may pull relaunch ETH from the hook.
        hook.setRegistry(address(registry));

        // Genesis: deploy Gen 1 token, create the V4 pool, seed liquidity.
        (address token, ) = registry.summon{value: genesisETH}();
        console2.log("Gen 1 token:", token);

        vm.stopBroadcast();
    }
}
