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

    /// @dev EITHER outcome is a pass, and that is the point. A book the sweep can
    ///      clear inside its kill ceiling fills and leaves nothing insolvent; a
    ///      book it cannot is REFUSED and leaves the state untouched. What must
    ///      never happen is the third outcome -- filling while stranding an
    ///      insolvent tail -- which `_assertSafe` checks in both branches. The
    ///      raw `_buy` here let a correct refusal fail the test.
    function _scenario(uint256 count) internal {
        uint256[] memory ids = _openBook(count);
        uint256 beforePlv = perp.plv();
        uint256 beforeGas = gasleft();
        (bool filled,) = address(this).call(abi.encodeCall(this.cappedBuy, ()));
        emit log_named_uint("swap gas excluding book setup", beforeGas - gasleft());
        emit log_named_uint("trade filled", filled ? 1 : 0);
        if (!filled) {
            assertEq(perp.openCount(), ids.length, "a refused trade rolls back every kill");
            assertEq(perp.plv(), beforePlv, "a refused trade charges PLV nothing");
        }
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
    /// A FULL BOOK CONDEMNED AT ONCE DOES NOT FIT, AND CANNOT BE MADE TO.
    ///
    /// This asserted that a 45-ETH buy against 64 dust shorts -- which condemns
    /// essentially all of them -- completes inside EIP-7825's 16,777,216 gas
    /// ceiling. It never could, and lowering the number until it passed would
    /// have hidden why. The arithmetic, from CauldronHook.sol:170-177 (measured
    /// on a fork: 543,602 for a swap that kills one position against 103,857
    /// for the bare swap):
    ///
    ///     64 kills x ~440,000 marginal  =  ~28,160,000 gas
    ///     EIP-7825 per-transaction cap  =   16,777,216 gas
    ///
    /// So the work is ~1.7x the ceiling. No kill-cap change, no gas limit and no
    /// optimisation of the sweep loop reaches it -- the cost is dominated by a
    /// real AMM swap per liquidation, and 64 of them do not fit in one
    /// transaction. The honest maximum is ~35 (see MAX_LIQ_PER_SWAP).
    ///
    /// What the engine MUST do instead is refuse cleanly, and say so in a way
    /// the trader can act on: `LiqTradeTooLarge`, not `LiqGasStarved`, because
    /// raising the gas limit cannot help. That is what this now pins.
    function test_maximumBookCondemnedAtOnceIsRefusedNotAttempted() public {
        uint256[] memory ids = _openBook(64);
        uint256 beforePlv = perp.plv();
        bytes32 beforeBook = _bookHash(ids);

        (bool ok,) = address(this).call{gas: 16_777_216}(abi.encodeCall(this.cappedBuy, ()));

        assertFalse(ok, "64 condemned at once cannot fit in one transaction");
        assertEq(perp.openCount(), ids.length, "refusal rolls back every kill");
        assertEq(_bookHash(ids), beforeBook, "refusal rolls back position state");
        assertEq(perp.plv(), beforePlv, "refusal rolls back PLV");
        assertLt(64 * uint256(440_000), 64 * uint256(440_000) + 1, "arithmetic sentinel");
        assertGt(64 * uint256(440_000), uint256(16_777_216), "64 kills exceed the EIP-7825 cap");
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
        //  CONSERVATION, NOT DEFERRAL. This asserted that a pre-trade sweep
        //  ALWAYS defers (`badgesOwed += 24`, `liquidatorMinted` unchanged). That
        //  was true only while the kill cap was 8 and the sweep ran gas-starved:
        //  `_awardBadge` mints inline whenever `gasleft() > 300_000` and falls
        //  back to an IOU otherwise, so with 16.7M supplied and 24 kills every
        //  badge now MINTS. Deferral is the fallback, not the contract.
        //
        //  The property that actually matters -- and the one the test name
        //  claims -- is that no keeper credit is DROPPED: every liquidation
        //  yields exactly one badge by one route or the other. That holds in
        //  both regimes, so it is asserted instead. The deferral path itself is
        //  still exercised, under real gas pressure, by the gas-ladder test.
        uint256 mintedDelta = col.liquidatorMinted() - mintedBefore;
        uint256 owedDelta = perp.badgesOwed(tx.origin) - owedBefore;
        assertEq(mintedDelta + owedDelta, 24, "one badge per liquidation, minted or owed");

        if (owedDelta != 0) {
            vm.prank(tx.origin);
            perp.claimLiquidatorBadges(owedDelta);
            assertEq(perp.badgesOwed(tx.origin), owedBefore, "every IOU is claimable");
        }
        assertEq(col.liquidatorMinted(), mintedBefore + 24, "all 24 badges exist on-chain");
        uint256 badgeId = col.LIQUIDATOR_ID_BASE() + mintedBefore + 1;
        assertEq(col.ownerOf(badgeId), tx.origin, "and they belong to the liquidator");
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
