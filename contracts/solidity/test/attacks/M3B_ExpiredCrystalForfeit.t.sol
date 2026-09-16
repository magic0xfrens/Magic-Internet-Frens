// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {ICauldronCollection} from "../../cauldron/ICauldron.sol";

/// @notice M3B — REGRESSION for the expired-crystal forfeit.
///
///  ORIGINAL BREAK: a paid crystal that nobody resolved inside two 256-block
///  windows was FORFEITED — resolved as a guaranteed loss regardless of the odds
///  the player paid for. `blockhash` is zero past 256 blocks, which is an EVM
///  constant, not a tunable; on Robinhood Chain (measured 0.1012 s/block) one
///  window is 25.9 s and the forfeit lands at 51.8 s. No attacker required.
///
///  THE FIX ({GachaLib} SEED_SLOT): any single `resolveTickets` call that lands
///  while a batch's commit-block hash is still live PINS that hash into storage,
///  after which the batch's outcome is frozen and the wall-clock deadline no
///  longer applies. The pinned value is the ORIGINAL commit seed — the one the
///  player could already read off-chain — so pinning hands out no second draw.
///
///  WHAT DELIBERATELY DID NOT CHANGE: a batch that NO call touches inside its
///  window still gets exactly one re-anchor and then commits a loss. That
///  terminal forfeit is the only ending a player who peeks at a losing seed and
///  declines to resolve cannot profit from. `_gamedExpiry` below asserts it is
///  still there: expiry must never become a refund or an extra roll.
contract M3B_ExpiredCrystalForfeit is YBase {
    CauldronGachaRouter internal router;

    struct Run {
        bool ran;
        uint256 opened;
        uint16 odds;
        uint256 pendingAfterCommit;
        uint256 processedFirst;   // resolve attempt after window #1
        uint256 processedSecond;  // resolve after window #2
        uint256 wonSecond;
        uint256 pendingEnd;
        uint256 mintedEnd;
        uint256 mintedStart;
        uint256 readyEnd;
        uint256 mintedStart2;   // credit already banked before the forfeit
        uint256 blocksPerWindow;
        uint256 blocksElapsed;
    }

    function setUp() public {
        _boot(50 ether, 0);
        if (!active) return;
        router = new CauldronGachaRouter(pm, address(hook), address(registry), address(this));
        hook.setOpener(address(router), true);
        vm.roll(vm.getBlockNumber() + 40); // past the anti-snipe surtax window
    }

    // ---- positive control: resolved promptly, the crystal actually rolls ----
    function _control() internal returns (Run memory r) {
        if (!active) return r;
        r.ran = true;
        vm.prank(victim, victim);
        r.opened = router.playChurn{value: 5 ether}(0, 10, 0, 5);
        r.pendingAfterCommit = hook.pendingOf(victim);
        vm.roll(vm.getBlockNumber() + 1);
        (r.processedFirst, r.wonSecond) = hook.resolveTickets(30);
        r.pendingEnd = hook.pendingOf(victim);
        r.mintedEnd = ICauldronCollection(hook.collection()).totalMinted();
    }

    // ---- THE FIX: one touch inside the window immunises the batch forever ----
    //  The touch resolves NOTHING (maxCount 0 — the shape the gas-capped in-swap
    //  path takes when the queue is deeper than its budget). Pre-fix this batch
    //  was forfeited exactly like `_gamedExpiry` below; post-fix it rolls at its
    //  true 9,000 bps hours later.
    function _pinnedSurvivesLongSilence() internal returns (Run memory r) {
        if (!active) return r;
        r.ran = true;
        r.mintedStart = ICauldronCollection(hook.collection()).totalMinted();

        uint256 bi = 1; // the control pushed batch 0
        vm.prank(attacker, attacker);
        r.opened = router.playChurn{value: 5 ether}(0, 10, 0, 5);
        r.pendingAfterCommit = hook.pendingOf(attacker);
        (address bp,,, uint16 odds,,) = hook.batches(bi);
        require(bp == attacker, "batch index assumption broken");
        r.odds = odds;

        // ONE touch inside window #1 that rolls nothing but pins the seed.
        uint256 b0 = vm.getBlockNumber();
        vm.roll(b0 + 1);
        assertEq(vm.getBlockNumber(), b0 + 1, "roll #1 did not land");
        (r.processedFirst,) = hook.resolveTickets(0);

        // Now go dark for ~8 blockhash windows (~3.4 minutes of RH wall clock).
        uint256 b1 = vm.getBlockNumber();
        vm.roll(b1 + 2048);
        r.blocksElapsed = vm.getBlockNumber() - b1;
        assertEq(r.blocksElapsed, 2048, "roll #2 did not land");

        (r.processedSecond, r.wonSecond) = hook.resolveTickets(30);
        r.pendingEnd = hook.pendingOf(attacker);
        r.mintedEnd = ICauldronCollection(hook.collection()).totalMinted();
    }

    // ---- the anti-gaming backstop: untouched two windows still forfeit ----
    function _gamedExpiry() internal returns (Run memory r) {
        if (!active) return r;
        r.ran = true;
        r.blocksPerWindow = 300; // > 256, the blockhash horizon
        r.mintedStart = ICauldronCollection(hook.collection()).totalMinted();

        vm.prank(victim, victim);
        r.opened = router.playChurn{value: 5 ether}(0, 10, 0, 5);
        r.pendingAfterCommit = hook.pendingOf(victim);
        //  Credit LEFT OVER after the commit (the play's swap fees mint more
        //  credit than 5 crystals cost). The forfeit must not add to it.
        r.mintedStart2 = hook.crystalsReady(victim);

        // WINDOW 1 elapses with nobody calling resolveTickets at all.
        uint256 b0 = vm.getBlockNumber();
        vm.roll(b0 + r.blocksPerWindow);
        assertEq(vm.getBlockNumber() - b0, r.blocksPerWindow, "roll #1 did not land");
        (r.processedFirst,) = hook.resolveTickets(30); // re-anchors, rolls nothing

        // WINDOW 2 elapses.
        uint256 b1 = vm.getBlockNumber();
        vm.roll(b1 + r.blocksPerWindow);
        assertEq(vm.getBlockNumber() - b1, r.blocksPerWindow, "roll #2 did not land");
        (r.processedSecond, r.wonSecond) = hook.resolveTickets(30);

        r.pendingEnd = hook.pendingOf(victim);
        r.mintedEnd = ICauldronCollection(hook.collection()).totalMinted();
        r.readyEnd = hook.crystalsReady(victim);
    }

    function test_M3B_two_missed_windows_destroy_a_paid_crystal() public {
        Run memory ctl = _control();
        Run memory fix = _pinnedSurvivesLongSilence();
        Run memory bad = _gamedExpiry();

        console2.log("CTL  opened     ", ctl.opened);
        console2.log("CTL  processed  ", ctl.processedFirst);
        console2.log("CTL  minted     ", ctl.mintedEnd);
        console2.log("PIN  opened     ", fix.opened);
        console2.log("PIN  oddsBps    ", fix.odds);
        console2.log("PIN  procTouch  ", fix.processedFirst);
        console2.log("PIN  blocksDark ", fix.blocksElapsed);
        console2.log("PIN  procLate   ", fix.processedSecond);
        console2.log("PIN  wonLate    ", fix.wonSecond);
        console2.log("GAME opened     ", bad.opened);
        console2.log("GAME proc#1     ", bad.processedFirst);
        console2.log("GAME proc#2     ", bad.processedSecond);
        console2.log("GAME won#2      ", bad.wonSecond);
        console2.log("GAME pendingEnd ", bad.pendingEnd);
        console2.log("GAME readyPre   ", bad.mintedStart2);
        console2.log("GAME readyEnd   ", bad.readyEnd);

        assertTrue(ctl.ran && fix.ran && bad.ran, "fork inactive: FORK_RPC unset");

        // POSITIVE CONTROL: a promptly-resolved batch really does roll.
        assertGt(ctl.opened, 0, "control opened nothing");
        assertEq(ctl.processedFirst, ctl.opened, "control did not resolve its crystals");

        // THE FIX. Pre-fix these three lines read 0 / 5 / 0 — the batch was
        // forfeited after the same two silent windows.
        assertGt(fix.opened, 0, "pinned run opened nothing");
        assertGe(uint256(fix.odds), 5000, "odds too low to make the point");
        assertEq(fix.processedFirst, 0, "the pinning touch must roll nothing");
        assertEq(fix.processedSecond, fix.opened, "pinned batch must still resolve");
        assertGt(fix.wonSecond, 0, "a 9,000-bps batch pinned in-window must still be able to WIN");
        assertGt(fix.mintedEnd, fix.mintedStart, "the win must have minted");
        assertEq(fix.pendingEnd, 0, "pinned crystals consumed");

        // THE ANTI-GAMING BACKSTOP. Letting a draw expire untouched must stay a
        // LOSS: no mint, no refund of credit, no extra roll. If any of these
        // flip, expiry has become a free option on a draw the player has already
        // peeked at, which is strictly worse than the bug this file fixes.
        assertGt(bad.opened, 0, "gamed run opened nothing");
        assertEq(bad.processedFirst, 0, "window #1 should only re-anchor");
        assertEq(bad.processedSecond, bad.opened, "window #2 should force-resolve");
        assertEq(bad.wonSecond, 0, "an untouched twice-expired crystal must not win");
        assertEq(bad.mintedEnd, bad.mintedStart, "forfeit must not mint");
        assertEq(bad.pendingEnd, 0, "crystals consumed, not re-queued");
        assertEq(bad.readyEnd, bad.mintedStart2, "forfeit must NOT refund credit (that would be a free re-roll)");
    }
}
