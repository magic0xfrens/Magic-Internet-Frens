// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title FeeRouteLib
 * @notice Sends a fee in whatever asset it was collected in.
 *
 *  The hook takes its fee on the quote side, and that side has been
 *  currency-agnostic for a while: a USDG-quoted pool collects USDG. But every
 *  route OUT was `.call{value:}` — the guild dividend, the floor vault, the perp
 *  stakers, the surtax — so a non-ETH generation would collect fees it could
 *  never distribute. That is the single remaining blocker for a live non-ETH
 *  brew, and it is the same blocker for perps, the dividend and the floor.
 *
 *  ── Why a library ──────────────────────────────────────────────────────────
 *  Branching native-vs-ERC20 at five call sites is several hundred bytes, and
 *  {CauldronHook} has tens. As a LINKED library this is `external`, so Solidity
 *  deploys it separately and reaches it by delegatecall — the code lives
 *  elsewhere while still running in the hook's context, so the value sent is the
 *  hook's and the tokens moved are the hook's. Same pattern as {PoolOps},
 *  {LegacyBuyLib} and {PerpSwapLib}.
 *
 *  ── Failure is never fatal ─────────────────────────────────────────────────
 *  Every send here is reached from inside a SWAP. A recipient that reverts — a
 *  contract with no `receive()`, a token that blacklists an address, a
 *  non-standard token returning false — must not take the user's trade down with
 *  it. So these report failure rather than throwing, and the caller decides:
 *  in practice, leave the fee buffered and try again next swap.
 */
library FeeRouteLib {
    /**
     * @notice Send `amount` of `asset` to `to`.
     * @param asset `address(0)` for native.
     * @param gasCap Forwarding limit for the native path, or 0 for no limit.
     *        A recipient the protocol does not control should get a bounded
     *        budget so it cannot consume the swap's gas; one the protocol does
     *        control can have the default.
     * @return ok false when nothing moved. NEVER reverts.
     */
    function send(address asset, address to, uint256 amount, uint256 gasCap)
        external
        returns (bool ok)
    {
        if (amount == 0) return true;
        if (asset == address(0)) {
            if (gasCap == 0) { (ok, ) = to.call{value: amount}(""); }
            else { (ok, ) = to.call{value: amount, gas: gasCap}(""); }
            return ok;
        }
        //  Return value CHECKED. USDT and most tokenized equities return false
        //  instead of reverting, and an unchecked transfer would mark a fee as
        //  routed while the tokens never left.
        (bool called, bytes memory ret) = asset.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        return called && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    /**
     * @notice Deliver a fee to a contract that must be TOLD about it.
     *
     *  The dividend and the perp engine cannot infer a token deposit from their
     *  balance — a stray transfer would look identical to a fee and silently
     *  dilute everyone. So for ERC20 the asset is approved and the recipient
     *  pulls, which is also why {MiFrensDividend.fundToken} is pull-based.
     *
     * @param selector The pull entrypoint, called as `selector(asset, amount)`.
     * @return ok false when nothing moved. NEVER reverts.
     */
    function deliver(
        address asset,
        address to,
        uint256 amount,
        bytes4 nativeSelector,
        bytes4 selector
    ) external returns (bool ok) {
        if (amount == 0) return true;
        if (asset == address(0)) {
            (ok, ) = to.call{value: amount}(abi.encodeWithSelector(nativeSelector));
            return ok;
        }
        (bool approved, ) = asset.call(
            abi.encodeWithSignature("approve(address,uint256)", to, amount)
        );
        if (!approved) return false;
        (ok, ) = to.call(abi.encodeWithSelector(selector, asset, amount));
        // Leave no standing allowance behind: an approval that outlives its
        // purpose is a permission nobody is tracking.
        if (!ok) asset.call(abi.encodeWithSignature("approve(address,uint256)", to, uint256(0)));
    }
}
