// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {QuoteRotator} from "../cauldron/QuoteRotator.sol";

/// @dev A registry stub exposing only the allowlist the rotator consults.
contract RegistryStub {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @dev The guild converting a MEASURED amount of one quote into another.
 *
 *  The design point these tests protect: a rotation is a FLOW ("convert 30% of
 *  our ETH"), not a target allocation ("hold 40% USDG"). A flow is a fraction of
 *  one asset measured against itself, so nothing is compared across assets and
 *  no price oracle is needed. An earlier version compared raw balances across
 *  assets, which is meaningless when ETH has 18 decimals and USDC has 6.
 */
contract QuoteRotatorTest is Test {
    QuoteRotator rot;
    RegistryStub reg;

    address constant USDG = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant STRANGER = address(0xBAD);
    address constant NATIVE = address(0);

    // 1 ETH -> at least 2,000 USDG, scaled 1e18.
    uint256 constant MIN_RATE = 2000e18;

    function setUp() public {
        reg = new RegistryStub();
        reg.set(USDG, true);
        rot = new QuoteRotator(address(reg), IPoolManager(address(0xdead)));
    }

    function _plan() internal {
        rot.setPlan(NATIVE, USDG, 30 ether, 3 ether, MIN_RATE, 1 hours);
    }

    // ---------------------------------------------------------------------
    // A plan is a flow, in each asset's own units
    // ---------------------------------------------------------------------

    function test_PlanIsDenominatedInTheSoldAssetAlone() public {
        _plan();
        (address from, address to, uint128 totalIn, uint128 sliceIn,,, uint256 minRate,,) = rot.plan();

        assertEq(from, NATIVE, "selling ETH");
        assertEq(to, USDG, "buying USDG");
        assertEq(totalIn, 30 ether, "a fraction of ONE asset, not a cross-asset ratio");
        assertEq(sliceIn, 3 ether, "ten slices");
        assertEq(minRate, MIN_RATE, "the price floor is governed, not read from a pool");
    }

    /// Nothing is due before the plan's interval elapses, and nothing at all is
    /// due while the contract holds none of the asset it is meant to sell.
    function test_NothingIsDueWithoutFunds() public {
        _plan();
        assertEq(rot.nextSliceSize(), 0, "no ETH held, so no slice is possible");
    }

    function test_SliceIsCappedByHoldings() public {
        _plan();
        vm.deal(address(rot), 1 ether); // less than one 3 ETH slice
        assertEq(rot.nextSliceSize(), 1 ether, "never sells more than it holds");
    }

    function test_SliceIsCappedByWhatRemains() public {
        rot.setPlan(NATIVE, USDG, 4 ether, 3 ether, MIN_RATE, 1 hours);
        vm.deal(address(rot), 100 ether);
        assertEq(rot.nextSliceSize(), 3 ether, "first slice is a full slice");
    }

    // ---------------------------------------------------------------------
    // The price floor is the whole protection, so it cannot be waived
    // ---------------------------------------------------------------------

    /// A zero floor accepts ANY fill, including a fully manipulated one. This is
    /// the single most dangerous value in the contract, so it is refused.
    function test_ZeroMinRateIsRefused() public {
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setPlan(NATIVE, USDG, 30 ether, 3 ether, 0, 1 hours);
    }

    /// The floor must come from governance rather than from the pool at
    /// execution time. Reading spot at execution is exactly the manipulation the
    /// bound exists to stop, and an earlier version did precisely that.
    function test_MinRateIsStoredNotDerived() public {
        _plan();
        (,,,,,, uint256 minRate,,) = rot.plan();
        assertEq(minRate, MIN_RATE, "stored verbatim from the vote");
    }

    // ---------------------------------------------------------------------
    // What a plan may never be
    // ---------------------------------------------------------------------

    function test_CannotBuyAnUnvettedQuote() public {
        vm.expectRevert(QuoteRotator.NotAllowedQuote.selector);
        rot.setPlan(NATIVE, address(0xDEAD), 30 ether, 3 ether, MIN_RATE, 1 hours);
    }

    function test_CannotRotateAnAssetIntoItself() public {
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setPlan(USDG, USDG, 30 ether, 3 ether, MIN_RATE, 1 hours);
    }

    function test_SliceCannotExceedTheTotal() public {
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setPlan(NATIVE, USDG, 3 ether, 30 ether, MIN_RATE, 1 hours);
    }

    function test_StrangerCannotSetOrCancelAPlan() public {
        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.setPlan(NATIVE, USDG, 30 ether, 3 ether, MIN_RATE, 1 hours);

        _plan();
        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.cancelPlan();
    }

    /// The guild must be able to abandon a rotation when the market moves
    /// against the thesis it was voted on, keeping whatever already converted.
    function test_PlanCanBeCancelled() public {
        _plan();
        rot.cancelPlan();
        (, , uint128 totalIn,,,,,,) = rot.plan();
        assertEq(totalIn, 0, "plan cleared");
        assertEq(rot.nextSliceSize(), 0, "and nothing more executes");
    }

    function test_StepWithoutAPlanReverts() public {
        vm.deal(address(rot), 10 ether);
        // A route is irrelevant here; there is simply nothing scheduled.
        vm.expectRevert(QuoteRotator.NoPlan.selector);
        rot.rotateStep(_dummyRoute());
    }

    // ---------------------------------------------------------------------
    // Custody
    // ---------------------------------------------------------------------

    /// Converted assets must be able to LEAVE, to be re-deployed as liquidity in
    /// the new pair. An earlier version could convert and then only ever hold.
    function test_ConvertedAssetsCanBeWithdrawn() public {
        vm.deal(address(rot), 5 ether);
        address dest = address(0xC0FFEE);

        rot.withdraw(NATIVE, dest, 2 ether);
        assertEq(dest.balance, 2 ether, "assets can be put back to work");
        assertEq(address(rot).balance, 3 ether, "the rest stays");
    }

    function test_StrangerCannotWithdraw() public {
        vm.deal(address(rot), 5 ether);
        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.withdraw(NATIVE, STRANGER, 5 ether);
    }

    function test_WithdrawToZeroIsRefused() public {
        vm.deal(address(rot), 1 ether);
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.withdraw(NATIVE, address(0), 1 ether);
    }

    function test_KeeperRewardIsCapped() public {
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setKeeperBps(101); // >1%
        rot.setKeeperBps(50);
        assertEq(rot.keeperBps(), 50);
    }

    // ---------------------------------------------------------------------
    // Arbitrage between the generation's own pools
    // ---------------------------------------------------------------------

    /// The two pools must trade the SAME token, or this is not an arb — it is
    /// an unrelated trade made with treasury funds.
    function test_ArbRequiresTheSameTokenInBothPools() public {
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.arbStep(_pool(NATIVE, address(0xAAA)), _pool(USDG, address(0xBBB)), 1 ether);
    }

    /// Arbing a pool against itself is not an arb.
    function test_ArbRequiresDifferentQuotes() public {
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.arbStep(_pool(NATIVE, TOKEN), _pool(NATIVE, TOKEN), 1 ether);
    }

    function test_ArbRejectsZeroSize() public {
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.arbStep(_pool(NATIVE, TOKEN), _pool(USDG, TOKEN), 0);
    }

    /// WITHOUT AN ORACLE THERE IS NO PROFIT TEST. The two legs are different
    /// assets, so "did this make money" has no answer without a common unit —
    /// and guessing with treasury funds is not an option.
    function test_ArbRefusesWithoutAnOracle() public {
        // No oracle configured: _usd returns 0 and the call must not proceed.
        vm.expectRevert();
        rot.arbStep(_pool(NATIVE, TOKEN), _pool(USDG, TOKEN), 1 ether);
    }

    /// The keeper's share is capped, so the reward cannot be tuned into a drain.
    function test_ArbKeeperShareIsCapped() public {
        vm.expectRevert(QuoteRotator.BadConfig.selector);
        rot.setArbParams(address(0xDEAD), 2001, 1e18); // ceiling is 20%

        rot.setArbParams(address(0xDEAD), 1000, 5e18);
        assertEq(rot.arbKeeperBps(), 1000);
        assertEq(rot.minArbProfitUsd(), 5e18);
    }

    function test_StrangerCannotSetArbParams() public {
        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.setArbParams(address(0xDEAD), 500, 1e18);
    }

    /// A profit floor exists so a keeper cannot farm the reward on dust arbs
    /// that cost the treasury more in price impact than they capture.
    function test_ArbHasAProfitFloor() public view {
        assertGt(rot.minArbProfitUsd(), 0, "a zero floor would pay for dust");
    }

    address constant TOKEN = 0x92B637d3De3587394664d5036e69399d8060C9c2;

    function _pool(address quote, address token) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(token),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    /// A well-formed ETH/USDG route. Never actually swapped through in these
    /// tests — the calls that use it revert before reaching the pool.
    function _dummyRoute() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(NATIVE),
            currency1: Currency.wrap(USDG),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }
}