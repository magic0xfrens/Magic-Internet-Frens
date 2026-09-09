// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";

/// @dev Minimal QuoteOracle stand-in: ETH at $3,000, expressed exactly the way
///      {QuoteOracle.usdPerRawUnit} does —
///        perWhole = $3,000 at 1e18            = 3000e18
///        factor   = perWhole * 1e18 / 10**18  = 3000e18
///      so `raw * factor / 1e18` turns 0.5e18 wei into 1500e18 = $1,500.
contract EthUsdOracle {
    uint256 public factor;
    constructor(uint256 f) { factor = f; }
    function usdPerRawUnit(address) external view returns (uint256) { return factor; }
}

/// @dev An oracle that refuses to price (returns 0 = "cannot judge").
contract RefusingOracle {
    function usdPerRawUnit(address) external pure returns (uint256) { return 0; }
}

/// @dev An oracle that reverts — must degrade, never brick a spin.
contract BrokenOracle {
    function usdPerRawUnit(address) external pure returns (uint256) { revert("boom"); }
}

/// @dev Stands in for the registry the router reads `currentToken()` from.
contract StubRegistry {
    function currentToken() external pure returns (address) { return address(0xB0B); }
}

/**
 * Q-02 — the odds curve's UNIT must be the same whichever interface forged the
 *        crystal. REGRESSION for the fix.
 *
 *  U-1 restated `oddsFullVolumeWei` into USD whenever an oracle is wired
 *  (`CauldronHook.setDeathThreshold`, :1586-1596), and `oddsForPlay` divides the
 *  play size by it (`:1947`) — so the play size must be USD too. The hook's
 *  NATIVE in-swap path feeds USD (`weighted`, from the USD-converted volume at
 *  `:768`/`:821`/`:848`). The gacha ROUTER measured an honest ETH notional
 *  (`CauldronGachaRouter:231`) and was never updated, so post-oracle it handed a
 *  wei numerator to a USD denominator and its players' odds collapsed by roughly
 *  the ETH price.
 *
 *  FIX: the router converts its ETH notional into curve units via its own
 *  `oracle` pointer ({CauldronGachaRouter._playInCurveUnits}) before calling
 *  `commitCrystals`. The conversion lives in the router because {CauldronHook}
 *  is against the EIP-170 ceiling with tens of bytes to spare.
 *
 *  These tests assert the router's conversion directly (the arithmetic that was
 *  wrong), plus the hook-side property that the two units now line up.
 */
contract Q02_GachaOddsUnitMismatch is Test {
    CauldronHook hook;
    CauldronGachaRouter router;

    // ETH = $3,000, as QuoteOracle reports it (USD per raw wei, scaled 1e18).
    uint256 constant ETH_USD_FACTOR = 3000e18;

    function setUp() public {
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(1)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(address(1)), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");

        router = new CauldronGachaRouter(
            IPoolManager(address(1)), address(hook), address(new StubRegistry()), address(this)
        );
    }

    /// The core regression: with the USD curve wired, a $1,500 buy reaches the
    /// SAME odds through the router as it does through the native in-swap path.
    function test_Fixed_Q02_RouterAndNativeAgreeUnderOracle() public {
        //  POST-U-1 STATE: "$1000 of volume reaches max odds".
        hook.setOddsParams(1000e18, 8);
        uint256 maxOdds = hook.maxOddsBps(); // 9000 bps

        router.setOracle(address(new EthUsdOracle(ETH_USD_FACTOR)));

        //  The trade: a $1,500 buy = 0.5 ETH at $3,000.
        uint256 ethNotional = 0.5 ether;

        //  ROUTER, after the fix: converts to USD before the hook sees it.
        uint256 routerPlay = router.playInCurveUnits(ethNotional);
        assertEq(routerPlay, 1500e18, "router expresses the play as $1,500");

        //  The hook prices both at the same odds now.
        uint256 oddsRouter = hook.oddsForPlay(routerPlay);
        uint256 oddsNative = hook.oddsForPlay(1500e18); // what afterSwap would feed
        assertEq(oddsRouter, oddsNative, "same trade, same odds, either interface");
        assertEq(oddsRouter, maxOdds, "and a $1,500 play reaches max odds as intended");

        //  Pre-fix this same trade produced 4 bps via the router — pin the gap is
        //  gone (the raw wei size would still price at ~0).
        assertLt(hook.oddsForPlay(ethNotional), 10, "the raw ETH size WOULD have collapsed");
    }

    /// With NO oracle wired the curve is in ether terms, so the size must pass
    /// through untouched — today's behaviour exactly, and the safe default.
    function test_Fixed_Q02_NoOracleIsAPassThrough() public {
        assertEq(router.oracle(), address(0), "unset by default");
        assertEq(router.playInCurveUnits(0.5 ether), 0.5 ether, "size passes through");
        // Default oddsFullVolumeWei = 0.5 ether ⇒ 0.5 ETH reaches max odds.
        assertEq(hook.oddsForPlay(0.5 ether), hook.maxOddsBps(), "ether curve still agrees");
    }

    /// An oracle that REFUSES to price (0 = "cannot judge") must leave the play
    /// size alone rather than zeroing a player's odds.
    function test_Fixed_Q02_RefusedPriceDoesNotZeroTheOdds() public {
        router.setOracle(address(new RefusingOracle()));
        assertEq(router.playInCurveUnits(0.5 ether), 0.5 ether, "refusal leaves the size unchanged, not 0");
    }

    /// A reverting oracle must degrade to the raw size, never brick the spin.
    function test_Fixed_Q02_BrokenOracleDegradesInsteadOfReverting() public {
        router.setOracle(address(new BrokenOracle()));
        assertEq(router.playInCurveUnits(0.5 ether), 0.5 ether, "broken oracle leaves the size unchanged");
    }

    /// Only the owner may point the router at an oracle — it decides how every
    /// player's odds are scaled.
    function test_Fixed_Q02_OracleIsOwnerGated() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        router.setOracle(address(0xDEAD));
    }
}
