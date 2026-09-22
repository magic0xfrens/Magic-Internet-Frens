// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/**
 * Engine stand-in with EXACTLY the real PerpEngine's vault-facing semantics:
 *   totalEth() = plv + longOiEth      (PerpEngine.sol:466)
 *   freeEth()  = plv                  (PerpEngine.sol:468)
 *   withdrawPlvTo: requires amount <= plv, pays through the LIVE quote
 *                                     (PerpEngine.sol:1641-1645 -> _pushQuote :213)
 *   quote: flipped by syncGeneration only when NOTHING quote-denominated is left —
 *          `plv|tokYieldEth|insuranceEth|payoutOwedTotal == 0` AND the vault reports
 *          `hasQuoteStake() == false` (PerpEngine.sol, syncGeneration)
 * `lend`/`badDebt` mirror openLong (:800) and a total-loss long settle (:1143-1147).
 */
interface IQuoteStake { function hasQuoteStake() external view returns (bool); }

contract X3cEngine {
    address public quote;                 // address(0) = native
    uint256 public plv;
    uint256 public longOiEth;
    address public tokenAddr;
    uint256 public tokYieldCumulative;

    constructor(address tok) { tokenAddr = tok; }
    function currentToken() external view returns (address) { return tokenAddr; }
    function totalEth() external view returns (uint256) { return plv + longOiEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external pure returns (uint256) { return 0; }
    function freeToken() external pure returns (uint256) { return 0; }

    function fundFromVault(uint256 amount) external payable {
        if (quote == address(0)) require(msg.value == amount, "value");
        else MockQuoteToken(quote).transferFrom(msg.sender, address(this), amount);
        plv += amount;
    }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "PlvInsufficient");
        plv -= amount;
        if (quote == address(0)) { (bool ok,) = to.call{value: amount}(""); require(ok, "send"); }
        else require(MockQuoteToken(quote).transfer(to, amount), "xfer");
    }
    function fundTokenFromVault(uint256) external pure { revert("n/a"); }
    function withdrawPlvTokenTo(uint256, address) external pure { revert("n/a"); }
    function withdrawTokYieldTo(uint256, address) external pure { revert("n/a"); }

    // simulation of the real engine's own state transitions
    function lend(uint256 a) external { plv -= a; longOiEth += a; }       // openLong
    function longTotalLoss(uint256 a) external { longOiEth -= a; }        // settle, proceeds 0
    address public vaultAddr;
    function setVault(address v) external { vaultAddr = v; }
    /// Mirrors the real engine's post-fix guard, line for line.
    function adoptQuote(address q) external {
        require(plv == 0, "VaultStaked");
        require(!IQuoteStake(vaultAddr).hasQuoteStake(), "VaultStaked");
        quote = q;
    }
    receive() external payable {}
}

/**
 * X3c — `PerpEngine.syncGeneration`'s only vault guard is `plv != 0`, so a quote
 * rotation can complete while the vault still carries a QUEUED exit denominated
 * in the old asset. The queue keeps its full nominal (wei) value across the flip
 * — `_haircut` can never write a claim down to zero because the write-down is
 * always followed by `revert ZeroAmount()` — and then claims that number of units
 * of the NEW asset out of the next honest depositor's capital.
 */
contract X3cStaleQueueSurvivesRotation is Test {
    X3cEngine engine;
    PerpVault vault;
    MockQuoteToken tok;
    MockQuoteToken usdg;          // 6-decimal asset the treasury rotates into
    address alice = address(0xA11CE);   // queued exit, denominated in wei
    address bob   = address(0xB0B);     // honest depositor in the NEW quote

    function setUp() public {
        tok = new MockQuoteToken("Gen1", "G1", 18);
        engine = new X3cEngine(address(tok));
        vault = new PerpVault(address(engine), address(engine));
        engine.setVault(address(vault));
        usdg = new MockQuoteToken("USDG", "USDG", 6);
        vm.deal(alice, 100 ether);
        usdg.mint(bob, 1_000e6);
    }

    // ── helpers ──────────────────────────────────────────────────────────────
    function _aliceQueuesExit() internal returns (uint256 queued) {
        vm.prank(alice);
        uint256 sh = vault.depositEth{value: 10 ether}();
        engine.lend(8 ether);                       // a long borrows 80%
        vm.prank(alice);
        (, queued) = vault.withdrawEth(sh);         // 2 paid, 8 queued
    }
    function _claim(address who) internal returns (bool ok, uint256 paid) {
        vm.prank(who);
        try vault.claimPendingEth() returns (uint256 p) { ok = true; paid = p; } catch { ok = false; }
    }
    function _bobDepositsNewQuote(uint256 amount) internal {
        vm.startPrank(bob);
        usdg.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    function test_StaleQueueCannotSurviveTheRotationNorEatTheNewDeposit() public {
        uint256 queued = _aliceQueuesExit();
        uint256 plvAfterQueue = engine.plv();

        engine.longTotalLoss(8 ether);              // the long settles at a total loss
        uint256 backing = engine.totalEth();

        // ── 1. the rotation is REFUSED while the stale queue stands ─────────
        bool staleReported = vault.hasQuoteStake();
        bool rotatedWhileStale = _tryAdopt(address(usdg));

        // ── 2. and the write-down the invariant relies on now PERSISTS ──────
        //  This used to zero the entry and then `revert ZeroAmount()` on the very
        //  next line, rolling it back — so an 8 ETH claim against ZERO backing
        //  kept its full nominal forever.
        (bool wroteDown, uint256 writeDownPaid) = _claim(alice);
        uint256 aliceStillOwed = vault.pendingEthOf(alice);
        uint256 queueTotalAfter = vault.pendingEth();

        // ── 3. with the side genuinely empty the rotation goes through ──────
        bool emptyReported = vault.hasQuoteStake();
        bool rotatedWhenDrained = _tryAdopt(address(usdg));

        //  The bob-deposit leg lives in its OWN frame. Under `via_ir` this
        //  function held 14 locals and overflowed the stack ("Variable _89 is 1
        //  too deep"), which fails the WHOLE tree with no filename attached —
        //  it cost two other sessions a debugging cycle each before it was
        //  isolated. Splitting is the standard remedy on this profile; the same
        //  was already done for {_assertProRata} below.
        _assertBobsDepositIsHisOwn();

        // ── assertions ───────────────────────────────────────────────────────
        assertEq(queued, 8 ether, "8 ETH queued behind the utilisation cap");
        assertEq(plvAfterQueue, 0, "plv emptied paying the instant portion");
        assertEq(backing, 0, "engine backing is zero after the loss");

        assertTrue(staleReported, "the vault REPORTS its stale quote-side claim");
        assertFalse(rotatedWhileStale, "H-2: the quote cannot flip under a live queue");

        assertTrue(wroteDown, "the zero-backed claim is written down instead of reverting");
        assertEq(writeDownPaid, 0, "nothing is paid - there is nothing behind it");
        assertEq(aliceStillOwed, 0, "the write-down PERSISTS (was rolled back before)");
        assertEq(queueTotalAfter, 0, "and the queue total falls with it");

        assertFalse(emptyReported, "a drained side reports no quote stake");
        assertTrue(rotatedWhenDrained, "a drained vault CAN rotate - not bricked");

    }

    /// @dev Split out of the test above purely for the `via_ir` stack limit — the
    ///      assertions are unchanged and still run inside the same test.
    function _assertBobsDepositIsHisOwn() internal {
        _bobDepositsNewQuote(1_000e6);
        assertEq(engine.plv(), 1_000e6, "bob's 1000 USDG reaches the engine");

        (bool aliceClaimed, ) = _claim(alice);
        assertFalse(aliceClaimed, "the stale wei claim is NOT payable in USDG");
        assertEq(usdg.balanceOf(alice), 0, "alice takes nothing of bob's deposit");

        (uint256 bobRedeemableAfter,,) = vault.ethPosition(bob);
        assertGe(bobRedeemableAfter, 999e6, "bob's shares are worth his own money");
        assertEq(usdg.balanceOf(address(engine)), 1_000e6, "engine still holds all of it");
    }

    function _tryAdopt(address q) internal returns (bool ok) {
        try engine.adoptQuote(q) { ok = true; } catch { ok = false; }
    }

    /// Control: with NO rotation the same queue is bounded to its honest size.
    function test_Control_NoRotation_QueueTakesOnlyItsNominal() public {
        //  ── BOB JOINS BEFORE THE LOSS, NOT AFTER (red-team T3a) ───────────
        //  {PerpVault.deposit} now refuses while `pendingEth > engine.totalEth()`:
        //  a deposit made into an insolvent queue mints shares worth ~nothing and
        //  the haircut hands the newcomer's whole principal to the stale queue
        //  (measured: 10 ETH in, < 1 gwei out). This control is not about that —
        //  it is the no-rotation baseline showing alice's queued claim is bounded
        //  to its own nominal and cannot reach into bob's stake. Ordering bob's
        //  deposit BEFORE the loss keeps the vault solvent to its queue, so the
        //  guard is not in the way and the property under test is unchanged.
        _aliceQueuesExit();
        vm.deal(bob, 1_000 ether);
        vm.prank(bob);
        vault.deposit{value: 1_000 ether}(1_000 ether);
        uint256 markBefore = engine.totalEth();          // 1008 ETH
        engine.longTotalLoss(8 ether);                    // a REAL 8 ETH loss
        uint256 backingAfter = engine.totalEth();         // 1000 ETH
        (bool ok, uint256 paid) = _claim(alice);
        assertTrue(ok, "claim succeeds");

        //  ── INVERTED BY 6634f2a (stale-by-success) ─────────────────────────
        //  The ORIGINAL assertion, verbatim:
        //
        //      assertEq(paid, 8 ether, "bounded to the 8 ETH actually queued");
        //
        //  That equality encoded SENIORITY, not the bound. `longTotalLoss(8 ether)`
        //  on the line above is a real 8 ETH impairment of a 1008 ETH book, and
        //  the old queue took none of it. {_syncEthQueue} now scales the index by
        //  `backing / ethBackingMark` = 1000/1008 = 125/126, so alice pays her
        //  pro-rata 1/126 of her own claim and bob pays the rest as a live LP.
        //  Measured: 7936507936507936507 wei. The bound the test is NAMED for —
        //  "cannot reach into bob's stake" — is asserted below and is unchanged.
        _assertProRata(paid, markBefore, backingAfter);
    }

    /// @dev Split out to keep the control test under the viaIR stack limit.
    function _assertProRata(uint256 paid, uint256 markBefore, uint256 backingAfter) internal view {
        uint256 expected = (8 ether * backingAfter) / markBefore;
        assertEq(paid, expected, "pro-rata: 8 ETH scaled by backing/mark (1000/1008)");
        assertLt(paid, 8 ether, "strictly LESS than nominal - she bore her share of the loss");
        assertEq(vault.pendingEth(), 0, "and the queue is fully retired by the claim");
        //  bob's live stake absorbed the rest of the loss, and nothing more.
        //
        //  ── CORRECTED EXPECTED VALUE (this assertion's arithmetic was wrong) ──
        //  The previous expectation, verbatim:
        //
        //      assertApproxEqAbs(bobRedeemable, 1_000 ether - (8 ether - expected), 1e6,
        //          "bob bears exactly the remainder of the 8 ETH - alice took none of his principal");
        //
        //  `8 ether - expected` is 0.063492 ETH — ALICE's share of the loss, not
        //  bob's. That expectation had bob keep 999.9365 of 1000 while alice lost
        //  0.0635 of 8, so only 0.127 ETH of a REAL 8 ETH loss was borne by anyone:
        //  it did not conserve. Pari passu splits L in proportion to CLAIMS, not
        //  equally: on T = 1008, L = 8, alice's claim is 8 and bob's is 1000, so
        //      alice bears 8/1008 * 8    = 0.063492 ETH -> claim  7.936507 ETH
        //      bob   bears 1000/1008 * 8 = 7.936507 ETH -> stake 992.063492 ETH
        //  and 0.063492 + 7.936507 = 8 ETH exactly. Equivalently every position is
        //  scaled by the SAME factor backing/mark = 1000/1008, which is precisely
        //  what {_syncEthQueue} does to the index and what {assetsEth}, as the
        //  residual, does to live shares. So bob's value is 1000 * 1000/1008.
        (uint256 bobRedeemable,,) = vault.ethPosition(bob);
        assertApproxEqAbs(bobRedeemable, (1_000 ether * backingAfter) / markBefore, 1e6,
            "bob bears his pro-rata 1000/1008 of the 8 ETH - alice took none of his principal");
        //  ...and the two shares of the loss add back up to the whole loss.
        assertApproxEqAbs((8 ether - paid) + (1_000 ether - bobRedeemable), 8 ether, 1e6,
            "conservation: alice's share + bob's share == the realised 8 ETH loss");
    }
}
