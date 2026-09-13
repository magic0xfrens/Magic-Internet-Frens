// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILegacyBuffer {
    function fundLegacyBuffer() external payable;
}

interface IAdoptable {
    function adopt(address asset) external returns (uint256);
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
 *  own address.
 *
 *  ── NOT EVERY MARKETPLACE PAYS IN ETHER ──────────────────────────────────
 *  This contract used to be `receive()` and nothing else. Blur settles in WETH
 *  and Seaport offers are routinely WETH or USDC, and an EIP-2981 receiver is
 *  paid in whatever the sale settled in — a plain `transfer` to this address.
 *  With no owner, no sweep and no adopt, every one of those royalties was
 *  stranded here at every privilege level, forever, and the receiver cannot be
 *  re-pointed either (`CauldronCollection.setRoyalty` is only ever called by the
 *  factory inside `deployBrew`).
 *
 *  {sweep} closes that. It is PERMISSIONLESS — anyone may push the funds along,
 *  which is the point: a royalty must not wait on a keeper — but it has no
 *  destination argument. Both destinations are immutable and fixed at
 *  construction, so a stranger can trigger delivery and can never redirect it.
 *
 *  THIS CONTRACT STILL AIMS TO HOLD NOTHING. `hook` is immutable and
 *  {CauldronHook.fundLegacyBuffer} accepts every payment and routes it — into the
 *  buyback buffer when the live generation is ether-quoted, into `relaunchETH`
 *  (which `releaseRelaunchETH` pays out) when it is not, because the buffer is
 *  spent in the live quote's units and must never hold wei it cannot spend.
 *  Either way the royalty backs the collection floor.
 */
contract RoyaltyRouter {
    /// @notice The CauldronHook whose legacy buffer these royalties fund.
    address public immutable hook;

    /**
     * @notice Where a royalty paid in an ERC20 is delivered.
     *
     * The genesis dividend (`CauldronRegistry`'s `royaltyDividend`, handed down as
     * the factory config's `royaltyReceiver`), which already knows how to take an
     * arbitrary ERC20 and split it to holders via `adopt`. Immutable, so {sweep}
     * being permissionless cannot become a redirect. Falls back to the hook rather
     * than address(0) if a deployment supplies none — a governed address is always
     * a better resting place than a burn.
     */
    address public immutable erc20Sink;

    /**
     * @notice Gas the forward in `receive()` needs before it is worth attempting.
     *
     * A payer using `transfer`/`send` hands us the 2300-gas stipend. A value-bearing
     * CALL costs far more than that, so the forward would run out of gas — and
     * because that failure bubbles, the SALE ITSELF would revert. A royalty
     * receiver must never be able to block the trade it is paid out of. Below this
     * floor we simply keep the ether; {sweep}`(address(0))` delivers it afterwards.
     */
    uint256 private constant FORWARD_GAS_FLOOR = 40_000;

    event Swept(address indexed asset, address indexed to, uint256 amount);

    constructor(address _hook, address _erc20Sink) {
        require(_hook != address(0), "hook");
        hook = _hook;
        erc20Sink = _erc20Sink == address(0) ? _hook : _erc20Sink;
    }

    receive() external payable {
        if (msg.value == 0) return;
        //  BEST EFFORT, NEVER FATAL. See {FORWARD_GAS_FLOOR}: a stipend-limited
        //  payer, or a `fundLegacyBuffer` that reverts for any reason, must not
        //  take the marketplace sale down with it. Anything not forwarded here is
        //  held and recoverable through {sweep}, which is the whole reason this
        //  contract now has an exit.
        if (gasleft() < FORWARD_GAS_FLOOR) return;
        (bool ok, ) = hook.call{value: msg.value}(abi.encodeWithSelector(ILegacyBuffer.fundLegacyBuffer.selector));
        ok; // held for {sweep} on failure
    }

    /**
     * @notice Push whatever this contract is holding on to its fixed destination.
     *         Permissionless: no owner, no keeper, no destination argument.
     * @param  asset The ERC20 to deliver, or `address(0)` for held ether.
     * @return amount What was delivered.
     */
    function sweep(address asset) external returns (uint256 amount) {
        if (asset == address(0)) {
            amount = address(this).balance;
            require(amount > 0, "nothing");
            //  Same destination the happy path uses. This one DOES bubble: a
            //  sweep is not a sale, so a failure here should be visible rather
            //  than silently leaving the ether where it was.
            ILegacyBuffer(hook).fundLegacyBuffer{value: amount}();
            emit Swept(address(0), hook, amount);
            return amount;
        }

        address to = erc20Sink;
        amount = _balanceOf(asset);
        require(amount > 0, "nothing");
        _safeTransfer(asset, to, amount);
        //  Tell the sink to book it if it knows how. `MiFrensDividend.adopt`
        //  refuses an asset it has not been told about yet, so this is advisory:
        //  the tokens have already LANDED, which is what makes them recoverable,
        //  and the sink's own funder/treasury can adopt an unknown asset later.
        //  A revert here must not undo a delivery that already succeeded.
        try IAdoptable(to).adopt(asset) returns (uint256) { } catch { }
        emit Swept(asset, to, amount);
    }

    function _balanceOf(address asset) private view returns (uint256) {
        (bool ok, bytes memory data) =
            asset.staticcall(abi.encodeWithSelector(0x70a08231, address(this))); // balanceOf(address)
        require(ok && data.length >= 32, "balance");
        return abi.decode(data, (uint256));
    }

    /// @dev Tolerates the non-standard ERC20s that return nothing on transfer.
    function _safeTransfer(address asset, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            asset.call(abi.encodeWithSelector(0xa9059cbb, to, amount)); // transfer(address,uint256)
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }
}
