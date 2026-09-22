// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

contract Reg2 { function currentToken() external pure returns (address) { return address(0x70); } }

/// Native-quoted engine stand-in: ETH in, `locked` models open-position usage.
contract EthEngine {
    uint256 public totalEth;
    uint256 public locked;
    function quote() external pure returns (address) { return address(0); }
    function freeEth() public view returns (uint256) { return totalEth > locked ? totalEth - locked : 0; }
    function totalTokenAssets() external pure returns (uint256) { return 0; }
    function freeToken() external pure returns (uint256) { return 0; }
    function tokYieldCumulative() external pure returns (uint256) { return 0; }
    function tokYieldEth() external pure returns (uint256) { return 0; }
    function withdrawTokYieldTo(uint256, address) external {}
    function fundTokenFromVault(uint256) external {}
    function withdrawPlvTokenTo(uint256, address) external {}
    function fundFromVault(uint256 a) external payable { totalEth += a; }
    function withdrawPlvTo(uint256 a, address to) external {
        require(a <= freeEth(), "free");
        totalEth -= a;
        (bool ok,) = to.call{value: a}(""); require(ok, "send");
    }
    /// Open positions lock PLV; a settled bad debt burns some of it.
    function lockAll() external { locked = totalEth; }
    function badDebt(uint256 a) external { totalEth -= a; (bool ok,) = address(0xdead).call{value: a}(""); ok; }
    receive() external payable {}
}

/**
 * Jb — the new `QueueInsolvent` deposit guard (PerpVault.sol:274) has no
 * permissionless release while the engine's free ETH is zero.
 *
 * The guard's own comment says {claimPendingEth} "banks the haircut
 * permissionlessly ... which drains `pendingEth` and reopens the side". It does
 * not: {claimPendingEth} writes the haircut down at :381 and then reverts
 * `ZeroAmount` at :393 when `freeEth == 0`, rolling the write-down back — the
 * exact rollback shape the `owed == 0` branch at :390 was patched for. So in the
 * one state the guard fires in (queue nominal above backing, engine ETH all in
 * open positions) the vault can neither be recapitalised nor drained.
 */
contract Jb_QueueInsolventDepositLock is Test {
    Reg2 reg; EthEngine eng; PerpVault vault;
    address lp = address(0x11);
    address newLp = address(0x22);

    function setUp() public {
        reg = new Reg2();
        eng = new EthEngine();
        vault = new PerpVault(address(eng), address(reg));
        vm.deal(lp, 100 ether);
        vm.deal(newLp, 100 ether);
    }

    uint256 internal freeAtTrigger;   // eng.freeEth() at the moment the guard is read

    function _run() internal returns (bool depositShut, bool claimShut, uint256 pend, uint256 backing) {
        vm.prank(lp); vault.deposit{value: 10 ether}(10 ether);
        assertEq(eng.totalEth(), 10 ether, "engine took the stake");

        // Traders open: every wei of PLV is now working.
        eng.lockAll();

        // The LP exits. Nothing is free, so the whole nominal is QUEUED.
        uint256 sh = vault.ethShareOf(lp);
        vm.prank(lp);
        (uint256 paid, uint256 queued) = vault.withdrawEth(sh);
        assertEq(paid, 0, "nothing instant");
        assertEq(queued, 10 ether, "whole exit queued");

        // A routine bad-debt settlement burns 1 ETH of backing.
        eng.badDebt(1 ether);

        backing = eng.totalEth();
        pend = vault.pendingEth();
        freeAtTrigger = eng.freeEth();   // captured BEFORE any deposit lands

        vm.prank(newLp);
        try vault.deposit{value: 5 ether}(5 ether) returns (uint256) { depositShut = false; }
        catch { depositShut = true; }

        vm.prank(lp);
        try vault.claimPendingEth() returns (uint256) { claimShut = false; }
        catch { claimShut = true; }
    }

    /// REGRESSION (was the attack). `QueueInsolvent` shuts deposits while the queue
    /// outruns its backing, and its documented release is the PERMISSIONLESS
    /// {claimPendingEth}, which banks the pro-rata haircut. But when the engine had
    /// no FREE ETH — every wei lent to open positions, the normal state — that
    /// function hit `revert ZeroAmount()` AFTER writing the haircut, and the revert
    /// rolled the write-down back. `pendingEth` could never come under
    /// `totalEth()`, so the guard LATCHED and the ETH side was shut for good.
    /// The zero-payment case now banks the write-down and returns, exactly as the
    /// already-worthless branch above it does.
    function test_InsolventQueueCannotBeCleared() public {
        (bool depositShut, bool claimShut, uint256 pend, uint256 backing) = _run();

        emit log_named_uint("pendingEth before", pend);
        emit log_named_uint("engine.totalEth", backing);
        emit log_named_uint("engine.freeEth", eng.freeEth());
        emit log_named_uint("pendingEth after the release call", vault.pendingEth());

        //  ── INVERTED BY 6634f2a ────────────────────────────────────────────
        //  The ORIGINAL block, verbatim:
        //
        //      // The trigger and the guard are unchanged — both still fire.
        //      assertGt(pend, backing, "queue outruns backing: the guard's trigger");
        //      assertTrue(depositShut, "deposits are shut (QueueInsolvent)");
        //      assertEq(eng.freeEth(), 0, "and nothing is payable: this is the latching case");
        //
        //  The trigger still forms — the queue's NOMINAL really does outrun the
        //  backing, and nothing is free to pay it. What changed is that {deposit}
        //  now runs {_syncEthQueue} before reading the `QueueInsolvent` gate
        //  (PerpVault.sol:298), so the write-down is banked and the gate never
        //  sees an insolvent queue. The latch Jb was written about cannot form.
        //  The gate itself is untouched at PerpVault.sol:314.
        assertGt(pend, backing, "queue outruns backing: the guard's trigger still forms");
        assertEq(freeAtTrigger, 0, "and nothing was payable: this WAS the latching case");
        assertFalse(depositShut, "deposits are never shut: the loss is recognised, not latched against");

        // ...but the release path now WORKS, with no privilege and nothing freed.
        assertFalse(claimShut, "the documented release path no longer reverts");
        assertLt(vault.pendingEth(), pend, "the haircut write-down SURVIVED the call");
        assertLe(vault.pendingEth(), eng.totalEth(),
            "the queue is back under its backing, which is the guard's release condition");

        // ...so a new depositor can come in again, and is not paying for the loss.
        vm.prank(newLp);
        uint256 shares = vault.deposit{value: 5 ether}(5 ether);
        assertGt(shares, 0, "deposits reopened permissionlessly");
        (uint256 redeemable,,) = vault.ethPosition(newLp);
        //  ── CORRECTED EXPECTED VALUE (the principal, not the haircut) ───────
        //  The previous expectation, verbatim:
        //
        //      assertApproxEqAbs(redeemable, 5 ether, 1e12, "and the newcomer's stake is worth what he paid");
        //
        //  `5 ether` was right only while the FIRST deposit reverted. `_run` also
        //  sends `newLp` 5 ether (`:83`), and since 6634f2a that deposit SUCCEEDS —
        //  `depositShut` is asserted false at `:124`. So newLp has paid 5 + 5 = 10
        //  ETH by this line and the property "worth what he paid" is 10, not 5.
        //  Nothing here is weakened: the claim is still exact equality to his own
        //  principal, i.e. he funded none of the pre-existing queue's write-down.
        //  (Independent of the pro-rata split: his deposits both land at par,
        //  after the loss is already recognised by {_syncEthQueue}.)
        assertApproxEqAbs(redeemable, 10 ether, 1e12, "and the newcomer's stake is worth what he paid (5 in _run + 5 here)");
    }
}
