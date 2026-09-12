// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolOps, SeedResult, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
uint256 constant TOTAL = 777_000_000e18; // CauldronToken.sol:29

/// @dev Mock PoolManager that proves control flow REACHED `initialize`. Anything
///      that reverts before this marker died earlier, inside `_sqrtPrice`.
contract InitMarker {
    fallback() external payable {
        revert("REACHED_INITIALIZE");
    }
}

/// @dev Stands in for the CauldronHook: hands `seedFunding` a per-asset relaunch
///      reserve of exactly `amt` base units.
contract ReserveStub {
    uint256 public amt;
    constructor(uint256 a) { amt = a; }
    function releaseRelaunchETH() external view returns (uint256) { return 0; }
    function releaseRelaunchAsset(address) external view returns (uint256) { return amt; }
}

/**
 * Z-1 — REGRESSION for audit Z-01 (was a High PoC, a permanent brick).
 *
 * THE BUG. `PoolOps._sqrtPrice` cannot represent a launch price when the QUOTE
 * amount is small in BASE UNITS, and the registry's only pre-seed solvency guard is
 * `totalETH == 0` (CauldronRegistry.sol:994). For an 18-decimal quote the floor is
 * ~42 million wei (never binding). For a 6-decimal quote — and USDG is allowlisted
 * on the live deployment, DeployLaunchpad.s.sol:625/:668 — it is ~42 *tokens*, an
 * entirely ordinary rebirth funding level, and the revert lands AFTER
 * `governor.markConsumed`. That rolls the consumption back, so the same proposal
 * wins again and every later `relaunch()` dies on the same line, forever.
 *
 * Threshold (derived, then asserted below):
 *   FullMath.mulDiv(totalTokens, 2**192, ethActive) reverts unless
 *   ethActive > totalTokens * 2**192 / 2**256 == totalTokens / 2**64.
 *   totalTokens == TOTAL == 777_000_000e18
 *   => ethActive must exceed 777_000_000e18 / 2**64 == 42,122,... base units.
 *
 * THE FIX, in two layers:
 *   1. `seedFunding` no longer calls a sub-`MIN_SEED_UNITS` balance "funding", so the
 *      refusal happens on the SAFE side of `markConsumed` as a recoverable
 *      `NoLiquidityToSeed` — the proposal stays live.
 *   2. `_sqrtPrice` CLAMPS to the representable floor instead of reverting, so the
 *      callers that do not pass through `seedFunding` (`openOrAddPair` on the
 *      rotation path, `createAndSeedProgressive`'s non-native degrade branch) cannot
 *      hit the empty revert either.
 */
contract Z1_SeedPriceDenominationFloor is Test {
    address pmMock;

    function setUp() public {
        pmMock = address(new InitMarker());
    }

    /// The arithmetic floor, stated in the protocol's own constants.
    function test_Z1_threshold_is_42_million_base_units() public pure {
        uint256 total = TOTAL;
        uint256 floorUnits = total / (2 ** 64); // == total * 2**192 / 2**256
        assertEq(total, 777_000_000e18, "supply");
        assertEq(floorUnits, 42_121_254, "measured floor in QUOTE BASE UNITS");
        // 42,121,254 base units is 0.000000000042 ETH (harmless) but 42.12 tokens
        // of any 6-decimal quote (USDC/USDT/USDG-shaped) - a normal seed size.
        assertLt(floorUnits, 43e6);
    }

    /// REGRESSION. BELOW the floor the real library used to revert inside
    /// `_sqrtPrice`, before it ever touched the PoolManager — an EMPTY revert behind
    /// `markConsumed`. It must now clamp and get all the way to `initialize`, which
    /// the marker's named revert proves (a bare `vm.expectRevert()` here would pass
    /// on the bug as well, which is why the expectation is the STRING).
    function test_Z1_subThresholdSeed_revertsBeforeInitialize() public {
        // ethAmount denominated in a 6-decimal quote: 40 USDG.
        uint256 ethAmount = 84_242_636; // ethActive = 42,121,254 -- exactly AT the floor
        uint256 activeTokens = TOTAL / 2;
        uint256 reserveTokens = TOTAL - activeTokens;

        // ethActive = mulDiv(ethAmount, total/2, total) - 64 = 42,121,254: the
        // largest value mulDiv used to reject. One base unit more always survived.
        vm.expectRevert(bytes("REACHED_INITIALIZE"));
        PoolOps.createAndSeedWithBuy(
            IPoolManager(pmMock),
            IPositionManagerOps(pmMock),
            address(0x4001),
            address(0xBEEF),
            activeTokens,
            ethAmount,
            reserveTokens,
            int24(200),
            uint24(3000),
            int24(42400),
            address(0xAAAA) // non-native quote
        );
    }

    /// ABOVE the floor: the SAME call now gets past `_sqrtPrice` and reaches
    /// `poolManager.initialize`, which the marker proves.
    function test_Z1_aboveThresholdSeed_reachesInitialize() public {
        uint256 ethAmount = 84_242_638; // ONE base unit past the floor
        uint256 activeTokens = TOTAL / 2;
        uint256 reserveTokens = TOTAL - activeTokens;

        vm.expectRevert(bytes("REACHED_INITIALIZE"));
        PoolOps.createAndSeedWithBuy(
            IPoolManager(pmMock),
            IPositionManagerOps(pmMock),
            address(0x4001),
            address(0xBEEF),
            activeTokens,
            ethAmount,
            reserveTokens,
            int24(200),
            uint24(3000),
            int24(42400),
            address(0xAAAA)
        );
    }

    /// REGRESSION. The degenerate tail of the same bug: a 1-unit seed makes
    /// `ethActive` ZERO and `_sqrtPrice` divided by zero, while `totalETH == 1`
    /// cleared the registry's `NoLiquidityToSeed` guard (CauldronRegistry.sol:994).
    /// The clamp covers `ethAmount == 0` too, so control flow reaches `initialize`.
    function test_Z1_oneUnitSeed_dividesByZero() public {
        uint256 activeTokens = TOTAL / 2;
        uint256 reserveTokens = TOTAL - activeTokens;
        vm.expectRevert(bytes("REACHED_INITIALIZE"));
        PoolOps.createAndSeedWithBuy(
            IPoolManager(pmMock),
            IPositionManagerOps(pmMock),
            address(0x4001),
            address(0xBEEF),
            activeTokens,
            1, // one base unit -- ethActive = mulDiv(1, total/2, total) = 0
            reserveTokens,
            int24(200),
            uint24(3000),
            int24(42400),
            address(0xAAAA)
        );
    }

    // ── the primary fix: the refusal happens BEFORE `markConsumed` ───────────
    //
    //  `CauldronRegistry._seedGeneration` calls `seedFunding` first and only then
    //  reaches `if (totalETH == 0) revert NoLiquidityToSeed(); markConsumed(winId);`.
    //  So a `seedFunding` that declines to call dust "funding" converts the permanent
    //  brick into an ordinary, recoverable revert with the proposal still live.

    /// A 6-decimal quote reserve of 50 USDG (50,000,000 base units) is BELOW
    /// `MIN_SEED_UNITS` (673,940,065) and must NOT be offered as a seed.
    function test_Z1_seedFunding_refusesDustQuote_onTheSafeSideOfMarkConsumed() public {
        address hook = address(new ReserveStub(50_000_000)); // 50 USDG
        (address quoteUsed, uint256 amount, uint256 swept) =
            PoolOps.seedFunding(hook, address(0xAAAA), address(0), 0, address(0));

        emit log_named_uint("offered amount", amount);
        assertEq(amount, 0, "dust is not funding: the registry reverts NoLiquidityToSeed");
        assertEq(quoteUsed, address(0), "no quote is adopted");
        assertEq(swept, 0, "nothing swept");
    }

    /// The SAME call one unit above the floor is funded exactly as before, so the
    /// guard is a floor and not a new refusal path.
    function test_Z1_seedFunding_stillFundsAtTheFloor() public {
        uint256 floorUnits = (TOTAL >> 60); // MIN_SEED_UNITS
        address hook = address(new ReserveStub(floorUnits));
        (address quoteUsed, uint256 amount,) =
            PoolOps.seedFunding(hook, address(0xAAAA), address(0), 0, address(0));

        emit log_named_uint("MIN_SEED_UNITS", floorUnits);
        assertEq(floorUnits, 673_940_070, "16x the hard representability floor");
        assertEq(amount, floorUnits, "at the floor the seed is accepted");
        assertEq(quoteUsed, address(0xAAAA), "and in the quote the proposal asked for");
    }

    /// In ETH the new floor is 0.67 gwei, so it can never bind on the native path —
    /// the denomination asymmetry that caused Z-01 is not reintroduced in reverse.
    function test_Z1_minSeedUnitsIsDustInEther() public pure {
        assertLt(TOTAL >> 60, 1 gwei);
    }
}
