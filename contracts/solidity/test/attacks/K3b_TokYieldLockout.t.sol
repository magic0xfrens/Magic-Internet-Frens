// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/**
 * K3b — {PerpEngine.syncGeneration} writes the token-side reward pot off on a
 * quote rotation (`tokYieldEth = 0`, PerpEngine.sol:1362) but leaves the
 * MONOTONIC accrual marker `tokYieldCumulative` untouched (only ever `+=`, see
 * :1897 / :2266). {PerpVault} builds every entitlement out of that marker
 * (`_syncTokYield`, PerpVault.sol:365-372) and pays out of the pot through
 * {PerpEngine.withdrawTokYieldTo}, which reverts wholesale when the ask exceeds
 * the pot (`if (amount > tokYieldEth) revert PlvInsufficient()`, :2296).
 *
 * {PerpVault.claimTokYield} has NO partial path: it asks for the FULL owed
 * amount or nothing. A staker who was staked across the rotation therefore
 * carries a permanently oversized `tokRewardOwed`, and every subsequent claim —
 * including the yield they legitimately earned AFTER the rotation — reverts.
 */
contract K3b_TokYieldLockout is Test {
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function _fresh() internal returns (MockEngine e, PerpVault v, MockToken t) {
        t = new MockToken();
        e = new MockEngine(t);
        v = new PerpVault(address(e), address(e));
        vm.deal(address(e), 100 ether);
        t.mint(alice, 1_000_000 ether);
        t.mint(bob, 1_000_000 ether);
    }

    // ── POSITIVE: no rotation. Accrued short-side yield is claimable. ────────
    function _noRotation() internal returns (uint256 claimed) {
        (MockEngine e, PerpVault v, MockToken t) = _fresh();
        vm.startPrank(alice);
        t.approve(address(v), type(uint256).max);
        v.depositToken(1000 ether);
        vm.stopPrank();

        e.accrueTokYield(5 ether);
        uint256 before = alice.balance;
        vm.prank(alice);
        v.claimTokYield();
        claimed = alice.balance - before;
    }

    function test_positive_tokStakerClaimsShortSideYield() public {
        uint256 claimed = _noRotation();
        assertApproxEqAbs(claimed, 5 ether, 1e9, "token staker claims accrued short-side yield");
    }

    // ── ATTACK: a rotation write-off permanently locks the SAME staker out of
    //    all FUTURE yield, while a staker who joined afterwards is paid. ──────
    struct R { bool aliceReverted; uint256 bobGot; uint256 alicePrincipal; uint256 aliceStillOwed; }

    function _afterRotation() internal returns (R memory r) {
        (MockEngine e, PerpVault v, MockToken t) = _fresh();
        vm.startPrank(alice);
        t.approve(address(v), type(uint256).max);
        uint256 aliceShares = v.depositToken(1000 ether);
        vm.stopPrank();

        e.accrueTokYield(5 ether);       // pot 5, cumulative 5

        // The quote rotation: PerpEngine.sol:1359-1362 — pot swept to treasury,
        // cumulative marker deliberately NOT rewound.
        e.rotationWriteOff();
        assertEq(e.tokYieldEth(), 0, "pot swept");
        assertEq(e.tokYieldCumulative(), 5 ether, "marker not rewound");

        // Life goes on: new short-side fees accrue in the NEW quote.
        e.accrueTokYield(1 ether);       // pot 1, cumulative 6

        // A post-rotation staker.
        vm.startPrank(bob);
        t.approve(address(v), type(uint256).max);
        v.depositToken(1000 ether);
        vm.stopPrank();
        e.accrueTokYield(1 ether);       // pot 2, cumulative 7

        // Alice's owed is built from the whole cumulative, including the swept part.
        r.aliceStillOwed = v.pendingTokYield(alice);
        vm.prank(alice);
        try v.claimTokYield() { r.aliceReverted = false; } catch { r.aliceReverted = true; }

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        try v.claimTokYield() {} catch {}
        r.bobGot = bob.balance - bobBefore;

        // Principal is untouched (the write-off only hits the reward pot).
        uint256 pb = t.balanceOf(alice);
        vm.prank(alice);
        v.withdrawToken(aliceShares);
        r.alicePrincipal = t.balanceOf(alice) - pb;
    }

    function test_attack_rotationPermanentlyLocksTokStakerOutOfFutureYield() public {
        R memory r = _afterRotation();
        assertGt(r.aliceStillOwed, 5 ether, "alice's entitlement still carries the swept 5 ETH");
        assertTrue(r.aliceReverted, "alice can never claim - not even her post-rotation earnings");
        assertGt(r.bobGot, 0, "a staker who joined AFTER the rotation is paid normally");
        assertApproxEqAbs(r.alicePrincipal, 1000 ether, 1e9, "token principal itself is safe");
    }
}

contract MockEngine {
    MockToken public immutable token;
    uint256 public plvTok;
    uint256 public tokYieldEth;
    uint256 public tokYieldCumulative;

    constructor(MockToken t) { token = t; }
    function quote() external pure returns (address) { return address(0); }
    function currentToken() external view returns (address) { return address(token); }
    function fundFromVault(uint256) external payable {}
    function withdrawPlvTo(uint256, address) external pure { revert("n/a"); }
    function fundTokenFromVault(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        plvTok += amount;
    }
    function withdrawPlvTokenTo(uint256 amount, address to) external {
        require(amount <= plvTok, "free");
        plvTok -= amount;
        token.transfer(to, amount);
    }
    function totalEth() external pure returns (uint256) { return 0; }
    function freeEth() external pure returns (uint256) { return 0; }
    function totalTokenAssets() external view returns (uint256) { return plvTok; }
    function freeToken() external view returns (uint256) { return plvTok; }

    /// Mirrors PerpEngine._routeFee's short-side leg (:1896-1897).
    function accrueTokYield(uint256 a) external { tokYieldEth += a; tokYieldCumulative += a; }
    /// Mirrors PerpEngine.syncGeneration's rotation write-off (:1359-1362).
    function rotationWriteOff() external { tokYieldEth = 0; }
    /// Mirrors PerpEngine.withdrawTokYieldTo (:2295-2297) exactly.
    function withdrawTokYieldTo(uint256 amount, address to) external {
        require(amount <= tokYieldEth, "PlvInsufficient");
        tokYieldEth -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok);
    }
    receive() external payable {}
}

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) { _move(msg.sender, to, a); return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _move(f, to, a); return true;
    }
    function _move(address f, address to, uint256 a) private { balanceOf[f] -= a; balanceOf[to] += a; }
}
