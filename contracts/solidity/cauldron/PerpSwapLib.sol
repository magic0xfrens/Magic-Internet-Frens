// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
            IERC20(Currency.unwrap(c)).transfer(address(poolManager), amount);
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
    }

    uint160 internal constant MIN_LIMIT = 4295128740;
    uint160 internal constant SQRT_MAX = 1461446703485210103287273052203988822378723970342;
}
