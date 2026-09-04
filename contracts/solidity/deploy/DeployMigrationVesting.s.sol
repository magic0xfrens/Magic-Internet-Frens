// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MigrationVesting} from "../cauldron/MigrationVesting.sol";
import {PerpStakerOracle} from "../cauldron/PerpStakerOracle.sol";

interface IRegistryGate {
    function emergencyAdmin() external view returns (address);
    function emergencyDelay() external view returns (uint256);
    function claimGate() external view returns (address);
    function setClaimGate(address gate) external;
}
interface IHookPerp { function perpEngine() external view returns (address); }
interface IEngineVault { function vault() external view returns (address); }

/**
 * @title DeployMigrationVesting
 * @notice Deploy the anti-dump migration vesting escrow + its instant-tier oracle,
 *         then ENFORCE it by routing the registry's 1:1 migration through the gate
 *         so the instant claim can't be skipped.
 *
 *  Deploys + wires:
 *    1. PerpStakerOracle(perpVault)         — instant tier = live perp PLV stakers
 *    2. MigrationVesting(registry, owner, vestWindow, oracle)
 *    3. registry.setClaimGate(vesting)      — ENFORCE (closes the instant direct
 *                                             path; perp engine stays exempt). Only
 *                                             the registry's emergencyAdmin can do
 *                                             this — done inline iff the broadcaster
 *                                             IS that admin, else the exact call is
 *                                             logged for the governance timelock.
 *
 *  The vesting contract's OWNER (tunes vestWindow within [1h,14d] + swaps the
 *  oracle) should be the governance timelock in production.
 *
 *  Env:
 *    PRIVATE_KEY   deployer (required)
 *    REGISTRY      CauldronRegistry (required)
 *    PERP_VAULT    PerpVault for the instant tier. Optional — if unset, derived
 *                  from HOOK: hook.perpEngine().vault().
 *    HOOK          CauldronHook (required only when PERP_VAULT is unset)
 *    VEST_WINDOW   linear vest seconds for non-stakers (default 259200 = 72h;
 *                  must be within MigrationVesting's [1h, 14d] bounds)
 *    VEST_OWNER    governance owner of the escrow (default: TIMELOCK, else deployer)
 *    TIMELOCK      governance timelock (used as VEST_OWNER default)
 *    ENFORCE       "true" to call setClaimGate now (default true). If the broadcaster
 *                  is not the emergencyAdmin, the call is logged instead of sent.
 *
 *  Run (from contracts/solidity):
 *    FOUNDRY_PROFILE=cauldron forge script deploy/DeployMigrationVesting.s.sol \
 *      --rpc-url $SEPOLIA_RPC --broadcast -vvv
 */
contract DeployMigrationVesting is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address registry = vm.envAddress("REGISTRY");
        uint64 window = uint64(vm.envOr("VEST_WINDOW", uint256(72 hours)));
        address timelock = vm.envOr("TIMELOCK", address(0));
        address owner = vm.envOr("VEST_OWNER", timelock == address(0) ? deployer : timelock);
        bool enforce = vm.envOr("ENFORCE", true);

        // Resolve the PerpVault for the instant tier: explicit env, else derive it
        // off the hook (hook.perpEngine().vault()).
        address perpVault = vm.envOr("PERP_VAULT", address(0));
        if (perpVault == address(0)) {
            address hook = vm.envAddress("HOOK");
            address engine = IHookPerp(hook).perpEngine();
            require(engine != address(0), "no perp engine on hook; set PERP_VAULT");
            perpVault = IEngineVault(engine).vault();
            require(perpVault != address(0), "engine has no vault; set PERP_VAULT");
        }

        vm.startBroadcast(pk);

        PerpStakerOracle oracle = new PerpStakerOracle(perpVault);
        console2.log("PerpStakerOracle :", address(oracle));

        MigrationVesting vesting = new MigrationVesting(registry, owner, window, address(oracle));
        console2.log("MigrationVesting :", address(vesting));
        console2.log("  owner          :", owner);
        console2.log("  vestWindow (s) :", window);
        console2.log("  instant tier   : perp PLV stakers via", perpVault);

        // ENFORCE — route the registry's instant 1:1 migration through the escrow so
        // holders CAN'T skip the drip. onlyEmergency: done inline iff the broadcaster
        // is that admin; otherwise the exact governance call is printed.
        if (enforce) {
            address admin = IRegistryGate(registry).emergencyAdmin();
            if (admin == deployer) {
                IRegistryGate(registry).setClaimGate(address(vesting));
                console2.log("ENFORCED: registry.claimGate ->", address(vesting));
            } else {
                console2.log("!! NOT ENFORCED - broadcaster is not emergencyAdmin.");
                console2.log("   emergencyAdmin :", admin);
                console2.log("   GOVERNANCE MUST CALL registry.setClaimGate with:", address(vesting));
                console2.log("   (delay is irrelevant - setClaimGate is onlyEmergency, not timelocked)");
            }
        } else {
            console2.log("ENFORCE=false - deployed but NOT gated (instant migration still open).");
            console2.log("   To enforce later, registry.setClaimGate with:", address(vesting));
        }

        vm.stopBroadcast();

        console2.log("--- VESTING WIRED ---");
        console2.log("registry.claimGate now:", IRegistryGate(registry).claimGate());
        console2.log("(should equal MigrationVesting above once enforced)");
    }
}
