// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {NativeQuoteZap} from "../../cauldron/NativeQuoteZap.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/// Production V4 manager and zap, a fee-bearing venue with three contiguous
/// ranges, and an ordinary mock ERC20. No hook or arbitrary token is modeled.
contract NativeQuoteZapLocalTest is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    IPoolManager internal manager;
    MockQuoteToken internal quote;
    NativeQuoteZap internal zap;
    PoolKey internal key;

    function setUp() public {
        manager = IPoolManager(deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this))));
        quote = new MockQuoteToken("Quote fixture", "Q", 18);
        zap = new NativeQuoteZap(manager);
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(quote)), 3000, 60, IHooks(address(0)));
        manager.initialize(key, uint160(1 << 96));
        vm.deal(address(this), 10 ether);
        quote.mint(address(this), 10 ether);
        manager.unlock("");
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        _range(-600, 600);
        _range(-1200, -600);
        _range(-1800, -1200);
        return "";
    }

    function _range(int24 lower, int24 upper) internal {
        (BalanceDelta delta,) = manager.modifyLiquidity(
            key, ModifyLiquidityParams(lower, upper, int256(1 ether), bytes32(0)), ""
        );
        if (delta.amount0() < 0) manager.settle{value: uint256(uint128(-delta.amount0()))}();
        if (delta.amount1() < 0) {
            manager.sync(key.currency1);
            assertTrue(quote.transfer(address(manager), uint256(uint128(-delta.amount1()))));
            manager.settle();
        }
    }

    function test_multiTickPartialFillRefundsWithoutExtraInput() public {
        uint256 beforeNative = address(this).balance;
        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 beforeManager = address(manager).balance;
        uint256 out = zap.zap{value: 1 ether}(key, 1);
        (, int24 tick,,) = manager.getSlot0(key.toId());
        assertLt(tick, -1800, "must cross all three ranges");
        assertGt(out, 0);
        assertEq(quote.balanceOf(address(this)) - beforeQuote, out);
        uint256 spent = beforeNative - address(this).balance;
        assertGt(spent, 0);
        assertLt(spent, 1 ether, "unspent input must be returned");
        assertEq(address(manager).balance - beforeManager, spent);
        assertEq(address(zap).balance, 0);
        assertEq(quote.balanceOf(address(zap)), 0);
    }

    function testFuzz_feeBearingExactInputNeverNeedsMoreThanBudget(uint96 raw) public {
        uint256 amount = bound(uint256(raw), 1e12, 1 ether);
        uint256 beforeNative = address(this).balance;
        uint256 beforeQuote = quote.balanceOf(address(this));
        uint256 out = zap.zap{value: amount}(key, 1);
        assertGt(out, 0);
        assertEq(quote.balanceOf(address(this)) - beforeQuote, out);
        assertLe(beforeNative - address(this).balance, amount);
        assertEq(address(zap).balance, 0);
        assertEq(quote.balanceOf(address(zap)), 0);
    }

    function test_unachievableFloorRollsBackVenueAndCustody() public {
        (uint160 beforePrice,,,) = manager.getSlot0(key.toId());
        uint256 beforeNative = address(this).balance;
        uint256 beforeManager = address(manager).balance;
        uint256 beforeQuote = quote.balanceOf(address(this));
        vm.expectRevert(NativeQuoteZap.Slippage.selector);
        zap.zap{value: 1 ether}(key, type(uint256).max);
        (uint160 afterPrice,,,) = manager.getSlot0(key.toId());
        assertEq(afterPrice, beforePrice);
        assertEq(address(this).balance, beforeNative);
        assertEq(address(manager).balance, beforeManager);
        assertEq(quote.balanceOf(address(this)), beforeQuote);
        assertEq(address(zap).balance, 0);
    }

    function test_untrustedCallbackAndZeroFloorAreRejected() public {
        vm.expectRevert(NativeQuoteZap.NotPoolManager.selector);
        zap.unlockCallback("");
        vm.expectRevert(NativeQuoteZap.NoFloor.selector);
        zap.zap{value: 1 ether}(key, 0);
    }

    receive() external payable {}
}
