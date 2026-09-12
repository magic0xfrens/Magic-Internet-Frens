// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/**
 * @title XL1 — one large swap must not leave a position permanently unliquidatable
 *
 *  REPRODUCES, locally and without a fork, the state measured on Sepolia r42
 *  (PerpEngine 0x336dA07F0A56439FA2eAd8694D44b0b87CDbB0c0, position id 3):
 *
 *    positionHealth(3) -> isLong=false, markValueEth=4.351380134704386112 ETH,
 *                         debtOrBackingEth=0.135023470083052223 ETH, liquidatable=true
 *    realised P&L -4.43 ETH on ~0.05 ETH of collateral (-9526%)
 *    liquidate(3) -> LiqCapped(), at EVERY maxLiqBps up to 10000
 *
 *  TWO COMPOUNDING BUGS.
 *
 *  BUG 1 — the liquidation trigger read ONLY the `twapWindow`-long TWAP mark
 *  ({PerpEngine._underwaterVal} fed by `_quoteMark`), so the hook's afterSwap
 *  sweep, running INSIDE the very swap that made the position insolvent, still
 *  saw the pre-swap average and left it open. Nothing closed it until the average
 *  caught up, by which time the loss was whatever the market had done in between.
 *
 *  BUG 2 — `liquidate`'s per-block throttle is a share of POOL DEPTH
 *  (`activeEthDepth() * maxLiqBps / BPS`). A position whose notional has grown
 *  PAST the active depth can never fit under it at any setting, so an
 *  anti-cascade throttle manufactured PERMANENT bad debt.
 */
contract XL1_LiqTwapAndDepthCap is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    IPoolManager internal pm;
    MockQuoteToken internal token;
    XL1Registry internal registry;
    XL1Hook internal hook;
    PerpEngine internal perp;
    PoolKey internal key;
    PoolId internal pid;

    address internal trader = address(0xBEEF);

    int24 internal constant SPACING = 200;
    uint24 internal constant FEE = 0; // PerpEngine.POOL_FEE
    uint160 internal constant MIN_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 internal constant MAX_LIMIT = TickMath.MAX_SQRT_PRICE - 1;
    uint256 internal constant Q96 = 1 << 96;

    /// Pool sized to the live one: ~3 ETH of active depth.
    uint256 internal constant POOL_ETH = 3 ether;
    uint256 internal constant POOL_TOK = 30_000_000 ether;
    /// The live position's collateral.
    uint256 internal constant COLLATERAL = 0.05 ether;

    uint128 internal L0;

    // modifyLiquidity payload for the unlock callback
    int24 private _tl;
    int24 private _tu;
    int256 private _ld;
    uint8 private _mode; // 0 = swap, 1 = modifyLiquidity

    //  ── TIME MUST BE TRACKED IN STORAGE, NOT READ BACK ────────────────────
    //  Under `via_ir` the optimizer treats TIMESTAMP and NUMBER as loop-invariant
    //  and hoists them out, so `vm.warp(block.timestamp + 15)` inside a loop warps
    //  to the SAME instant on every iteration and the clock silently freezes. That
    //  produced a suite that "warmed the TWAP ring" for 40 iterations of zero
    //  elapsed time. Keep the clock in storage instead; a cheatcode call cannot be
    //  optimized across an SLOAD.
    uint256 private _clock;
    uint256 private _blk;

    // -----------------------------------------------------------------------
    // Harness
    // -----------------------------------------------------------------------
    function setUp() public {
        _clock = 1_800_000_000;
        _blk = block.number;
        vm.warp(_clock);
        pm = IPoolManager(address(new PoolManager(address(this))));
        token = new MockQuoteToken("Gen1", "G1", 18);
        registry = new XL1Registry();

        // A hook carrying ONLY the afterSwap flag — the production delivery path
        // for keeperless liquidation (CauldronHook calls sweepLiquidations there,
        // discarding the result).
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        bytes memory args = abi.encode(address(this));
        (address hookAddr, bytes32 salt) = HookMiner.find(address(this), flags, type(XL1Hook).creationCode, args);
        hook = new XL1Hook{salt: salt}(address(this));
        require(address(hook) == hookAddr, "hook addr");

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(hook))
        });
        pid = key.toId();
        pm.initialize(key, _sqrtPriceFor(POOL_TOK, POOL_ETH));

        vm.deal(address(this), 100_000 ether);
        token.mint(address(this), 5_000_000_000 ether);

        // The default book: full range, ~3 ETH of depth.
        L0 = uint128(_sqrt(POOL_ETH * POOL_TOK));
        _modify(-887_200, 887_200, int256(uint256(L0)));

        registry.set(address(token), 1, _clock - 3 days);

        perp = new PerpEngine(
            pm, address(hook), address(registry), address(new XL1Frens()),
            address(0), address(0), address(this)
        );
        hook.arm(address(perp));

        // Fund both sides generously: the engine must be ABLE to settle, so that
        // whatever loss we measure is the protocol's economics and not a
        // liquidity accident.
        perp.fundPlv{value: 20 ether}(20 ether);
        token.approve(address(perp), type(uint256).max);
        perp.fundPlvToken(10_000_000 ether);
        perp.fundInsurance{value: 2 ether}(2 ether);
        // Only `warmup` is moved (a test cannot wait 24h). Every risk parameter
        // that matters here keeps its SHIPPED value: maintenanceBps 1500,
        // maxNotionalBps 500, maxOiBps 3000, maxLiqBps 2000, twapWindow 300.
        perp.setRisk(60, 3, 1_500, 500, 3_000, 100);

        vm.deal(trader, 10 ether);

        // Warm the TWAP ring PROPERLY: a full `twapWindow` of history at the
        // seeded price, so the "stale mark" this test is about is the real thing
        // and not a cold start.
        _rest(40);
    }

    // ── pool primitives (this contract holds its own unlock) ────────────────
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        if (_mode == 1) {
            pm.modifyLiquidity(
                key,
                ModifyLiquidityParams({tickLower: _tl, tickUpper: _tu, liquidityDelta: _ld, salt: bytes32(0)}),
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

    function _modify(int24 tl, int24 tu, int256 ld) internal {
        _tl = tl; _tu = tu; _ld = ld; _mode = 1;
        pm.unlock("");
        _mode = 0;
    }

    /// @dev A raw ETH->token BUY of `amountIn`: what any router, bot or aggregator
    ///      does. Fires the hook's afterSwap sweep on the way out.
    function _buy(uint256 amountIn) internal {
        pm.unlock(abi.encode(true, -int256(amountIn)));
    }

    /// @dev A raw token->ETH SELL: the market putting token back into the pool.
    function _sell(uint256 amountIn) internal {
        pm.unlock(abi.encode(false, -int256(amountIn)));
    }

    /// @dev Advance the clock by `dt` seconds and one block.
    function _skip(uint256 dt) internal {
        _clock += dt;
        _blk += 1;
        vm.warp(_clock);
        vm.roll(_blk);
    }

    /// @dev Quiet blocks with an oracle poke, so the TWAP genuinely converges.
    function _rest(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            _skip(15);
            perp.poke();
        }
    }

    /**
     *  @dev Re-shape the book into the DISCRETE BANDS the production seeder
     *       actually places (CauldronSeeder mints narrow ask/bid ranges, it does
     *       not hold a full-range position). A full-range constant-product book
     *       cannot express the r42 state at all: there, notional > depth is
     *       arithmetically identical to "more token owed than the pool holds", so
     *       the position is unbuyable-back and the cap is moot. With bands the
     *       price can sit in a THIN one — active depth collapses — while a DEEP
     *       band further along still holds every token the buy-back needs. That
     *       is precisely the shape that produced `LiqCapped()` on chain.
     */
    function _reshapeToBands() internal {
        _modify(-887_200, 887_200, -int256(uint256(L0)));   // drop the full range
        _modify(161_000, 200_000, int256(uint256(L0)));      // DEEP, holds spot (tick ~161181)
        _modify(140_000, 161_000, int256(1e20));             // THIN
        _modify(80_000, 140_000, int256(5e22));              // DEEP, token-only, below
    }

    function _sqrtPriceFor(uint256 tok, uint256 eth) internal pure returns (uint160) {
        // sqrt(tok/eth) * 2^96 == sqrt((tok<<96)/eth) << 48
        return uint160(_sqrt((tok << 96) / eth) << 48);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    function _tick() internal view returns (int24 t) { (, t,,) = pm.getSlot0(pid); }

    /// @dev What `size` token is worth in ETH at LIVE SPOT (the engine's `_quoteEth`).
    function _spotValue(uint256 size) internal view returns (uint256) {
        (uint160 sp,,,) = pm.getSlot0(pid);
        return ((((size * Q96) / sp) * Q96) / sp);
    }

    function _openShort() internal returns (uint256 id) {
        vm.prank(trader);
        id = perp.openShort{value: COLLATERAL}(2, 0, 0, COLLATERAL);
    }

    function _vaultEth() internal view returns (uint256) { return perp.plv() + perp.insuranceEth(); }

    function _size(uint256 id) internal view returns (uint256 s) { (,,, s,,,,) = perp.positions(id); }

    function _traderOf(uint256 id) internal view returns (address t) { (t,,,,,,,) = perp.positions(id); }

    // -----------------------------------------------------------------------
    // BUG 1 — the swap that makes a position insolvent must close it
    // -----------------------------------------------------------------------
    /**
     *  A short opened at the seeded price, then ONE buy that drives SPOT clean
     *  through its liquidation point in a single transaction.
     *
     *  BEFORE THE FIX the afterSwap sweep asked only the TWAP, which still held
     *  the pre-swap average, so the position survived the swap — and then survived
     *  every later swap too while the price kept going, so the loss grew with the
     *  market instead of being capped at the moment of insolvency.
     *
     *  AFTER THE FIX the sweep tests the WORSE of the mark and live SPOT, so the
     *  position dies inside the swap that killed it and the vault's bad debt is
     *  bounded by that one swap's impact.
     */
    function test_XL1_OneLargeBuyLiquidatesInTheSameTransaction() public {
        uint256 id = _openShort();
        assertEq(perp.openCount(), 1, "precondition: the short is open");

        (,, uint256 backing,) = perp.positionHealth(id);
        uint256 size = _size(id);
        uint256 vaultBefore = _vaultEth();

        _skip(15);

        // ── THE ONE SWAP ────────────────────────────────────────────────────
        // 1.2 ETH into a ~3 ETH book. That carries this short past ZERO equity:
        // its backing can no longer buy the borrowed token back.
        _buy(1.2 ether);

        uint256 vaultAfter = _vaultEth();
        uint256 badDebt = vaultBefore > vaultAfter ? vaultBefore - vaultAfter : 0;

        console2.log("backing at open (wei)      ", backing);
        console2.log("spot value of size after   ", _spotValue(size));
        console2.log("vault ETH before the swap  ", vaultBefore);
        console2.log("vault ETH after the swap   ", vaultAfter);
        console2.log("bad debt charged to vault  ", badDebt);
        console2.log("openCount after the swap   ", perp.openCount());

        // (a) it is liquidated in the SAME transaction as the swap.
        assertEq(perp.openCount(), 0, "the swap that made it insolvent must also close it");
        assertEq(_traderOf(id), address(0), "position must be gone");

        // (b) the loss is bounded near the collateral, not 88x it.
        assertLt(badDebt, COLLATERAL * 3, "bad debt must be bounded by the one swap's impact");
    }

    /**
     *  THE CONTROL for the manipulation trade-off this fix makes explicit.
     *
     *  A position that is UNHEALTHY at spot — past its maintenance buffer — but
     *  still SOLVENT must NOT be liquidatable off a one-block push. Only the
     *  TWAP, which cannot be moved inside a block, may take that decision. The
     *  spot trigger carries no maintenance buffer at all, precisely so that it
     *  cannot be used this way.
     */
    function test_XL1_FlashPushCannotLiquidateAMerelyUnhealthyPosition() public {
        uint256 id = _openShort();
        uint256 size = _size(id);
        (,, uint256 backing,) = perp.positionHealth(id);

        _skip(15);

        _buy(0.58 ether);

        uint256 spotVal = _spotValue(size);
        console2.log("backing            ", backing);
        console2.log("spot value of size ", spotVal);
        // Past the 15% maintenance buffer at spot...
        assertGt(spotVal * 10_000, backing * 8_500, "precondition: unhealthy at spot");
        // ...but still solvent: the backing can still repay.
        assertLt(spotVal, backing, "precondition: still solvent at spot");

        assertEq(perp.openCount(), 1, "a solvent-at-spot position must survive a flash push");
        assertFalse(perp.isLiquidatable(id), "spot alone must not make it liquidatable");
        vm.expectRevert(PerpEngine.Healthy.selector);
        perp.liquidate(id);
    }

    // -----------------------------------------------------------------------
    // BUG 2 — a notional larger than the active depth must still be liquidatable
    // -----------------------------------------------------------------------
    /**
     *  The live r42 state, rebuilt on a BANDED book: no in-swap sweep (a hook-less
     *  interface, an unwired engine, or — before the fix — simply the stale mark),
     *  the price runs out of the deep band into a thin one, and the TWAP then
     *  fully catches up. So `positionHealth` reports `liquidatable`, and
     *  `liquidate` reverts `LiqCapped()` because the notional is bigger than the
     *  ACTIVE depth. Raising `maxLiqBps` to 100% does not help — the cap is a
     *  SHARE of depth — which is exactly what was measured on chain.
     */
    function test_XL1_InsolventPositionLargerThanPoolDepthIsStillLiquidatable() public {
        _reshapeToBands();
        uint256 id = _openShort();
        uint256 size = _size(id);
        hook.disarm(); // no in-swap sweep: isolate the throttle

        _skip(60);
        _buy(0.16 ether); // out of the deep band, into the thin one

        // Let the TWAP fully catch up: nobody can argue the mark is stale here.
        _rest(40);

        (, uint256 markValue, uint256 backing, bool liquidatable) = perp.positionHealth(id);
        uint256 depth = perp.activeEthDepth();
        console2.log("tick                      ", _tick());
        console2.log("mark value of the position", markValue);
        console2.log("spot value of the position", _spotValue(size));
        console2.log("backing                   ", backing);
        console2.log("ACTIVE pool depth         ", depth);
        assertTrue(liquidatable, "precondition: the mark says it is liquidatable");
        assertGt(markValue, backing, "precondition: genuinely INSOLVENT at the mark");
        assertGt(markValue, depth, "precondition: notional EXCEEDS the active depth");

        // Even at 100% the depth-bounded cap cannot admit it. This is the
        // inversion: an anti-cascade throttle manufacturing permanent bad debt.
        perp.setGuards(300, 10_000, 5_000);

        _skip(15);
        uint256 vaultBefore = _vaultEth();

        perp.liquidate(id); // MUST NOT revert LiqCapped()

        assertEq(perp.openCount(), 0, "an insolvent position must be closeable at any size");
        assertEq(_traderOf(id), address(0), "position must be gone");
        console2.log("vault ETH before liq      ", vaultBefore);
        console2.log("vault ETH after liq       ", _vaultEth());
        console2.log("bad debt realised         ", vaultBefore > _vaultEth() ? vaultBefore - _vaultEth() : 0);
    }

    /**
     *  The throttle must KEEP doing its real job. A merely-unhealthy (still
     *  SOLVENT) position is discretionary, so the per-block cap still refuses it
     *  once the block's budget is spent — only genuine insolvency is exempt, and
     *  the position comes straight back the moment the cap is sane.
     */
    function test_XL1_ThrottleStillRefusesADiscretionarySolventLiquidation() public {
        uint256 id = _openShort();
        hook.disarm();

        // A SUSTAINED move: enough for the TWAP trigger (the maintenance buffer is
        // eaten) but NOT enough to take the position past zero equity.
        for (uint256 i = 0; i < 29; i++) {
            _skip(15);
            _buy(0.02 ether);
            perp.poke();
        }
        _rest(40);

        (, uint256 markValue, uint256 backing, bool liquidatable) = perp.positionHealth(id);
        console2.log("mark value ", markValue);
        console2.log("backing    ", backing);
        assertTrue(liquidatable, "precondition: underwater at the TWAP mark");
        assertLt(markValue, backing, "precondition: still SOLVENT (inside the buffer)");

        // Squeeze the cap so the discretionary path is refused.
        perp.setGuards(300, 1, 5_000);
        vm.expectRevert(PerpEngine.LiqCapped.selector);
        perp.liquidate(id);

        // ... and it works again under a sane cap, so nothing is ever stuck.
        perp.setGuards(300, 10_000, 5_000);
        perp.liquidate(id);
        assertEq(perp.openCount(), 0, "solvent liquidation still works under a sane cap");
    }

    // -----------------------------------------------------------------------
    // BUG 3 — a position the pool cannot fully unwind must still be closeable
    // -----------------------------------------------------------------------
    /**
     *  Same live position 3, later state (price back to sane levels):
     *
     *    size       83_075_039_111_919_524_157_682_700  (83.07M tokens owed)
     *    backing    0.135023470083052223 ETH
     *    activeEthDepth 1.281016633551938573 ETH, pool token side ~12.18M
     *    maxLiqBps  10000
     *    liquidate(3) -> EMPTY revert data. close(3,0) from the OWNER -> reverts.
     *
     *  Closing a short buys back `size` token with an EXACT-OUTPUT swap whose only
     *  price limit is MIN_SQRT_PRICE. When the pool holds less token than the
     *  position owes, v4 walks the price all the way to that limit and the ETH the
     *  engine is then asked to `settle` is astronomically more than it holds, so
     *  the settle call fails for lack of value — empty revert data, from inside the
     *  unlock callback. The position is unclosable at EVERY privilege level: its
     *  own owner, any liquidator, and the in-swap sweep (which fails silently
     *  inside the hook's try/catch).
     */
    function test_XL1_ShortLargerThanThePoolIsStillCloseable() public {
        uint256 id = _openShort();
        uint256 size0 = _size(id);

        // An LP exits: the book thins to 2.5% while the position stays open, which
        // leaves the pool holding LESS token than the short owes.
        _modify(-887_200, 887_200, -int256(uint256(L0) - uint256(L0) / 40));

        // A small buy on the now-thin book drives spot far past zero equity.
        _skip(15);
        _buy(0.05 ether);
        _rest(40);

        (, uint256 markValue, uint256 backing, bool liquidatable) = perp.positionHealth(id);
        uint256 poolTok = token.balanceOf(address(pm));
        console2.log("size owed        ", size0);
        console2.log("pool token side  ", poolTok);
        console2.log("mark value       ", markValue);
        console2.log("backing          ", backing);
        assertTrue(liquidatable, "precondition: liquidatable");
        assertGt(markValue, backing, "precondition: insolvent");
        assertGt(size0, poolTok, "precondition: the pool holds LESS token than the short owes");

        // ── THE INVARIANT: closeable, IN PIECES if necessary ────────────────
        //  Before the fix this line reverted `SafeCastOverflow()` from inside v4's
        //  own swap math (on chain: an out-of-value `settle`, i.e. empty revert
        //  data). It reverted for the liquidator, for the OWNER's `close`, and
        //  silently for the in-swap sweep — the position was unclosable at every
        //  privilege level while its bad debt sat on the vault.
        _skip(15);
        perp.liquidate(id);
        uint256 size1 = _size(id);
        console2.log("size after 1 liq ", size1);
        assertLt(size1, size0, "a liquidation must never revert and must make progress");
        assertGt(perp.openCount(), 0, "the piece it could not buy stays OPEN, not written off");

        // The market returns: someone puts token back into the pool. More bites
        // become possible, and none of them may revert.
        _skip(15);
        _sell(3_000_000 ether);
        for (uint256 i = 0; i < 20 && perp.openCount() > 0; i++) {
            _skip(15);
            perp.liquidate(id); // MUST NEVER revert, at any point in this sequence
        }
        console2.log("openCount after bites", perp.openCount());
        console2.log("size after bites     ", _size(id));

        //  ── AND A RELAUNCH MUST NEVER BE BLOCKED BY IT ──────────────────────
        //  `syncGeneration` refuses while `openCount != 0`, so whatever the pool
        //  could never supply has to be write-off-able on the DEATH path. If the
        //  bites above already cleared it, this is a no-op and the assert below
        //  holds anyway.
        if (perp.openCount() > 0) {
            hook.setDead(true);
            _skip(15);
            perp.forceCloseDead(id);
        }
        console2.log("openCount at end ", perp.openCount());
        assertEq(perp.openCount(), 0, "the book must always be clearable for a relaunch");
        assertEq(_traderOf(id), address(0), "position must be gone");
    }

    receive() external payable {}
}

// ---------------------------------------------------------------------------
// Minimal stand-ins
// ---------------------------------------------------------------------------

/// @dev Only `balanceOf` is ever called (the OG open-fee discount).
contract XL1Frens {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract XL1Registry {
    address public currentToken;
    uint256 public currentGeneration;
    uint256 public lastSummonAt;

    function set(address t, uint256 g, uint256 s) external {
        currentToken = t; currentGeneration = g; lastSummonAt = s;
    }
    function generationQuote(uint256) external pure returns (address) { return address(0); }
    function generationToken(uint256) external view returns (address) { return currentToken; }
    function generationPoolId(uint256) external pure returns (bytes32) { return bytes32(0); }
    function claimByBurn(uint256, uint256) external pure returns (uint256) { return 0; }
    function claimByBurnUpTo(uint256, uint256) external pure returns (uint256) { return 0; }
}

/**
 * @dev Stands in for {CauldronHook}'s afterSwap. The production keeperless
 *      liquidation path is `afterSwap -> PerpEngine.sweepLiquidations`, fired on
 *      EVERY swap from any interface with its result discarded; mirrored exactly,
 *      including the try/catch that keeps a sweep from reverting the swap.
 */
contract XL1Hook {
    address public immutable admin;
    address public perp;
    address public collection;
    bool public armed;

    constructor(address _admin) { admin = _admin; }

    function arm(address _perp) external { require(msg.sender == admin); perp = _perp; armed = true; }
    function disarm() external { require(msg.sender == admin); armed = false; }

    bool public dead;
    function setDead(bool d) external { require(msg.sender == admin); dead = d; }
    function isDead(PoolId) external view returns (bool) { return dead; }

    /// @dev Signature IDENTICAL to {IHooks.afterSwap} — asserted below by
    ///      returning `IHooks.afterSwap.selector`, which v4 checks.
    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        if (armed) {
            //  PRODUCTION-FAITHFUL: CauldronHook.sol:949 fires the sweep with a
            //  LOW-LEVEL, gas-reserved `.call` and DISCARDS the result, so a
            //  reverting sweep can never revert the triggering swap. Solidity's
            //  try/catch is NOT equivalent here and measurably let a
            //  `SafeCastOverflow()` out of v4's swap math escape into the swap.
            (bool ok, ) = perp.call(abi.encodeWithSelector(IXL1Sweep.sweepLiquidations.selector, tx.origin));
            ok;
        }
        return (IHooks.afterSwap.selector, int128(0));
    }
}

interface IXL1Sweep {
    function sweepLiquidations(address liquidator) external;
}
