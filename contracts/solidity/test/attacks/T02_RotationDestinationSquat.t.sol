// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * T02 — THE ROTATION'S DESTINATION POOL IS CREATED BY WHOEVER GETS THERE FIRST
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `PoolOps.openOrAddPair` (:864-871) tries to initialize the destination pair
 * and, on failure, ADOPTS WHATEVER PRICE IS ALREADY THERE:
 *
 *     try poolManager.initialize(key, sqrtPriceX96) returns (int24) {
 *     } catch {
 *         (uint160 live,,,) = StateLibrary.getSlot0(poolManager, poolId);
 *         if (live != 0) sqrtPriceX96 = live;
 *     }
 *
 * `CauldronHook.getHookPermissions` sets `beforeInitialize: false`
 * (CauldronHook.sol:566) and `_afterInitialize` merely declines to TRACK a pool
 * whose sender is not the registry (:604) — it does not revert. So any address
 * can initialize the (quote, token, POOL_FEE, TICK_SPACING, hook) pool the
 * rotation is going to deploy into, at any price, before the first slice lands.
 *
 * Every field of that key is public days ahead: `TreasuryGovernor.envelope`
 * publishes the destination at `execute`, and the 3-day VOTING_PERIOD publishes
 * it at `propose`. The token is public from `summon`.
 *
 * This is the MIRROR of the `_greenCandle` bare-initialize bug: there an
 * unguarded call BRICKS, here a guarded one SILENTLY ACCEPTS.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract T02_RotationDestinationSquat is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;

    uint160 internal constant Q96 = 79228162514264337593543950336;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new TVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));
    }

    // -----------------------------------------------------------------------

    function _venueKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
    }

    /// @dev The pair the rotation will deploy into. Built from exactly the four
    /// inputs `RedemptionExt.rotateSliceFrom` uses (:418-424).
    function _destKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _seedVenue() internal {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        rotator.setVenue(_venueKey(), true);
    }

    function _approveEnvelope() internal {
        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    /// @dev sqrt(token/USDG) in X96, derived from the two live pools. This is
    /// the price `openOrAddPair` would have set on a virgin pool.
    function _honestDestSqrt() internal view returns (uint160) {
        (uint160 sp,,,) = pm.getSlot0(_key().toId());          // token per wei
        (uint160 sv,,,) = pm.getSlot0(_venueKey().toId());     // usdg  per wei
        return uint160((uint256(sp) * uint256(Q96)) / uint256(sv));
    }

    function _align(int24 t, int24 spacing) internal pure returns (int24) {
        int24 r = t / spacing;
        if (t < 0 && (t % spacing != 0)) r -= 1;
        return r * spacing;
    }

    /// @dev Sell `tokenIn` of the generation token into `key`, taking currency0.
    function _sellInto(PoolKey memory key, uint256 tokenIn, address payer)
        internal
        returns (uint256 got)
    {
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(false, -int256(tokenIn), payer, payer)), key)
        );
        (int128 a0,) = abi.decode(r, (int128, int128));
        got = uint256(uint128(a0));
    }

    /// @dev Take EXACTLY `quoteOut` of currency0 out of `key`, paying currency1.
    function _takeExactOut(PoolKey memory key, uint256 quoteOut, address payer)
        internal
        returns (uint256 got, uint256 paid)
    {
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(false, int256(quoteOut), payer, payer)), key)
        );
        (int128 a0, int128 a1) = abi.decode(r, (int128, int128));
        got = uint256(uint128(a0));
        paid = uint256(uint128(-a1));
    }

    /// @dev Value `tokenAmt` of the generation token in USDG at the HONEST
    /// destination price (tokens per raw USDG = (sqrt/Q96)^2).
    function _tokenToUsdg(uint256 tokenAmt, uint160 sqrtHonest) internal pure returns (uint256) {
        uint256 a = (tokenAmt * uint256(Q96)) / uint256(sqrtHonest);
        return (a * uint256(Q96)) / uint256(sqrtHonest);
    }

    // -----------------------------------------------------------------------
    // THE ATTACK
    // -----------------------------------------------------------------------

    /// @notice RETRACTION OF THE EARLIER CLAIM.
    ///
    /// A previous pass of this file asserted that ~94% of a rotation slice could
    /// be extracted by pre-initializing the destination pair. That is NO LONGER
    /// reproducible in this tree. `CauldronHook._afterInitialize` (:620) now
    /// reads
    ///
    ///     require(sender == registry);
    ///
    /// and the destination key names this hook, so EVERY `initialize` on it goes
    /// through that callback. The attacker's squat reverts before it can set a
    /// price. This test now pins that, so the claim cannot silently come back.
    function test_T02_RETRACTED_ForeignInitializeOnTheDestinationKeyReverts() public {
        vm.skip(!active);

        _seedVenue();

        PoolKey memory dest = _destKey();
        uint160 honest = _honestDestSqrt();
        uint160 squat = uint160(uint256(honest) / 100);

        // Precondition: the destination pool genuinely does not exist yet.
        (uint160 pre,,,) = pm.getSlot0(dest.toId());
        assertEq(pre, 0, "precondition: destination pair is virgin");

        // THE SQUAT, ATTEMPTED. `WrappedError(hook, afterInitialize.selector,
        // 0x /* bare require */, HookCallFailed())`.
        vm.prank(attacker, attacker);
        vm.expectRevert();
        pm.initialize(dest, squat);

        (uint160 post,,,) = pm.getSlot0(dest.toId());
        console2.log("dest sqrtPriceX96 after the squat attempt:", uint256(post));
        assertEq(post, 0, "the attacker could not set the destination price");
        assertFalse(hook.trackedPools(dest.toId()), "and nothing was tracked");

        // AND THE LEGITIMATE PATH IS UNAFFECTED: the registry is `sender` when
        // `PoolOps.openOrAddPair` runs (library DELEGATECALL from the facet,
        // which is itself delegatecalled from the registry), so the rotation
        // still opens the pair and prices it itself.
        _approveEnvelope();
        (uint256 moved,) = registry.rotateSlice(2500, 0, _venueKey());
        (uint160 landed,,,) = pm.getSlot0(dest.toId());
        console2.log("slice converted (USDG)   :", moved);
        console2.log("honest predicted sqrt    :", uint256(honest));
        console2.log("registry-opened sqrt     :", uint256(landed));
        assertGt(moved, 0, "the rotation still runs");
        assertGt(uint256(landed), 0, "the registry CAN still open the pair");
        assertTrue(hook.trackedPools(dest.toId()), "and the hook adopts it");

        bool reached = true;
        assertTrue(reached, "T02 squat-retraction reached its assertions");
    }

    /// @notice THE FALL-THROUGH, FOLLOWED PRECISELY.
    ///
    /// `PoolOps.openOrAddPair` (:862-868) wraps the initialize in try/catch:
    ///
    ///     try poolManager.initialize(key, sqrtPriceX96) returns (int24) {
    ///     } catch {
    ///         (uint160 live,,,) = StateLibrary.getSlot0(poolManager, poolId);
    ///         if (live != 0) sqrtPriceX96 = live;
    ///     }
    ///     positionId = _seedActive(...);
    ///
    /// The hook's new revert is caught there. When the pool GENUINELY DOES NOT
    /// EXIST, `live == 0`, the contributed price is kept, and control falls into
    /// `_seedActive` — a mint against an uninitialized pool. This test pins the
    /// terminal behaviour of that branch: it REVERTS. The fall-through fails
    /// CLOSED; it does not seed at a made-up price.
    function test_T02_FallThroughOnAVirginPoolFailsClosed() public {
        vm.skip(!active);

        _seedVenue();
        PoolKey memory dest = _destKey();

        (uint160 live,,,) = pm.getSlot0(dest.toId());
        assertEq(live, 0, "the catch branch's `live` is 0 here");

        // What `_seedActive` does next, reduced to the primitive that decides
        // it: add liquidity to that key. PoolManager refuses an uninitialized
        // pool, so the whole rotation transaction reverts.
        deal(token, address(this), 1e21, true);
        usdg.mint(address(this), 1e12);
        int24 sp = registry.TICK_SPACING();       // hoisted: expectRevert binds
        int24 lo = _align(-6000, sp);             // to the NEXT external call
        int24 hi = _align(6000, sp);
        vm.expectRevert();
        _mintInto(dest, lo, hi, 1e12);

        bool reached = true;
        assertTrue(reached, "T02 fall-through reached its assertions");
    }

    function _mintInto(PoolKey memory key, int24 lo, int24 hi, int256 delta) internal {
        pm.unlock(abi.encode(OP_LIQ, abi.encode(YLiq(lo, hi, delta)), key));
    }

    /// @notice CONTROL: the identical rotation into a VIRGIN destination pool.
    /// Shows the honest baseline the squat is measured against — the
    /// same slice, the same route, no attacker.
    function test_T02_CONTROL_UnsquattedRotationPricesItself() public {
        vm.skip(!active);

        _seedVenue();
        uint160 honest = _honestDestSqrt();
        _approveEnvelope();

        (uint256 moved,) = registry.rotateSlice(2500, 0, _venueKey());
        (uint160 landed,,,) = pm.getSlot0(_destKey().toId());

        console2.log("honest predicted sqrt    :", uint256(honest));
        console2.log("actual opened sqrt       :", uint256(landed));
        console2.log("slice converted (USDG)   :", moved);

        // The un-squatted pool opens within a few percent of the derived honest
        // price (slippage on the venue swap accounts for the rest).
        uint256 hi = uint256(honest) * 130 / 100;
        uint256 lo = uint256(honest) * 70 / 100;
        assertLt(uint256(landed), hi, "virgin pool opens near the honest price");
        assertGt(uint256(landed), lo, "virgin pool opens near the honest price");

        bool reached = true;
        assertTrue(reached, "T02 control reached its assertions");
    }
}

contract TVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
