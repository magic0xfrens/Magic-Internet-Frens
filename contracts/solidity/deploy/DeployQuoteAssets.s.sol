// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {QuoteRotator} from "../cauldron/QuoteRotator.sol";
import {MockQuoteToken} from "../cauldron/MockQuoteToken.sol";

interface IRegistryQuoteAdmin {
    function setAllowedQuote(address quote, bool allowed) external;
    function allowedQuote(address quote) external view returns (bool);
    function owner() external view returns (address);
}

/**
 * @notice Deploys the QuoteRotator and the testnet quote assets the guild can
 *         rotate the LP into, then allowlists them.
 *
 *  The rotator was never part of DeployLaunchpad because it did not exist yet
 *  when that script was written. Without it `beginRotation` reverts
 *  NotConfigured, so this must run before any rotation UI means anything.
 *
 *  USDG and xNVDA here are MOCKS. There is no real tokenized-equity on Sepolia,
 *  and inventing an address would allowlist a contract nobody controls. These
 *  are mintable so a rotation can actually be executed end to end on testnet;
 *  on mainnet the same allowlist call names the real asset instead.
 */
contract DeployQuoteAssets is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registry = vm.envAddress("REGISTRY");
        address poolManager = vm.envAddress("POOL_MANAGER");

        vm.startBroadcast(pk);

        // 6 decimals like real USDC/USDG — the decimals trap the frontend's
        // formatQuote exists to handle.
        MockQuoteToken usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        // 18 decimals, mirroring how tokenized equities are usually issued.
        MockQuoteToken xnvda = new MockQuoteToken("Nvidia (synthetic)", "xNVDA", 18);

        QuoteRotator rotator = new QuoteRotator(registry, IPoolManager(poolManager));

        IRegistryQuoteAdmin reg = IRegistryQuoteAdmin(registry);
        address owner = reg.owner();
        if (owner == vm.addr(pk)) {
            reg.setAllowedQuote(address(usdg), true);
            reg.setAllowedQuote(address(xnvda), true);
            console2.log("allowlisted directly (deployer owns the registry)");
        } else {
            // Ownership is already with the timelock, so allowlisting has to go
            // through governance. Print the calls rather than failing.
            console2.log("REGISTRY OWNED BY TIMELOCK - queue these via the timelock:");
            console2.log("  setAllowedQuote(usdg,  true)");
            console2.log("  setAllowedQuote(xnvda, true)");
        }

        vm.stopBroadcast();

        console2.log("--- DEPLOYED ---");
        console2.log("USDG          :", address(usdg));
        console2.log("xNVDA         :", address(xnvda));
        console2.log("QuoteRotator  :", address(rotator));
        console2.log("registry owner:", owner);
    }
}
