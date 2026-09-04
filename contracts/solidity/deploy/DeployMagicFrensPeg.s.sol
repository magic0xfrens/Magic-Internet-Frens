// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../MagicFrensPeg.sol";

/**
 * @title DeployMagicFrensPeg
 * @notice Deployment script for MagicFrensPeg across Ethereum, Base, and BNB
 *
 * Usage:
 * - Ethereum:  forge script DeployMagicFrensPeg --rpc-url $ETH_RPC --broadcast --verify
 * - Base:      forge script DeployMagicFrensPeg --rpc-url $BASE_RPC --broadcast --verify
 * - BNB:       forge script DeployMagicFrensPeg --rpc-url $BNB_RPC --broadcast --verify
 *
 * After deployment:
 * 1. Link presale contract: cast send PRESALE_ADDR "setTokenAddress(address)" TOKEN_ADDR
 * 2. Transfer tokens to presale: cast send TOKEN_ADDR "transfer(address,uint256)" PRESALE_ADDR AMOUNT
 * 3. End presale: cast send PRESALE_ADDR "endPresale()"
 */
contract DeployMagicFrensPeg is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        MagicFrensPeg magicFrensPeg = new MagicFrensPeg(treasury);

        vm.stopBroadcast();

        console.log("=== MagicFrensPeg Deployment ===");
        console.log("Token Contract:", address(magicFrensPeg));
        console.log("Treasury:", treasury);
        console.log("Token Name:", magicFrensPeg.name());
        console.log("Token Symbol:", magicFrensPeg.symbol());
        console.log("Max Supply:", magicFrensPeg.MAX_SUPPLY());
        console.log("Commit Fee:", magicFrensPeg.COMMIT_FEE());
        console.log("Unit Per Fren:", magicFrensPeg.UNIT_PER_FREN());
        console.log("");
        console.log("Next Steps:");
        console.log("1. Link to presale: cast send YOUR_PRESALE_ADDRESS \"setTokenAddress(address)\" ", address(magicFrensPeg));
        console.log("2. Mint tokens to presale after it ends for claims");
    }
}
