// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/// PoolManager stand-in with a settable slot0 (sqrtPriceX96 | tick), which is
/// exactly what PerpEngine._currentTick() reads via StateLibrary.getSlot0.
contract X3dPM {
    bytes32 public s0;
    constructor() { setPrice(0, 79228162514264337593543950336); }
    function setPrice(int24 t, uint160 sp) public { s0 = bytes32((uint256(uint24(t)) << 160) | uint256(sp)); }
    function extsload(bytes32) external view returns (bytes32) { return s0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata x) external pure returns (bytes32[] memory r) { r = new bytes32[](x.length); }
}

contract X3dRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/**
 * X3d — `syncGeneration` wipes the TWAP ring (PerpEngine.sol:1055-1061) but the
 * only cold-start protection, `warmup`, is measured from `registry.lastSummonAt()`
 * (PerpEngine.sol:1283) and is NOT re-armed by a sync. A quote rotation is
 * mid-generation, so after the permissionless sync the 5-minute liquidation mark
 * collapses to whatever span the single seeded observation covers — `twapTick`
 * accepts it as `ok` on MIN_TWAP = 1 SECOND of history (PerpEngine.sol:268, :656).
 */
contract X3dRingResetCollapsesTwap is Test {
    X3dPM pm;
    X3dRegistry reg;
    PerpEngine perp;
    MockQuoteToken tok;
    MockQuoteToken usdg;
    int24 constant PUSH = 60000;      // the tick an attacker pushes the pool to
    uint256 ts;                       // explicit clock (block.timestamp is loop-hoisted by solc)

    function setUp() public {
        pm = new X3dPM();
        tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X3dRegistry(address(tok));
        reg.rotateQuote(address(0));
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), address(this)
        );
        usdg = new MockQuoteToken("USDG", "USDG", 18);
        ts = block.timestamp;
    }

    function _jump(uint256 d) internal { ts += d; vm.warp(ts); }

    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers ──────────────────────────────────────────────────────────────
    /// Fill the observation ring with 10 minutes of honest history at tick 0.
    function _fillRing() internal {
        for (uint256 i; i < 40; ++i) { _jump(15); perp.poke(); }
    }
    /// Hold the pool at `PUSH` for `secs` seconds of INTEGRATED time, then read
    /// the mark the liquidation path would use.
    function _pushAndRead(uint256 secs) internal returns (int24 t, bool ok) {
        pm.setPrice(PUSH, 79228162514264337593543950336);
        _jump(1); perp.poke();      // lastTick := PUSH
        _jump(secs); perp.poke();   // integrate `secs` at PUSH
        (t, ok) = perp.twapTick();
    }
    function _relaxTo(int24 t) internal {
        pm.setPrice(t, 79228162514264337593543950336);
        for (uint256 i; i < 24; ++i) { _jump(15); perp.poke(); }
    }
    /// A treasury quote rotation, followed by the permissionless sync.
    function _rotateAndSync() internal returns (bool ok) {
        reg.rotateQuote(address(usdg));
        vm.prank(address(0xBADBAD));
        try perp.syncGeneration() { ok = true; } catch { ok = false; }
    }

    function test_RotationResetsRingAndHandsTheMarkToA10SecondPush() public {
        _fillRing();
        (int24 baseTick, bool baseOk) = perp.twapTick();

        // ── POSITIVE CONTROL: with a warm ring the 5-minute TWAP resists a push.
        (int24 armedTick, bool armedOk) = _pushAndRead(10);
        _relaxTo(0);

        // ── ATTACK: a rotation wipes the ring; warmup is NOT re-armed.
        _jump(perp.warmup() + 1); perp.poke();   // the 24h open-warmup expires
        uint256 warmupEndsAt = reg.lastSummonAt() + perp.warmup();
        bool synced = _rotateAndSync();
        bool warmupLongExpired = block.timestamp > warmupEndsAt;

        //  ── THE FIX (red-team H-4) ──────────────────────────────────────────
        //  The wiped ring still REPORTS a collapsed mark — that is unavoidable,
        //  it has no history — but `_guardOpen` now re-arms off `ringArmedAt`, so
        //  nothing can be opened against it. `openCount == 0` is a precondition of
        //  the sync, so there is nothing already open either: the window is empty.
        bytes4 rightAfterSync = _tryOpen();
        (int24 resetTick, bool resetOk) = _pushAndRead(10);
        bytes4 duringWindow = _tryOpen();
        _jump(perp.twapWindow() + 1); perp.poke();
        bytes4 afterWindow = _tryOpen();

        // ── assertions ───────────────────────────────────────────────────────
        assertTrue(baseOk, "warm ring gives an ok mark");
        assertEq(baseTick, int24(0), "honest mark is tick 0");

        assertTrue(armedOk, "control: mark still ok under the push");
        assertLt(armedTick, int24(3000), "control: 10s of push moves a warm 5m TWAP <5%");

        assertTrue(synced, "syncGeneration is permissionless after a rotation");
        assertTrue(warmupLongExpired, "the 24h warmup gate is long past - opens are live");

        assertTrue(resetOk, "the wiped ring still reports a mark off ~1s of history");
        assertGt(resetTick, int24(45000), "and it IS collapsed - 10s of push dominates it");
        assertGt(int256(resetTick), int256(armedTick) * 15, "same push, 15x+ the effect");

        // ...but nobody may take leverage against it until the ring has refilled.
        assertEq(rightAfterSync, PerpEngine.NotWarm.selector, "opens gated the instant the ring is wiped");
        assertEq(duringWindow, PerpEngine.NotWarm.selector, "still gated while the collapsed mark stands");
        assertTrue(afterWindow != PerpEngine.NotWarm.selector, "gate LIFTS once twapWindow of history exists");
    }

    /// The revert selector `openLong` gives back, or 0x0 if it succeeded.
    function _tryOpen() internal returns (bytes4 sel) {
        //  The book is USDG-denominated after the rotation, so the collateral is
        //  pulled by transferFrom and NO value may be sent (PerpEngine._pullQuote).
        usdg.mint(address(this), 1 ether);
        usdg.approve(address(perp), 1 ether);
        try perp.openLong(1, 0, 0, 1 ether) returns (uint256) { return bytes4(0); }
        catch (bytes memory err) { if (err.length >= 4) { sel = bytes4(err); } }
    }

    receive() external payable {}
}
