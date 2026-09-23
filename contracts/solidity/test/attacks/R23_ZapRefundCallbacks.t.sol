// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {NativeQuoteZapLocalTest} from "../audit_full_scope/NativeQuoteZapLocal.t.sol";
import {NativeQuoteZap} from "../../cauldron/NativeQuoteZap.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract R23RefundReceiver {
    NativeQuoteZap immutable target;
    PoolKey internal route;
    bool immutable rejectRefund;
    bool public attempted;
    bool public nestedSucceeded;
    bytes4 public nestedError;
    constructor(NativeQuoteZap z, bool reject_) { target = z; rejectRefund = reject_; }
    function run(PoolKey calldata k) external payable returns (uint256) {
        route = k;
        return target.zap{value: msg.value}(k, 1);
    }
    receive() external payable {
        if (rejectRefund) revert("no refund");
        attempted = true;
        (bool ok, bytes memory result) = address(target).call{value: 1e12}(
            abi.encodeCall(target.zap, (route, 1))
        );
        nestedSucceeded = ok;
        if (result.length >= 4) nestedError = bytes4(result);
    }
}

contract R23ZapRefundCallbacks is NativeQuoteZapLocalTest {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    function test_R23_RefundCannotNestManagerUnlockButOriginalTradeCompletes() public {
        R23RefundReceiver recipient = new R23RefundReceiver(zap, false);
        uint256 managerBefore = address(manager).balance;
        uint256 out = recipient.run{value: 1 ether}(key);
        assertTrue(recipient.attempted(), "partial-fill refund callback executed");
        assertFalse(recipient.nestedSucceeded(), "nested swap refused");
        assertEq(recipient.nestedError(), IPoolManager.AlreadyUnlocked.selector);
        assertEq(quote.balanceOf(address(recipient)), out, "original output delivered");
        assertEq(address(manager).balance - managerBefore + address(recipient).balance, 1 ether);
        assertEq(address(zap).balance, 0);
        assertEq(quote.balanceOf(address(zap)), 0);
    }
    function test_R23_RejectingRefundRollsBackTradeAndCustody() public {
        R23RefundReceiver recipient = new R23RefundReceiver(zap, true);
        (uint160 priceBefore,,,) = manager.getSlot0(key.toId());
        uint256 payerBefore = address(this).balance;
        uint256 managerBefore = address(manager).balance;
        uint256 managerQuoteBefore = quote.balanceOf(address(manager));
        vm.expectRevert(NativeQuoteZap.EthReturnFailed.selector);
        recipient.run{value: 1 ether}(key);
        (uint160 priceAfter,,,) = manager.getSlot0(key.toId());
        assertEq(priceAfter, priceBefore);
        assertEq(address(this).balance, payerBefore);
        assertEq(address(manager).balance, managerBefore);
        assertEq(quote.balanceOf(address(manager)), managerQuoteBefore);
        assertEq(address(recipient).balance, 0);
        assertEq(quote.balanceOf(address(recipient)), 0);
        assertEq(address(zap).balance, 0);
        assertEq(quote.balanceOf(address(zap)), 0);
    }
}
