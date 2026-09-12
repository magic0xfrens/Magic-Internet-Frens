// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X9dPM {
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X9dRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/// {QuoteOracle}-shaped: `usdPerRawUnit` is 1e18-scaled USD per RAW unit, so it
/// already contains the token's decimals (QuoteOracle.sol:202). ETH at $3,000 and
/// two dollar-pegged quotes, one 18-decimal and one 6-decimal.
contract X9dOracle {
    mapping(address => uint256) public usdPerRawUnit;
    function set(address q, uint256 f) external { usdPerRawUnit[q] = f; }
}

/**
 * X9d — REGRESSION for F-03.
 *
 * `_q()` rescaled the UNITS of its wei-written thresholds (`10**decimals()`), but
 * every one of those constants is a VALUE statement: `tierDepthWei = [25, 100,
 * 300] ether` means "≈ $80k / $320k / $1M of pool depth" and `insuranceFloor =
 * 0.05 ether` means "≈ $160". Unit scaling turned them into $25 / $100 / $300 and
 * $0.05 on a 6-decimal stable — ~1e12 of economic meaning gone — so the leverage
 * tiering, the dust filter and the insurance circuit breaker all silently switched
 * off, with no event and no revert. A `decimals()` of 0 made them exactly zero.
 *
 * The scale is now a VALUE factor priced through the protocol's own quote oracle,
 * and an unpriceable quote falls back to a unit count CLAMPED at 1e6 so a
 * degenerate `decimals()` can only over-apply a protection, never disable one.
 *
 * `insuranceEth < _q(insuranceFloor) + amount` in {skimInsurance} is the exact,
 * un-mocked read of `_q(insuranceFloor)`: fund the buffer to F+1 and the last wei
 * is skimmable, fund it to F and nothing is. That pins the threshold to the wei.
 */
contract X9dQuoteThresholdValue is Test {
    uint256 constant ETH_USD = 3_000e18;                 // 1e18-scaled USD / ETH
    uint256 constant P_NATIVE = ETH_USD;                 // USD per wei, 1e18-scaled
    uint256 constant P_PEG18 = 1e18 * 1e18 / 1e18;       // $1 token, 18 decimals
    uint256 constant P_PEG6 = 1e18 * 1e18 / 1e6;         // $1 token, 6 decimals
    uint256 constant FLOOR_WEI = 0.05 ether;             // DeployPerp's INSURANCE_FLOOR_WEI
    /// 0.05 ETH at $3,000 = $150. The SAME economic amount in either quote.
    uint256 constant FLOOR_USD18 = 150e18;
    uint256 constant FLOOR_USD6 = 150e6;

    X9dOracle oracle;

    function setUp() public {
        oracle = new X9dOracle();
        oracle.set(address(0), P_NATIVE);
    }

    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers ──────────────────────────────────────────────────────────────

    /// A live engine that has ADOPTED `q` through the real `syncGeneration`, with
    /// the insurance floor armed exactly as the deploy script arms it.
    function _engineOn(MockQuoteToken q) internal returns (PerpEngine perp) {
        X9dPM pm = new X9dPM();
        MockQuoteToken tok = new MockQuoteToken("Gen1", "G1", 18);
        X9dRegistry reg = new X9dRegistry(address(tok));
        reg.rotateQuote(address(0));
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), address(this)
        );
        perp.setRouting(address(0xD1D1), address(0x7E7E), address(0x7E7E), address(0), address(oracle), 3_000, 1_000);
        perp.setVaultLimits(5_000, FLOOR_WEI);
        reg.rotateQuote(address(q));
        perp.syncGeneration();
    }

    /// Top the insurance buffer up to exactly `amount` raw units of the quote.
    function _fundInsurance(PerpEngine perp, MockQuoteToken q, uint256 amount) internal {
        q.mint(address(this), amount);
        q.approve(address(perp), amount);
        perp.fundInsurance(amount);
    }

    /// Can the owner skim one raw unit out of the buffer? False == the circuit
    /// breaker's protected floor is biting, which is what we are measuring.
    function _canSkimOne(PerpEngine perp) internal returns (bool ok) {
        try perp.skimInsurance(1, address(0xFEE)) { ok = true; } catch { ok = false; }
    }

    function test_ThresholdsMeanTheSameValueOn18And6DecimalQuotes() public {
        // ── the scale factor itself, both quotes ─────────────────────────────
        MockQuoteToken q18 = new MockQuoteToken("USDG18", "USDG18", 18);
        MockQuoteToken q6 = new MockQuoteToken("USDG6", "USDG6", 6);
        oracle.set(address(q18), P_PEG18);
        oracle.set(address(q6), P_PEG6);

        uint256 f18 = PerpSwapLib.quoteFactor(address(oracle), address(q18));
        uint256 f6 = PerpSwapLib.quoteFactor(address(oracle), address(q6));
        // `_q(wei18) = wei18 * factor / 1e18`, reproduced here from the source.
        uint256 floor18 = FLOOR_WEI * f18 / 1e18;
        uint256 floor6 = FLOOR_WEI * f6 / 1e18;

        // ── and what a LIVE engine actually enforces after adopting each ─────
        PerpEngine e18 = _engineOn(q18);
        _fundInsurance(e18, q18, FLOOR_USD18 + 1);
        bool skim18AtFloorPlusOne = _canSkimOne(e18);
        bool skim18AtFloor = _canSkimOne(e18);           // now exactly at the floor

        PerpEngine e6 = _engineOn(q6);
        _fundInsurance(e6, q6, FLOOR_USD6 + 1);
        bool skim6AtFloorPlusOne = _canSkimOne(e6);
        bool skim6AtFloor = _canSkimOne(e6);

        // ── an unpriceable quote must not disable the protection ─────────────
        MockQuoteToken qDead = new MockQuoteToken("NOFEED", "NOFEED", 6);   // not in the oracle
        MockQuoteToken q0 = new MockQuoteToken("ZERODEC", "ZERODEC", 0);    // decimals() == 0
        uint256 fUnpriced = PerpSwapLib.quoteFactor(address(oracle), address(qDead));
        uint256 fZeroDec = PerpSwapLib.quoteFactor(address(oracle), address(q0));

        // ── assertions ───────────────────────────────────────────────────────
        assertEq(floor18, FLOOR_USD18, "0.05 ETH of insurance = $150 on an 18-decimal quote");
        assertEq(floor6, FLOOR_USD6, "...and the SAME $150 on a 6-decimal quote");
        assertEq(floor6 * 1e12, floor18, "the two differ by decimals ALONE, not by 1e12 of value");

        assertTrue(skim18AtFloorPlusOne, "the wei above the floor is skimmable (18-dec)");
        assertFalse(skim18AtFloor, "and the protected $150 floor is not (18-dec)");
        assertTrue(skim6AtFloorPlusOne, "the unit above the floor is skimmable (6-dec)");
        assertFalse(skim6AtFloor, "and the protected $150 floor is not (6-dec)");

        assertEq(fUnpriced, 1e6, "an unpriceable quote falls back to its UNIT count...");
        assertEq(fZeroDec, 1e18, "...and a degenerate decimals() to 1e18, never to a scale of 1");
        assertGt(FLOOR_WEI * fZeroDec / 1e18, 0, "so a zero-decimal quote cannot zero the floor");
    }
}
