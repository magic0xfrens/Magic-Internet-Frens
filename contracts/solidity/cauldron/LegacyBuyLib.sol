// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @dev The swap bought nothing — a "buyback" that acquires zero token is not
    ///      a buyback, it is a donation to the book. Reverting rolls the caller's
    ///      whole `legacyBuyStep` frame back, so the buffer is preserved.
    error NoOutput();
    /// @dev The quote token reported a failed (or false-returning) transfer.
    error QuoteTransferFailed();

    /// @dev Widest price move this buy may itself cause, as a fraction of the
    ///      LIVE sqrt price, in bps. 9486/10000 of sqrtP is ~0.8998 of the price:
    ///      the buy may push the pool at most ~10% before it stops early.
    uint256 internal constant SLIP_SQRT_BPS = 9486;
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
     *      QUOTE-AT-CURRENCY0 ONLY. `zeroForOne: true` assumes the quote sits
     *      at currency0; the settle path below handles native OR ERC20. The
     *      caller gates on `quoteIsCurrency0` AND on the buffer's denomination
     *      matching `key.currency0` — see CauldronHook._maybeLegacyBuyback.
     *
     * @param encumbered How much of this contract's `currency0` balance is spoken
     *      for by OTHER counters (the relaunch reserve). `amt` is clamped to the
     *      free remainder so a buyback can never move balance the reserve's own
     *      counter still claims — which used to leave `releaseRelaunchAsset`
     *      unable to send what it believed it held.
     *
     * @return spent The quote actually consumed — settle THIS, not `amt`.
     * @return got   The token bought, owed to the caller.
     */
    function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt, uint256 encumbered)
        external
        returns (uint256 spent, uint256 got)
    {
        address q = Currency.unwrap(key.currency0);

        //  SPEND ONLY WHAT IS FREE. The hook's currency0 balance is shared: part
        //  of it is the buyback buffer, part is `relaunchETH`/`relaunchAsset[q]`,
        //  a holder-facing reserve. Nothing here debits those counters, so a buy
        //  larger than the free remainder would move reserve balance while the
        //  reserve still believed it held it — `releaseRelaunchAsset`'s send then
        //  fails and the remainder locks. Clamp instead: the unspent part is
        //  returned to the buffer by the caller and retried next time.
        uint256 bal = q == address(0) ? address(this).balance : IERC20(q).balanceOf(address(this));
        uint256 free = bal > encumbered ? bal - encumbered : 0;
        if (amt > free) amt = free;
        if (amt == 0) return (0, 0);

        //  A REAL PRICE BOUND, NOT `MIN_SQRT_LIMIT`. The limit used to be the
        //  absolute minimum tick price, i.e. "fill at any price at all": a book
        //  drained or skewed inside the same transaction could take the whole
        //  buffer for dust. Bound the move to a fixed fraction of the live sqrt
        //  price — if it binds, the pool consumes less than `amt` and the
        //  remainder rolls back into the buffer (already handled by the caller).
        (uint160 sp,,,) = poolManager.getSlot0(key.toId());
        uint256 lim = (uint256(sp) * SLIP_SQRT_BPS) / 10_000;
        // Exact-INPUT quote→token: spend up to `amt` for whatever token it buys.
        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(amt),
                sqrtPriceLimitX96: lim > MIN_SQRT_LIMIT ? uint160(lim) : MIN_SQRT_LIMIT
            }),
            ""
        );

        // SETTLE THE REALISED DEBIT, not the intended `amt` (audit Z-17). If the
        // price limit ever binds, the pool consumes LESS than `amt`; settling the
        // constant would over-settle, leaving a positive delta that is never
        // taken — and since deltas must net to zero at unlock close, that would
        // revert the USER's parent swap.
        spent = uint256(uint128(-d.amount0()));

        //  SETTLE IN WHATEVER THE QUOTE IS, not always ether.
        //
        //  This was `settle{value: spent}()` unconditionally, which is why the
        //  hook refused to buffer a non-native fee at all: paying ether into an
        //  ERC20-quoted pool settles nothing the pool asked for, currency0's
        //  delta stays open, and the unlock closes with `CurrencyNotSettled()` —
        //  reverting the USER'S parent swap, since this runs nested inside it.
        //  Skipping the buyback was the safe workaround; generalising the
        //  settlement removes the reason for it, so the collection floor keeps
        //  accruing on a rotated generation instead of silently stopping.
        //
        //  ERC20 settlement in v4 is sync -> transfer -> settle: `sync` snapshots
        //  the manager's balance, the transfer moves the tokens in, and `settle`
        //  credits the difference. This library is delegatecalled by the hook, so
        //  `address(this)` is the hook and the tokens paid are its own.
        got = uint256(uint128(d.amount1()));
        //  A BUY THAT BOUGHT NOTHING IS NOT A BUYBACK. Reverting here rolls back
        //  the caller's `legacyBuffer = 0` too, so the buffer survives intact.
        if (got == 0) revert NoOutput();

        if (q == address(0)) {
            poolManager.settle{value: spent}();
        } else {
            poolManager.sync(key.currency0);
            //  CHECKED. A false-returning ERC20 used to leave currency0's delta
            //  open, and the unlock then closed with `CurrencyNotSettled()` —
            //  reverting the USER'S parent swap, which the caller's
            //  result-ignored self-call does NOT contain (it is the outer frame
            //  that dies, not this one).
            (bool okT, bytes memory r) =
                q.call(abi.encodeWithSelector(IERC20.transfer.selector, address(poolManager), spent));
            if (!okT || (r.length != 0 && !abi.decode(r, (bool)))) revert QuoteTransferFailed();
            poolManager.settle();
        }

        poolManager.take(key.currency1, address(this), got); // hold it on the hook
    }
}
