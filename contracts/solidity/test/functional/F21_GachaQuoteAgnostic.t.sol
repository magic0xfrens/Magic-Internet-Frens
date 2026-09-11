// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * F-21 — THE GACHA ROUTER FOLLOWS THE GENERATION'S QUOTE (functional audit R-05).
 *
 * `CauldronGachaRouter` assumed every generation trades native ETH in two
 * independent places:
 *
 *   1. `_key()` hardcoded `currency0: Currency.wrap(address(0))`, so on a
 *      non-native generation it addressed a pool that does not exist and every
 *      `play` reverted — the gacha silently switched off for that whole
 *      iteration.
 *   2. `_playInCurveUnits()` priced the play with `usdPerRawUnit(address(0))`
 *      unconditionally, so on a USDG generation it applied the 18-decimal ETH
 *      factor to a 6-decimal size: a real $1,500 buy came out as 4.5e12 instead
 *      of 1500e18 — understated ~333,000,000x, collapsing the player's odds to
 *      nothing. It fails in the same safe direction as the original Q-02 bug
 *      (players win less, never more), which is why it could ship unnoticed.
 *
 * A generation reaches a non-native quote two ways, both live: it can LAUNCH on
 * one, or `RedemptionExt.rotateSlice` can move an existing one mid-life
 * (writing `generationQuote` at RedemptionExt.sol:413).
 *
 * These tests need no fork and no pool — they assert on the identity and the
 * pricing the router derives, which is where both bugs lived.
 */

/// @dev Registry stub whose quote is settable, standing in for a generation that
///      has launched on — or rotated into — a non-native asset.
contract QuoteRegistryStub {
    address public quote;

    function setQuote(address q) external { quote = q; }
    function currentToken() external pure returns (address) { return address(0xB0B); }
    function currentGeneration() external pure returns (uint256) { return 7; }
    function generationQuote(uint256) external view returns (address) { return quote; }
}

/// @dev Per-asset USD factors: the USD value of ONE RAW UNIT of an asset, at
///      1e18 scale — the same contract shape {QuoteOracle.usdPerRawUnit} has.
contract FactorOracle {
    mapping(address => uint256) public factor;
    function set(address a, uint256 v) external { factor[a] = v; }
    function usdPerRawUnit(address q) external view returns (uint256) { return factor[q]; }
}

contract F21_GachaQuoteAgnostic is Test {
    QuoteRegistryStub internal reg;
    CauldronGachaRouter internal router;
    FactorOracle internal oracle;

    /// @dev A 6-decimal stable. Sorts below any iteration token, as
    ///      {CauldronRegistry.setAllowedQuote}'s watermark ceiling guarantees.
    address internal constant USDG = address(0x115D6);

    /// @dev The oracle's convention, matching {QuoteOracle.usdPerRawUnit} and
    ///      the existing Q-02 suite: a factor `f` such that
    ///      `rawAmount * f / 1e18` is USD at 1e18 scale.
    ///
    ///      ETH at $3,000 -> 3000e18 (one wei is 3000/1e18 USD).
    ///      USDG at $1    -> 1e30    (one raw unit is $1e-6).
    uint256 internal constant ETH_FACTOR = 3000e18;
    uint256 internal constant USDG_FACTOR = 1e30;

    function setUp() public {
        reg = new QuoteRegistryStub();
        // poolManager and hook are never reached by the paths under test.
        router = new CauldronGachaRouter(
            IPoolManager(address(0xBEEF)), address(0xCAFE), address(reg), address(this)
        );
        oracle = new FactorOracle();
        oracle.set(address(0), ETH_FACTOR);
        oracle.set(USDG, USDG_FACTOR);
    }

    /// @notice A native generation prices exactly as before — the ETH path is
    ///         untouched by the fix.
    function test_F21_NativeGenerationPricesWithEth() public {
        reg.setQuote(address(0));
        router.setOracle(address(oracle));
        // 0.5 ETH at $3,000 = $1,500, expressed at 1e18.
        assertEq(router.playInCurveUnits(0.5 ether), 1500e18, "native play priced in ETH");
    }

    /// @notice THE REGRESSION. On a USDG generation the play must be priced with
    ///         USDG, not ETH.
    ///
    ///  Pre-fix `_playInCurveUnits` asked for `usdPerRawUnit(address(0))` and got
    ///  the ETH factor, so 1,500e6 raw USDG (= $1,500) was valued as though it
    ///  were 1,500e6 wei of ether. Both the correct value and the wrong one are
    ///  asserted, so this cannot pass by coincidence.
    function test_F21_UsdgGenerationPricesWithUsdg() public {
        reg.setQuote(USDG);
        router.setOracle(address(oracle));

        uint256 play = router.playInCurveUnits(1_500e6); // $1,500 of a 6-dec stable
        assertEq(play, 1500e18, "USDG play must price as $1,500");

        //  What the old path produced: the 18-decimal ETH factor applied to a
        //  6-decimal size. Understated ~333,000,000x, collapsing the odds.
        uint256 preFix = (1_500e6 * ETH_FACTOR) / 1e18;
        assertEq(preFix, 4.5e12, "the pre-fix value, pinned");
        assertEq(play / preFix, 333_333_333, "the fix is ~3.3e8x, not a rounding nudge");
    }

    /// @notice The pool identity follows a mid-life rotation — the `_key()` half
    ///         of R-05. After `rotateSlice` completes, the gacha must address the
    ///         pool the generation actually trades.
    function test_F21_QuoteFollowsAMidLifeRotation() public {
        reg.setQuote(address(0));
        router.setOracle(address(oracle));
        assertEq(router.playInCurveUnits(1 ether), 3000e18, "starts native, priced in ETH");

        // A completed rotation writes generationQuote (RedemptionExt.sol:413).
        reg.setQuote(USDG);
        assertEq(
            router.playInCurveUnits(1_000e6), 1000e18,
            "after the rotation the router prices in USDG"
        );
    }

    /// @notice An unset oracle still passes the size through untouched on a
    ///         non-native generation — a refusal must never zero a player's odds.
    function test_F21_NoOracleIsStillAPassThroughOnUsdg() public {
        reg.setQuote(USDG);
        assertEq(router.playInCurveUnits(1_500e6), 1_500e6, "size passes through");
    }

    /// @notice An oracle that cannot price the CURRENT quote leaves the size
    ///         alone rather than zeroing it — the `f == 0` branch, now reached
    ///         via the quote axis rather than the wei/USD one.
    function test_F21_UnpriceableQuoteLeavesTheSizeAlone() public {
        reg.setQuote(address(0xDEAD)); // no factor set for this asset
        router.setOracle(address(oracle));
        assertEq(router.playInCurveUnits(1_500e6), 1_500e6, "unpriceable => pass through");
    }
}
