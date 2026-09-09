// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";

/**
 * @dev A PoolManager stand-in exposing only what the mark source reads:
 *      `getSlot0` (for the tick) and `getLiquidity` (for the weight).
 *
 *      {StateLibrary} reads these through `extsload` on the real manager, so the
 *      mock implements `extsload` over a slot map that mirrors what the library
 *      computes. Rather than reproduce v4's slot maths, this mock implements the
 *      two library entrypoints' underlying storage reads directly — see
 *      {_setPool}, which writes the exact slots StateLibrary derives.
 */
contract MockPoolManager {
    // poolId => packed slot0 (sqrtPriceX96 | tick | protocolFee | lpFee)
    mapping(bytes32 => bytes32) public slot0Of;
    mapping(bytes32 => uint128) public liquidityOf;

    /// @dev StateLibrary reads `POOLS_SLOT` keyed state via extsload. We serve
    ///      the two slots it asks for: the pool's slot0 word and its liquidity.
    function extsload(bytes32 slot) external view returns (bytes32) {
        return _store[slot];
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory r) {
        r = new bytes32[](nSlots);
        for (uint256 i; i < nSlots; ++i) {
            r[i] = _store[bytes32(uint256(startSlot) + i)];
        }
    }

    mapping(bytes32 => bytes32) internal _store;

    function setStore(bytes32 slot, bytes32 val) external { _store[slot] = val; }
}

/**
 * Q-07 / P-1 — the liquidity-weighted mark, which is what lets a generation run
 *              SEVERAL POOLS *and* perps instead of choosing.
 *
 *  The engine used to mark off `slot0` of one pool. Split a generation's
 *  liquidity and the thin pool — the CHEAP one to push — stayed fully
 *  authoritative over liquidations, while the deep sibling set the price the
 *  market actually traded at. The protocol worked around it with an interlock
 *  ("several pools OR perps"); {PerpMarkSource} fixes the property instead.
 *
 *  These tests assert the properties that make the interlock unnecessary:
 *   1. the mark tracks the DEEP pool, not the thin one;
 *   2. pushing a thin pool barely moves the mark (the attack gets weaker, not
 *      stronger, as the split gets more lopsided);
 *   3. cross-quote pools are REFUSED, because their ticks are not comparable
 *      and making them so would put an oracle on the liquidation path;
 *   4. every degenerate configuration falls back to the primary's tick.
 */
contract Q07_WeightedMark is Test {
    using PoolIdLibrary for PoolKey;

    MockPoolManager pm;
    PerpMarkSource mark;

    address constant QUOTE = address(0); // native ETH
    address constant TOKEN = address(0xBEEF);

    PoolKey primaryKey;
    PoolKey siblingKey;

    function setUp() public {
        pm = new MockPoolManager();
        mark = new PerpMarkSource(IPoolManager(address(pm)), address(this));

        primaryKey = PoolKey({
            currency0: Currency.wrap(QUOTE),
            currency1: Currency.wrap(TOKEN),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        // Same pair, different fee tier — the realistic way depth splits.
        siblingKey = PoolKey({
            currency0: Currency.wrap(QUOTE),
            currency1: Currency.wrap(TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    // ── helpers: write the exact slots StateLibrary reads ────────────────────

    bytes32 constant POOLS_SLOT = bytes32(uint256(6));

    function _poolStateSlot(PoolId id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(id), POOLS_SLOT));
    }

    function _setPool(PoolKey memory key, int24 tick, uint128 liquidity) internal {
        bytes32 base = _poolStateSlot(key.toId());
        // slot0 layout: sqrtPriceX96 (160) | tick (24) | protocolFee (24) | lpFee (24)
        uint256 packed = uint256(uint160(1 << 96)) | (uint256(uint24(tick)) << 160);
        pm.setStore(base, bytes32(packed));
        // liquidity lives at base + 3 (see StateLibrary.LIQUIDITY_OFFSET)
        pm.setStore(bytes32(uint256(base) + 3), bytes32(uint256(liquidity)));
    }

    // ── the properties ───────────────────────────────────────────────────────

    /// THE CORE PROPERTY: with liquidity concentrated in the sibling, the mark
    /// follows the SIBLING, not the primary the engine used to read blindly.
    function test_Fixed_Q07_MarkFollowsTheDeepPoolNotThePrimary() public {
        // Primary is thin and sitting at a manipulated tick; the sibling is deep
        // and holds the honest price.
        _setPool(primaryKey, 60000, 1e18);      //  1 unit of depth, pushed high
        _setPool(siblingKey, 10000, 99e18);     // 99 units of depth, true price

        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);

        int24 t = mark.weightedTick();
        // Weighted: (60000*1 + 10000*99) / 100 = 10500 — pinned to the deep pool.
        assertEq(t, 10500, "the mark tracks the deep pool");
        assertLt(t, 12000, "and is nowhere near the pushed thin pool");
    }

    /// THE ATTACK GETS WEAKER, NOT STRONGER, AS THE SPLIT WORSENS. This is the
    /// property that makes the interlock unnecessary: under the old single-pool
    /// mark, a thinning primary became MORE authoritative; now it becomes less.
    function test_Fixed_Q07_PushingAThinPoolBarelyMovesTheMark() public {
        _setPool(primaryKey, 10000, 1e18);
        _setPool(siblingKey, 10000, 99e18);
        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);
        assertEq(mark.weightedTick(), 10000, "calm: both pools agree");

        // Attacker pushes the THIN primary a long way (10000 -> 110000).
        _setPool(primaryKey, 110000, 1e18);
        int24 pushed = mark.weightedTick();

        // (110000*1 + 10000*99)/100 = 11000 — a 100,000-tick shove in the cheap
        // pool moves the mark by 1,000. The old mark would have moved the FULL
        // 100,000, which is precisely how solvent positions got liquidated.
        assertEq(pushed, 11000, "a 100k-tick push yields a 1k-tick mark move");
        assertEq((110000 - 10000) / (pushed - 10000), 100, "attenuated 100x, exactly the depth ratio");
    }

    /// CROSS-QUOTE POOLS ARE REFUSED. Their ticks measure different things, and
    /// making them comparable needs a USD oracle on the LIQUIDATION path —
    /// deliberately out of scope, so the contract enforces the restriction
    /// rather than documenting it.
    function test_Fixed_Q07_ACrossQuotePoolIsRefused() public {
        mark.setPrimary(primaryKey);
        PoolKey memory foreign = PoolKey({
            currency0: Currency.wrap(address(0x1111)), // a different quote
            currency1: Currency.wrap(TOKEN),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        vm.expectRevert(PerpMarkSource.WrongPair.selector);
        mark.addPool(foreign);
    }

    /// FAIL-SOFT 1: with no siblings registered the answer is exactly the
    /// primary's tick — wiring a mark source changes nothing on day one.
    function test_Fixed_Q07_SinglePoolIsThePrimaryTick() public {
        _setPool(primaryKey, 12345, 5e18);
        mark.setPrimary(primaryKey);
        assertEq(mark.weightedTick(), 12345, "single pool = primary tick");
    }

    /// FAIL-SOFT 2: a sibling with NO in-range liquidity sets no price and is
    /// skipped, rather than dragging the mark toward a pool nobody can trade in.
    function test_Fixed_Q07_AnEmptySiblingIsIgnored() public {
        _setPool(primaryKey, 20000, 7e18);
        _setPool(siblingKey, 99000, 0); // no depth
        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);
        assertEq(mark.weightedTick(), 20000, "an empty pool cannot move the mark");
    }

    /// FAIL-SOFT 3: everything empty still yields the primary's tick.
    function test_Fixed_Q07_AllEmptyFallsBackToPrimary() public {
        _setPool(primaryKey, 4242, 0);
        _setPool(siblingKey, 9999, 0);
        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);
        assertEq(mark.weightedTick(), 4242, "falls back to the primary tick");
    }

    /// The pool set is CAPPED: this loop runs inside `afterSwap` on every swap.
    function test_Fixed_Q07_PoolSetIsCapped() public {
        mark.setPrimary(primaryKey);
        for (uint256 i; i < 4; ++i) {
            mark.addPool(PoolKey({
                currency0: Currency.wrap(QUOTE),
                currency1: Currency.wrap(TOKEN),
                fee: uint24(100 + i),
                tickSpacing: 200,
                hooks: IHooks(address(0))
            }));
        }
        assertEq(mark.poolCount(), 4, "four siblings");
        vm.expectRevert(PerpMarkSource.PoolCapped.selector);
        mark.addPool(PoolKey({
            currency0: Currency.wrap(QUOTE),
            currency1: Currency.wrap(TOKEN),
            fee: 999,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        }));
    }

    /// A new generation must not inherit the old one's pools.
    function test_Fixed_Q07_SetPrimaryClearsTheSiblings() public {
        mark.setPrimary(primaryKey);
        mark.addPool(siblingKey);
        assertEq(mark.poolCount(), 1, "sibling registered");
        mark.setPrimary(primaryKey); // a relaunch re-points the mark
        assertEq(mark.poolCount(), 0, "siblings cleared for the new generation");
    }

    /// Only the owner decides what the mark averages over.
    function test_Fixed_Q07_PoolSetIsOwnerGated() public {
        mark.setPrimary(primaryKey);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        mark.addPool(siblingKey);
    }
}
