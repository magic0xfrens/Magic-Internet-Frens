// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {PreSweepLargeBookLocalTest} from "../audit_full_scope/PreSweepLargeBookLocal.t.sol";

/// R23-L1 with heterogeneous thresholds. Lower-leverage shorts occupy the LOW
/// book indices, maximum-leverage shorts the high ones, so a cascade pass checks
/// the sturdier group before killing the fragile group. A later kill's buyback
/// moves spot; the property is that no position the trade condemns survives a
/// filled trade (the engine's own promise: "the ONLY clean exit is a full pass
/// that finds nothing condemned"). Production hook/engine, local managers,
/// fixture's explicit ambient manager inventory. No target storage writes.
contract R23CascadeMixedLeverage is PreSweepLargeBookLocalTest {
    function r23Buy(uint256 amount) external {
        require(msg.sender == address(this), "self only");
        _buy(amount, attacker);
    }

    function _openMixed(uint256 seed, uint256 nSturdy, uint256 nFragile) internal returns (uint256[] memory ids) {
        ids = new uint256[](nSturdy + nFragile);
        uint8 maxLev = perp.maxLeverage();
        for (uint256 i; i < ids.length; ++i) {
            uint256 h = uint256(keccak256(abi.encode(seed, i)));
            bool sturdy = i < nSturdy;
            uint256 collateral = sturdy ? (1 + h % 6) * 0.01 ether : (2 + h % 10) * 0.01 ether;
            address account = address(uint160(0xB000 + i));
            vm.deal(account, 1 ether);
            vm.prank(account, account);
            ids[i] = perp.openShort{value: collateral}(sturdy ? 1 + uint8(h % 2) : maxLev, 0, 0, collateral);
        }
        for (uint256 i; i < ids.length; ++i) assertFalse(perp.isLiquidatable(ids[i]), "healthy before trade");
    }

    function _run(uint256 seed, uint256 amount) internal returns (bool filled, uint256 victims) {
        uint256[] memory ids = _openMixed(seed, 8, 8);
        uint256 plvBefore = perp.plv();
        bytes32 bookBefore = _bookHash(ids);
        (filled,) = address(this).call(abi.encodeCall(this.r23Buy, (amount)));
        if (!filled) {
            assertEq(_bookHash(ids), bookBefore, "refusal restores positions");
            assertEq(perp.plv(), plvBefore, "refusal restores PLV");
            return (false, 0);
        }
        for (uint256 i; i < ids.length; ++i) {
            (address owner,,,,,,,) = perp.positions(ids[i]);
            if (owner != address(0) && perp.isLiquidatable(ids[i])) {
                ++victims;
                console2.log("surviving trade victim index", i);
            }
        }
        console2.log("buy wei", amount, "open after", perp.openCount());
        console2.log("trade victims left open", victims);
        _assertSafe(ids, plvBefore);
    }

    /// Non-vacuity: the same property over a deterministic ladder, requiring
    /// that some FILLED trades actually liquidated positions (so the pass loop
    /// and its exit condition were exercised, not skipped).
    function test_R23_mixedLeverageLadderExercisesKills() public {
        uint256 snap = vm.snapshotState();
        uint256 fills;
        uint256 killFills;
        uint256 refusals;
        for (uint256 s; s < 24; ++s) {
            vm.revertToState(snap);
            (bool filled, uint256 victims) = _run(s, 2 ether + s * 2.5 ether);
            assertEq(victims, 0, "a filled trade must not leave a position it condemned open");
            if (!filled) { ++refusals; continue; }
            ++fills;
            if (perp.openCount() < 16) ++killFills;
        }
        console2.log("fills", fills, "fills with kills", killFills);
        console2.log("refusals", refusals);
        assertGt(killFills, 0, "ladder must include filled trades that liquidated positions");
    }

    function testFuzz_R23_mixedLeverageCascadeClosesEveryTradeVictim(uint256 seed, uint96 amountSeed) public {
        uint256 amount = bound(uint256(amountSeed), 2 ether, 60 ether);
        (, uint256 victims) = _run(seed, amount);
        assertEq(victims, 0, "a filled trade must not leave a position it condemned open");
    }
}
