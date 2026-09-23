// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {R23MarkMalformed} from "./R23_MarkMalformed.t.sol";

contract R23MarkAcceptance is R23MarkMalformed {
    function _expectTick(uint256 word, int24 expected) private {
        _wire(word, false);
        (int24 actual, bool ok) = engine.twapTick();
        assertTrue(ok);
        assertEq(actual, expected);
        assertGt(engine.markSqrtPriceX96(), 0);
    }
    function test_acceptMinimumValidMark() public {
        _expectTick(uint256(int256(-887272)), -887272);
    }
    function test_acceptMaximumValidMark() public { _expectTick(887272, 887272); }
    function test_acceptNegativeCanonicalMark() public { _expectTick(type(uint256).max, -1); }
    function test_rejectBelowMinimumMark() public {
        _expectTick(uint256(int256(-887273)), 0);
    }
    function test_rejectNoncanonicalMarkInsteadOfTruncating() public {
        _expectTick((uint256(1) << 24) + 42, 0);
    }
}
