// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {PreSweepLargeBookLocalTest} from "../audit_full_scope/PreSweepLargeBookLocal.t.sol";
import {R23MalformedMark} from "./R23_MarkMalformed.t.sol";

/// Production beforeSwap hook and engine, local V4 managers. No external poke
/// in the tested sequence; normal buys record and subsequently consume the mark.
contract R23MarkBeforeSwap is PreSweepLargeBookLocalTest {
    function _scenarioMark(bool fails) internal {
        _openBook(1);
        perp.setRouting(address(0xD1), address(0x7777), address(0x7777),
            address(new R23MalformedMark(887273, fails)), address(0));
        _buy(0.001 ether, attacker);
        _warp(3600);
        uint256 tokensBefore = IERC20Balance(token).balanceOf(attacker);
        _buy(0.001 ether, attacker);
        assertGt(IERC20Balance(token).balanceOf(attacker), tokensBefore,
            "ordinary buy must remain available through beforeSwap");
        assertEq(perp.openCount(), 1);
    }
    function test_beforeSwapMalformedSourceMustFallBack() public { _scenarioMark(false); }
    function test_beforeSwapRevertingSourceControl() public { _scenarioMark(true); }
}
interface IERC20Balance { function balanceOf(address) external view returns (uint256); }
