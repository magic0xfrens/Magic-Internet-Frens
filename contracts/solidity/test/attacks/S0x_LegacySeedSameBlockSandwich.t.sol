// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronToken} from "../../CauldronToken.sol";
import {LegacyBuyLib} from "../../cauldron/LegacyBuyLib.sol";

/**
 * S0xA — the SEED-AND-SPEND-IN-ONE-BLOCK bypass of LegacyBuyLib's sandwich fix.
 *
 * LegacyBuyLib.sol:176-177
 *     (int24 ref, bool seeded) = _syncRef(pid, tick);
 *     if (seeded) return (0, 0);
 * LegacyBuyLib.sol:290-300
 *     if (refBlock == 0) { ref = tick; seeded = true; }
 *     else if (refBlock != uint64(block.number)) { ...clamped catch-up... }
 *     else { return (ref, false); }   // <-- same block: seeded == FALSE
 *
 * `seeded` is true only on the call that WRITES the sentinel. A SECOND call in the
 * SAME BLOCK takes the `refBlock == block.number` branch and reports seeded=false,
 * so the buy proceeds against a reference that was born from the attacker's own
 * tick, in the attacker's own transaction. CauldronHook calls
 * `_maybeLegacyBuyback` twice per afterSwap (CauldronHook.sol:799 and :1002), and a
 * caller can make as many swaps in one transaction as it likes, so "two buyStep
 * calls in one block" costs nothing to arrange.
 *
 * No fork: a real v4-core PoolManager is deployed locally.
 */
contract S0xLegacySeedSameBlockSandwich is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    IPoolManager pm;
    CauldronToken token;
    Harness hookLike;
    PoolKey key;
    PoolId pid;

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000;
    uint160 constant MIN_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    uint256 constant POOL_ETH = 10 ether;
    uint256 constant POOL_TOK = 100_000_000 ether;
    uint256 constant BUFFER = 1 ether;

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
        vm.deal(address(this), 10_000 ether);
        _addLiquidity();
        hookLike = new Harness(pm, key);
        vm.roll(block.number + 10);
    }

    // ── measurements (internal helpers return values; no early return above) ──

    /// @dev Honest: seed and spend in the same block, NO manipulation. This is the
    ///      control — it also proves the second same-block call really does spend.
    function _honestSameBlock() internal returns (uint256 spent, uint256 got) {
        vm.deal(address(hookLike), BUFFER);
        hookLike.run(BUFFER);            // call 1: seeds
        (spent, got) = hookLike.run(BUFFER); // call 2: same block
    }

    /// @dev The attack: push the token dear, THEN let the reference be born at that
    ///      tick, then spend the buffer against it — all in one block.
    function _attackSameBlock(uint256 pushEth)
        internal
        returns (uint256 spent, uint256 got, int256 pnl)
    {
        vm.deal(address(hookLike), BUFFER);
        uint256 ethBefore = address(this).balance;
        uint256 tokBefore = token.balanceOf(address(this));

        _swap(true, -int256(pushEth));   // ETH -> token: tick DOWN, token dearer
        uint256 bought = token.balanceOf(address(this)) - tokBefore;

        hookLike.run(BUFFER);            // seeds the reference AT THE PUSHED TICK
        (spent, got) = hookLike.run(BUFFER); // same block -> seeded == false -> SPENDS

        _swap(false, -int256(bought));   // unwind

        pnl = int256(address(this).balance) - int256(ethBefore)
            + int256(token.balanceOf(address(this))) - int256(tokBefore);
    }

    function test_SeedAndSpendInOneBlockRestoresTheSandwich() public {
        uint256 snap = vm.snapshotState();

        (uint256 hSpent, uint256 hGot) = _honestSameBlock();
        emit log_named_uint("honest  spent (wei)", hSpent);
        emit log_named_uint("honest  got   (tok)", hGot);

        vm.revertToState(snap);

        (uint256 aSpent, uint256 aGot, int256 pnl) = _attackSameBlock(30 ether);
        emit log_named_uint("attacked spent (wei)", aSpent);
        emit log_named_uint("attacked got   (tok)", aGot);
        emit log_named_int("attacker net   (wei)", pnl);

        //  ── FLIPPED INTO A REGRESSION TEST (the attack is now CLOSED) ────────
        //  As written this proved the sandwich: a reference SEEDED at :799 and
        //  SPENT at :1002 inside one `afterSwap` let the attacker manufacture the
        //  price the floor bought at. Measured on the vulnerable code: honest
        //  5,139,999 tok for 0.547 ETH vs 612,853 tok for 1.000 ETH (-88.1%),
        //  attacker +0.552 ETH.
        //
        //  {LegacyBuyLib.VIRGIN_BIT} now keeps a newborn reference untradeable for
        //  the WHOLE block it was born in, not just for the call that took it. So
        //  the ASSERTIONS INVERT: the same-block spend must be zero and the round
        //  trip must not pay. Measured after the fix: attacker net -0.375 ETH.
        //  Keeping the attack's own machinery and inverting only the expectations
        //  means this still fails loudly if the defer is ever weakened back to
        //  per-call.

        // 1. the second same-block call IS deferred: nothing is spent either way.
        assertEq(hSpent, 0, "FIXED: a same-block second call spends nothing");
        assertEq(aSpent, 0, "FIXED: the attacker cannot spend the buffer in their own block");

        // 2. nothing was bought, so the floor cannot have been shortchanged.
        assertEq(aGot, 0, "FIXED: no token bought at a manufactured tick");
        assertEq(hGot, 0, "FIXED: the honest same-block path bought nothing either");

        // 3. and the round trip LOSES money, so there is no reason to run it.
        assertLt(pnl, 0, "FIXED: the sandwich costs the attacker instead of paying");
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
        (bool z, int256 amt) = abi.decode(data, (bool, int256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: z, amountSpecified: amt, sqrtPriceLimitX96: z ? MIN_LIMIT : MAX_LIMIT}),
            ""
        );
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

    function _swap(bool zeroForOne, int256 amt) internal returns (BalanceDelta) {
        _mode = 0;
        return abi.decode(pm.unlock(abi.encode(zeroForOne, amt)), (BalanceDelta));
    }

    receive() external payable {}

    function _sqrtPriceFor(uint256 amount1, uint256 amount0) internal pure returns (uint160) {
        uint256 ratio = (amount1 * 1e18) / amount0;
        return uint160(_sqrt(ratio) * 2 ** 96 / 1e9);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
}

/// @dev Stands in for {CauldronHook} as the DELEGATECALLER of the linked library.
contract Harness {
    IPoolManager public immutable pm;
    PoolKey internal key;

    constructor(IPoolManager _pm, PoolKey memory _key) {
        pm = _pm;
        key = _key;
    }

    function run(uint256 amt) external returns (uint256 spent, uint256 got) {
        (spent, got) = abi.decode(pm.unlock(abi.encode(amt)), (uint256, uint256));
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
