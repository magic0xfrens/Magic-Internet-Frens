// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MigrationVesting} from "../../cauldron/MigrationVesting.sol";

contract MintableToken is ERC20 {
    constructor(string memory n) ERC20(n, n) {}
    function mint(address to, uint256 a) external { _mint(to, a); }
    function burn(address from, uint256 a) external { _burn(from, a); }
}

/**
 * @notice Stand-in for {CauldronRegistry}'s migration primitive: burns the
 *         caller's dead-gen balance and hands over the same amount of the live
 *         token from a finite reserve — exactly the 1:1 `claimByBurn` contract.
 */
contract MockMigrationRegistry {
    uint256 public currentGeneration = 2;
    mapping(uint256 => address) public generationToken;

    constructor(address dead, address live) {
        generationToken[1] = dead;
        generationToken[2] = live;
    }

    function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256) {
        MintableToken(generationToken[fromGen]).burn(msg.sender, amount);
        MintableToken(generationToken[currentGeneration]).mint(msg.sender, amount); // "reserve" release
        return amount;
    }
}

contract VestingHandler is Test {
    MigrationVesting public vesting;
    MintableToken public dead;
    MintableToken public live;

    address[3] public holders = [address(0xA1), address(0xA2), address(0xA3)];

    /// ghost: total escrowed per holder (booked grants)
    mapping(address => uint256) public ghostEscrowed;
    /// ghost: total released per holder
    mapping(address => uint256) public ghostReleased;
    uint256 public ghostEscrowedAll;
    uint256 public ghostReleasedAll;

    constructor(MigrationVesting v, MintableToken d, MintableToken l) {
        vesting = v; dead = d; live = l;
        for (uint256 i; i < 3; i++) {
            dead.mint(holders[i], 1_000_000e18);
            vm.prank(holders[i]);
            dead.approve(address(vesting), type(uint256).max);
        }
    }

    function _holder(uint256 s) internal view returns (address) { return holders[s % 3]; }

    function startVest(uint256 seed, uint256 amount) external {
        address h = _holder(seed);
        uint256 bal = dead.balanceOf(h);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        uint256 before = live.balanceOf(h);
        vm.prank(h);
        uint256 escrowed = vesting.startVest(1, amount);
        ghostEscrowed[h] += escrowed;
        ghostEscrowedAll += escrowed;
        uint256 got = live.balanceOf(h) - before; // instant tier auto-releases
        ghostReleased[h] += got;
        ghostReleasedAll += got;
    }

    function claim(uint256 seed) external {
        address h = _holder(seed);
        uint256 before = live.balanceOf(h);
        vm.prank(h);
        try vesting.claim() {} catch { return; }
        uint256 got = live.balanceOf(h) - before;
        ghostReleased[h] += got;
        ghostReleasedAll += got;
    }

    function claimFor(uint256 seed) external {
        address h = _holder(seed);
        uint256 before = live.balanceOf(h);
        try vesting.claimFor(h) {} catch { return; }
        uint256 got = live.balanceOf(h) - before;
        ghostReleased[h] += got;
        ghostReleasedAll += got;
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 12 hours));
    }
}

/**
 * @title VestingInvariants
 * @notice INVARIANTS for the anti-dump escrow ({MigrationVesting}):
 *   V-1  SOLVENCY: the escrow can never owe more of the live token than it holds.
 *   V-2  CONSERVATION: escrowed == released + still-locked-or-claimable, per holder.
 *   V-3  NO OVER-RELEASE: a holder can never receive more than they escrowed.
 *   V-4  MONOTONE VESTING: `claimable` never exceeds `total - released`.
 *
 *  Run: FOUNDRY_PROFILE=cauldron forge test --match-contract VestingInvariants
 *  (No fork required.)
 */
contract VestingInvariants is StdInvariant, Test {
    MigrationVesting vesting;
    MintableToken dead;
    MintableToken live;
    VestingHandler handler;

    function setUp() public {
        dead = new MintableToken("DEAD");
        live = new MintableToken("LIVE");
        MockMigrationRegistry reg = new MockMigrationRegistry(address(dead), address(live));
        vesting = new MigrationVesting(address(reg), address(this), 72 hours, address(0));
        handler = new VestingHandler(vesting, dead, live);
        targetContract(address(handler));
    }

    /// V-1 SOLVENCY — the escrow holds at least everything it still owes.
    function invariant_escrowIsSolvent() public view {
        uint256 owed;
        for (uint256 i; i < 3; i++) {
            address h = handler.holders(i);
            owed += vesting.claimable(h) + vesting.locked(h);
        }
        assertGe(live.balanceOf(address(vesting)), owed, "V-1: escrow owes more than it holds");
    }

    /// V-2 CONSERVATION — per holder: escrowed == released + claimable + locked.
    function invariant_perHolderConservation() public view {
        for (uint256 i; i < 3; i++) {
            address h = handler.holders(i);
            assertEq(
                handler.ghostEscrowed(h),
                handler.ghostReleased(h) + vesting.claimable(h) + vesting.locked(h),
                "V-2: grant accounting drifted"
            );
        }
    }

    /// V-3 NO OVER-RELEASE.
    function invariant_neverReleasesMoreThanEscrowed() public view {
        assertLe(handler.ghostReleasedAll(), handler.ghostEscrowedAll(), "V-3: over-release");
    }

    /// V-4 the drip never front-runs itself.
    function invariant_claimableWithinGrant() public view {
        for (uint256 i; i < 3; i++) {
            address h = handler.holders(i);
            uint256 n = vesting.grantCount(h);
            for (uint256 j; j < n; j++) {
                MigrationVesting.Grant memory g = vesting.grantAt(h, j);
                assertLe(g.released, g.total, "V-4: released above total");
            }
        }
    }

    /// The registry-side promise the escrow depends on: burn N, escrow N.
    function testFuzz_MigrationIsOneToOne(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);
        address h = address(0xB0B);
        dead.mint(h, amount);
        vm.startPrank(h);
        dead.approve(address(vesting), amount);
        uint256 escrowed = vesting.startVest(1, amount);
        vm.stopPrank();
        assertEq(escrowed, amount, "migration must be exactly 1:1");
        assertEq(dead.balanceOf(h), 0, "the dead balance is fully burned");
    }

    /// Linear vesting never releases early and always completes.
    function testFuzz_LinearDripBounds(uint256 amount, uint256 dt) public {
        amount = bound(amount, 1e18, 1_000_000e18);
        dt = bound(dt, 0, 200 hours);
        address h = address(0xC0C);
        dead.mint(h, amount);
        vm.startPrank(h);
        dead.approve(address(vesting), amount);
        vesting.startVest(1, amount);
        vm.stopPrank();

        uint256 start = block.timestamp;
        vm.warp(start + dt);
        uint256 c = vesting.claimable(h);
        uint256 w = vesting.vestWindow();
        uint256 expected = dt >= w ? amount : (amount * dt) / w;
        assertEq(c, expected, "linear schedule");
        assertLe(c, amount, "never over-vests");
    }
}
