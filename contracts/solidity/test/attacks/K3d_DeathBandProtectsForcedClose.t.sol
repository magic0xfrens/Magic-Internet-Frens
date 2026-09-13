// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";

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

    /// Positive control: the stub pool is 1:1, so the engine's own mark values
    /// `size` tokens at exactly `size` wei. Every band below is read against this.
    function test_control_theMarkIsOneToOneSoTheBandIsReadable() public view {
        assertEq(perp.markSqrtPriceX96(), 79228162514264337593543950336, "1:1 sqrtPrice");
        assertEq(perp.quoteMark(10 ether), 10 ether, "10 tokens mark at 10 ETH");
    }

    // ── (a) a forced SALE more than 10% below the mark is refused ────────────
    function test_FIXED_deadPathRefusesASaleBelowTheMarkBand() public {
        // 8.9 ETH for a position the engine itself marks at 10 ETH: an 11% haircut
        // the keeper would have pocketed.
        vm.expectRevert(PerpEngine.Slippage.selector);
        perp.deathBand(false, 8.9 ether, 10 ether);
    }

    // ── (b) an honest forced close, inside the band, still goes through ──────
    function test_FIXED_deadPathStillAllowsAnHonestForcedClose() public view {
        perp.deathBand(false, 9.5 ether, 10 ether);   // 5% slip: normal depth
        perp.deathBand(false, 9 ether, 10 ether);     // exactly at the floor
        perp.deathBand(false, 11 ether, 10 ether);    // better than mark: never refused
    }

    // ── (c) a keeper cannot profit by buying a SOLVENT short back above mark ─
    function test_FIXED_aKeeperCannotSqueezeTheBuyBackAboveTheMarkBand() public {
        perp.deathBand(true, 10.9 ether, 10 ether);   // 9% over: inside the band
        vm.expectRevert(PerpEngine.Slippage.selector);
        perp.deathBand(true, 11.1 ether, 10 ether);   // 11% over: refused
    }

    /// The band is symmetric and pinned to the constant, not to the caller: a
    /// stranger has no argument that widens it. 20% below mark on a solvent
    /// position — the profitable sandwich — is refused outright.
    function test_FIXED_thereIsNoCallerSuppliedFloorOnTheDeadPath() public {
        vm.expectRevert(PerpEngine.Slippage.selector);
        perp.deathBand(false, 8 ether, 10 ether);
        assertEq(perp.slipBps(), 1000, "the band is a constant 10%, not an argument");
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

    function deathBand(bool buy, uint256 realised, uint256 size) external view {
        _deathBand(buy, realised, size);
    }
    function quoteMark(uint256 size) external view returns (uint256) { return _quoteMark(size); }
    function slipBps() external pure returns (uint256) { return DEATH_SLIP_BPS; }
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
