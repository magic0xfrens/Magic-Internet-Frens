// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILegacyBuffer {
    function fundLegacyBuffer() external payable;
}

/**
 * @title RoyaltyRouter
 * @notice The EIP-2981 royalty receiver for a volume (creature) collection under the
 *         UNIFIED floor. Marketplaces pay secondary-sale royalties as plain ETH to
 *         the receiver, so this contract's `receive()` forwards them straight into
 *         the hook's legacy buyback buffer — where they market-BUY the live
 *         iteration token and back the collection's per-gen TOKEN floor (the
 *         `materializeLegacyReserve` sweep then deposits + credits it). So NFT
 *         royalties become token buy pressure + floor, not inert ETH.
 *

 *  Dedicated (not the hook's own `receive()`): the hook takes raw ETH internally
 *  (swap-fee takes) that must never be miscounted as buffer, so royalties get their
 *  own address. Holds nothing; forwards atomically.
 *
 *  THIS CONTRACT MUST NEVER HOLD ETH, and it never does. It has no owner, no
 *  sweep and no withdraw, so anything left here would be stranded at every
 *  privilege level. The old comment claimed a failed forward would leave the ETH
 *  here "recoverable by re-pointing" — there is nothing to re-point with, and
 *  `hook` is immutable, so that was never true. It is moot now: the forward
 *  cannot fail. {CauldronHook.fundLegacyBuffer} accepts every payment and routes
 *  it — into the buyback buffer when the live generation is ether-quoted, into
 *  `relaunchETH` (which `releaseRelaunchETH` pays out) when it is not, because
 *  the buffer is spent in the live quote's units and must never hold wei it
 *  cannot spend. Either way the royalty backs the collection floor and this
 *  contract's balance returns to zero in the same call.
 */
contract RoyaltyRouter {
    /// @notice The CauldronHook whose legacy buffer these royalties fund.
    address public immutable hook;

    constructor(address _hook) {
        require(_hook != address(0), "hook");
        hook = _hook;
    }

    receive() external payable {
        if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
    }
}
