// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title NativeQuoteZap
 * @notice Swap native ether into a generation's ERC20 quote, so a buyer can pay
 *         in ETH on a brew that no longer trades against ETH.
 *
 *  ── WHY THIS IS A SEPARATE CONTRACT AND NOT A "BUY WITH ETH" WRAPPER ──────
 *  The obvious shape is a zap that takes ETH, swaps it, and calls
 *  `CauldronGachaRouter.play` on the user's behalf. That shape is WRONG here,
 *  and not subtly: `play` credits everything to `msg.sender` — the brew tokens
 *  AND `hook.commitCrystals(msg.sender, ...)`. A contract calling `play` would
 *  therefore be minted the player's crystals. The gacha entitlement is the
 *  thing the whole front page is about, so a helper that quietly takes it is
 *  worse than no helper.
 *
 *  So this does ONE job and stops: ether in, quote out, to the caller. The buy
 *  itself stays a direct `play` call from the user's own address, which is the
 *  only way the attribution stays theirs.
 *
 *  ── WHY IT EXISTS AT ALL ──────────────────────────────────────────────────
 *  A completed rotation legitimately redenominates a generation (ETH -> USDG).
 *  From that moment `play` takes the quote by `transferFrom` and REVERTS on any
 *  ether (`ErcQuoteTakesNoValue`), so every buyer needs a token they have no way
 *  to get. Measured on Sepolia r40 the day the first rotation completed: every
 *  USDG in existence sat in the venue or the treasury. A treasury vote must not
 *  be able to switch buying off.
 *
 *  ── SLIPPAGE IS THE CALLER'S, AND IT IS MANDATORY ─────────────────────────
 *  `minOut` is enforced and a zero floor is REFUSED. v4-core ships
 *  `PoolSwapTest`, which would have done this in ten lines, and it has no
 *  slippage protection at all — this codebase has already shipped a `minOut =
 *  0n` on a live swap path once (SwapWidget, worst case 100% loss), and a helper
 *  whose whole purpose is to stand between a user and a pool is the last place
 *  to repeat it.
 *
 *  Holds nothing between calls: every path ends with the balance at zero or the
 *  transaction reverted. There is no owner, no upgrade and no privileged caller,
 *  so the worst an attacker can do with it is swap their own ether.
 */
contract NativeQuoteZap is IUnlockCallback {
    IPoolManager public immutable poolManager;

    error NotPoolManager();
    error ZeroValue();
    error NoFloor();
    error Slippage();
    error NotNativePair();
    error EthReturnFailed();
    error QuoteTransferFailed();

    event Zapped(address indexed buyer, address indexed quote, uint256 ethIn, uint256 quoteOut);

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    struct Call {
        PoolKey key;
        uint256 amountIn;
        address payer;
    }

    /**
     * @notice Swap `msg.value` of ether for `key.currency1`, delivered to the
     *         caller.
     * @param key    the venue pool. `currency0` MUST be native — a rotation
     *               venue is always native/quote, and accepting anything else
     *               would let a caller point this at an unrelated pool and have
     *               the contract settle a currency it never received.
     * @param minOut the least quote the caller will accept. Zero is refused: a
     *               floor of zero is not a loose bound, it is the absence of
     *               one, and this contract cannot invent a fair price.
     */
    function zap(PoolKey calldata key, uint256 minOut) external payable returns (uint256 out) {
        if (msg.value == 0) revert ZeroValue();
        if (minOut == 0) revert NoFloor();
        if (Currency.unwrap(key.currency0) != address(0)) revert NotNativePair();

        out = abi.decode(
            poolManager.unlock(abi.encode(Call({key: key, amountIn: msg.value, payer: msg.sender}))),
            (uint256)
        );
        if (out < minOut) revert Slippage();

        //  CHECK THE TRANSFER. USDT-shaped tokens return no data and a bare
        //  `transfer` would compile against them and silently no-op, leaving the
        //  quote stranded in a contract with no sweep. This is the same
        //  unchecked-transfer shape the audit flagged on `_approve`.
        address quote = Currency.unwrap(key.currency1);
        (bool ok, bytes memory ret) =
            quote.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, out));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert QuoteTransferFailed();
        emit Zapped(msg.sender, quote, msg.value, out);
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        Call memory c = abi.decode(raw, (Call));

        //  zeroForOne: native (currency0) in, quote (currency1) out. The price
        //  limit is the tick bound rather than a caller-supplied value — an
        //  unbounded `sqrtPriceLimitX96` supplied by the caller is exactly the
        //  shape that made the seeder's prime buy sandwichable. `minOut` above
        //  is the real protection and it is checked after settlement.
        BalanceDelta delta = poolManager.swap(
            c.key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(c.amountIn), // exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );

        //  amount0 is what we OWE (negative), amount1 what we are OWED.
        uint256 owed = uint256(uint128(-delta.amount0()));
        uint256 got = uint256(uint128(delta.amount1()));

        poolManager.sync(c.key.currency0);
        poolManager.settle{value: owed}();
        poolManager.take(c.key.currency1, address(this), got);

        //  A partial fill leaves ether here. Return it rather than keeping it:
        //  this contract is meant to hold nothing, and dust that accumulates in
        //  a permissionless helper is dust nobody can ever claim.
        uint256 refund = c.amountIn - owed;
        if (refund > 0) {
            (bool ok,) = c.payer.call{value: refund}("");
            if (!ok) revert EthReturnFailed();
        }
        return abi.encode(got);
    }

    receive() external payable {}
}
