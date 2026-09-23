// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-12 — THE VAULT'S LEDGER MOVES WITH A CARRIED BOOK
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  {PerpEngine.requoteBook} restates the book with positions still open: `plv`
 *  at the swap's REALIZED rate, the longs' borrowed principal (`longOiEth`) at
 *  the ORACLE rate. So `engine.totalEth()` — what every vault share is worth —
 *  moves by a BLEND of the two, and the vault's absolute old-unit figures must
 *  follow that blend exactly:
 *
 *    • {assetsEth} = `totalEth - pendingEth`. The queue is an absolute claim; if
 *      it does not move with the pot, a 6-decimal backing has an 18-decimal claim
 *      subtracted from it and every live share saturates to zero.
 *    • {_syncEthQueue} compares backing against `ethBackingMark`; an unmoved mark
 *      reads the change of UNIT as a total loss and retires the queue.
 *
 *  The real engine needs real swaps to hold open longs, so this drives the REAL
 *  vault's two hooks from a quote-strict mock engine that restates exactly as
 *  {PerpSwapLib.requoteBook} does. The seam itself (real engine ↔ real vault)
 *  is F12b; open positions on a real pool are F14 / F14c.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F12_RequoteBacking is Test {
    RQEngine internal engine;
    PerpVault internal vault;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    /// realized 2,850 USDG/ETH on the swapped pot; oracle 3,000 on the debt
    uint256 internal constant REALIZED = 2850e6;
    uint256 internal constant ORACLE = 3000e6;

    function setUp() public {
        engine = new RQEngine();
        vault = new PerpVault(address(engine), address(engine));
        engine.setVault(address(vault));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // ── T1: live shares keep their proportion; the pot is the blended figure ──

    function test_T1_LiveShares_KeepProportion_AcrossACarriedBook() public {
        vm.prank(alice);
        vault.depositEth{value: 3 ether}();
        vm.prank(bob);
        vault.depositEth{value: 1 ether}();
        engine.lend(2 ether);                     // an open long borrowed half the pot

        engine.requote(REALIZED, ORACLE);

        //  plv 2 ETH x 2850 + lent 2 ETH x 3000 = 11,700 USDG backs the shares.
        assertEq(engine.totalEth(), 11_700e6, "blended pot");
        (uint256 a,,) = vault.ethPosition(alice);
        (uint256 b,,) = vault.ethPosition(bob);
        assertApproxEqRel(a * 1e18 / (a + b), 0.75e18, 1e12, "alice still 75%");
        assertApproxEqRel(a + b, 11_700e6, 1e12, "and they own the whole pot, NOT zero");
    }

    // ── T2: a queued exit straddling the flip moves with the pot ─────────────

    function test_T2_QueuedExit_MovesWithThePot_NotRetired() public {
        vm.prank(alice);
        uint256 shares = vault.depositEth{value: 4 ether}();
        engine.lend(3.5 ether);                   // longs hold 3.5 ETH of it
        vm.prank(alice);
        (, uint256 queued) = vault.withdrawEth(shares);
        assertGt(queued, 0, "the exit MUST queue for this test to mean anything");
        uint256 pendBefore = vault.pendingEth();
        uint64 epochBefore = vault.ethQueueEpoch();
        uint256 totalBefore = engine.totalEth();

        engine.requote(REALIZED, ORACLE);         // the book is carried, longs still open

        uint256 pendAfter = vault.pendingEth();
        assertEq(vault.ethQueueEpoch(), epochBefore, "no epoch bump = the unit change was not read as a loss");
        assertGt(pendAfter, 0, "THE QUEUE MUST NOT BE RETIRED BY A UNIT CHANGE");
        //  Same fraction of the pot before and after.
        assertApproxEqRel(
            pendAfter * 1e18 / engine.totalEth(), pendBefore * 1e18 / totalBefore, 1e12, "same share of the pot"
        );
        assertLe(pendAfter, engine.totalEth(), "queue stays within backing");
        assertEq(vault.ethBackingMark(), engine.totalEth(), "the mark is re-taken in the new unit");

        //  The queue is still honoured once the longs repay (in USDG, at the
        //  oracle-restated principal).
        engine.repayAll();
        vm.prank(alice);
        uint256 paid = vault.claimPendingEth();
        assertApproxEqRel(paid, pendAfter, 1e12, "claim pays the rescaled figure");
        console2.log("F12 queued before (wei) ", pendBefore);
        console2.log("F12 queued after  (usdg)", pendAfter);
    }

    // ── T3: hooks are the engine's alone ────────────────────────────────────

    function test_T3_HooksAreEngineOnly() public {
        vm.prank(alice);
        vm.expectRevert(PerpVault.NotEngine.selector);
        vault.afterBookRequote(1, 1, 1, 1);
        vm.prank(alice);
        vm.expectRevert(PerpVault.NotEngine.selector);
        vault.beforeBookRequote();
    }
}

// ── mock engine ─────────────────────────────────────────────────────────────

/// Quote-strict (it pays in whatever `quote` names), and its {requote} is the
/// ledger half of {PerpSwapLib.requoteBook}: plv at the realized rate, lent
/// principal at the oracle rate, vault hooks before and after. Also the registry.
contract RQEngine {
    address public vault;
    address public quote;                 // starts native
    uint256 public plv;
    uint256 public lentEth;
    uint256 public tokYieldCumulative;
    uint256 public tokYieldEth;
    RQUsdg public immutable usdg = new RQUsdg();

    function setVault(address v) external { vault = v; }
    function currentToken() external pure returns (address) { return address(0xDEAD); }

    function totalEth() external view returns (uint256) { return plv + lentEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external pure returns (uint256) { return 0; }
    function freeToken() external pure returns (uint256) { return 0; }

    function fundFromVault(uint256 amount) external payable {
        require(quote == address(0) ? msg.value == amount : msg.value == 0, "BadParam");
        plv += amount;
    }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "free");
        plv -= amount;
        if (quote == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "send");
        } else {
            usdg.mint(to, amount);
        }
    }

    function lend(uint256 a) external { plv -= a; lentEth += a; }
    function repayAll() external { plv += lentEth; lentEth = 0; }

    function requote(uint256 realizedPerEth, uint256 oraclePerEth) external {
        (bool ok,) = vault.call(abi.encodeWithSignature("beforeBookRequote()"));
        require(ok, "before");
        uint256 oldTotal = plv + lentEth;
        plv = FullMath.mulDiv(plv, realizedPerEth, 1 ether);
        lentEth = FullMath.mulDivRoundingUp(lentEth, oraclePerEth, 1 ether);
        quote = address(usdg);
        (ok,) = vault.call(abi.encodeWithSignature(
            "afterBookRequote(uint256,uint256,uint256,uint256)", oldTotal, plv + lentEth, realizedPerEth, 1 ether
        ));
        require(ok, "after");
    }

    receive() external payable {}
}

contract RQUsdg {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
}
