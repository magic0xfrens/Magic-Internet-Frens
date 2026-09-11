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

        _bobDepositsNewQuote(1_000e6);
        uint256 plvAfterBob = engine.plv();

        (bool aliceClaimed, ) = _claim(alice);
        uint256 aliceUsdg = usdg.balanceOf(alice);
        (uint256 bobRedeemableAfter,,) = vault.ethPosition(bob);

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

        assertEq(plvAfterBob, 1_000e6, "bob's 1000 USDG reaches the engine");
        assertFalse(aliceClaimed, "the stale wei claim is NOT payable in USDG");
        assertEq(aliceUsdg, 0, "alice takes nothing of bob's deposit");
        assertGe(bobRedeemableAfter, 999e6, "bob's shares are worth his own money");
        assertEq(usdg.balanceOf(address(engine)), 1_000e6, "engine still holds all of it");
    }

    function _tryAdopt(address q) internal returns (bool ok) {
        try engine.adoptQuote(q) { ok = true; } catch { ok = false; }
    }

    /// Control: with NO rotation the same queue is bounded to its honest size.
    function test_Control_NoRotation_QueueTakesOnlyItsNominal() public {
        _aliceQueuesExit();
        engine.longTotalLoss(8 ether);
        vm.deal(bob, 1_000 ether);
        vm.prank(bob);
        vault.deposit{value: 1_000 ether}(1_000 ether);
        (bool ok, uint256 paid) = _claim(alice);
        assertTrue(ok, "claim succeeds");
        assertEq(paid, 8 ether, "bounded to the 8 ETH actually queued");
    }
}
