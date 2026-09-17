// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/**
 * K3d — the DEAD path used to settle at any price at all.
 *
 *   PerpEngine.sol  forceCloseDead(uint256 id) external          // permissionless
 *   PerpEngine.sol      _settle(id, p, 0, MODE_DEATH, msg.sender) // literal minOut 0
 *   PerpEngine.sol      bool ownerSlippage = mode == MODE_NORMAL; // so 0 is never checked
 *   PerpEngine.sol      } else if (mode == MODE_DEATH && keeper != address(0)) { // keeper cut
 *
 * And a position CAN be on the book when the token reads dead: with a mark source
 * armed, `blocksVolumeLink()` is false regardless of `openCount`, so `linkVolume`
 * — and with it the quote rotation that flips `_isDead()` — goes through over an
 * OPEN book (T3d). A stranger could therefore sandwich his own force-close of a
 * SOLVENT position and keep the difference, with the keeper cut on top.
 *
 * THE FIX under test is {PerpEngine._deathBand}: on MODE_DEATH the realised price
 * must sit inside DEATH_SLIP_BPS (10%) of the engine's OWN TWAP mark, in both
 * directions. This drives that function on a REAL PerpEngine (via a thin harness
 * that only widens its visibility — no reimplementation, no mock of the maths)
 * against a real mark read out of the engine's real TWAP machinery.
 *
 * Reaching MODE_DEATH through `forceCloseDead` end-to-end needs a live v4 pool to
 * swap against; `test_Invariant_A03_ForceCloseAllDeadClearsEveryPosition`
 * (A02_PerpAttacks, on fork) covers that wiring and still passes with the band in
 * place, so honest force-closes are unaffected.
 */
contract K3d_DeathBandProtectsForcedClose is Test {
    Harness perp;
    address timelock = address(0x7171);

    function setUp() public {
        StubPM pm = new StubPM();
        StubRegistry reg = new StubRegistry(address(new StubERC20()));
        perp = new Harness(
            IPoolManager(address(pm)), address(new StubHook()), address(reg),
            address(new StubERC721()), address(0xD1), address(0x7E), timelock
        );
    }

    uint160 constant ONE = 79228162514264337593543950336; // sqrtPrice for 1:1

    /// Positive control: the stub pool is 1:1, so the engine's own mark is ONE and
    /// every band below is read against it.
    function test_control_theMarkIsOneToOneSoTheBandIsReadable() public view {
        assertEq(perp.markSqrtPriceX96(), ONE, "1:1 sqrtPrice");
        assertEq(perp.quoteMark(10 ether), 10 ether, "10 tokens mark at 10 ETH");
    }

    // ── (a) a forced SALE is CAPPED at the band edge, never refused ──────────
    //    A long close SELLS, which pushes the pool price UP and the position's
    //    value DOWN, so the band is a CEILING at mark*sqrt(1/0.9).
    function test_FIXED_aForcedSaleIsCappedAtTheBandEdgeNotRefused() public view {
        uint160 lim = perp.band(false);
        assertGt(lim, ONE, "a sell limit sits ABOVE spot: the swap may move price up, but only this far");
        assertApproxEqRel(uint256(lim), uint256(ONE) * 1054093 / 1e6, 1e12,
            "the ceiling is mark*sqrt(1/0.90) - a 10% VALUE band");
        //  The 10% claim, restated in the units the trader feels: value scales with
        //  (Q96/sp)^2, so filling all the way out to the limit still returns 90%.
        assertApproxEqRel(perp.quoteMark(10 ether) * 1e18 / _valueAt(10 ether, lim), uint256(1e18) * 10 / 9, 1e12,
            "a fill at the very edge still clears 90% of the marked value");
    }

    // ── (b) a forced BUY-BACK is floored, so a keeper cannot squeeze it ──────
    function test_FIXED_aForcedBuyBackIsFlooredAtTheBandEdge() public view {
        uint160 lim = perp.band(true);
        assertLt(lim, ONE, "a buy limit sits BELOW spot: price may move down, but only this far");
        assertApproxEqRel(uint256(lim), uint256(ONE) * 953463 / 1e6, 1e12,
            "the floor is mark*sqrt(1/1.10) - the mirrored 10% band");
    }

    // ── (c) the buy-back takes the TIGHTER of the budget bound and the band ──
    function test_FIXED_closeLimitTakesTheTighterOfBudgetAndBand() public pure {
        uint160 band = uint160(uint256(ONE) * 953463 / 1e6);
        uint128 L = 1e24;
        // A huge budget would let the price run far below the band; the band wins.
        uint160 lim = PerpSwapLib.closeLimit(ONE, L, 1e24, true, band);
        assertEq(lim, band, "the band binds when the budget would allow a bigger move");
        // A tiny budget cannot even reach the band edge; the budget bound wins.
        uint160 tight = PerpSwapLib.closeLimit(ONE, L, 1, true, band);
        assertGt(tight, band, "the budget binds when it is the tighter of the two");
        // And with no band asked for, the budget bound is returned unchanged.
        assertEq(PerpSwapLib.closeLimit(ONE, L, 1, true, 0), tight, "band 0 == pre-band behaviour");
    }

    // ── (d) THE LIQ-02 PROPERTY: outside the band it fills nothing, never reverts
    //    A reverting band made a short bigger than the pool unclearable and blocked
    //    the relaunch (XL1_LiqTwapAndDepthCap:520). Pinning the limit one wei from
    //    spot yields a ~zero fill, which the caller's partial path handles.
    function test_FIXED_alreadyOutsideTheBandFillsNothingInsteadOfReverting() public pure {
        uint160 mark = ONE;
        uint160 crashed = uint160(uint256(ONE) / 2);   // spot already far past the buy floor
        uint160 lim = PerpSwapLib.bandLimit(mark, crashed, true, true);
        assertEq(lim, crashed - 1, "pinned one wei from spot: fills ~nothing, does NOT revert");
        uint160 spiked = uint160(uint256(ONE) * 3);    // spot already past the sell ceiling
        assertEq(PerpSwapLib.bandLimit(mark, spiked, false, true), spiked + 1,
            "same on the sell side - the book stays clearable");
    }

    /// The band is pinned to the engine's own mark, not to anything the caller
    /// supplies, and it is disabled only in the documented carve-out (a quote that
    /// sorts SECOND, where {PerpEngine._quoteAt}'s value convention is inverted).
    function test_FIXED_thereIsNoCallerSuppliedFloorOnTheDeadPath() public pure {
        assertEq(PerpSwapLib.bandLimit(ONE, ONE, true, false), 0,
            "quote-not-currency0 gets no band, exactly as documented");
        assertEq(PerpSwapLib.bandLimit(0, ONE, true, true), 0, "no mark, no band");
    }

    /// @dev value = size*(Q96/sp)^2, the same convention as PerpEngine._quoteAt.
    function _valueAt(uint256 size, uint160 sp) internal pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(size, uint256(ONE), sp), uint256(ONE), sp);
    }
}

/// @dev Visibility-only harness: it adds no logic, it just makes the real
///      `internal` functions callable from a test. Any change to the real
///      {PerpEngine._deathBand} is seen here immediately.
contract Harness is PerpEngine {
    constructor(
        IPoolManager _pm, address _hook, address _registry, address _mifrens,
        address _dividend, address _treasury, address _owner
    ) PerpEngine(_pm, _hook, _registry, _mifrens, _dividend, _treasury, _owner) {}

    /// The exact expression {_settle} uses to build the dead path's swap limit.
    function band(bool buy) external view returns (uint160) {
        return PerpSwapLib.bandLimit(markSqrtPriceX96(), _sqrtP(), buy, quote < syncedToken);
    }
    function quoteMark(uint256 size) external view returns (uint256) { return _quoteMark(size); }
}

// ── stubs (same shape as K3c's) ─────────────────────────────────────────────

contract StubPM {
    function extsload(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(79228162514264337593543950336));
    }
    function extsload(bytes32 startSlot, uint256 n) external pure returns (bytes32[] memory r) {
        startSlot; r = new bytes32[](n);
        for (uint256 i; i < n; ++i) r[i] = bytes32(uint256(79228162514264337593543950336));
    }
    function extsload(bytes32[] calldata slots) external pure returns (bytes32[] memory r) {
        r = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) r[i] = bytes32(uint256(79228162514264337593543950336));
    }
}

contract StubHook {
    function isDead(PoolId) external pure returns (bool) { return false; }
}

contract StubERC20 {
    uint8 public constant decimals = 18;
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract StubERC721 {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract StubRegistry {
    address public immutable currentToken;
    constructor(address t) { currentToken = t; }
    function currentGeneration() external pure returns (uint256) { return 1; }
    function generationQuote(uint256) external pure returns (address) { return address(0); }
    function lastSummonAt() external pure returns (uint256) { return 1; }
    function generationPoolId(uint256) external pure returns (PoolId) { return PoolId.wrap(bytes32(0)); }
    function generationToken(uint256) external view returns (address) { return currentToken; }
}
