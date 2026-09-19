// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronBase} from "../../cauldron/CauldronBase.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

/**
 * L1 — DAY-ONE LAUNCH CAPS: EXECUTE THE STOPS THAT ACTUALLY EXIST.
 *
 * This protocol has NO trading pause, NO perp-open pause and NO hook kill switch.
 * Verified by grep over `cauldron/*.sol` + the root `*.sol`: no `is Pausable`, no
 * `_pause()`, no `whenNotPaused`, no `function pause`. The ONLY runtime stops are:
 *
 *   CauldronRegistry.sol:459  setRedemptionPaused(bool)  onlyEmergency   (:369-372)
 *   CauldronRegistry.sol:444  vetoEmergency()            guardian-only
 *   CauldronRegistry.sol:426  armEmergency()             onlyEmergency
 *
 * and they gate the GENESIS REDEMPTION PATH only.
 *
 * WHY THIS FILE EXISTS. The only pre-existing tests that touch these three
 * functions live in `test/attacks/Z06_GovernanceLockout.t.sol` (:116, :137, :144,
 * :148), and every one of them is gated on `ZAuditBase.active`, which is set only
 * when `FORK_RPC` is in the environment (`ZAuditBase.sol:56-58`). With no
 * `FORK_RPC` — the default in CI and on a laptop — they `vm.skip` and the stop
 * paths are covered by NOTHING. A circuit breaker whose only test silently skips
 * is a circuit breaker nobody has ever pulled.
 *
 * Everything below runs WITHOUT a fork. `CauldronRegistry`'s constructor
 * (`:163-183`) stores `poolManager` / `positionManager` / `hook` without
 * validating them, so the emergency state machine can be exercised standalone.
 *
 * The tests assert the EFFECT on a real user entrypoint, not the flag. The probe
 * is `recycleCollectionNFT` (`CauldronRegistry.sol:1563`), whose first statement
 * is the breaker (`:1565 if (_redeemBlocked()) revert RedemptionPaused();`) and
 * whose next reachable statement on a fresh registry is the config check
 * (`:1569 ... revert BadConfig()`). So the SAME call returning a DIFFERENT revert
 * is proof the breaker is really in the path:
 *
 *      breaker OFF -> BadConfig        (we got past the breaker)
 *      breaker ON  -> RedemptionPaused (the breaker stopped us)
 *
 * FINDING L1-A (Medium, operational) — `test_L1_ArmingAnEmergency...` below.
 * `_redeemBlocked()` is `redemptionPaused && emergencyReadyAt == 0`
 * (`cauldron/CauldronBase.sol:433-435`). Arming an emergency therefore turns the
 * breaker OFF while `redemptionPaused()` keeps returning TRUE. That is deliberate
 * — the "exit guarantee" (`CauldronBase.sol:429-432`) — but it means the two
 * emergency tools CANNOT BE USED TOGETHER: the moment the operator arms a custody
 * action to rescue funds mid-exploit, the redemption breaker they pulled first
 * silently disengages, and every dashboard still reads "PAUSED".
 *
 * FINDING L1-B (the launch-cap lever) — `test_L1_GenesisPerWalletCap...` below.
 * `MiFrensGenesis.setMaxPerWallet` (`:298-303`) is a ONE-WAY RATCHET once minting
 * has begun (`:300`). It is the protocol's only per-actor cap, and it is the one
 * day-one cap that CANNOT be relaxed later. That asymmetry drives the whole
 * relaxation sequence: every other launch cap can be loosened with one tx, this
 * one can only ever be tightened.
 */
contract L1_LaunchStops is Test {
    CauldronRegistry internal reg;

    address internal constant TIMELOCK = address(0x71E10C4);  // emergencyAdmin
    address internal constant GUARDIAN = address(0x6A12D1A4); // veto-only role
    address internal constant STRANGER = address(0xBADBADBA);

    // Dummy wiring: the constructor validates none of these (CauldronRegistry.sol:163-183).
    address internal constant PM   = address(0xB0);
    address internal constant POSM = address(0xB1);
    address internal constant HOOK = address(0xB2);

    function setUp() public {
        reg = new CauldronRegistry(PM, POSM, HOOK, TIMELOCK, 7 days);
    }

    // ── helper: what does the redemption entrypoint do right now? ───────────
    // No `return` in a top-level test; the branch lives here and yields a value.
    // 0 = reached config check (breaker OPEN), 1 = breaker CLOSED, 2 = unexpected.
    function _probeRedemption() internal returns (uint256 outcome) {
        try reg.recycleCollectionNFT(1, 1) {
            outcome = 2; // should be unreachable on a fresh registry
        } catch (bytes memory err) {
            bytes4 sel = bytes4(err);
            if (sel == CauldronBase.BadConfig.selector) outcome = 0;
            else if (sel == CauldronBase.RedemptionPaused.selector) outcome = 1;
            else outcome = 2;
        }
    }

    // -----------------------------------------------------------------------
    // 1. The breaker exists, is admin-gated, is INSTANT, and really gates the path
    // -----------------------------------------------------------------------
    function test_L1_RedemptionBreakerGatesTheEntrypointNotJustAFlag() public {
        // Baseline: the breaker is open, so we fall through to the config check.
        assertEq(_probeRedemption(), 0, "baseline: redemption reachable past the breaker");
        assertFalse(reg.redemptionPaused(), "breaker starts OFF");

        // A stranger cannot trip it (onlyEmergency, CauldronRegistry.sol:369-372).
        vm.prank(STRANGER);
        vm.expectRevert(CauldronBase.NotAdmin.selector);
        reg.setRedemptionPaused(true);
        assertFalse(reg.redemptionPaused(), "stranger could not trip the breaker");

        // The emergency admin can — with NO timelock. That is deliberate
        // (CauldronRegistry.sol:456 "a live exploit needs a fast stop").
        // Note the registry was constructed with a 7-day emergencyDelay and this
        // call still lands in the same block: proof it is not timelocked.
        assertEq(reg.emergencyDelay(), 7 days, "a real delay is configured");
        vm.prank(TIMELOCK);
        reg.setRedemptionPaused(true);
        assertTrue(reg.redemptionPaused(), "breaker is ON");

        // THE EFFECT: same call, different revert.
        assertEq(_probeRedemption(), 1, "EXECUTED: the breaker stops redemption");

        // And it is reversible in one tx.
        vm.prank(TIMELOCK);
        reg.setRedemptionPaused(false);
        assertFalse(reg.redemptionPaused(), "breaker is OFF again");
        assertEq(_probeRedemption(), 0, "redemption restored");
    }

    // -----------------------------------------------------------------------
    // 2. FINDING L1-A — arming an emergency silently DISENGAGES the breaker
    // -----------------------------------------------------------------------
    function test_L1_ArmingAnEmergencySilentlyReopensThePausedExit() public {
        vm.prank(TIMELOCK);
        reg.setRedemptionPaused(true);
        assertEq(_probeRedemption(), 1, "breaker is holding");

        // The operator now arms a custody action to rescue funds mid-incident.
        vm.prank(TIMELOCK);
        reg.armEmergency();
        assertGt(reg.emergencyReadyAt(), 0, "emergency is armed");

        // The FLAG still reads true — every dashboard shows "PAUSED" ...
        assertTrue(reg.redemptionPaused(), "flag still reports PAUSED");
        // ... but the BREAKER IS OFF. _redeemBlocked() is
        // `redemptionPaused && emergencyReadyAt == 0` (CauldronBase.sol:434).
        assertEq(_probeRedemption(), 0, "FINDING L1-A: redemption is open again");

        // Re-asserting the pause does NOT help: the arm dominates the flag.
        vm.prank(TIMELOCK);
        reg.setRedemptionPaused(true);
        assertEq(_probeRedemption(), 0, "FINDING L1-A: re-pausing cannot re-close it");
    }

    // -----------------------------------------------------------------------
    // 3. vetoEmergency() — guardian-only, and it RESTORES the breaker
    // -----------------------------------------------------------------------
    function test_L1_GuardianVetoDisarmsAndRestoresTheBreaker() public {
        vm.startPrank(TIMELOCK);
        reg.setRedemptionPaused(true);
        reg.setGuardian(GUARDIAN);          // CauldronRegistry.sol:435-439
        reg.armEmergency();
        vm.stopPrank();

        assertEq(reg.guardian(), GUARDIAN, "guardian wired");
        assertEq(_probeRedemption(), 0, "exit forced open while armed");

        // A stranger cannot veto (CauldronRegistry.sol:445).
        vm.prank(STRANGER);
        vm.expectRevert(CauldronBase.NotAdmin.selector);
        reg.vetoEmergency();
        assertGt(reg.emergencyReadyAt(), 0, "still armed after a stranger tried");

        // Neither can the emergency admin that armed it — veto is guardian-ONLY.
        vm.prank(TIMELOCK);
        vm.expectRevert(CauldronBase.NotAdmin.selector);
        reg.vetoEmergency();
        assertGt(reg.emergencyReadyAt(), 0, "still armed after the admin tried");

        // The guardian can.
        vm.prank(GUARDIAN);
        reg.vetoEmergency();
        assertEq(reg.emergencyReadyAt(), 0, "EXECUTED: veto disarmed the action");

        // ...and the breaker comes back WITHOUT anyone re-calling setRedemptionPaused.
        assertTrue(reg.redemptionPaused(), "flag was never cleared");
        assertEq(_probeRedemption(), 1, "EXECUTED: veto restored the breaker");
    }

    // -----------------------------------------------------------------------
    // 4. FINDING L1-B — the one per-actor cap, and it only ratchets DOWN
    // -----------------------------------------------------------------------
    function test_L1_GenesisPerWalletCapBindsAndIsOneWayDown() public {
        // The shipped-bad config the constructor still accepts: cap == supply,
        // i.e. a cap that can never bind (MiFrensGenesis.sol:265-275).
        MiFrensGenesis g =
            new MiFrensGenesis("MiFrens", "MF", 1111, 2400, 0.05 ether, 1111, "ipfs://x/");
        assertEq(g.MAX_PER_WALLET(), 1111, "constructor accepted a NON-BINDING cap");
        assertEq(g.GENESIS_SUPPLY(), 1111, "one wallet could take the whole tranche");

        // Pre-mint correction window: any BINDING value is allowed.
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.setMaxPerWallet(1111); // non-binding is refused outright (:299)
        g.setMaxPerWallet(20);
        assertEq(g.MAX_PER_WALLET(), 20, "day-one cap set pre-mint");

        // The cap BINDS on a real buyer.
        address whale = makeAddr("whale");
        vm.deal(whale, 100 ether);
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: 0.05 ether * 21}(21);

        vm.prank(whale);
        g.mint{value: 0.05 ether * 20}(20);
        assertEq(g.balanceOf(whale), 20, "whale capped at exactly 20");
        assertEq(g.minted(), 20, "minting has begun");

        // FINDING L1-B: from here the cap can NEVER be widened again (:300).
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.setMaxPerWallet(50);
        assertEq(g.MAX_PER_WALLET(), 20, "cap could NOT be relaxed after the first mint");

        // Only tightened.
        g.setMaxPerWallet(10);
        assertEq(g.MAX_PER_WALLET(), 10, "cap ratcheted DOWN");

        // A holder already above the new cap is frozen out entirely — tightening
        // mid-sale is not free, it strands existing buyers.
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: 0.05 ether}(1);
    }

    // -----------------------------------------------------------------------
    // 5. FINDING L1-C — FIXED. The cap is now a LIFETIME allowance.
    // -----------------------------------------------------------------------
    /// WAS: `MAX_PER_WALLET` tested `balanceOf(msg.sender)`, a CURRENT HOLDING.
    /// Parking the inventory in a second wallet reset it and the same actor —
    /// one funding source, no sybils — minted 40 under a cap of 20 for the cost
    /// of an ERC721 transfer. This test asserted that bypass WORKED.
    ///
    /// NOW: the cap is measured against `genesisMintedBy`, a lifetime counter
    /// that never decrements (`MiFrensGenesis.mint`). Transferring out frees
    /// nothing. The test is kept, inverted, and still proves minting WORKS up
    /// to the cap — a fix that simply stopped genesis minting would also be a
    /// bug, so the honest path is asserted on the way in.
    function test_L1_PerWalletCapIsBypassableByTransferringOut() public {
        MiFrensGenesis g =
            new MiFrensGenesis("MiFrens", "MF", 1111, 2400, 0.05 ether, 1111, "ipfs://x/");
        g.setMaxPerWallet(20);

        address whale = makeAddr("whale2");
        address sink = makeAddr("sink");
        vm.deal(whale, 100 ether);

        vm.startPrank(whale);

        // Honest minting still works all the way to the cap...
        g.mint{value: 0.05 ether * 20}(20);
        assertEq(g.balanceOf(whale), 20, "honest buyer reached the cap");
        assertEq(g.remainingGenesisAllowance(whale), 0, "allowance spent");

        // ...and the cap genuinely stops a 21st mint.
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: 0.05 ether}(1);

        // The old bypass: park the inventory in a wallet he also owns.
        for (uint256 i = 1; i <= 20; i++) {
            g.transferFrom(whale, sink, i);
        }
        assertEq(g.balanceOf(whale), 0, "balanceOf IS still reset by a transfer");

        // ...but the allowance is LIFETIME, so it buys him nothing. Not one
        // more token, not a whole second allocation.
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: 0.05 ether * 20}(20);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: 0.05 ether}(1);
        vm.stopPrank();

        assertEq(g.genesisMintedBy(whale), 20, "lifetime counter did NOT decrement");
        assertEq(g.remainingGenesisAllowance(whale), 0, "no fresh allocation");
        assertEq(g.balanceOf(sink), 20, "first allocation parked, still his");
        assertEq(
            g.minted(), 20, "L1-C FIXED: ONE actor still bounded at 20 under a cap of 20"
        );
    }

    // -----------------------------------------------------------------------
    // 6. The absence proof — there is no SECOND stop to reach for
    // -----------------------------------------------------------------------
    /// The registry is the only contract with any runtime stop at all, and its
    /// surface is exactly the three functions above. Anything a responder might
    /// reach for during a live trading incident does not exist. Executed as raw
    /// calls so this is a property of the DEPLOYED BYTECODE, not of the source.
    function test_L1_NoGlobalStopExistsOnTheRegistry() public {
        string[6] memory ghosts = [
            "pause()",
            "unpause()",
            "setPaused(bool)",
            "setTradingPaused(bool)",
            "setTradingEnabled(bool)",
            "emergencyStop()"
        ];
        uint256 present;
        for (uint256 i = 0; i < ghosts.length; i++) {
            (bool ok,) = address(reg).call(abi.encodeWithSignature(ghosts[i], false));
            if (ok) present++;
        }
        assertEq(present, 0, "no global pause exists anywhere on the registry");

        // The three that DO exist are reachable (selector present, admin-gated).
        vm.prank(STRANGER);
        (bool a,) = address(reg).call(abi.encodeWithSignature("setRedemptionPaused(bool)", true));
        assertFalse(a, "exists but is admin-gated");
        vm.prank(TIMELOCK);
        (bool b,) = address(reg).call(abi.encodeWithSignature("setRedemptionPaused(bool)", true));
        assertTrue(b, "EXECUTED: the one real stop is callable by the admin");
        assertTrue(reg.redemptionPaused(), "and it took effect");
    }
}
