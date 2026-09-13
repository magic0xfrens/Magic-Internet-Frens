// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/// Minimal ERC20 (no fork, no v4).
contract Tok {
    string public name = "T"; string public symbol = "T"; uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        balanceOf[f] -= a; balanceOf[to] += a; return true;
    }
}

contract Reg { address public currentToken; constructor(address t) { currentToken = t; } }

/// Stands in for PerpEngine's token side + segregated `tokYieldEth` pot.
contract MockEngine {
    address public quoteAddr;
    Tok public tok;
    uint256 public tokYieldCumulative;
    uint256 public tokYieldEth;
    uint256 public tokenAssets;

    constructor(Tok _t) { tok = _t; }
    function quote() external pure returns (address) { return address(0); }
    function totalEth() external pure returns (uint256) { return 0; }
    function freeEth() external pure returns (uint256) { return 0; }
    function totalTokenAssets() external view returns (uint256) { return tokenAssets; }
    function freeToken() external view returns (uint256) { return tokenAssets; }
    function fundTokenFromVault(uint256 a) external { tok.transferFrom(msg.sender, address(this), a); tokenAssets += a; }
    function withdrawPlvTokenTo(uint256 a, address to) external { tokenAssets -= a; tok.transfer(to, a); }
    function fundFromVault(uint256) external payable {}
    function withdrawPlvTo(uint256, address) external {}

    /// Short-side fee credit: the pot and the cumulative move together.
    function creditTokYield() external payable { tokYieldEth += msg.value; tokYieldCumulative += msg.value; }
    /// What PerpEngine.syncGeneration does to the pot on a quote rotation
    /// (PerpEngine.sol:1359 region): the pot is written off, the cumulative is NOT rewound.
    function rotationWriteOff() external {
        uint256 a = tokYieldEth; tokYieldEth = 0;
        (bool ok,) = address(0xdead).call{value: a}(""); ok;
    }
    function withdrawTokYieldTo(uint256 amount, address to) external {
        require(amount <= tokYieldEth, "pot");
        tokYieldEth -= amount;
        (bool ok,) = to.call{value: amount}(""); require(ok, "send");
    }
    receive() external payable {}
}

/**
 * Ja — PerpVault's new write-off EPOCH over-forfeits.
 *
 * `_syncTokYield` (PerpVault.sol:421-453) sets the forfeit line `epochAcc` to the
 * accumulator AFTER folding in the whole `cum - last` delta whenever
 * `cut == pulled + lost` is not strictly greater than `last`. `cut == cum - pot`,
 * and when the vault was up to date at the moment of the rotation (`last == cum`
 * at write-off time) that is EXACTLY equal to `last` — the split-fold branch can
 * never be taken — so any short-side yield credited AFTER the write-off but
 * BEFORE the vault's next interaction is swept below the forfeit line and lost.
 */
contract Ja_VaultEpochOverForfeit is Test {
    Tok tok; Reg reg; MockEngine eng; PerpVault vault;
    address staker = address(0x57A);

    function setUp() public {
        tok = new Tok();
        reg = new Reg(address(tok));
        eng = new MockEngine(tok);
        vault = new PerpVault(address(eng), address(reg));
        tok.mint(staker, 1000 ether);
        vm.prank(staker); tok.approve(address(vault), type(uint256).max);
    }

    /// Credit yield, write the pot off, then credit MORE.
    /// @param syncAtRotation whether the vault had OBSERVED the pre-rotation yield
    ///        before the write-off. That is the boundary this test is about: it makes
    ///        `lastTokYieldCum` land exactly on the write-off watermark (`cut == last`),
    ///        which the first cut of the epoch fold skipped.
    function _run(bool syncAtRotation)
        internal
        returns (uint256 pendingAfter, uint256 potAfter, bool claimReverted, uint256 claimed)
    {
        vm.prank(staker); vault.depositToken(100 ether);

        // 1. Ten ether of genuine short-side yield.
        eng.creditTokYield{value: 10 ether}();
        if (syncAtRotation) {
            vm.prank(staker); vault.depositToken(1);          // forces _syncTokYield
            assertEq(vault.lastTokYieldCum(), 10 ether, "vault observed the first credit");
            assertEq(vault.pendingTokYield(staker), 10 ether, "10 ETH earned");
        }

        // 2. A quote rotation writes the pot off. The staker's 10 ETH is gone: that
        //    is the intended forfeit and is NOT what this test is about.
        eng.rotationWriteOff();

        // 3. FIVE ETHER OF BRAND-NEW, FULLY-BACKED YIELD lands before the staker
        //    touches the vault again. This is post-write-off money the header
        //    promises is "preserved for everyone".
        eng.creditTokYield{value: 5 ether}();
        potAfter = eng.tokYieldEth();

        pendingAfter = vault.pendingTokYield(staker);
        uint256 before = staker.balance;
        vm.prank(staker);
        try vault.claimTokYield() returns (uint256) { claimReverted = false; }
        catch { claimReverted = true; }
        claimed = staker.balance - before;
    }

    /// REGRESSION (was the attack). The epoch fold's split branch required
    /// `cut > last`, so when the vault happened to be SYNCED at the rotation —
    /// `last` sitting exactly on the write-off watermark — the split never ran and
    /// {epochAcc} was stamped at the TOP of the fold, above the post-rotation
    /// accrual. Every wei of fully-backed NEW yield was forfeited and left stranded
    /// in the engine's pot with nobody able to claim it. The boundary is now `>=`
    /// (in fact `cut` is clamped into `[last, cum]` and the split is the only
    /// shape), so the forfeit lands on exactly the accrual the pot lost.
    function test_PostWriteOffYieldIsForfeitedAndStranded() public {
        (uint256 pendingAfter, uint256 potAfter, bool claimReverted, uint256 claimed) = _run(true);

        emit log_named_uint("pot backing after write-off (wei)", potAfter);
        emit log_named_uint("pendingTokYield after write-off (wei)", pendingAfter);
        emit log_named_uint("yieldEpoch", vault.yieldEpoch());

        assertEq(potAfter, 5 ether, "5 ETH of post-write-off yield really is in the pot");
        assertApproxEqAbs(pendingAfter, 5 ether, 1e9,
            "the only token staker is entitled to ALL of it");
        assertFalse(claimReverted, "claimTokYield no longer reverts on backed yield");
        assertApproxEqAbs(claimed, 5 ether, 1e9, "and she is actually paid it");
        assertLt(eng.tokYieldEth(), 1e9, "nothing is left stranded in the engine");
        assertEq(vault.yieldEpoch(), 1, "exactly one write-off was observed");
    }

    /// The OTHER side of the same boundary: the vault had NOT synced at the
    /// rotation, so `cut > last` and the split branch always ran. This case worked
    /// before and must keep working — it is the control that proves the fix moved
    /// the boundary rather than moving the bug.
    function test_FIXED_theUnsyncedCaseStillPaysPostWriteOffYield() public {
        (uint256 pendingAfter,, bool claimReverted, uint256 claimed) = _run(false);
        assertApproxEqAbs(pendingAfter, 5 ether, 1e9, "post-write-off yield is claimable");
        assertFalse(claimReverted, "and the claim goes through");
        assertApproxEqAbs(claimed, 5 ether, 1e9, "paid in full");
        assertLt(eng.tokYieldEth(), 1e9, "nothing stranded");
    }
}
