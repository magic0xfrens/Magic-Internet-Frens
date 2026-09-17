// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockEngine, MockRegistry, MockToken} from "./R2Mock.sol";

/**
 * R2B — the TOKEN side never received the two fixes the ETH side got.
 *
 *   PerpVault.sol:333  claimPendingEth   : if (owed == 0) { emit ...; return 0; }
 *   PerpVault.sol:347  claimPendingEth   : if (paid == 0) { emit ...; return 0; }
 * vs
 *   PerpVault.sol:566  claimPendingToken : if (owed == 0) revert ZeroAmount();
 *   PerpVault.sol:569  claimPendingToken : if (paid == 0) revert ZeroAmount();
 *
 * Both reverts roll back the haircut written on the line above
 * (PerpVault.sol:565), so `pendingTok` can never be reduced once the token
 * backing has gone. Consequences proved below:
 *   (1) `pendingTok != 0` forever -> hasStakers() (PerpVault.sol:205) is true
 *       forever -> PerpEngine.setVault (PerpEngine.sol:2620) reverts BadParam
 *       for the life of the engine: a buggy vault can never be replaced.
 *   (2) depositToken (PerpVault.sol:507) has NO `QueueInsolvent` guard — the
 *       ETH side's deposit (PerpVault.sol:270) does — so the next token staker
 *       mints ~worthless shares and his principal is paid straight out to the
 *       stale queue.
 *
 * REGRESSION (fixed): claimPendingToken now banks the write-down on both
 * branches and depositToken carries the QueueInsolvent guard. The assertions
 * below are INVERTED: the queue drains, hasStakers releases, the new depositor
 * is refused while the queue is unbacked and keeps his principal afterwards.
 */
contract R2B_TokenQueueLatch is Test {
    MockEngine eng;
    MockRegistry reg;
    MockToken tok;
    PerpVault vault;

    address lpT = address(0x7011);   // the queued token staker
    address victim = address(0x71C71);

    function setUp() public {
        eng = new MockEngine();
        reg = new MockRegistry();
        tok = new MockToken();
        reg.set(address(tok));
        eng.setToken(address(tok));
        vault = new PerpVault(address(eng), address(reg));
        eng.setVault(address(vault));
        tok.mint(lpT, 1_000 ether);
        tok.mint(victim, 1_000 ether);
    }

    struct R {
        bool ownedZeroBranchReverted;
        bool paidZeroBranchReverted;
        uint256 pendingAfter;
        bool hasStakersAfter;
        uint256 victimShares;
        uint256 victimRedeemable;
        uint256 attackerClaimed;
        bool depositRefusedWhileInsolvent;
    }

    function _latch() internal returns (R memory r) {
        // 1. One token staker, everything lent to shorts (the normal state).
        vm.startPrank(lpT);
        tok.approve(address(vault), type(uint256).max);
        vault.depositToken(100 ether);
        vm.stopPrank();
        eng.lendToken(100 ether);              // plvToken 0, lentToken 100
        assertEq(eng.freeToken(), 0, "utilised");

        // 2. He queues out (free inventory is zero, so it all queues).
        uint256 s = vault.tokShareOf(lpT);
        vm.prank(lpT);
        (, uint256 queued) = vault.withdrawToken(s);
        assertApproxEqAbs(queued, 100 ether, 1e12, "queued");
        assertEq(vault.tokShares(), 0, "no live token shares");

        // 3. A death settle writes off the token debt the pool could not supply:
        //    PerpEngine._writeOffTok(id, unbought, false) -> shortOiToken -= amount
        //    (PerpEngine.sol:2225). Half here: backing 50 < claims 100.
        eng.writeOffTok(50 ether);
        assertEq(eng.totalTokenAssets(), 50 ether, "partial backing");

        // 3a. `paid == 0` branch: haircut computed, then thrown away by the revert.
        vm.prank(lpT);
        try vault.claimPendingToken() { r.paidZeroBranchReverted = false; }
        catch { r.paidZeroBranchReverted = true; }

        // 4. The rest is written off too: zero backing.
        eng.writeOffTok(50 ether);
        assertEq(eng.totalTokenAssets(), 0, "no backing at all");

        // 4-guard. REGRESSION: with pendingTok (50e18) standing against ZERO
        //    backing, the token side must now refuse new principal exactly as the
        //    ETH side does. Before the fix this deposit sailed through.
        vm.prank(victim); tok.approve(address(vault), type(uint256).max);
        vm.prank(victim);
        try vault.depositToken(100 ether) { r.depositRefusedWhileInsolvent = false; }
        catch { r.depositRefusedWhileInsolvent = true; }

        // 4a. `owed == 0` branch: same rollback.
        vm.prank(lpT);
        try vault.claimPendingToken() { r.ownedZeroBranchReverted = false; }
        catch { r.ownedZeroBranchReverted = true; }

        r.pendingAfter = vault.pendingTok();
        r.hasStakersAfter = vault.hasStakers();

        // 5. A fresh token staker arrives. The ETH side would refuse him
        //    (QueueInsolvent, PerpVault.sol:270). The token side does not.
        vm.startPrank(victim);
        tok.approve(address(vault), type(uint256).max);
        vault.depositToken(100 ether);
        vm.stopPrank();
        r.victimShares = vault.tokShareOf(victim);
        (r.victimRedeemable,,) = vault.tokenPosition(victim);

        // 6. ...and the stale queue takes his principal.
        uint256 b0 = tok.balanceOf(lpT);
        vm.prank(lpT);
        try vault.claimPendingToken() {} catch {}
        r.attackerClaimed = tok.balanceOf(lpT) - b0;
    }

    /// POSITIVE CONTROL: the identical sequence on the ETH side drains the queue
    /// and releases the side, because those two branches bank the write-down.
    function _ethControl() internal returns (uint256 pendingAfter) {
        MockEngine e2 = new MockEngine();
        MockRegistry r2 = new MockRegistry();
        PerpVault v2 = new PerpVault(address(e2), address(r2));
        e2.setVault(address(v2));
        address lp = address(0xE711);
        vm.deal(lp, 200 ether);
        vm.prank(lp); v2.depositEth{value: 100 ether}();
        e2.lend(100 ether);
        uint256 s = v2.ethShareOf(lp);
        vm.prank(lp); v2.withdrawEth(s);
        e2.absorbLentLoss(100 ether);            // total wipe-out
        vm.prank(lp); v2.claimPendingEth();      // banks the zero, does NOT revert
        pendingAfter = v2.pendingEth();
    }

    function test_R2B_token_queue_latches_and_eats_the_next_depositor() public {
        uint256 ethPending = _ethControl();
        R memory r = _latch();

        console2.log("ETH-side pendingEth after a total wipe-out:", ethPending);
        console2.log("TOKEN-side pendingTok after the same:      ", r.pendingAfter);
        console2.log("hasStakers() (gates PerpEngine.setVault):  ", r.hasStakersAfter);
        console2.log("victim shares:", r.victimShares);
        console2.log("victim redeemable token:", r.victimRedeemable);
        console2.log("stale queue claimed from victim principal:", r.attackerClaimed);

        // POSITIVE: the ETH side does release.
        assertEq(ethPending, 0, "ETH side banks the write-down and empties");

        // INVERTED (R2B(i)): both branches now BANK the write-down instead of
        // reverting it away, so the token queue drains exactly like the ETH one.
        assertFalse(r.paidZeroBranchReverted, "paid==0 branch banks the haircut, no revert");
        assertFalse(r.ownedZeroBranchReverted, "owed==0 branch banks the haircut, no revert");
        assertEq(r.pendingAfter, 0, "pendingTok drains to zero after a TOTAL wipe-out");
        assertFalse(r.hasStakersAfter, "hasStakers releases -> setVault is reachable again");

        // INVERTED (R2B(ii)): the insolvent-queue gate now protects the token side.
        assertTrue(r.depositRefusedWhileInsolvent, "depositToken refuses while the queue is unbacked");
        assertApproxEqAbs(r.victimRedeemable, 100 ether, 1e12, "victim's principal is intact, not confiscated");
        assertEq(r.attackerClaimed, 0, "the stale queue takes nothing from the new depositor");
    }
}
