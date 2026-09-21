// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LocalLifecycleBoot} from "./LocalLifecycleAdapters.t.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";

/// Full production hook/engine + local managers. The existing adapter's ambient
/// manager inventory is explicit; this is not a fork or deployed-state test.
contract PreSweepLargeBookLocalTest is LocalLifecycleBoot {
    function setUp() public {
        _boot(60 ether, 0);
        _bootPerp(40 ether, 400_000_000 ether);
    }

    function _openBook(uint256 count) internal returns (uint256[] memory ids) {
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            address owner = address(uint160(0xA000 + i));
            vm.deal(owner, 1 ether);
            vm.prank(owner);
            ids[i] = perp.openShort{value: 0.01 ether}(2, 0, 0, 0.01 ether);
        }
        assertEq(perp.openCount(), count, "every intended position must remain open before the trigger");
        for (uint256 i; i < count; ++i) assertFalse(perp.isLiquidatable(ids[i]), "healthy before trade");
    }

    function _assertSafe(uint256[] memory ids, uint256 beforePlv) internal {
        uint256 insolvent;
        uint256 shortfall;
        for (uint256 i; i < ids.length; ++i) {
            (address owner, bool isLong, uint128 collateral, uint256 size, uint256 principal,,,) = perp.positions(ids[i]);
            if (owner != address(0)) {
                uint256 value = PerpSwapLib.quoteAt(size, uint256(_sqrtP()));
                uint256 backing = uint256(collateral) + principal;
                if (isLong ? value < principal : value > backing) {
                    ++insolvent;
                    shortfall += isLong ? principal - value : value - backing;
                }
            }
        }
        emit log_named_uint("open after swap", perp.openCount());
        emit log_named_uint("insolvent after swap", insolvent);
        emit log_named_uint("spot-valued open shortfall", shortfall);
        emit log_named_uint("PLV decrease", beforePlv > perp.plv() ? beforePlv - perp.plv() : 0);
        assertEq(insolvent, 0, "a successful preempted trade must not leave an unscanned insolvent tail");
        assertGe(perp.plv(), beforePlv, "preemption must preserve PLV for this scenario");
    }

    function _scenario(uint256 count) internal {
        uint256[] memory ids = _openBook(count);
        uint256 beforePlv = perp.plv();
        uint256 beforeGas = gasleft();
        _buy(45 ether, attacker);
        emit log_named_uint("swap gas excluding book setup", beforeGas - gasleft());
        _assertSafe(ids, beforePlv);
    }

    function test_twentyFourPositionExactOutputBuy() public {
        uint256[] memory ids = _openBook(24);
        uint256 beforePlv = perp.plv();
        uint256 tokenOut = PerpSwapLib.ethToToken(perp.activeEthDepth(), _sqrtP()) / 2;
        uint256 paid = _buyExactOut(tokenOut, attacker);
        assertGt(paid, 0, "funded exact-output trade must execute");
        _assertSafe(ids, beforePlv);
    }

    /// EIP-7825's transaction ceiling. Giving the inner trade this ENTIRE
    /// budget is optimistic: a real transaction also pays intrinsic/router gas.
    /// This is a liveness probe, not a change to the profile's Cancun EVM.
    function test_maximumBookTradeMustFitSepoliaTransactionGasCap() public {
        uint256[] memory ids = _openBook(64);
        uint256 beforePlv = perp.plv();
        (bool ok,) = address(this).call{gas: 16_777_216}(abi.encodeCall(this.cappedBuy, ()));
        assertTrue(ok, "valid 64-position trade exceeds the chain transaction gas cap");
        _assertSafe(ids, beforePlv);
    }

    /// Pre-trade sweeps may defer NFT minting to keep the bounded book within
    /// the transaction budget. Keeper credit remains one-for-one; claim-later
    /// badges intentionally do not carry liquidation stats (approved trade-off).
    function test_preTradeBadgesDeferWithoutDroppingKeeperCredits() public {
        uint256[] memory ids = _openBook(24);
        CauldronCollection col = CauldronCollection(hook.collection());
        uint256 owedBefore = perp.badgesOwed(tx.origin);
        uint256 mintedBefore = col.liquidatorMinted();
        uint256 beforePlv = perp.plv();
        (bool ok,) = address(this).call{gas: 16_777_216}(abi.encodeCall(this.cappedBuy, ()));
        assertTrue(ok, "pre-trade sweep with deferred badges must execute");
        _assertSafe(ids, beforePlv);
        assertEq(perp.badgesOwed(tx.origin), owedBefore + 24, "one claimable badge per liquidation");
        assertEq(col.liquidatorMinted(), mintedBefore, "pre-trade sweep did not mint inline");
        vm.prank(tx.origin);
        perp.claimLiquidatorBadges(24);
        assertEq(perp.badgesOwed(tx.origin), owedBefore);
        assertEq(col.liquidatorMinted(), mintedBefore + 24);
        uint256 badgeId = col.LIQUIDATOR_ID_BASE() + mintedBefore + 1;
        assertEq(col.ownerOf(badgeId), tx.origin);
        assertEq(col.liqStats(badgeId).victim, address(0), "approved no-stats claim-later badge");
    }

    function cappedBuy() external {
        require(msg.sender == address(this), "self only");
        _buy(45 ether, attacker);
    }

    function cursorNudge() external {
        require(msg.sender == address(this), "self only");
        _buy(0.000001 ether, attacker);
    }

    function test_mixedBookRotatedCursorMustNotSkipDangerousPrefix() public {
        uint256[] memory ids = new uint256[](24);
        for (uint256 i; i < ids.length; ++i) {
            address owner = address(uint160(0xB000 + i));
            vm.deal(owner, 1 ether);
            vm.prank(owner);
            ids[i] = i < 12
                ? perp.openShort{value: 0.01 ether}(2, 0, 0, 0.01 ether)
                : perp.openLong{value: 0.01 ether}(2, 0, 0, 0.01 ether);
        }
        assertEq(perp.openCount(), 24);
        for (uint256 i; i < ids.length; ++i) assertFalse(perp.isLiquidatable(ids[i]));
        bool rotated;
        for (uint256 cap = 1_000_000; cap <= 4_000_000; cap += 25_000) {
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(this).call{gas: cap}(abi.encodeCall(this.cursorNudge, ()));
            // Read-only probe. Slot 80 is compiler-verified sweepCursor in the
            // current layout; no target storage is forced to seed this state.
            uint256 cursor = uint256(vm.load(address(perp), bytes32(uint256(80))));
            if (ok && cursor > 1 && cursor < ids.length) {
                rotated = true;
                emit log_named_uint("reachable cursor", cursor);
                emit log_named_uint("cursor nudge gas cap", cap);
                break;
            }
            assertTrue(vm.revertToState(snap));
        }
        assertTrue(rotated, "probe must reach a nontrivial cursor through a funded public swap");
        assertEq(perp.openCount(), 24, "nudge must not settle the book");
        uint256 beforePlv = perp.plv();
        _buy(45 ether, attacker);
        _assertSafe(ids, beforePlv);
    }

    function _bookHash(uint256[] memory ids) internal view returns (bytes32 result) {
        for (uint256 i; i < ids.length; ++i) {
            (address owner, bool isLong, uint128 collateral, uint256 size, uint256 principal,
                uint64 openedAt, uint8 leverage, int256 fundingEntry) = perp.positions(ids[i]);
            result = keccak256(abi.encode(result, owner, isLong, collateral, size, principal,
                openedAt, leverage, fundingEntry));
        }
    }

    function test_largeBookGasLadderEitherRejectsAtomicallyOrLeavesSafeBook() public {
        uint256[] memory ids = _openBook(24);
        uint256 beforePlv = perp.plv();
        bytes32 beforeBook = _bookHash(ids);
        uint160 beforePrice = _sqrtP();
        uint256 beforeBalance = address(this).balance;
        uint256 beforeKeeper = attacker.balance;
        uint256[6] memory caps = [uint256(1_000_000), 3_000_000, 5_000_000, 8_000_000, 12_000_000, 16_000_000];
        uint256 successes;
        uint256 failures;
        for (uint256 i; i < caps.length; ++i) {
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(this).call{gas: caps[i]}(abi.encodeCall(this.cappedBuy, ()));
            emit log_named_uint("gas cap", caps[i]);
            emit log_named_uint("success", ok ? 1 : 0);
            if (ok) {
                ++successes;
                _assertSafe(ids, beforePlv);
            } else {
                ++failures;
                assertEq(perp.openCount(), ids.length, "failed trade rolls back kills");
                assertEq(_bookHash(ids), beforeBook, "failed trade rolls back position state");
                assertEq(_sqrtP(), beforePrice, "failed trade rolls back price");
                assertEq(perp.plv(), beforePlv, "failed trade rolls back PLV");
                assertEq(address(this).balance, beforeBalance, "failed trade rolls back payer balance");
                assertEq(attacker.balance, beforeKeeper, "failed trade rolls back keeper payout");
            }
            assertTrue(vm.revertToState(snap), "snapshot restoration");
        }
        assertGt(successes, 0, "large-book trade remains executable with enough gas");
        assertGt(failures, 0, "gas-starvation branch actually exercised");
    }

    function test_fourPositionControl() public { _scenario(4); }
    function test_twentyFourPositionsCannotBypassPreSweepViaKillCap() public { _scenario(24); }
    function test_maximumBookCannotBypassPreSweepViaKillCap() public { _scenario(64); }
}
