// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {LaunchSniper} from "../cauldron/LaunchSniper.sol";

interface IHookExempt {
    function setTaxExempt(address who, bool exempt) external;
    function isOpener(address who) external view returns (bool);
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
        //  PRECONDITION, MADE EXPLICIT (blind red-team X5e, hygiene). The sniper's
        //  fee exemption is NOT granted by `setTaxExempt` alone: the hook's gate is
        //  `taxExempt[_taxedPlayer(sender, hookData)] && isOpener[sender]`
        //  (CauldronHook.sol:2384), where `sender` is the GACHA ROUTER. So this
        //  script silently assumed `DeployLaunchpad.s.sol:241`
        //  (`hook.setOpener(address(gacha), true)`) had already run. It always has
        //  in the shipped order — but nothing asserted it, and out of order the
        //  sniper would be flagged exempt and still pay the ~99% launch surtax with
        //  no error anywhere. Assert it instead of assuming it.
        address gacha = vm.envAddress("GACHA");
        require(
            IHookExempt(hook).isOpener(gacha),
            "run DeployLaunchpad first: hook.setOpener(gacha,true) is a precondition of the sniper's tax exemption"
        );

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
