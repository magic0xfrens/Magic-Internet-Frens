// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X9cPM {
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X9cRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/// A fee sink that is only TRANSIENTLY unable to receive — a contract paused for
/// an upgrade, a recipient blacklisted by the quote token for a while, anything
/// whose `receive()` reverts today and works tomorrow. The realistic victim.
contract X9cSink {
    bool public paused = true;
    uint256 public received;
    function unpause() external { paused = false; }
    function pause() external { paused = true; }
    receive() external payable {
        require(!paused, "paused");
        received += msg.value;
    }
}

/// Thin exposure of the REAL `_routeFee`, so the escrow entry is created by
/// production code (`_routeFee` -> `_payOut` -> the payoutOwed credit) rather
/// than planted with vm.store. Nothing is overridden.
contract X9cEngine is PerpEngine {
    constructor(IPoolManager pm, address hook, address reg, address mf, address div, address tre, address own)
        PerpEngine(pm, hook, reg, mf, div, tre, own) {}
    function routeFee(uint256 amount, bool longSide) external { _routeFee(amount, longSide); }
}

/**
 * X9c — REGRESSION for F-02.
 *
 * `retirePayout` is permissionless while the engine's quote diverges from its
 * generation's (a deliberate liveness promise: a diverged engine must be
 * recoverable by anyone, S01's invariant). It also DISCARDED `_tryPush`'s return
 * value, so the escrow entry was retired whether or not the value moved.
 *
 * Together that was a burn-someone-else's-escrow primitive: any address could
 * pick a recipient that happened to be transiently unpayable and permanently
 * destroy its settlement proceeds — proceeds `claimPayout()` would have preserved,
 * because it reverts on a failed push instead of writing the claim off.
 *
 * The narrowing: an unprivileged caller may only retire an entry whose value
 * ACTUALLY went somewhere. Liveness is untouched for every recipient that can be
 * paid; a recipient that refuses at FULL gas is a write-off, and only the owner
 * (a timelock) may take that decision.
 */
contract X9cRetirePayoutBurnsEscrow is Test {
    X9cEngine perp;
    X9cRegistry reg;
    X9cSink victim;
    MockQuoteToken newQuote;

    address constant ATTACKER = address(0xBADBAD);

    function setUp() public {
        X9cPM pm = new X9cPM();
        MockQuoteToken tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X9cRegistry(address(tok));
        reg.rotateQuote(address(0));                  // gen-1 launched NATIVE
        victim = new X9cSink();
        perp = new X9cEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(victim), address(0), address(this)
        );
        newQuote = new MockQuoteToken("USDG", "USDG", 18);
        // 100% of the routed fee goes to the dividend sink, so the whole fee
        // becomes escrow owed to a recipient that cannot take it right now.
        perp.setFees(0, 0, 0, 10_000, 0);
    }

    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers ──────────────────────────────────────────────────────────────
    function _escrow(uint256 amount) internal {
        vm.deal(address(perp), amount);               // raw backing, no counter
        perp.routeFee(amount, true);
    }
    function _strangerRetires() internal returns (bool ok) {
        vm.prank(ATTACKER);
        try perp.retirePayout(address(victim)) { ok = true; } catch { ok = false; }
    }
    function _ownerRetires() internal returns (bool ok) {
        try perp.retirePayout(address(victim)) { ok = true; } catch { ok = false; }
    }
    function _victimClaims() internal returns (bool ok) {
        vm.prank(address(victim));
        try perp.claimPayout() returns (uint256) { ok = true; } catch { ok = false; }
    }
    function _sync() internal returns (bool ok) {
        vm.prank(address(0xCEE9E4));
        try perp.syncGeneration() { ok = true; } catch { ok = false; }
    }

    function test_StrangerCannotBurnATransientlyUnpayableEscrow() public {
        _escrow(1 ether);
        uint256 owed = perp.payoutOwed(address(victim));

        // The engine is DIVERGED from here on: `retirePayout` is permissionless.
        reg.rotateQuote(address(newQuote));

        // ── 1. the attack: a stranger writes off a paused recipient's escrow ──
        bool burned = _strangerRetires();
        uint256 owedAfterBurn = perp.payoutOwed(address(victim));
        uint256 totalAfterBurn = perp.payoutOwedTotal();

        // ── 2. and the claim is still there when the recipient recovers ───────
        victim.unpause();
        bool claimed = _victimClaims();
        uint256 paidToVictim = victim.received();

        // ── 3. liveness is intact: a stranger CAN still clear a payable entry ──
        //  Escrowed while paused (so the entry certainly exists — `_payOut`'s own
        //  push runs on a 30k budget), then retired by a stranger at FULL gas.
        victim.pause();
        _escrow(2 ether);
        victim.unpause();
        bool strangerClearedPayable = _strangerRetires();
        uint256 receivedAfterRetire = victim.received();
        uint256 owedAfterPayableRetire = perp.payoutOwed(address(victim));

        // ── 4. and the owner keeps the write-off power for a hard refusal, so a
        //       genuinely unpayable entry can never permanently veto adoption ──
        victim.pause();
        _escrow(3 ether);
        bool strangerRefused = _strangerRetires();
        bool ownerWroteOff = _ownerRetires();
        bool syncedAfterWriteOff = _sync();

        // ── assertions ───────────────────────────────────────────────────────
        assertEq(owed, 1 ether, "the fee is escrowed to a sink that cannot take it");
        assertFalse(burned, "a STRANGER can no longer retire an entry that did not move");
        assertEq(owedAfterBurn, 1 ether, "the victim's escrow is untouched");
        assertEq(totalAfterBurn, 1 ether, "and so is the counter");

        assertTrue(claimed, "the recipient still owns its claim once it can receive");
        assertEq(paidToVictim, 1 ether, "and is paid in full");

        assertTrue(strangerClearedPayable, "PERMISSIONLESS RECOVERY STILL WORKS for a payable recipient");
        assertEq(receivedAfterRetire, 3 ether, "and the value really moved (1 + 2)");
        assertEq(owedAfterPayableRetire, 0, "the entry is gone because it was PAID");

        assertFalse(strangerRefused, "a hard refusal is not a stranger's decision to make");
        assertTrue(ownerWroteOff, "the owner (timelock) may still write it off");
        assertEq(perp.payoutOwedTotal(), 0, "so the veto can always be cleared");
        assertTrue(syncedAfterWriteOff, "and the diverged engine adopts its generation's quote");
    }
}
