// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";

/**
 * @dev The oracle against REAL Chainlink feeds.
 *
 *  The unit tests use a mock, which proves the refusal logic and nothing about
 *  whether the decimals maths survives contact with a live aggregator. Sepolia
 *  carries the same feed contracts as mainnet, so this is the real interface.
 */
contract QuoteOracleForkTest is Test {
    // Live Chainlink aggregators on Sepolia, verified on-chain.
    address constant ETH_USD  = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant USDC_USD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant NATIVE   = address(0);
    /// Stands in for a 6-decimal stable; only its decimals matter here.
    address constant USDC_LIKE = address(0xC0DE);

    bool active;
    QuoteOracle oracle;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        oracle = new QuoteOracle(address(this));
        // Generous heartbeats: testnet feeds update less often than mainnet, and
        // this test is about the maths, not about testnet liveness.
        oracle.setFeed(NATIVE, ETH_USD, 30 days, 18);
        oracle.setFeed(USDC_LIKE, USDC_USD, 30 days, 6);
    }

    /// A real ETH/USD feed must produce a sane dollar figure for 1 ETH.
    function test_RealEthFeedPricesOneEther_OnFork() public view {
        if (!active) return;
        uint256 factor = oracle.usdPerRawUnit(NATIVE);
        assertGt(factor, 0, "ETH must be priceable");

        uint256 usdForOneEth = (1e18 * factor) / 1e18;
        // Wide bounds on purpose: this asserts the SCALE is right, not the price.
        // A decimals error lands orders of magnitude outside, not inside.
        assertGt(usdForOneEth, 100e18, "1 ETH should be worth more than $100");
        assertLt(usdForOneEth, 100_000e18, "and less than $100,000");
    }

    /// THE PROPERTY THE WHOLE DESIGN RESTS ON: the same dollar amount of volume
    /// must read the same whether it happened in an 18-decimal or a 6-decimal
    /// pool. Quote-side these differ by 1e12.
    function test_EthAndStableAgreeOnDollars_OnFork() public view {
        if (!active) return;
        uint256 ethFactor = oracle.usdPerRawUnit(NATIVE);
        uint256 usdcFactor = oracle.usdPerRawUnit(USDC_LIKE);
        assertGt(usdcFactor, 0, "the stable must be priceable");

        // Dollars in 1 ETH, per the feed.
        uint256 ethUsd = (1e18 * ethFactor) / 1e18;
        // The same dollar figure expressed in 6-decimal stable units.
        uint256 stableRaw = (ethUsd / 1e18) * 1e6;
        uint256 stableUsd = (stableRaw * usdcFactor) / 1e18;

        assertApproxEqRel(stableUsd, ethUsd, 0.02e18, "one ETH and its value in a stable must agree");
    }

    /// A feed nobody configured must be unusable rather than zero-and-trusted.
    function test_UnconfiguredIsUnusable_OnFork() public view {
        if (!active) return;
        assertEq(oracle.usdPerRawUnit(address(0xBEEF)), 0, "no feed -> cannot judge");
    }

    /// What a real read costs, since it lands on the swap hot path.
    function test_ReadGas_OnFork() public view {
        if (!active) return;
        uint256 g = gasleft();
        oracle.usdPerRawUnit(NATIVE);
        console_gas(g - gasleft());
    }

    function console_gas(uint256 used) internal pure {
        require(used < 200_000, "an oracle read on every swap must stay cheap");
    }
}
