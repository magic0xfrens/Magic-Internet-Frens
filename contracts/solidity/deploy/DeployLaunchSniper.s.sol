// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {LaunchSniper} from "../cauldron/LaunchSniper.sol";

interface IHookExempt {
    function setTaxExempt(address who, bool exempt) external;
}

interface IPresaleFinalizer {
    function setFinalizer(address who) external;
}

/**
 * Deploy the LaunchSniper for an atomic, MEV-proof iteration-1 launch + buy, and
 * flag it fee-exempt on the hook. Run BEFORE selling out the presale.
 *
 *   HOOK   the deployed CauldronHook
 *   Then, once the presale is sold out, call:
 *     sniper.launch{value: fundingETH}(presale, registry, gacha, airdropWallet,
 *                                      minGnomeOut, openMax)
 *   ideally via a PRIVATE mempool (Flashbots Protect / MEVblocker) so the launch
 *   tx is never publicly visible → zero front-run.
 */
contract DeployLaunchSniper is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address hook = vm.envAddress("HOOK");
        address presale = vm.envAddress("PRESALE");

        vm.startBroadcast(pk);
        LaunchSniper sniper = new LaunchSniper(deployer);
        // The hook owner (deployer, pre-ownership-handoff) flags the sniper exempt
        // so its launch buy pays zero tax/surtax.
        IHookExempt(hook).setTaxExempt(address(sniper), true);
        // Gate genesis ignition to the sniper → only IT can finalize, so no bot
        // can front-run the summon and break the atomic launch+buy.
        IPresaleFinalizer(presale).setFinalizer(address(sniper));
        vm.stopBroadcast();

        console2.log("LaunchSniper   :", address(sniper));
        console2.log("  fee-exempt + set as presale finalizer");
        console2.log("  sell out the presale, then call sniper.launch{value:...}()");
    }
}
