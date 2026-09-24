// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";

/**
 *  P-30 — DOES A CASCADE AT THE NEW KILL CEILING STAY SOLVENT?
 *
 *  `MAX_LIQ_PER_SWAP` went 8 -> 30 and the sweep gained a multi-pass cascade
 *  loop that chases its own settlement impact. Every existing cascade test
 *  drives 8-24 DUST positions (0.01-0.05 ETH). None has ever run the path at
 *  the ceiling, and none asserts the property that actually matters at scale.
 *
 *  THE PROPERTY, stated as conservation rather than as an outcome:
 *
 *      a trade that FILLS must leave no position insolvent at spot, and must
 *      not have created bad debt that nothing absorbed
 *      (`PerpEngine.unabsorbedEth` unchanged)
 *
 *  and its converse, which is the half a green test usually forgets:
 *
 *      a trade that is REFUSED must leave the book bit-identical -- no kills
 *      banked, no PLV moved, no keeper paid
 *
 *  Either outcome is a pass. The third outcome -- filling while leaving an
 *  insolvent tail, or filling while silently minting bad debt -- is the defect
 *  the pre-trade sweep exists to prevent, and is what this pins.
 *
 *  WHY THIS IS NOT COVERED BY THE EXISTING SUITE. `_assertSafe` in
 *  `PreSweepLargeBookLocal` checks spot-insolvency of a position LIST it holds.
 *  It cannot see `unabsorbedEth`, which did not exist when it was written, so a
 *  cascade that closes every position but funds the closes from nobody reads as
 *  a clean pass there. Bad debt that is absorbed is a cost; bad debt that is
 *  UNABSORBED is a hole, and only the second is a solvency failure.
 */
contract P30_FullCascadeSolvency is YBase {
    address internal taker = address(0xBEEF30);

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(10 ether, 50_000_000 ether);
    }

    /// @dev Open `n` shorts of `col` each, from distinct owners so no single
    ///      account's balance bounds the book.
    uint256[] internal ids;

    function _openShorts(uint256 n, uint256 col) internal returns (uint256 opened) {
        for (uint256 i; i < n; ++i) {
            address o = address(uint160(0xC000 + i));
            vm.deal(o, col * 4);
            vm.prank(o);
            try perp.openShort{value: col}(2, 0, 0, col) returns (uint256 id) {
                ids.push(id);
                opened++;
            } catch { break; }
        }
    }

    function extBuy(uint256 ethIn) external returns (uint256) {
        require(msg.sender == address(this), "self only");
        return _buy(ethIn, taker);
    }

    /// @dev Returns (filled, ethSpentOrZero). A refused trade is a legitimate
    ///      outcome, not a test failure -- the assertions below cover both.
    function _tryBuy(uint256 ethIn) internal returns (bool filled) {
        (filled, ) = address(this).call(abi.encodeCall(this.extBuy, (ethIn)));
    }

    /// @dev How many open positions are insolvent at LIVE spot right now.
    ///      Insolvent, not merely underwater: a position with backing left is a
    ///      liquidation opportunity, not a hole in the vault.
    function _insolventNow() internal view returns (uint256 bad) {
        uint256 sp = uint256(_sqrtP());
        for (uint256 i; i < ids.length; ++i) {
            (address t, bool isLong, uint128 col, uint256 size, uint256 principal,,,) = perp.positions(ids[i]);
            if (t == address(0)) continue;
            uint256 value = PerpSwapLib.quoteAt(size, sp);
            uint256 backing = uint256(col) + principal;
            if (isLong ? value < principal : value > backing) ++bad;
        }
    }

    function test_P30_fullCascadeEitherFillsCleanOrRefusesWhole() public {
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        assertTrue(active, "fork harness must be live (FORK_RPC)");

        // A book at the ceiling, with real positions rather than dust: 30 shorts
        // is exactly MAX_LIQ_PER_SWAP, so a trade condemning all of them sits on
        // the boundary between "the sweep can finish" and "it must refuse".
        //  MEASURED: the OI cap binds long before either count cap. At 0.05 ETH
        //  of collateral the book stops at SIXTEEN shorts on a 10 ETH engine --
        //  `maxOiBps = 3000` refuses the 17th -- so `MAX_LIQ_PER_SWAP = 30` and
        //  `MAX_OPEN_POSITIONS = 64` are NOT reachable on one side with
        //  meaningful positions. They are dust-only ceilings. Dropping to 0.02
        //  ETH gets the count up without changing the property under test.
        uint256 opened = _openShorts(40, 0.02 ether);
        assertGt(opened, 8, "book must exceed the OLD kill cap to exercise the new path");
        console2.log("OI cap bound the book at", opened);

        uint256 plvBefore = perp.plv();
        uint256 insBefore = perp.insuranceEth();
        uint256 badBefore = perp.unabsorbedEth();
        uint256 openBefore = perp.openCount();
        uint256 takerBefore = taker.balance;

        // Large enough to condemn the whole side, which is the case the kill
        // ceiling and the cascade loop were both written for.
        bool filled = _tryBuy(6 ether);

        uint256 insolventAfter = _insolventNow();
        uint256 badAfter = perp.unabsorbedEth();

        console2.log("opened / filled", opened, filled ? 1 : 0);
        console2.log("open before / after", openBefore, perp.openCount());
        console2.log("insolvent at spot after", insolventAfter);
        console2.log("unabsorbed before / after", badBefore, badAfter);
        console2.log("plv before / after", plvBefore, perp.plv());

        if (filled) {
            //  A FILL IS A CERTIFICATE. The sweep said the book is clean, so it
            //  must be: nothing insolvent left standing, and no bad debt that
            //  landed on nobody. `plv` may legitimately fall -- stakers backing
            //  a loss is the product working -- but `unabsorbedEth` rising means
            //  a loss exceeded insurance AND the whole vault, which no trade
            //  should be allowed to certify as safe.
            assertEq(insolventAfter, 0, "a filled trade left an insolvent position open");
            assertEq(badAfter, badBefore, "a filled trade minted bad debt nothing absorbed");
        } else {
            //  A REFUSAL IS ATOMIC. This is the half that is easy to forget:
            //  LiqGasStarved / LiqTradeTooLarge roll back the kills the sweep
            //  already banked, so a refused trade must be invisible.
            assertEq(perp.openCount(), openBefore, "a refused trade banked kills");
            assertEq(perp.plv(), plvBefore, "a refused trade moved PLV");
            assertEq(perp.insuranceEth(), insBefore, "a refused trade moved insurance");
            assertEq(perp.unabsorbedEth(), badBefore, "a refused trade minted bad debt");
            assertEq(taker.balance, takerBefore, "a refused trade paid the taker");
        }
    }

    /// @notice The same property under a book DEEPER than the kill ceiling, where
    ///         refusal is the expected answer rather than an edge case. 40 > 30,
    ///         so a trade condemning the whole side cannot be finished in one
    ///         swap and must be turned away whole.
    function test_P30_bookBeyondTheCeilingRefusesWhole() public {
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        assertTrue(active, "fork harness must be live (FORK_RPC)");

        //  Smallest positions the dust filter allows, to push the COUNT as high
        //  as the OI cap permits. If this still cannot exceed MAX_LIQ_PER_SWAP,
        //  that is itself the result: the kill ceiling is unreachable in
        //  practice and the binding constraint is economic, not numeric.
        uint256 opened = _openShorts(64, 0.005 ether);
        assertGt(opened, 8, "book must exceed the OLD kill cap");
        console2.log("deepest book the OI cap allows", opened);

        uint256 plvBefore = perp.plv();
        uint256 badBefore = perp.unabsorbedEth();
        uint256 openBefore = perp.openCount();

        bool filled = _tryBuy(8 ether);

        console2.log("opened / filled", opened, filled ? 1 : 0);
        console2.log("insolvent at spot after", _insolventNow());
        console2.log("unabsorbed before / after", badBefore, perp.unabsorbedEth());

        //  Whichever way it goes, the invariant is the same one. Asserting the
        //  OUTCOME ("it must refuse") would encode today's ceiling into a test
        //  and break the next time the ceiling moves; asserting the PROPERTY
        //  survives that.
        if (filled) {
            assertEq(_insolventNow(), 0, "a filled trade left an insolvent position open");
            assertEq(perp.unabsorbedEth(), badBefore, "a filled trade minted bad debt nothing absorbed");
        } else {
            assertEq(perp.openCount(), openBefore, "a refused trade banked kills");
            assertEq(perp.plv(), plvBefore, "a refused trade moved PLV");
            assertEq(perp.unabsorbedEth(), badBefore, "a refused trade minted bad debt");
        }
    }
}
