// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ILiquidatorMintable, LiqStats} from "./ILiquidatorMintable.sol";

/**
 * @title PerpSwapLib
 * @notice The perp engine's pool-swap leg, lifted out of {PerpEngine}.
 *
 *  A LINKED library — `external`, so Solidity deploys it separately and reaches
 *  it by `delegatecall`. It runs in the engine's context: `address(this)` is the
 *  engine, settled value comes from the engine's balance, and taken currency
 *  lands on the engine. Behaviour is identical to the inlined version.
 *
 *  Why it moved: PerpEngine was 536 bytes over the EIP-170 limit BEFORE any
 *  quote work — already undeployable, and not caught by `forge script`, which
 *  does not enforce code size in simulation.
 *
 *  Holds no state. Every position, balance and accounting write stays in the
 *  engine.
 */
library PerpSwapLib {
    uint256 internal constant Q96X = 0x1000000000000000000000000;

    /// @notice `10**decimals()` of `q`, read defensively; 1e18 for native or for any
    ///         token that has no `decimals()` or answers nonsense. Here for EIP-170:
    ///         the encode + staticcall + decode is ~120 B and {PerpEngine} calls it
    ///         once, on the cold rotation path.
    function unitOf(address q) external view returns (uint256) {
        if (q == address(0)) return 1e18;
        (bool ok, bytes memory ret) = q.staticcall(abi.encodeWithSignature("decimals()"));
        if (!ok || ret.length < 32) return 1e18;
        uint256 d = abi.decode(ret, (uint256));
        return d > 36 ? 1e18 : 10 ** d;
    }

    /// @notice tick -> sqrtPriceX96.
    ///
    ///  Here for EIP-170 headroom, and it is the single biggest win available:
    ///  `TickMath` is an INTERNAL library whose `getSqrtPriceAtTick` body is a long
    ///  chain of magic-constant multiplications, so {PerpEngine} was inlining the
    ///  whole thing for its ONE call site while sitting at the ceiling. Pure, one
    ///  value argument, identical result.
    function sqrtPriceAtTick(int24 t) external pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(t);
    }

    /// @notice Best-effort Liquidatoor badge mint: the stats-bearing mint first, the
    ///         pre-stats `mintLiquidator` as a fallback for a collection deployed
    ///         before stats existed. Reports rather than reverting, so a liquidation
    ///         is never taken down by its own reward.
    ///
    ///  Here for EIP-170 headroom — two `abi.encodeWithSelector`s (one carrying a
    ///  struct, so a full memory encode) plus two gas-metered calls was the largest
    ///  self-contained block left in {PerpEngine}, and it takes only value
    ///  arguments. As an EXTERNAL library function this runs by DELEGATECALL, so the
    ///  collection still sees the ENGINE as `msg.sender`, which every mint gate
    ///  depends on. `gasleft()` inside the delegatecall is 63/64 of the engine's and
    ///  both thresholds carry six-figure margins, so the fall-through is unchanged;
    ///  the floor below makes the subtraction safe on its own rather than relying on
    ///  the caller's guard.
    function tryMintBadge(address col, address to, LiqStats memory st) external returns (bool ok) {
        if (col.code.length == 0 || gasleft() < 200_000) return false;
        uint256 fwd;
        unchecked { fwd = gasleft() - 120_000; }
        (ok, ) = col.call{gas: fwd}(
            abi.encodeWithSelector(ILiquidatorMintable.mintLiquidatorWithStats.selector, to, st)
        );
        if (!ok && gasleft() > 200_000) {
            unchecked { fwd = gasleft() - 120_000; }
            (ok, ) = col.call{gas: fwd}(
                abi.encodeWithSelector(ILiquidatorMintable.mintLiquidator.selector, to)
            );
        }
    }

    /// @notice token size -> quote value at `sp`. {PerpEngine._quoteAt}'s body.
    ///
    ///  These three live here purely for EIP-170 headroom. `FullMath.mulDiv` is an
    ///  INTERNAL library, so every call site inlined its assembly: six copies in
    ///  PerpEngine, which is at the ceiling, versus one here where there are
    ///  kilobytes. Pure value arguments, no storage, so the move is mechanical.
    function quoteAt(uint256 size, uint256 sp) external pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(size, Q96X, sp), Q96X, sp);
    }

    /// @notice quote amount -> token amount at `sp`. {PerpEngine._ethToToken}'s body.
    function ethToToken(uint256 eth, uint256 sp) external pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(eth, sp, Q96X), sp, Q96X);
    }

    /// @notice Active quote-side depth of a pool from its liquidity and sqrt price.
    ///         {PerpEngine.activeEthDepth}'s body.
    function ethDepth(uint128 L, uint160 sp) external pure returns (uint256) {
        if (sp == 0 || L == 0) return 0;
        uint256 term = FullMath.mulDiv(uint256(L), uint256(SQRT_MAX) - sp, uint256(SQRT_MAX));
        return FullMath.mulDiv(term, Q96X, sp);
    }

    /// @notice ERC20 `transfer` with the return value CHECKED, REPORTING failure
    ///         instead of reverting.
    ///
    ///  Lives here rather than inline in {PerpEngine} for EIP-170 headroom: the
    ///  engine had three byte-identical copies of `encodeWithSelector` + `call` +
    ///  decode, and the engine is 67 bytes from the limit while this library has
    ///  kilobytes. `external`, so it is a DELEGATECALL from the engine — the token
    ///  still sees the engine as `msg.sender`, which is what every caller needs.
    ///
    ///  Reporting rather than reverting is load-bearing, not stylistic: a
    ///  blacklistable token (true of most tokenized equities) can make ONE
    ///  recipient permanently unpayable, and a non-standard token returns false
    ///  rather than reverting. Callers that must not be griefed by either
    ///  ({PerpEngine._payOut}, {PerpEngine.retirePayout}) need the boolean;
    ///  callers that should abort ({PerpEngine._safeTransfer}) revert on it.
    function tryTransferFrom(address token, address from, uint256 amount) external returns (bool) {
        (bool called, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount)
        );
        return called && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    /// @notice Twin of {tryTransferFrom} for plain `transfer`. See that note.
    function tryTransfer(address token, address to, uint256 amount) external returns (bool) {
        (bool called, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        return called && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    /// @notice One leg of a perp's pool interaction.
    /// @param buy       true = acquire the iteration token (pay the quote in)
    /// @param exactOut  true = `amount` is the exact TOKEN out; else exact quote in
    /// @param amount    the specified side's amount
    struct Req {
        bool buy;
        bool exactOut;
        uint256 amount;
    }

    /**
     * @notice Execute one leg and settle both sides.
     * @param quoteIsCurrency0 which side of the pool is the QUOTE.
     *
     *  v4 orders currencies by address. Native ETH is `address(0)` and always
     *  sorts first, so "quote = currency0" held for free; an ERC20 quote sorts
     *  against a CREATE-deployed token and lands on either side. Passed in
     *  rather than re-derived here so the engine and this library can never
     *  disagree about which leg is which — that disagreement would make a long
     *  sell and read the deltas backwards.
     *
     * @return spent the amount paid in
     * @return got   the amount received
     */
    function swapLeg(
        IPoolManager poolManager,
        PoolKey memory key,
        Req memory r,
        bool quoteIsCurrency0,
        bytes memory hookData
    ) external returns (uint256 spent, uint256 got) {
        Currency quote = quoteIsCurrency0 ? key.currency0 : key.currency1;
        Currency tok = quoteIsCurrency0 ? key.currency1 : key.currency0;

        // A BUY pays the quote in for the token out, which is `zeroForOne` only
        // while the quote is currency0. The price limit follows the resulting
        // direction, not the intent.
        bool z = r.buy == quoteIsCurrency0;
        uint160 limit = z ? MIN_LIMIT : SQRT_MAX - 1;

        int256 spec;
        if (r.buy) {
            // exactOut → positive (exact token out); else negative (exact quote in)
            spec = r.exactOut ? int256(r.amount) : -int256(r.amount);
        } else {
            spec = -int256(r.amount);
        }

        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({zeroForOne: z, amountSpecified: spec, sqrtPriceLimitX96: limit}),
            hookData
        );

        // The quote leg is amount0 when the quote is currency0, else amount1.
        int128 quoteAmt = quoteIsCurrency0 ? d.amount0() : d.amount1();
        int128 tokAmt = quoteIsCurrency0 ? d.amount1() : d.amount0();

        if (r.buy) {
            spent = uint256(uint128(-quoteAmt));
            got = uint256(uint128(tokAmt));
            _settle(poolManager, quote, spent);
            if (got > 0) poolManager.take(tok, address(this), got);
        } else {
            spent = uint256(uint128(-tokAmt));
            got = uint256(uint128(quoteAmt));
            _settle(poolManager, tok, spent);
            if (got > 0) poolManager.take(quote, address(this), got);
        }
    }

    /// @dev Pay what we owe. Native settles with value; an ERC20 settles by
    ///      sync-transfer-settle, which is the v4 flow for token currencies.
    function _settle(IPoolManager poolManager, Currency c, uint256 amount) private {
        if (amount == 0) return;
        if (Currency.unwrap(c) == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(c);
            //  Return value CHECKED: a token that returns false instead of
            //  reverting would leave the settle short, and v4 requires deltas to
            //  net to zero at unlock close — so the failure would surface as the
            //  USER's swap reverting, with no clue why.
            (bool ok, bytes memory ret) = Currency.unwrap(c).call(
                abi.encodeWithSelector(IERC20.transfer.selector, address(poolManager), amount)
            );
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer");
            poolManager.settle();
        }
    }

    /// @notice Convert the engine's leftover balance of a DEAD generation's token
    ///         into the live one, 1:1, via the registry's burn-claim.
    /// @dev CAPACITY-AWARE (audit H-03): claims as much as the reserve can
    ///      actually deliver. The strict `claimByBurn` reverts on a thin reserve
    ///      and would strand the engine holding a dead token.
    ///
    ///      Best-effort by design — if migration is unavailable the caller keeps
    ///      the old inventory and the owner can re-seed, rather than the sync
    ///      reverting and leaving the engine armed on a dead generation.
    /// @notice A dead-generation inventory migration moved LESS than the engine
    ///         held — `stranded` of `oldToken` is still sitting in the engine and
    ///         is no longer counted as token principal. `reason` is the raw revert
    ///         data when the claim reverted outright, empty when it merely came up
    ///         short against a thin reserve.
    /// @dev Emitted from a delegatecalled library, so the log carries the PERP
    ///      ENGINE's address — which is what an operator or indexer watches.
    event InventoryMigrationShortfall(
        uint256 indexed fromGen, address indexed oldToken, uint256 stranded, bytes reason
    );

    function migrateInventory(address registry, address oldToken, uint256 fromGen)
        external
        returns (uint256 migratedIn)
    {
        uint256 oldBal = IERC20(oldToken).balanceOf(address(this));
        if (oldBal == 0) return 0;
        (bool ok, bytes memory ret) = registry.call(
            abi.encodeWithSignature("claimByBurnUpTo(uint256,uint256)", fromGen, oldBal)
        );
        if (ok && ret.length >= 32) migratedIn = abi.decode(ret, (uint256));
        //  A FAILED MIGRATION MUST BE LOUD.
        //  `syncGeneration` re-points `plvToken` at the engine's balance of the NEW
        //  token the instant this returns, so whatever does NOT migrate is token
        //  principal that disappears from the LP's books with no error anywhere.
        //  That is not hypothetical: when the registry's `claimByBurnUpTo` body
        //  moved to {RedemptionExt}, a registry without that facet wired answered
        //  `NotConfigured()` here, this returned 0, and the engine's whole token
        //  side went to zero silently.
        //  Reverting is still not an option — the sync runs inside relaunch's
        //  try/catch and a revert would leave the engine armed on a dead
        //  generation (the reason this is best-effort in the first place). So
        //  RECORD the shortfall instead: the operator sees the amount and the raw
        //  reason, the stranded balance is still in the engine, and the token side
        //  is re-seeded with `fundPlvToken` once the cause is fixed.
        if (migratedIn < oldBal) {
            emit InventoryMigrationShortfall(fromGen, oldToken, oldBal - migratedIn, ok ? bytes("") : ret);
        }
    }

    uint160 internal constant MIN_LIMIT = 4295128740;
    uint160 internal constant SQRT_MAX = 1461446703485210103287273052203988822378723970342;
}
