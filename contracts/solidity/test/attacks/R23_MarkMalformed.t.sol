// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {PerpVaultEngineWriteoffTest} from "../audit_full_scope/PerpVaultEngineWriteoff.t.sol";

contract R23MalformedMark {
    uint256 immutable word;
    bool immutable fails;
    constructor(uint256 value, bool reverts_) { word = value; fails = reverts_; }
    fallback() external {
        require(!fails, "feed down");
        uint256 value = word;
        assembly { mstore(0, value) return(0, 32) }
    }
}

/// Production engine, stub manager/registry. Only tests oracle observation and
/// public mark availability; liquidation impact is a separate integration gap.
contract R23MarkMalformed is PerpVaultEngineWriteoffTest {
    function _wire(uint256 word, bool fails) internal {
        engine.setRouting(address(0xD1), TREASURY, TREASURY,
            address(new R23MalformedMark(word, fails)), address(0));
        engine.poke();
        vm.warp(block.timestamp + 3600);
        engine.poke();
    }
    function test_outOfRangeMarkMustFallBackToPrimary() public {
        _wire(887273, false);
        assertGt(engine.markSqrtPriceX96(), 0, "malformed dependency must preserve usable mark");
    }
    function test_revertingMarkFallsBackToPrimary() public {
        _wire(0, true);
        assertGt(engine.markSqrtPriceX96(), 0);
    }
}
