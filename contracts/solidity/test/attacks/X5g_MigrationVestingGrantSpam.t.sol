// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MigrationVesting} from "../../cauldron/MigrationVesting.sol";
import {MockToken, MockRegistry, MockOracle} from "../MigrationVesting.t.sol";

/// @notice X5g — REGRESSION (was: `vestBatch` permissionless + `_release`
///         unpaginated = a stranger locks a holder out of their own migration).
///
///  MigrationVesting.sol:153 `vestBatch(uint256, address[])` has NO access control
///  and books a grant for ANY holder who has an allowance on this escrow — which
///  every holder who has ever migrated has, because the standard UX is an infinite
///  approval. The amount is `min(balance, allowance)`, so an attacker who DUSTS a
///  victim with one wei of the dead-gen token can convert that dust into one more
///  `Grant` pushed onto `_grants[victim]`.
///
///  MigrationVesting.sol:221-223 `_release` iterates that array with no bound and
///  it is the ONLY way tokens leave the escrow (`claim` and `claimFor` both go
///  through it). Grow the array past what a block can process and the victim's
///  entire migrated balance is locked forever: the loop reverts, so it never makes
///  partial progress, and there is no paginated exit. Measured on the unfixed
///  contract: 2,000 forced grants, `claimFor` consumed a whole 30,000,000-gas
///  block and failed, with 1,000e18 stuck in the escrow.
///
///  FIX: `MAX_GRANTS` (64) bounds the array absolutely, so `_release` is bounded
///  by construction; `MAX_BATCH_GRANTS` (32) is the smaller slice the
///  permissionless path may fill, so a spammer can never consume the headroom a
///  holder needs for their OWN {startVest}. Test name kept from the PoC; the
///  assertions are inverted.
contract X5gMigrationVestingGrantSpam is Test {
    MockRegistry reg;
    MockToken genA; // dead gen (1)
    MockToken genB; // live gen (2)
    MockOracle oracle;
    MigrationVesting vest;

    address alice = address(0xA11CE);
    address attacker = address(0xBADBAD);
    uint64 constant WINDOW = 72 hours;
    uint256 constant BLOCK_GAS = 30_000_000; // a generous mainnet block
    uint256 constant SPAM = 2000;

    function setUp() public {
        reg = new MockRegistry();
        genA = new MockToken("GEN-A");
        genB = new MockToken("GEN-B");
        reg.setGen(1, address(genA));
        reg.setGen(2, address(genB));
        reg.setCurrent(2);
        oracle = new MockOracle();
        vest = new MigrationVesting(address(reg), address(this), WINDOW, address(oracle));
        genB.mint(address(reg), 1_000_000e18); // the registry's migration reserve
    }

    // ---- helpers: every branch lives here, never in a test_* body ----------

    /// @dev Alice migrates for real, the way the product intends.
    function _aliceMigrates(uint256 amount) internal {
        genA.mint(alice, amount);
        vm.prank(alice);
        genA.approve(address(vest), type(uint256).max); // the standard infinite approval
        vm.prank(alice);
        vest.startVest(1, amount);
    }

    /// @dev The attacker dusts alice and converts the dust into a grant on her.
    function _spamGrants(uint256 n) internal {
        address[] memory one = new address[](1);
        one[0] = alice;
        for (uint256 i; i < n; ++i) {
            genA.mint(attacker, 1);
            vm.prank(attacker);
            genA.transfer(alice, 1); // dusting needs no permission from alice
            vm.prank(attacker);
            vest.vestBatch(1, one); // permissionless
        }
    }

    function _tryClaimWithinABlock() internal returns (bool ok) {
        (ok, ) = address(vest).call{gas: BLOCK_GAS}(
            abi.encodeWithSelector(MigrationVesting.claimFor.selector, alice)
        );
    }

    /// @dev Alice fills her OWN remaining headroom, one self-service vest at a
    ///      time, and reports where it stopped.
    function _fillOwnHeadroom(uint256 tries) internal returns (uint256 done, bool hitCap) {
        genA.mint(alice, tries * 1e18);
        for (uint256 i; i < tries; ++i) {
            vm.prank(alice);
            try vest.startVest(1, 1e18) returns (uint256) { ++done; }
            catch { return (done, true); }
        }
        return (done, false);
    }

    // ---- positive control: the ordinary path works ------------------------

    function test_Positive_NormalVestAndClaimWorks() public {
        _aliceMigrates(1_000e18);
        vm.warp(block.timestamp + WINDOW + 1);
        vm.prank(alice);
        vest.claim();
        assertEq(genB.balanceOf(alice), 1_000e18, "alice gets her whole migration");
        assertEq(vest.grantCount(alice), 0, "the drained grant is pruned");
    }

    // ---- attack: a stranger locks alice out of her own migration ----------

    function test_Attack_ThirdPartyGrantSpamLocksTheHolderOut() public {
        _aliceMigrates(1_000e18);
        assertEq(vest.grantCount(alice), 1, "alice consented to exactly ONE grant");

        _spamGrants(SPAM);
        uint256 count = vest.grantCount(alice);

        vm.warp(block.timestamp + WINDOW + 1);

        uint256 g0 = gasleft();
        bool ok = _tryClaimWithinABlock();
        uint256 used = g0 - gasleft();

        emit log_named_uint("spam attempts by a stranger", SPAM);
        emit log_named_uint("grants actually forced     ", count - 1);
        emit log_named_uint("gas for one full claim     ", used);

        assertEq(count, vest.MAX_BATCH_GRANTS(), "FIXED: a stranger is capped at the batch sub-cap");
        assertLe(count, vest.MAX_GRANTS(), "the array can never exceed the loop bound");
        assertTrue(ok, "FIXED: alice claims well inside a 30M-gas block");
        assertLt(used, BLOCK_GAS, "and the claim is cheap, not merely possible");
        assertGe(genB.balanceOf(alice), 1_000e18, "she gets her whole migration back");
        assertEq(vest.grantCount(alice), 0, "every grant drained and pruned");
    }

    /// @notice The spam must not eat the headroom alice needs for her OWN vests.
    function test_Fixed_SpamCannotConsumeTheHoldersOwnHeadroom() public {
        _aliceMigrates(1_000e18);
        _spamGrants(SPAM); // a stranger fills his whole allowance of slots
        assertEq(vest.grantCount(alice), vest.MAX_BATCH_GRANTS(), "stranger at his sub-cap");

        // alice still has MAX_GRANTS - MAX_BATCH_GRANTS slots of her own
        uint256 headroom = vest.MAX_GRANTS() - vest.MAX_BATCH_GRANTS();
        (uint256 done, bool hitCap) = _fillOwnHeadroom(headroom);
        assertEq(done, headroom, "alice can still migrate on her own path");
        assertFalse(hitCap, "the stranger did not consume her headroom");

        // and the hard cap is real: one more reverts explicitly, it does not
        // silently grow the array `_release` has to walk
        (uint256 extra, bool capped) = _fillOwnHeadroom(1);
        assertEq(extra, 0, "no grant booked past the cap");
        assertTrue(capped, "MAX_GRANTS is enforced");
        assertEq(vest.grantCount(alice), vest.MAX_GRANTS(), "array pinned at the loop bound");

        // even at the absolute cap the only exit still fits in a block
        vm.warp(block.timestamp + WINDOW + 1);
        assertTrue(_tryClaimWithinABlock(), "a FULL array still claims within a block");
        assertEq(vest.grantCount(alice), 0, "fully drained");
    }

    /// @notice `Ownable.renounceOwnership` would permanently freeze the vest window
    ///         and pin the instant-tier oracle. It is disabled.
    function test_Fixed_OwnershipCannotBeRenounced() public {
        assertEq(vest.owner(), address(this), "this test is the owner");
        vm.expectRevert(MigrationVesting.OwnershipCannotBeRenounced.selector);
        vest.renounceOwnership();
        assertEq(vest.owner(), address(this), "still owned");
        // and the governance surface it protects still works
        vest.setStakerOracle(address(0));
        assertEq(address(vest.stakerOracle()), address(0), "oracle still swappable");
    }
}
