// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../MagicFrensPresale.sol";

/**
 * @title DeployPresale
 * @notice Deploy MagicFrensPresale contract
 *
 * Usage:
 * - Ethereum:  forge script DeployPresale --rpc-url $ETH_RPC --broadcast --verify
 * - Base:      forge script DeployPresale --rpc-url $BASE_RPC --broadcast --verify
 * - BNB:       forge script DeployPresale --rpc-url $BNB_RPC --broadcast --verify
 */
contract DeployPresale is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy presale contract
        MagicFrensPresale presale = new MagicFrensPresale(treasury);

        vm.stopBroadcast();

        console.log("=== MagicFrensPresale Deployment ===");
        console.log("Presale Contract:", address(presale));
        console.log("Treasury:", treasury);
        console.log("Presale Price:", presale.PRESALE_PRICE());
        console.log("Max Tokens:", presale.MAX_PRESALE_TOKENS());
        console.log("Min Contribution:", presale.MIN_CONTRIBUTION());
        console.log("Max Per Address:", presale.MAX_CONTRIBUTION_PER_ADDRESS());
    }
}
