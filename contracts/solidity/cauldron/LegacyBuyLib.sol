// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

/**
 * @title LegacyBuyLib
 * @notice The legacy-buyback swap, lifted out of {CauldronHook}.
 *
 *  This is a LINKED library — `external` functions, so Solidity deploys it
 *  separately and reaches it by `delegatecall`. It therefore runs in the hook's
 *  context: `address(this)` is the hook, the ETH paid to `settle` comes from the
 *  hook's balance, and the tokens `take` credits land on the hook. Identical
 *  behaviour to the inlined version, ~700 bytes lighter in the hook's own code.
 *
 *  Why it had to move: the hook was over the EIP-170 24,576-byte limit and could
 *  not be deployed. `forge script` does not catch that — simulation does not
 *  enforce the code-size limit — so it only surfaces against a real chain. This
 *  is the same pattern {PoolOps} already uses for the registry.
 *
 *  It deliberately holds NO state. Every storage read and write stays in the
 *  hook, which keeps the public getters the indexer and frontend read exactly
 *  where they were, and keeps this library's contract free of any layout
 *  coupling.
 */
library LegacyBuyLib {
    /// @dev Mirrors CauldronHook.MIN_SQRT_LIMIT — the widest allowable downward
    ///      bound for an exact-input buy, i.e. "no price limit".
    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;

    /**
     * @notice Spend up to `amt` of the quote to market-buy the iteration token.
     * @dev Caller MUST have set its self-buy re-entry flag first: this swap
     *      re-enters the hook's own before/afterSwap, and without that flag the
     *      nested swap would be charged a fee and accrue volume as though a user
     *      had made it.
     *
     *      ETH-QUOTE ONLY. `zeroForOne: true` assumes the quote sits at
     *      currency0, and `settle{value:}` assumes it is native. The caller
     *      gates on that; see CauldronHook._maybeLegacyBuyback.
     *
     * @return spent The quote actually consumed — settle THIS, not `amt`.
     * @return got   The token bought, owed to the caller.
     */
    function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt)
        external
        returns (uint256 spent, uint256 got)
    {
        // Exact-INPUT quote→token: spend up to `amt` for whatever token it buys.
        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(amt),
                sqrtPriceLimitX96: MIN_SQRT_LIMIT
            }),
            ""
        );

        // SETTLE THE REALISED DEBIT, not the intended `amt` (audit Z-17). If the
        // price limit ever binds, the pool consumes LESS than `amt`; settling the
        // constant would over-settle, leaving a positive delta that is never
        // taken — and since deltas must net to zero at unlock close, that would
        // revert the USER's parent swap.
        spent = uint256(uint128(-d.amount0()));
        poolManager.settle{value: spent}();

        got = uint256(uint128(d.amount1()));
        poolManager.take(key.currency1, address(this), got); // hold it on the hook
    }
}
