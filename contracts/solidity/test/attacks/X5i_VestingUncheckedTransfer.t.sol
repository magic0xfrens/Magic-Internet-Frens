// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MigrationVesting} from "../../cauldron/MigrationVesting.sol";
import {MockToken, MockRegistry, MockOracle} from "../MigrationVesting.t.sol";

/// @dev An ERC20 that can be switched into "report failure, move nothing" mode.
///      This is the standards-compliant-but-non-reverting shape: `transfer`
///      returns false rather than reverting, which is exactly what an unchecked
///      call cannot distinguish from success.
contract X5iLyingToken {
    string public name = "LIE";
    string public symbol = "LIE";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    bool public lying;
    mapping(address => uint256) public balanceOf;

    function setLying(bool v) external { lying = v; }
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function burn(address from, uint256 a) external { balanceOf[from] -= a; totalSupply -= a; }

    function transfer(address to, uint256 a) external returns (bool) {
        if (lying) return false; // <-- reports failure, moves nothing, does NOT revert
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
    function allowance(address, address) external pure returns (uint256) { return type(uint256).max; }
    function approve(address, uint256) external pure returns (bool) { return true; }
}

/// @notice X5i — REGRESSION (was: `_release` wrote `grt.released = vested` and
///         then made an UNCHECKED `IERC20.transfer`).
///
///  MigrationVesting.sol:270-272:
///      grt.released = vested;
///      totalMoved  += due;
///      IERC20(grt.token).transfer(holder, due);   // return value ignored
///
///  A token that returns false instead of reverting therefore books the payout,
///  emits `Claimed`, counts it in `totalMoved` — and moves nothing. Worse, the very
///  next branch prunes the grant because `released >= total`, so the claim is not
///  merely mis-recorded, it is DELETED. The escrow keeps the tokens and the books
///  say the beneficiary was paid in full.
///
///  Same shape as CauldronHook.sol:1183 and the same class as the codeless-recipient
///  findings: a failure that reports success and leaves the books wrong.
///
///  FIX: `if (!IERC20(grt.token).transfer(holder, due)) revert TransferFailed();`.
///  The revert rolls the `released` write back with it, so the grant survives intact
///  and the claim stays open until the transfer really succeeds. Test name kept from
///  the PoC; the assertions are inverted.
contract X5iVestingUncheckedTransfer is Test {
    MockRegistry reg;
    MockToken genA;        // dead gen (1) — well-behaved
    X5iLyingToken genB;    // live gen (2) — the payout token
    MockOracle oracle;
    MigrationVesting vest;

    address alice = address(0xA11CE);
    uint64 constant WINDOW = 72 hours;
    uint256 constant AMOUNT = 1_000e18;

    function setUp() public {
        reg = new MockRegistry();
        genA = new MockToken("GEN-A");
        genB = new X5iLyingToken();
        reg.setGen(1, address(genA));
        reg.setGen(2, address(genB));
        reg.setCurrent(2);
        oracle = new MockOracle();
        vest = new MigrationVesting(address(reg), address(this), WINDOW, address(oracle));
        genB.mint(address(reg), 1_000_000e18); // the registry's migration reserve
    }

    // ---- helpers: every branch lives here, never in a test_* body ----------

    /// @dev Alice migrates for real, while the payout token still behaves.
    function _aliceMigrates() internal {
        genA.mint(alice, AMOUNT);
        vm.prank(alice);
        genA.approve(address(vest), type(uint256).max);
        vm.prank(alice);
        vest.startVest(1, AMOUNT);
    }

    function _tryClaim(address who) internal returns (bool ok) {
        vm.prank(who);
        try vest.claim() { return true; } catch { return false; }
    }

    function _releasedOf(address who, uint256 i) internal view returns (uint256) {
        return vest.grantAt(who, i).released;
    }

    // ---- positive control: an honest token pays out ------------------------

    function test_Positive_HonestTokenPaysAndPrunes() public {
        _aliceMigrates();
        vm.warp(block.timestamp + WINDOW + 1);
        assertTrue(_tryClaim(alice), "honest claim succeeds");
        assertEq(genB.balanceOf(alice), AMOUNT, "alice actually received it");
        assertEq(vest.grantCount(alice), 0, "drained grant pruned");
    }

    // ---- the bug ----------------------------------------------------------

    function test_Attack_FalseReturningTokenMarksPaidAndDeletesTheClaim() public {
        _aliceMigrates();
        assertEq(vest.grantCount(alice), 1, "one grant booked");
        assertEq(genB.balanceOf(address(vest)), AMOUNT, "the escrow really holds the tokens");

        // the payout token starts lying AFTER the grant is booked
        genB.setLying(true);
        vm.warp(block.timestamp + WINDOW + 1);

        bool claimed = _tryClaim(alice);
        uint256 grantsLeft = vest.grantCount(alice);

        emit log_named_uint("alice received (wei)   ", genB.balanceOf(alice));
        emit log_named_uint("grants left for alice  ", grantsLeft);

        assertFalse(claimed, "FIXED: a lying transfer reverts instead of reporting success");
        assertEq(genB.balanceOf(alice), 0, "she received nothing - and the books agree");
        assertEq(grantsLeft, 1, "FIXED: the grant SURVIVES, it is not pruned");
        assertEq(_releasedOf(alice, 0), 0, "FIXED: `released` was rolled back, not left written");
        assertEq(vest.grantAt(alice, 0).total, AMOUNT, "the full claim is still booked");
        assertEq(vest.claimable(alice), AMOUNT, "and the escrow still owes her all of it");
        assertEq(genB.balanceOf(address(vest)), AMOUNT, "the tokens are still there to pay it");

        // the exact revert reason, and it is the escrow's own error
        vm.prank(alice);
        vm.expectRevert(MigrationVesting.TransferFailed.selector);
        vest.claim();

        // ── and it is fully RECOVERABLE once the token behaves ──────────────
        genB.setLying(false);
        assertTrue(_tryClaim(alice), "the claim is still open and now succeeds");
        assertEq(genB.balanceOf(alice), AMOUNT, "alice gets her whole migration");
        assertEq(vest.grantCount(alice), 0, "now it prunes - because she was really paid");
        assertEq(genB.balanceOf(address(vest)), 0, "escrow emptied exactly");
    }

    /// @notice A lying token must not let the CALLER of {claimFor} pretend a payout
    ///         happened either - the keeper path goes through the same `_release`.
    function test_Fixed_ClaimForAlsoRevertsOnALyingToken() public {
        _aliceMigrates();
        genB.setLying(true);
        vm.warp(block.timestamp + WINDOW + 1);

        vm.expectRevert(MigrationVesting.TransferFailed.selector);
        vest.claimFor(alice);

        assertEq(vest.grantCount(alice), 1, "grant intact after the keeper attempt");
        assertEq(_releasedOf(alice, 0), 0, "nothing booked as released");
    }
}
