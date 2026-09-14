// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {FinalAuditBase} from "../final/FinalAuditBase.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * GACHA1 — the crystal-resolution loop after it moved into the linked library
 * {GachaLib} (CauldronHook.sol:2442, GachaLib.sol:60-112).
 *
 * The extraction's ONE semantic change: `batchCursor` and `outstandingCrystals`
 * are read into the library BY VALUE at call start and written back by the hook
 * AFTER the call returns (CauldronHook.sol:2446-2447), where before they were
 * hook storage the loop touched directly. Any re-entry that lands inside the
 * library call therefore works from a stale copy of both scalars.
 *
 * The loop makes an external call per win — `ICauldronCollection(col).mint(player)`
 * (GachaLib.sol:98) — and {CauldronCollection._update} (CauldronCollection.sol:174-177)
 * routes EVERY mint through the ERC-721C transfer validator, an arbitrary
 * contract address the collection's `deployer` (= the registry, line 156) can set.
 * So control IS handed out mid-loop. These tests establish (a) that it is handed
 * out, (b) what stops the re-entry today, (c) that the storage-reference writes
 * still land in the hook.
 */
contract GACHA1_ResolveLoopExtraction is FinalAuditBase {
    CauldronCollection internal col;
    address internal constant PM_STUB = address(0xBEEF02);
    address internal player;

    uint256 internal constant NFT_CREDIT_SLOT = 29; // forge inspect CauldronHook storageLayout

    function setUp() public {
        player = address(this);
        _deployOffchain(PM_STUB);
        col = new CauldronCollection(
            "Creature", "CRT", address(hook), address(registry), 1000,
            MetadataMode.BaseURI, "ipfs://c/", address(0), address(0), 0
        );
        vm.prank(address(registry));
        hook.setCollection(address(col));
        hook.setOpener(address(this), true);
        vm.roll(1000);
    }

    function _grantCredit(address who, uint256 amount) internal {
        uint256 epoch = hook.creditEpoch();
        bytes32 inner = keccak256(abi.encode(epoch, NFT_CREDIT_SLOT));
        bytes32 slot = keccak256(abi.encode(who, inner));
        vm.store(address(hook), slot, bytes32(amount));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // A. Control IS handed out inside the library loop — what catches the re-entry
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Probe A1: a validator that merely OBSERVES (no state write). It tries
    ///      to re-enter the resolve loop; if the re-entry ever returns, it reverts
    ///      with Reentered() so the outer call cannot hide it.
    function _probeReentry() internal returns (bool resolveSucceeded, uint256 mintedAfter) {
        _grantCredit(player, type(uint128).max);
        uint256 n = hook.commitCrystals(player, 8, 0.5 ether); // 0.5 ETH ⇒ maxOddsBps
        require(n == 8, "8 crystals");
        vm.roll(vm.getBlockNumber() + 1);

        ProbeValidator v = new ProbeValidator(address(hook));
        vm.prank(address(registry));
        col.setTransferValidator(address(v));

        try hook.resolveTickets(8) { resolveSucceeded = true; } catch { resolveSucceeded = false; }
        mintedAfter = col.totalMinted();
        require(hook.outstandingTickets() == 0, "8 crystals not fully resolved");
        require(hook.outstandingTickets() == hook.pendingOf(player), "outstanding != pending");
    }

    /// @dev Probe A2: an identical validator that writes ONE storage slot. If the
    ///      collection reached it by CALL this succeeds; under STATICCALL the write
    ///      traps and the whole resolve reverts — which is how we prove the
    ///      validator is a read-only frame and cannot re-enter with side effects.
    function _probeStateWrite() internal returns (bool resolveSucceeded, uint256 mintedDuring) {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, 2, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);

        WritingValidator v = new WritingValidator();
        vm.prank(address(registry));
        col.setTransferValidator(address(v));

        uint256 mintedBefore = col.totalMinted();
        try hook.resolveTickets(2) { resolveSucceeded = true; } catch { resolveSucceeded = false; }
        mintedDuring = col.totalMinted() - mintedBefore;
    }

    function test_GACHA1a_mint_yields_only_into_a_static_frame() public {
        (bool ok, uint256 mintedAfter) = _probeReentry();
        (bool writeResolveOk, uint256 mintedWithWriter) = _probeStateWrite();

        emit log_named_string("resolve with observing validator", ok ? "completed" : "REVERTED");
        emit log_named_uint("NFTs minted", mintedAfter);
        emit log_named_uint("NFTs minted with a STORAGE-WRITING validator", mintedWithWriter);
        emit log_named_string("resolve with writing validator", writeResolveOk ? "completed" : "REVERTED");

        // (a) The loop does hand execution to a third-party contract mid-flight,
        //     but it cannot WRITE: `validateTransfer` is `external view`, so the
        //     mint reverts. Since GACHA1-b that revert is CAUGHT — resolution
        //     finishes and the crystals are recorded as losses instead of wedging
        //     the FIFO — so "cannot write" now shows up as "nothing minted"
        //     rather than as "the whole call reverted".
        assertEq(mintedWithWriter, 0, "a storage-writing validator must not be able to mint");
        assertTrue(writeResolveOk, "FIXED (GACHA1-b): a failing mint must not wedge resolution");
        // (b) ...but only as a STATICCALL (ICreatorToken.sol:8 `external view`), so
        //     the stale by-value scalars can never be observed by a mutating re-entry.
        assertTrue(ok, "an observing validator broke resolution");
        assertGt(mintedAfter, 0, "wins still minted");
        // (c) Accounting intact after the observing run (checked inside the helper,
        //     before the second probe enqueues its own 2 crystals).
        assertEq(mintedAfter, 7, "7 of 8 crystals won at 90% odds");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B. A validator that REJECTS the hook's mint halts the FIFO for everybody
    // ─────────────────────────────────────────────────────────────────────────

    function _blockedQueue()
        internal
        returns (bool resolveReverts, uint256 outstandingWhileBlocked, bool victimStuck)
    {
        address other = address(0xB0B);
        _grantCredit(player, type(uint128).max);
        _grantCredit(other, type(uint128).max);
        hook.commitCrystals(player, 4, 0.5 ether); // batch 0 — head of the FIFO
        hook.commitCrystals(other, 4, 0.5 ether);  // batch 1 — queued behind it
        vm.roll(vm.getBlockNumber() + 1);

        RejectValidator v = new RejectValidator();
        vm.prank(address(registry));
        col.setTransferValidator(address(v));

        try hook.resolveTickets(30) { resolveReverts = false; }
        catch { resolveReverts = true; }
        outstandingWhileBlocked = hook.outstandingTickets();
        victimStuck = hook.pendingOf(other) == 4;
    }

    function test_GACHA1b_FIXED_rejectingValidatorNoLongerWedgesTheFifo() public {
        (bool resolveReverts, uint256 outstanding, bool victimStuck) = _blockedQueue();

        emit log_named_string("resolveTickets reverts", resolveReverts ? "YES" : "no");
        emit log_named_uint("crystals stuck", outstanding);

        //  FIXED (GACHA1-b): a reverting mint is caught and recorded as a loss,
        //  so the cursor passes the batch and nobody behind it is wedged.
        assertFalse(resolveReverts, "FIXED: resolve must survive a rejecting validator");
        assertEq(outstanding, 0, "FIXED: every crystal resolved (as losses), none stuck");
        assertFalse(victimStuck, "FIXED: the unrelated player's crystals drained too");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // C. Storage-reference semantics: the expired-seed RE-STAMP must land in the
    //    hook's own `batches` array, not in a library-local copy.
    // ─────────────────────────────────────────────────────────────────────────

    function _restamp() internal returns (uint48 before_, uint48 after_, uint256 outstandingAfter) {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, 3, 0.5 ether);
        (,, before_,,,) = hook.batches(0);
        vm.roll(vm.getBlockNumber() + 300); // seed aged out of the 256-block window
        hook.resolveTickets(30);
        (,, after_,,,) = hook.batches(0);
        outstandingAfter = hook.outstandingTickets();
    }

    function test_GACHA1c_expired_seed_restamp_writes_through_to_hook_storage() public {
        (uint48 before_, uint48 after_, uint256 outstandingAfter) = _restamp();

        emit log_named_uint("commitBlock before", before_);
        emit log_named_uint("commitBlock after ", after_);

        assertGt(after_, before_, "library write to b.commitBlock did NOT reach hook storage");
        assertEq(uint256(after_), vm.getBlockNumber(), "re-stamped to the current block");
        assertEq(outstandingAfter, 3, "re-stamp consumes nothing");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // D. Events emitted from inside the DELEGATECALL must carry the HOOK address
    //    and the pre-extraction topic layout.
    // ─────────────────────────────────────────────────────────────────────────

    function _logs() internal returns (uint256 won, uint256 lost, uint256 foreignEmitter) {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, 6, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);

        vm.recordLogs();
        hook.resolveTickets(6);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 wonSig = keccak256("TicketWon(address,uint256,uint256)");
        bytes32 lostSig = keccak256("TicketLost(address,uint256)");
        for (uint256 i; i < entries.length; ++i) {
            bytes32 t0 = entries[i].topics[0];
            if (t0 != wonSig && t0 != lostSig) continue;
            if (entries[i].emitter != address(hook)) { foreignEmitter += 1; continue; }
            // indexed player, indexed ticketId (== batch index 0 here)
            require(entries[i].topics.length == 3, "topic layout changed");
            require(address(uint160(uint256(entries[i].topics[1]))) == player, "player topic");
            require(uint256(entries[i].topics[2]) == 0, "ticketId topic");
            if (t0 == wonSig) won += 1; else lost += 1;
        }
    }

    function test_GACHA1d_ticket_events_still_come_from_the_hook() public {
        (uint256 won, uint256 lost, uint256 foreign) = _logs();

        emit log_named_uint("TicketWon from hook ", won);
        emit log_named_uint("TicketLost from hook", lost);
        emit log_named_uint("ticket events from a FOREIGN emitter", foreign);

        assertEq(foreign, 0, "an indexer filtering on the hook address would miss these");
        assertEq(won + lost, 6, "one ticket event per crystal, emitted by the hook");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // E. Accounting totality across interleaved commits and partial resolves.
    // ─────────────────────────────────────────────────────────────────────────

    function _interleave() internal returns (uint256 outstanding, uint256 sumPending, uint256 minted) {
        address p2 = address(0xB0B);
        address p3 = address(0xCAFE);
        _grantCredit(player, type(uint128).max);
        _grantCredit(p2, type(uint128).max);
        _grantCredit(p3, type(uint128).max);

        hook.commitCrystals(player, 5, 0.5 ether);
        hook.commitCrystals(p2, 5, 0.1 ether);
        vm.roll(vm.getBlockNumber() + 1);
        hook.resolveTickets(3); // partial: stops mid-batch-0
        hook.commitCrystals(p3, 5, 0.02 ether);
        vm.roll(vm.getBlockNumber() + 1);
        hook.resolveTickets(4); // finishes batch 0, eats into batch 1
        hook.commitCrystals(player, 2, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);
        hook.resolveTickets(100); // drain

        outstanding = hook.outstandingTickets();
        sumPending = hook.pendingOf(player) + hook.pendingOf(p2) + hook.pendingOf(p3);
        minted = col.totalMinted();
    }

    function test_GACHA1e_outstanding_equals_sum_of_pending_through_partial_resolves() public {
        (uint256 outstanding, uint256 sumPending, uint256 minted) = _interleave();

        emit log_named_uint("outstandingCrystals", outstanding);
        emit log_named_uint("sum pendingOf      ", sumPending);
        emit log_named_uint("minted             ", minted);

        assertEq(outstanding, sumPending, "by-value write-back drifted from the per-player mapping");
        assertEq(outstanding, 0, "every committed crystal resolved");
        assertGt(minted, 0, "wins actually minted");
    }

    // ── Gas: the in-swap budget vs what the step actually costs ─────────────

    function _gasFor(uint256 crystals) internal returns (uint256 used) {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, crystals, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);
        uint256 g0 = gasleft();
        hook.resolveTickets(crystals);
        used = g0 - gasleft();
    }

    /// @dev Exactly what afterSwap fires, measured, and then re-run at the WORST
    ///      case gas afterSwap will ever forward it.
    function _inSwapStep() internal returns (uint256 fullCost, bool okAtFloor, uint256 committedAtFloor) {
        _grantCredit(player, type(uint128).max);
        hook.commitCrystals(player, 6, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);
        uint256 g0 = gasleft();
        vm.prank(address(hook));
        hook.nativeGachaStep(player, 0.5 ether);
        fullCost = g0 - gasleft();

        // Second player, same work, but only the floor budget afterSwap guarantees:
        // gg > GACHA_GAS_MIN ⇒ forwarded = gg - GACHA_GAS_RESERVE. GACHA1-f raised
        // GACHA_GAS_MIN 500k → 700k, so that floor is 700k - 200k = 500k.
        address p2 = address(0xB0B);
        _grantCredit(p2, type(uint128).max);
        hook.commitCrystals(p2, 6, 0.5 ether);
        vm.roll(vm.getBlockNumber() + 1);
        uint256 outstandingBefore = hook.outstandingTickets();
        uint256 committedBefore = hook.committedOf(p2);
        vm.prank(address(hook));
        (okAtFloor,) = address(hook).call{gas: 500_000}(
            abi.encodeWithSelector(CauldronHook.nativeGachaStep.selector, p2, 0.5 ether)
        );
        // Delta: nothing committed AND nothing resolved — the whole step rolled back.
        committedAtFloor = (hook.committedOf(p2) - committedBefore)
            + (outstandingBefore - hook.outstandingTickets());
    }

    function test_GACHA1f_FIXED_inSwapGachaStepFitsItsOwnGasFloor() public {
        uint256 g1 = _gasFor(1);
        uint256 g6 = _gasFor(6); // NATIVE_RESOLVE_MAX
        (uint256 fullCost, bool okAtFloor, uint256 committedAtFloor) = _inSwapStep();

        emit log_named_uint("gas resolveTickets(1)", g1);
        emit log_named_uint("gas resolveTickets(6) [NATIVE_RESOLVE_MAX]", g6);
        emit log_named_uint("gas nativeGachaStep (commit 4 + resolve 6)", fullCost);
        emit log_named_string("nativeGachaStep at the 500k floor", okAtFloor ? "succeeded" : "OOG, silently skipped");
        emit log_named_uint("crystals committed+resolved at the floor", committedAtFloor);

        //  FIXED (GACHA1-f). The hook forwards `gasleft() - GACHA_GAS_RESERVE`
        //  whenever `gasleft() > GACHA_GAS_MIN`, so the floor the step can be
        //  handed is MIN - RESERVE. At the old 500k MIN that floor was 300k for
        //  work measuring ~490k: on a gas-tight direct buy the step OOGed, burned
        //  the buyer's gas and committed nothing, silently. MIN is 700k now, so
        //  the floor is 500k and the step fits inside its own guarantee.
        assertLt(fullCost, 500_000, "the step no longer fits the floor its own gate guarantees");
        assertTrue(okAtFloor, "the step must survive the floor budget its gate guarantees");
        assertGt(committedAtFloor, 0, "the step must do real work at the floor budget");
    }
}

/// @notice ERC-721C validator that tries to re-enter the resolve loop from inside
///         the mint the loop itself made, writing NO state of its own.
contract ProbeValidator {
    error Reentered();
    CauldronHook public immutable hook;

    constructor(address h) { hook = CauldronHook(payable(h)); }

    function validateTransfer(address, address, address, uint256) external {
        // Non-`view` in Solidity terms (it makes a state-mutating call) but it
        // writes nothing itself, so it survives the collection's STATICCALL.
        // A successful re-entry would resolve tickets against the OUTER call's
        // stale `batchCursor` / `outstandingCrystals`. Surface it loudly.
        try hook.resolveTickets(30) returns (uint256, uint256) { revert Reentered(); }
        catch { }
    }
}

/// @notice Same shape, but writes one slot — a probe for CALL vs STATICCALL.
contract WritingValidator {
    uint256 public touched;
    function validateTransfer(address, address, address, uint256) external { touched += 1; }
}

/// @notice ERC-721C validator that refuses the hook's mint.
contract RejectValidator {
    error Blocked();
    function validateTransfer(address, address, address, uint256) external pure { revert Blocked(); }
}
