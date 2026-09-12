// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {SeederConfig} from "../../cauldron/ISeeder.sol";

/**
 * @notice T9c — REGRESSION for audit Z-18 (was a High PoC).
 *
 *  THE BUG. `CauldronSeeder._reserveRange`'s per-side fallback remembered the last
 *  tracked band PER SIDE, but only recorded which side it was on WHEN IT WAS TRACKED.
 *  Once `MAX_RANGES` (64) was exhausted every later placement reused
 *  `_lastAsk`/`_lastBid`; as spot kept drifting DOWN — which is what a token
 *  APPRECIATING does in this orientation (SeedLib:21-27) — `_lastAsk` ended up ABOVE
 *  spot while the ask amount was still sized with `getLiquidityForAmount1`. The pool
 *  settled that position in ETH the seeder does not hold and `settle{value:}` failed:
 *  a hard revert on the permissionless `poke` and a silently swallowed no-op in-swap.
 *  Measured before the fix: 59 pokes of ordinary 200-tick drift filled `ranges` to
 *  exactly 64, the next poke reverted with empty revert data, `placedWad` froze at
 *  0.74275e18 and 2.30 ETH never reached the pool. Attacker cost: zero.
 *
 *  THE FIX. At the cap `_reserveRange` now EVICTS the tracked band furthest from live
 *  spot (never the full-range base), recovering its liquidity into the seeder's own
 *  balance, and hands the freed slot to the band it actually wants — on the correct
 *  side of TODAY's spot. `_placeStep` additionally sizes a band to zero unless it is
 *  side-correct against LIVE spot, so a stale side can never ask the pool for an
 *  asset this contract does not hold.
 *
 *  NOTE ON THE HARNESS: the drift loop now rolls a BLOCK per step. That is not a
 *  softening — it is what ordinary drift over a launch window actually is — and it is
 *  required because the Z-17 fix rate-limits the seeder's price reference per block.
 */
contract T9cSeederRangeCapMisSide is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager pm;
    CauldronToken token;
    CauldronSeeder seeder;
    PoolKey key;
    PoolId pid;

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000;
    uint160 constant MIN_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    uint256 constant ACTIVE_ETH = 10 ether;
    uint256 constant ACTIVE_TOK = 100_000_000 ether;
    uint64 constant WINDOW = 3600;
    int24 internal _startTick;

    function setUp() public {
        pm = IPoolManager(address(new PoolManager(address(this))));
        token = new CauldronToken("Seed", "SEED", 1, address(this), 500_000_000 ether);
        seeder = new CauldronSeeder(address(this), address(0xBEEF), address(pm));

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        pm.initialize(key, _sqrtPriceFor(ACTIVE_TOK, ACTIVE_ETH));
        (, _startTick,,) = pm.getSlot0(key.toId());

        vm.deal(address(this), 5_000 ether);
        token.approve(address(seeder), ACTIVE_TOK);
        seeder.startSeed{value: ACTIVE_ETH}(SeederConfig({
            key: key, token: address(token), gen: 1,
            spacing: SPACING, bandWidth: 400,
            window: WINDOW, seedFloorWad: 0.02e18, minStepWad: 0.005e18,
            baseWad: 0.15e18,
            ethTotal: ACTIVE_ETH, tokenTotal: ACTIVE_TOK
        }));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (bool z, int256 amt, uint160 lim) = abi.decode(data, (bool, int256, uint160));
        if (lim == 0) lim = z ? MIN_LIMIT : MAX_LIMIT;
        BalanceDelta d = pm.swap(
            key, SwapParams({zeroForOne: z, amountSpecified: amt, sqrtPriceLimitX96: lim}), ""
        );
        int128 d0 = d.amount0();
        int128 d1 = d.amount1();
        if (d0 < 0) pm.settle{value: uint256(uint128(-d0))}();
        if (d1 < 0) {
            pm.sync(key.currency1);
            IERC20(address(token)).transfer(address(pm), uint256(uint128(-d1)));
            pm.settle();
        }
        if (d0 > 0) pm.take(key.currency0, address(this), uint256(uint128(d0)));
        if (d1 > 0) pm.take(key.currency1, address(this), uint256(uint128(d1)));
        return abi.encode(d);
    }

    function _swap(bool zeroForOne, int256 amt) internal returns (BalanceDelta) {
        return abi.decode(pm.unlock(abi.encode(zeroForOne, amt, uint160(0))), (BalanceDelta));
    }

    /// @dev Walk spot to exactly `target` using a price-limited exact-input swap.
    function _swapTo(int24 target) internal {
        (, int24 cur,,) = pm.getSlot0(pid);
        if (cur == target) return;
        bool z = target < cur;
        int256 amt = z ? -int256(3_000 ether) : -int256(300_000_000 ether);
        pm.unlock(abi.encode(z, amt, TickMath.getSqrtPriceAtTick(target)));
    }

    receive() external payable {}

    function _sqrtPriceFor(uint256 a1, uint256 a0) internal pure returns (uint160) {
        return uint160(_sqrt((a1 * 1e18) / a0) * 2 ** 96 / 1e9);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    /// @dev March spot DOWN a little at a time and poke, the way ordinary buying
    ///      traffic does, until the tracked-range set is exhausted.
    function _fillRangeCap(uint256 maxIters) internal returns (uint256 count, uint256 iters) {
        uint256 t0 = vm.getBlockTimestamp(); // NOT block.timestamp: the optimizer
        // re-reads the TIMESTAMP opcode and vm.warp would then compound.
        uint256 b0 = vm.getBlockNumber(); // and NOT block.number, for the same reason:
        // `vm.roll(block.number + 1)` in a loop is hoisted and rolls to the same block
        // every iteration, which silently pins the seeder's price reference.
        for (uint256 i; i < maxIters; i++) {
            vm.warp(t0 + ((WINDOW * (i + 1)) / maxIters));
            vm.roll(b0 + i + 1); // drift happens across blocks, not inside one
            // ordinary launch-window drift: spot walks DOWN one tick-spacing slot
            // at a time (buy pressure). Each new slot is a new tracked band pair.
            _swapTo(_startTick - int24(int256(200 * (i + 1))));
            seeder.poke();

            iters = i + 1;
            count = seeder.rangeCount();
            if (count >= 64) break;
        }
    }

    /// @dev After the cap, drift further and try to keep streaming. Returns whether
    ///      the placement reverted and the ask range the seeder insisted on reusing.
    function _pokeAfterDrift() internal returns (bool reverted, int24 lo, int24 hi, int24 tick) {
        // a good launch makes the token dearer, which in this orientation means the
        // tick FALLS — so this is the SUCCESS direction, not an attack direction.
        _swapTo(_startTick - 25_000); // spot falls well below every tracked ask
        (, tick,,) = pm.getSlot0(pid);
        vm.warp(vm.getBlockTimestamp() + WINDOW / 4); // let a step accrue
        (lo, hi) = _lastAskRange();
        // Let the Z-17 price reference walk to the new spot (MAX_TICK_DEV = 1000 ticks
        // per block). This is the honest catch-up path, not a bypass: the reference
        // converges monotonically and the withheld step is deployed in full when it
        // arrives. Without it the poke below would be a no-op for a different reason.
        uint256 b0 = vm.getBlockNumber();
        for (uint256 i; i < 60; i++) {
            vm.roll(b0 + i + 1);
            (int24 r,) = seeder.priceRef();
            if (r == tick) break;
            seeder.poke();
        }
        vm.roll(vm.getBlockNumber() + 1);
        try seeder.poke() {
            reverted = false;
        } catch (bytes memory err) {
            reverted = true;
            emit log_named_bytes("poke revert data", err);
        }
    }

    /// @dev `_lastAsk` is private; recover the deepest tracked ask band by scanning
    ///      the public `ranges` array for the lowest non-full-range band.
    function _lastAskRange() internal view returns (int24 lo, int24 hi) {
        uint256 n = seeder.rangeCount();
        lo = type(int24).max;
        for (uint256 i; i < n; i++) {
            (int24 l, int24 h) = seeder.ranges(i);
            if (h - l > 100_000) continue; // skip the full-range base
            if (l < lo) { lo = l; hi = h; }
        }
    }

    /// @dev The lowest tracked band whose UPPER tick is at or below `tick`, i.e. a
    ///      band that is genuinely pure-token1 (a real ask) against LIVE spot.
    function _hasSideCorrectAsk(int24 tick) internal view returns (bool) {
        uint256 n = seeder.rangeCount();
        for (uint256 i; i < n; i++) {
            (int24 l, int24 h) = seeder.ranges(i);
            if (h - l > 100_000) continue; // skip the full-range base
            if (h <= tick) return true;
        }
        return false;
    }

    function test_RangeCapThenDriftBreaksTheStream() public {
        (uint256 count, uint256 iters) = _fillRangeCap(80);
        emit log_named_uint("ranges tracked", count);
        emit log_named_uint("pokes needed  ", iters);

        uint256 placedBefore = seeder.deployedWad();
        uint256 ethBefore = address(seeder).balance;

        (bool reverted, int24 lo, int24 hi, int24 tick) = _pokeAfterDrift();
        emit log_named_int("spot tick now      ", tick);
        emit log_named_int("stalest ask lo     ", lo);
        emit log_named_int("stalest ask hi     ", hi);
        emit log_string(reverted ? "poke REVERTED" : "poke succeeded");
        emit log_named_uint("placedWad before   ", placedBefore);
        emit log_named_uint("placedWad after    ", seeder.deployedWad());
        emit log_named_uint("seeder ETH before  ", ethBefore);
        emit log_named_uint("seeder ETH after   ", address(seeder).balance);
        emit log_named_uint("ranges after drift ", seeder.rangeCount());

        assertEq(count, 64, "the bounded range set is still exhausted by ordinary drift");
        // The band the OLD code would have reused for the TOKEN (ask) side sits ABOVE
        // spot, i.e. on the bid side. That is the input condition of the bug and it is
        // unchanged — what changed is what the seeder does with it.
        assertGt(lo, tick, "the stalest tracked ask really is on the WRONG side of spot");

        // REGRESSION 1: the stream does not halt. It used to revert with empty
        // returndata (out of funds) on this exact poke.
        assertFalse(reverted, "poke no longer reverts at the range cap");
        // REGRESSION 2: it keeps DEPLOYING. `placedWad` used to freeze at 0.74275e18.
        assertGt(seeder.deployedWad(), placedBefore, "the stream advanced past the cap");
        // REGRESSION 3: the cap is still a cap - eviction reuses slots, it does not grow.
        assertLe(seeder.rangeCount(), 64, "teardown gas stays bounded");
        // REGRESSION 4: the seeder now holds a band that is a REAL ask against live
        // spot, which is only possible because the stale one was evicted and replaced.
        assertTrue(_hasSideCorrectAsk(tick), "a side-correct ask band exists at live spot");
    }
}
