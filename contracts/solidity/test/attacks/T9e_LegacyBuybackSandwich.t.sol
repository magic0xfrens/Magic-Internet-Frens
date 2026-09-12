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
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronToken} from "../../CauldronToken.sol";
import {LegacyBuyLib} from "../../cauldron/LegacyBuyLib.sol";

/**
 * @notice T9e — the LEGACY BUYBACK twin of audit Z-17.
 *
 *  THE SHAPE. `CauldronHook._maybeLegacyBuyback` (CauldronHook.sol:1016) fires from
 *  `afterSwap` — inside a STRANGER'S swap, at the tick that swap just produced — and
 *  hands `legacyBuffer` to `LegacyBuyLib.buyStep`. buyStep bounded its own impact
 *  (`SLIP_SQRT_BPS`) but it derived that bound from `getSlot0`, i.e. from the price
 *  the triggering swap had just set. A bound measured from a manipulated price is a
 *  manipulated bound: push the token dear, let the protocol spend its whole buffer
 *  at your price, sell your inventory back into the hole the protocol's own buy dug.
 *
 *  THE FIX. buyStep keeps a reference tick (namespaced storage slot in the delegating
 *  contract) that can move at most `MAX_TICK_DEV` ticks per BLOCK and is never
 *  rewritten twice in one block. The `sqrtPriceLimitX96` is now the TIGHTER of the
 *  self-impact bound and a bound derived from that reference, and the output must
 *  clear a minimum valued at the worst allowed price. An atomic sandwich is skipped:
 *  buyStep returns (0, 0) and the hook's existing short-fill path
 *  (`legacyBuffer += amt - spent`, CauldronHook.sol:1129) puts the whole buffer back.
 *
 *  The skip is a RETURN, not a revert, and that is load-bearing — a revert would roll
 *  the price reference's own write back with it and the reference could then never
 *  catch up. Found by execution: the first cut of this fix reverted and every later
 *  buyback in this file refused with it.
 *
 *  No fork: a real v4-core PoolManager is deployed locally.
 */
contract T9eLegacyBuybackSandwich is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    IPoolManager pm;
    CauldronToken token;
    BuyHarness hookLike;
    PoolKey key;
    PoolId pid;

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000; // 1%, the production pool fee
    uint160 constant MIN_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    uint256 constant POOL_ETH = 10 ether;
    uint256 constant POOL_TOK = 100_000_000 ether;
    /// @dev What the hook has buffered from fees/royalties when the swap lands.
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
        // A full-range book, the shape the registry seeds.
        _addLiquidity();

        hookLike = new BuyHarness(pm, key);
        // Roll off block 1 so the reference's first sync and the attack can be put
        // in different blocks deliberately, not by accident.
        vm.roll(block.number + 10);
    }

    // ── pool primitives (this test contract holds its own unlock) ────────────

    uint8 private _mode; // 0 = swap, 1 = addLiquidity

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

    uint128 private _liq;

    function _addLiquidity() internal {
        // Liquidity sized so the full-range book holds ~POOL_ETH / POOL_TOK.
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

    // ── scenarios ───────────────────────────────────────────────────────────

    /// @dev The live state the sandwich actually lands in: the hook has been buying
    ///      back on this pool for a few blocks, so the price reference exists. (The
    ///      very first buyback on a pool only SEEDS the reference and refuses to
    ///      spend — asserted separately in
    ///      `test_TheFirstBuybackOnAPoolOnlySeedsTheReference`.)
    function _warmUp() internal {
        vm.deal(address(hookLike), BUFFER);
        hookLike.run(BUFFER);                  // seeds the reference, spends nothing
        vm.roll(vm.getBlockNumber() + 1);
        vm.deal(address(hookLike), BUFFER);
        hookLike.run(BUFFER);                  // a real buyback at an honest price
        vm.roll(vm.getBlockNumber() + 1);
        // Leave the book where it started so `honest` and `attacked` compare.
        uint256 held = token.balanceOf(address(hookLike));
        if (held > 0) {
            vm.prank(address(hookLike));
            token.transfer(address(this), held);
        }
    }

    /// @dev The honest path: the buffer is spent on an unmanipulated book.
    function _honest() internal returns (uint256 got) {
        vm.deal(address(hookLike), BUFFER);
        (, got) = hookLike.run(BUFFER);
    }

    /// @dev The sandwich, all in ONE block: push the token dear with an ETH buy,
    ///      let the hook's buyback fire at that tick, then sell the inventory back
    ///      through the price the protocol's own spend just moved.
    function _attack(uint256 pushEth) internal returns (uint256 got, int256 pnl, bool refused) {
        vm.deal(address(hookLike), BUFFER);
        uint256 ethBefore = address(this).balance;
        uint256 tokBefore = token.balanceOf(address(this));

        _swap(true, -int256(pushEth)); // ETH -> token: tick DOWN, token dearer
        uint256 bought = token.balanceOf(address(this)) - tokBefore;

        (uint256 s_, uint256 g_) = hookLike.run(BUFFER);
        got = g_;
        refused = (s_ == 0);

        _swap(false, -int256(bought)); // unwind the exact position

        pnl = int256(address(this).balance) - int256(ethBefore)
            + int256(token.balanceOf(address(this))) - int256(tokBefore);
    }

    /**
     * @dev REGRESSION (T-1). Before the fix the sandwiched buyback executed against
     *      the attacker's tick: the protocol received far fewer tokens for the same
     *      ETH, and the attacker's round trip turned a profit paid for by the
     *      collection's floor. It must now be REFUSED, and the round trip must lose
     *      money, which is what removes the incentive.
     */
    function test_LegacyBuybackExecutesAtAnAttackerChosenTick() public {
        _warmUp(); // the hook has been buying back on this pool for a couple of blocks
        uint256 snap = vm.snapshotState();

        uint256 honest = _honest();
        assertGt(honest, 0, "honest buyback delivers tokens");
        emit log_named_uint("tokens bought, honest      ", honest);

        vm.revertToState(snap);

        (uint256 attacked, int256 pnl, bool refused) = _attack(30 ether);
        emit log_named_uint("tokens bought, sandwiched  ", attacked);
        emit log_named_int("attacker net (wei)         ", pnl);
        emit log_named_uint("buyback refused (1 = yes)  ", refused ? 1 : 0);

        // The mechanism: the buffer may NOT be spent against a tick set in the
        // same transaction. Either the swap is refused outright, or it fills at
        // a price no worse than the reference allows.
        assertTrue(refused, "the sandwiched buyback is SKIPPED, not filled at the pushed price");
        assertEq(attacked, 0, "no tokens were bought at the manipulated tick");
        assertEq(address(hookLike).balance, BUFFER, "the buffer survives the skip intact");

        // And the incentive is gone: the round trip is a loss.
        assertLt(pnl, 0, "the sandwich is a LOSS, so there is no reason to run it");
    }

    /**
     * @dev The other half: a gate that also breaks the feature is not a fix. An
     *      HONEST swap — no manipulation, price moved organically across blocks —
     *      must still let the buyback spend the buffer and take real tokens.
     */
    function test_TheFirstBuybackOnAPoolOnlySeedsTheReference() public {
        vm.deal(address(hookLike), BUFFER);
        (uint256 s0, uint256 g0) = hookLike.run(BUFFER);
        assertEq(s0, 0, "the first buyback on a pool spends nothing");
        assertEq(g0, 0, "and buys nothing");
        assertEq(address(hookLike).balance, BUFFER, "the deferred buyback keeps the buffer");

        // ...and the very next block it spends normally. The deferral is one block
        // on a brand-new pool, not a gate that has to be cleared by an admin.
        vm.roll(vm.getBlockNumber() + 1);
        (uint256 spent, uint256 got) = hookLike.run(BUFFER);
        assertGt(spent, 0, "the next block's buyback spends");
        assertGt(got, 0, "and takes real tokens");
    }

    function test_HonestBuybackStillSpendsTheBuffer() public {
        _warmUp();
        // Organic drift across blocks, the way a live book actually moves.
        for (uint256 i = 0; i < 5; i++) {
            vm.roll(vm.getBlockNumber() + 1);
            _swap(true, -0.2 ether);
            vm.deal(address(hookLike), BUFFER);
            (uint256 spent, uint256 got) = hookLike.run(BUFFER);
            assertGt(got, 0, "organic swap still funds a real buyback");
            assertGt(spent, 0, "the buffer is actually spent");
        }
        assertGt(token.balanceOf(address(hookLike)), 0, "the hook holds the bought tokens");
        emit log_named_uint("tokens held after 5 honest buybacks", token.balanceOf(address(hookLike)));
    }
}

/// @dev Stands in for {CauldronHook}: it is the contract that DELEGATECALLS the
///      linked {LegacyBuyLib}, so `address(this)` inside the library is this
///      contract, the ETH settled is this contract's, and the tokens taken land
///      here — exactly as they do on the hook. Nothing else about the hook matters
///      to the mechanism under test.
contract BuyHarness {
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
