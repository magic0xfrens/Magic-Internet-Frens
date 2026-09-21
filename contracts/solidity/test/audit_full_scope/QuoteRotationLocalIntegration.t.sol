// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/// Production V4 pool and rotator; this fixture implements only registry
/// allowlisting/forwarding and the liquidity provider's settlement callback.
contract QuoteRotationLocalIntegrationTest is Test {
    IPoolManager internal pm;
    QuoteRotator internal rotator;
    QuoteOracle internal oracle;
    MockQuoteToken internal quote;
    PoolKey internal route;

    function allowedQuote(address q) external view returns (bool) { return q == address(quote); }

    function setUp() public {
        pm = IPoolManager(address(new PoolManager(address(this))));
        quote = new MockQuoteToken("Quote", "Q", 18);
        route = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(quote)), 3000, 60, IHooks(address(0)));
        pm.initialize(route, uint160(1 << 96));
        vm.deal(address(this), 100 ether);
        quote.mint(address(this), 100 ether);
        pm.unlock("");
        rotator = new QuoteRotator(address(this), pm);
        rotator.setVenue(route, true);
        oracle = new QuoteOracle(address(this));
        oracle.setPegged(address(0), 18);
        oracle.setPegged(address(quote), 18);
        vm.deal(address(rotator), 10 ether);
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(pm));
        (BalanceDelta d,) = pm.modifyLiquidity(
            route, ModifyLiquidityParams(-887220, 887220, int256(10 ether), bytes32(0)), ""
        );
        pm.settle{value: uint256(uint128(-d.amount0()))}();
        pm.sync(route.currency1);
        quote.transfer(address(pm), uint256(uint128(-d.amount1())));
        pm.settle();
        return "";
    }

    function test_controlFreshOracleAcceptsSmallTradeAndConservesInput() public {
        rotator.setArbParams(address(oracle), 1000, 5e18);
        uint256 nativeBefore = address(rotator).balance;
        uint256 out = rotator.swapOnce(route, address(0), address(quote), 0.01 ether, 1);
        assertGt(out, 0.0097 ether);
        assertEq(nativeBefore - address(rotator).balance, 0.01 ether);
        assertEq(quote.balanceOf(address(rotator)), out);
    }

    function test_controlFreshOracleRejectsLargePriceImpact() public {
        rotator.setArbParams(address(oracle), 1000, 5e18);
        vm.expectRevert(QuoteRotator.SlippageTooHigh.selector);
        rotator.swapOnce(route, address(0), address(quote), 5 ether, 1);
        assertEq(address(rotator).balance, 10 ether, "revert restores treasury funds");
    }

    function test_unsetOracleMustNotRemovePermissionlessPriceFloor() public {
        vm.expectRevert(QuoteRotator.NotPriceable.selector);
        rotator.swapOnce(route, address(0), address(quote), 5 ether, 1);
        assertEq(address(rotator).balance, 10 ether);
    }

    function test_strangerCannotCallSettlementCallback() public {
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rotator.unlockCallback("");
    }
}
