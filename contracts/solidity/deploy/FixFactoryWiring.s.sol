// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";

interface IRegistryFactoryAdmin {
    function setFactory(address f) external;
    function owner() external view returns (address);
}

interface ITimelock {
    function schedule(address target, uint256 value, bytes calldata data, bytes32 pred, bytes32 salt, uint256 delay) external;
    function execute(address target, uint256 value, bytes calldata data, bytes32 pred, bytes32 salt) external payable;
    function getMinDelay() external view returns (uint256);
}

/**
 * @notice Replaces a live deployment's factory with one that can actually wire
 *         the badge renderer.
 *
 *  WHY A NEW FACTORY AND NOT A SETTER. The bug was in CauldronCollection's
 *  access guard, and the factory embeds that contract's creation code — so the
 *  fix only reaches new collections once the factory itself is redeployed.
 *  Nothing else needs replacing: no state lives on the factory beyond the
 *  renderer pointer, and collections it already deployed are unaffected.
 *
 *  Safe to run before a summon. Afterwards the live generation's collection
 *  would keep the old code, which still works — it just cannot be repointed at
 *  an on-chain renderer by the factory.
 */
contract FixFactoryWiring is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registry = vm.envAddress("REGISTRY");
        address timelock = vm.envAddress("TIMELOCK");
        bytes32 Z = bytes32(0);
        bool execute = vm.envOr("EXECUTE", false);

        vm.startBroadcast(pk);

        //  THE EXECUTE RUN MUST REUSE THE SCHEDULED FACTORY (FS-deployfactory-01).
        //  The timelock's operation id hashes the calldata, which embeds the new
        //  factory's address. Deploying a fresh factory on the EXECUTE run encoded a
        //  different address, so `execute` looked up an operation that was never
        //  scheduled and reverted. The schedule run deploys and prints FACTORY; the
        //  execute run takes it back from the environment and deploys nothing.
        address factory;
        if (execute) {
            factory = vm.envAddress("FACTORY");
        } else {
            CauldronFactory f = new CauldronFactory();
            f.setLiquidatorRenderer(vm.envAddress("BADGE_RENDERER"));
            factory = address(f);
        }

        bytes memory data = abi.encodeCall(IRegistryFactoryAdmin.setFactory, (factory));
        uint256 delay = ITimelock(timelock).getMinDelay();

        // The registry is timelock-owned, so repointing it is a governance
        // action even when the deployer holds both roles.
        if (execute) {
            ITimelock(timelock).execute(registry, 0, data, Z, Z);
            console2.log("factory repointed (timelock executed):", factory);
        } else {
            ITimelock(timelock).schedule(registry, 0, data, Z, Z, delay);
            console2.log("scheduled; after this many seconds re-run with EXECUTE=true FACTORY=<below>:", delay);
        }

        vm.stopBroadcast();
        console2.log("FACTORY         :", factory);
    }
}
