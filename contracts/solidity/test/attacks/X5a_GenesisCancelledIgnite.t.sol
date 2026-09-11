// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

/// @dev Minimal stand-in for CauldronRegistry: it only has to accept the
///      presale's `summon{value: balance}()` the way the real one does.
contract X5MockSummonRegistry {
    uint256 public received;
    function summon() external payable returns (address token, bytes32 poolId) {
        received += msg.value;
        return (address(0xBEEF), bytes32(uint256(1)));
    }
    function summoned() external pure returns (bool) { return false; }
}

/// @notice X5a — REGRESSION (was: `igniteCauldron()` never checked `cancelled`).
///
///  A cancelled, SOLD-OUT presale used to satisfy every gate in
///  MiFrensGenesis.igniteCauldron, so the whole refund pot could be forwarded
///  into the registry and every outstanding refund permanently destroyed. The
///  test names are kept from the PoC on purpose; the ASSERTIONS are inverted —
///  each one now proves the ignite is refused and the refunds survive.
///  Fix: `if (cancelled) revert AlreadyCancelled();` in `igniteCauldron`.
contract X5aGenesisCancelledIgnite is Test {
    MiFrensGenesis g;
    X5MockSummonRegistry reg;

    address dev = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address stranger = address(0xBADBAD);

    uint256 constant PRICE = 0.0222 ether;
    uint256 constant SUPPLY = 100;     // genesis tranche (constructor arg; 1111 on mainnet)
    uint256 constant PER_WALLET = 50;

    function setUp() public {
        g = new MiFrensGenesis("MiFrens", "MIFREN", SUPPLY, 2 * SUPPLY, PRICE, PER_WALLET, "u/");
        reg = new X5MockSummonRegistry();
        g.setRegistry(address(reg));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(stranger, 1 ether);
    }

    // ---- helpers: every branch lives here, never in a test_* body ----------

    function _sellOut() internal {
        vm.prank(alice); g.mint{value: PRICE * PER_WALLET}(PER_WALLET);
        vm.prank(bob);   g.mint{value: PRICE * PER_WALLET}(PER_WALLET);
    }

    function _tryRefund(address who) internal returns (bool ok, uint256 amount) {
        vm.prank(who);
        try g.refund() returns (uint256 a) { return (true, a); } catch { return (false, 0); }
    }

    function _tryIgnite(address who) internal returns (bool ok) {
        vm.prank(who);
        try g.igniteCauldron() returns (address) { return true; } catch { return false; }
    }

    // ---- positive control: the safety valve works when nobody ignites -----

    function test_Positive_CancelledPresaleRefundsInFull() public {
        _sellOut();
        g.cancelPresale();

        (bool aOk, uint256 aGot) = _tryRefund(alice);
        (bool bOk, uint256 bGot) = _tryRefund(bob);

        assertTrue(aOk, "alice refund must succeed on a cancelled presale");
        assertTrue(bOk, "bob refund must succeed on a cancelled presale");
        assertEq(aGot, PRICE * PER_WALLET, "alice refunded in full");
        assertEq(bGot, PRICE * PER_WALLET, "bob refunded in full");
        assertEq(address(g).balance, 0, "pot fully returned");
    }

    function _tryMint(address who, uint256 q) internal returns (bool ok) {
        vm.prank(who);
        try g.mint{value: PRICE * q}(q) { return true; } catch { return false; }
    }

    // ---- REGRESSION: the ignite is refused on a CANCELLED sale -------------

    function test_Attack_StrangerIgnitesCancelledPresale_DestroysRefunds() public {
        _sellOut();
        uint256 pot = address(g).balance;

        // 1. deployer pulls the documented safety valve
        g.cancelPresale();
        bool cancelledFlag = g.cancelled();

        // 2. alice gets out first (proving refunds really were open)
        (bool aOk, uint256 aGot) = _tryRefund(alice);
        uint256 potAfterAlice = address(g).balance;

        // 3. a stranger, paying only gas, tries to ignite the CANCELLED sale
        bool ignited = _tryIgnite(stranger);
        // 3b. and so does the deployer, who IS the default finalizer — the gate
        //     is on the state, not on the caller.
        bool ignitedByDev = _tryIgnite(dev);
        // 3c. and the explicit revert reason is the cancelled one
        vm.expectRevert(MiFrensGenesis.AlreadyCancelled.selector);
        g.igniteCauldron();

        // 4. bob's refund is still payable, in full
        (bool bOk, uint256 bGot) = _tryRefund(bob);
        uint256 bobStillOwed = g.paid(bob);
        uint256 swept = reg.received();
        bool finalizedFlag = g.finalized();
        bool stillCancelled = g.cancelled();

        emit log_named_uint("ETH swept out of the cancelled pot (wei)", swept);
        emit log_named_uint("bob refunded (wei)", bGot);

        assertTrue(cancelledFlag, "presale was cancelled");
        assertTrue(aOk, "alice refunded");
        assertEq(aGot, PRICE * PER_WALLET, "alice got her full refund");
        assertEq(potAfterAlice, pot - aGot, "pot shrank by alice's refund only");

        assertFalse(ignited, "FIXED: a stranger cannot ignite a CANCELLED presale");
        assertFalse(ignitedByDev, "FIXED: not even the finalizer can ignite a CANCELLED presale");
        assertEq(swept, 0, "not one wei left the refund pot");

        assertTrue(bOk, "bob can still refund");
        assertEq(bGot, PRICE * PER_WALLET, "bob refunded in full");
        assertEq(bobStillOwed, 0, "bob's debt is settled, not stranded");
        assertEq(address(g).balance, 0, "pot fully returned to contributors");

        assertFalse(finalizedFlag, "never finalized");
        assertTrue(stillCancelled, "still cancelled");
        // minting stays shut too - a cancel is terminal in both directions
        assertFalse(_tryMint(stranger, 1), "a cancelled sale cannot be re-minted into");
    }

    // ---- positive control #2: a NORMAL (uncancelled) sale still ignites ----

    function test_Positive_NormalIgniteStillWorks() public {
        _sellOut();
        uint256 pot = address(g).balance;

        assertTrue(g.soldOut(), "sold out");
        assertFalse(g.cancelled(), "not cancelled");

        bool ignited = _tryIgnite(stranger); // no finalizer set in setUp -> anyone
        assertTrue(ignited, "an uncancelled sold-out presale still ignites");
        assertEq(reg.received(), pot, "the whole pot funded the summon");
        assertEq(address(g).balance, 0, "presale forwarded everything");
        assertTrue(g.finalized(), "finalized");

        // and a post-ignition cancel can no longer open a refund path on money
        // that is already in the LP
        vm.expectRevert(MiFrensGenesis.PresaleOver.selector);
        g.cancelPresale();
    }

    receive() external payable {}
}
