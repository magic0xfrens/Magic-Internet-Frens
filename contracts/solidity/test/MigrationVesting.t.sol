// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MigrationVesting, IStakerOracle} from "../cauldron/MigrationVesting.sol";

/// @dev Test-only burnable/mintable token (stands in for a CauldronToken).
contract MockToken is ERC20 {
    constructor(string memory n) ERC20(n, n) {}
    function mint(address to, uint256 a) external { _mint(to, a); }
    function burn(address from, uint256 a) external { _burn(from, a); }
}

/// @dev Minimal registry that mirrors `claimByBurn`: burn the CALLER's dead-gen
///      tokens, pay the same amount of the live token from its own reserve. This is
///      exactly the 1:1, non-inflationary migration the real registry performs from
///      the out-of-range reserve LP — reproduced without the v4 pool so the escrow
///      logic can be tested in isolation.
contract MockRegistry {
    uint256 public currentGeneration;
    mapping(uint256 => address) public generationToken;

    function setGen(uint256 g, address tok) external { generationToken[g] = tok; }
    function setCurrent(uint256 g) external { currentGeneration = g; }

    function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256) {
        MockToken(generationToken[fromGen]).burn(msg.sender, amount);
        MockToken(generationToken[currentGeneration]).transfer(msg.sender, amount);
        return amount;
    }
}

/// @dev Instant-tier oracle whose membership the test flips at will.
contract MockOracle is IStakerOracle {
    mapping(address => bool) public instant;
    function set(address who, bool v) external { instant[who] = v; }
    function isInstant(address who) external view returns (bool) { return instant[who]; }
}

/**
 * @notice Unit coverage for the anti-dump migration vesting escrow.
 *
 *  Core properties proven:
 *    - a non-staker's 1:1 claim DRIPS linearly over the window (can't dump at once);
 *    - a staker (instant tier) gets the WHOLE claim immediately;
 *    - the escrow can never pay out more than it was handed (conservation);
 *    - grants stack, prune when drained, and survive a mid-vest "relaunch".
 */
contract MigrationVestingTest is Test {
    MockRegistry reg;
    MockToken genA; // dead gen (1)
    MockToken genB; // live gen (2)
    MockOracle oracle;
    MigrationVesting vest;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint64 constant WINDOW = 72 hours;

    function setUp() public {
        reg = new MockRegistry();
        genA = new MockToken("GEN-A");
        genB = new MockToken("GEN-B");
        reg.setGen(1, address(genA));
        reg.setGen(2, address(genB));
        reg.setCurrent(2);
        oracle = new MockOracle();
        vest = new MigrationVesting(address(reg), address(this), WINDOW, address(oracle));

        // The registry holds the live-token reserve it pays migrations from.
        genB.mint(address(reg), 1_000_000e18);
        // Alice + Bob each hold dead-gen tokens to migrate.
        genA.mint(alice, 1_000e18);
        genA.mint(bob, 1_000e18);
    }

    function _startVest(address who, uint256 amount) internal {
        vm.startPrank(who);
        genA.approve(address(vest), amount);
        vest.startVest(1, amount);
        vm.stopPrank();
    }

    // ── linear drip for non-stakers ────────────────────────────────────────
    function test_NonStaker_DripsLinearly() public {
        // Anchor to an absolute base so the two warps unambiguously land at 50% and
        // 100% of the 72h window. (Chained `block.timestamp + 36h` warps didn't
        // stack → the 2nd claim saw 0 new vested → NothingToClaim.)
        uint256 t0 = block.timestamp;
        _startVest(alice, 1_000e18);

        // t0: nothing vested, escrow holds the full claim.
        assertEq(vest.claimable(alice), 0, "nothing at t0");
        assertEq(vest.locked(alice), 1_000e18, "all locked at t0");
        assertEq(genB.balanceOf(address(vest)), 1_000e18, "escrow custodies it");
        assertEq(genA.balanceOf(alice), 0, "dead tokens burned");

        // halfway → half claimable.
        vm.warp(t0 + 36 hours);
        assertApproxEqAbs(vest.claimable(alice), 500e18, 1e12, "half at 50%");

        vm.prank(alice);
        vest.claim();
        assertApproxEqAbs(genB.balanceOf(alice), 500e18, 1e12, "got half");

        // full window → remainder claimable, grant prunes to zero.
        vm.warp(t0 + 72 hours);
        vm.prank(alice);
        vest.claim();
        assertEq(genB.balanceOf(alice), 1_000e18, "fully vested");
        assertEq(vest.grantCount(alice), 0, "grant pruned when drained");
        assertEq(vest.claimable(alice), 0);
    }

    // ── instant tier ───────────────────────────────────────────────────────
    function test_Staker_ClaimsInstantly() public {
        oracle.set(bob, true);
        _startVest(bob, 1_000e18);
        // startVest auto-released the instant grant in the same tx.
        assertEq(genB.balanceOf(bob), 1_000e18, "instant full claim");
        assertEq(vest.grantCount(bob), 0, "nothing left to vest");
    }

    function test_OracleUnset_EveryoneVests() public {
        vest.setStakerOracle(address(0));
        oracle.set(bob, true); // ignored now
        _startVest(bob, 1_000e18);
        assertEq(genB.balanceOf(bob), 0, "no instant without oracle");
        assertEq(vest.locked(bob), 1_000e18);
    }

    // ── stacking + conservation ────────────────────────────────────────────
    function test_GrantsStack_AndConserve() public {
        _startVest(alice, 400e18);
        _startVest(alice, 600e18);
        assertEq(vest.grantCount(alice), 2);
        assertEq(vest.locked(alice), 1_000e18);

        vm.warp(block.timestamp + WINDOW);
        vm.prank(alice);
        vest.claim();
        // Never pays more than the 1000 it was handed.
        assertEq(genB.balanceOf(alice), 1_000e18);
        assertEq(vest.grantCount(alice), 0);
    }

    // ── batch keeper path ──────────────────────────────────────────────────
    function test_VestBatch_SkipsUnapproved() public {
        // Alice approves; Bob does not.
        vm.prank(alice);
        genA.approve(address(vest), 1_000e18);

        address[] memory who = new address[](2);
        who[0] = alice;
        who[1] = bob;
        vest.vestBatch(1, who);

        assertEq(vest.grantCount(alice), 1, "approved holder vested");
        assertEq(vest.grantCount(bob), 0, "unapproved skipped, no revert");
        assertEq(vest.locked(alice), 1_000e18);
    }

    // ── governance ─────────────────────────────────────────────────────────
    function test_SetWindow_Bounds() public {
        vest.setVestWindow(7 days);
        assertEq(vest.vestWindow(), 7 days);
        vm.expectRevert(MigrationVesting.WindowOutOfRange.selector);
        vest.setVestWindow(15 days);
        vm.expectRevert(MigrationVesting.WindowOutOfRange.selector);
        vest.setVestWindow(1 minutes);
    }

    function test_WindowSnapshot_PerGrant() public {
        _startVest(alice, 1_000e18);       // booked at 72h
        vest.setVestWindow(1 hours);        // retune AFTER
        vm.warp(block.timestamp + 36 hours);
        // Alice's grant still uses the 72h it snapshotted → ~half, not fully vested.
        assertApproxEqAbs(vest.claimable(alice), 500e18, 1e12, "retune doesn't touch open grants");
    }

    function test_Claim_RevertsWhenNothing() public {
        vm.expectRevert(MigrationVesting.NothingToClaim.selector);
        vm.prank(alice);
        vest.claim();
    }

    function test_OnlyOwner_Setters() public {
        vm.prank(alice);
        vm.expectRevert();
        vest.setVestWindow(1 days);
        vm.prank(alice);
        vm.expectRevert();
        vest.setStakerOracle(address(0));
    }
}
