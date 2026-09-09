// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ICauldronHookGacha {
    function commitCrystals(address player, uint256 maxCount, uint256 playWei) external returns (uint256);
    function resolveTickets(uint256 maxCount) external returns (uint256, uint256);
    function crystalsReady(address player) external view returns (uint256);
    function costOfNextCrystals(uint256 count) external view returns (uint256);
    function buyWeightBps() external view returns (uint256);
}

interface IRegistryCurrent {
    function currentToken() external view returns (address);
}

/// @notice The quote oracle's uncached view, used to convert a play's ETH
///         notional into the same USD unit the hook's odds curve uses (audit
///         Q-02). Returns the USD value of one raw unit of `quote` scaled by
///         1e18, or 0 when the price is unusable.
interface IQuoteOracleView {
    function usdPerRawUnit(address quote) external view returns (uint256);
}

/**
 * @title CauldronGachaRouter
 * @notice One-click entry to the Cauldron crystal gacha. The player sends ETH
 *         (a BUY) and/or GNOME/creature-token (a SELL); the router routes the
 *         swap(s) through the V4 pool, tagging the swap `hookData` with the
 *         PLAYER'S address so the hook credits volume to the player (not this
 *         router). It then OPENS the player's crystals at the honest ETH play
 *         size — enqueuing lottery tickets — and resolves matured ones.
 *
 *  Unlike GnomeLand's router there is NO separate game fee: the CauldronHook
 *  already skims its fee (in ETH) on every swap and routes it to the floor
 *  vault / genesis dividend / relaunch reserve. So a losing ticket's swap has
 *  already lifted the floor for everyone.
 *
 *  The pool ROTATES each iteration (new creature token → new pool), so the key
 *  is rebuilt from `registry.currentToken()` on every call. ETH is always
 *  currency0 (address(0) sorts first).
 */
contract CauldronGachaRouter is IUnlockCallback, Ownable {
    using BalanceDeltaLibrary for BalanceDelta;

    IPoolManager public immutable poolManager;
    ICauldronHookGacha public immutable hook;
    IRegistryCurrent public immutable registry;
    address public immutable hookAddr;

    uint24 public constant POOL_FEE = 0;
    int24 public constant TICK_SPACING = 200;
    uint256 public constant MAX_MINTS_PER_CALL = 30;
    uint256 public constant MAX_LOOPS = 10;

    uint256 private _locked = 1;

    /**
     * @notice The same {QuoteOracle} the hook prices volume with — used ONLY to
     *         express this router's play size in the hook's odds-curve unit.
     *
     *  ── WHY THIS LIVES HERE (audit Q-02) ──────────────────────────────────
     *  The hook's odds curve (`oddsFullVolumeWei`) is denominated in ether while
     *  no oracle is wired, and restated into USD the moment one is (audit U-1,
     *  {CauldronHook.setDeathThreshold}). The hook's NATIVE in-swap gacha already
     *  feeds a USD figure, but this router measures an honest ETH notional from
     *  the swap deltas — so once an oracle is wired the router's play size was a
     *  wei numerator over a USD denominator, collapsing its odds by roughly the
     *  ETH price (measured: 9000 bps native vs 4 bps router for the same $1,500
     *  buy). The conversion belongs on whichever side can afford the bytes, and
     *  {CauldronHook} is against the EIP-170 ceiling with tens of bytes spare
     *  while this router has kilobytes.
     *
     *  UNSET = today's behaviour exactly: the play size passes through unchanged,
     *  which is correct for the ether-denominated curve. Wire this in the same
     *  step that wires the hook's oracle, or the router keeps under-pricing its
     *  own odds — it fails SAFE (players win less, never more), never unsafe.
     */
    address public oracle;

    event OracleSet(address oracle);

    /// @notice Point the router at the hook's quote oracle (see {oracle}).
    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
        emit OracleSet(_oracle);
    }

    /**
     * @dev Express an ETH-notional play size in the hook's odds-curve unit.
     *
     *  With no oracle wired (or a price the oracle refuses) the value passes
     *  through untouched — the curve is in ether terms then, so that is exactly
     *  right, and a refusal must never zero a player's odds. Otherwise convert
     *  ETH wei → USD at 1e18, matching what the hook's `_toUsd` produces for the
     *  native path.
     *
     *  `staticcall` via try/catch so a broken oracle degrades to the raw size
     *  rather than reverting a player's whole gacha spin.
     */
    /// @notice The play size this router would hand the hook for a given ETH
    ///         notional, in the hook's odds-curve unit. Exposed so a UI can show
    ///         the same odds the chain will roll (and so the conversion is
    ///         directly testable).
    function playInCurveUnits(uint256 playWei) external view returns (uint256) {
        return _playInCurveUnits(playWei);
    }

    function _playInCurveUnits(uint256 playWei) internal view returns (uint256) {
        address o = oracle;
        if (o == address(0)) return playWei;
        try IQuoteOracleView(o).usdPerRawUnit(address(0)) returns (uint256 f) {
            if (f == 0) return playWei; // "cannot judge" → leave the size alone
            return (playWei * f) / 1e18;
        } catch {
            return playWei;
        }
    }

    struct PlayData {
        address player;
        uint256 ethIn;      // ETH to spend on a buy leg (0 to skip)
        uint256 tokenIn;    // iteration token to spend on a sell leg (0 to skip)
        uint256 minTokenOut;
        uint256 minEthOut;
        uint256[] liqHints; // perp positions to auto-liquidate this swap (empty = none)
    }

    struct ChurnData {
        address player;
        uint256 ethIn;
        uint256 loops;
    }

    error Reentrancy();
    error NotPoolManager();
    error NothingSupplied();
    error Slippage();
    error RefundFailed();
    error BadLoops();

    event Played(address indexed player, uint256 playWei, uint256 opened);
    event Churned(address indexed player, uint256 loops, uint256 volumeWei, uint256 opened);

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(IPoolManager _poolManager, address _hook, address _registry, address _owner)
        Ownable(_owner)
    {
        poolManager = _poolManager;
        hook = ICauldronHookGacha(_hook);
        hookAddr = _hook;
        registry = IRegistryCurrent(_registry);
    }

    /// @dev The current iteration's pool key (ETH is currency0).
    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hookAddr)
        });
    }

    /// @notice One-click play. Send ETH to buy and/or approve+pass `tokenIn` to
    ///         sell; the volume is credited to you and your crystals opened.
    function play(uint256 tokenIn, uint256 minTokenOut, uint256 minEthOut, uint256 openMax)
        external
        payable
        nonReentrant
        returns (uint256 opened)
    {
        return _play(tokenIn, minTokenOut, minEthOut, openMax, new uint256[](0));
    }

    /// @notice Same as {play}, but tags the swap with perp `liqHints`: any of
    ///         those positions that is underwater at the TWAP mark is auto-
    ///         liquidated inside this swap (a single trade can rekt SEVERAL),
    ///         minting YOU (the swapper) a Liquidatoor badge + keeper reward for
    ///         each. Stale/healthy hints are silent no-ops, so passing them never
    ///         risks your trade. Frontends supply the crossed position ids here.
    function playLiq(uint256 tokenIn, uint256 minTokenOut, uint256 minEthOut, uint256 openMax, uint256[] calldata liqHints)
        external
        payable
        nonReentrant
        returns (uint256 opened)
    {
        return _play(tokenIn, minTokenOut, minEthOut, openMax, liqHints);
    }

    function _play(uint256 tokenIn, uint256 minTokenOut, uint256 minEthOut, uint256 openMax, uint256[] memory liqHints)
        internal
        returns (uint256 opened)
    {
        if (msg.value == 0 && tokenIn == 0) revert NothingSupplied();
        PoolKey memory key = _key();

        if (tokenIn > 0) {
            _safeTransferFrom(Currency.unwrap(key.currency1), msg.sender, address(this), tokenIn);
        }

        bytes memory ret = poolManager.unlock(
            abi.encode(
                uint8(0),
                abi.encode(PlayData({
                    player: msg.sender,
                    ethIn: msg.value,
                    tokenIn: tokenIn,
                    minTokenOut: minTokenOut,
                    minEthOut: minEthOut,
                    liqHints: liqHints
                }))
            )
        );
        (uint256 ethConsumed, uint256 tokenConsumed, uint256 sellEthGross) =
            abi.decode(ret, (uint256, uint256, uint256));

        // Slippage guard on the sell proceeds before any external send.
        if (sellEthGross > 0 && sellEthGross < minEthOut) revert Slippage();

        // EFFECTS first: commit + resolve the gacha, THEN pay the player out
        // (audit L3 — external ETH/token sends happen last, after all state).
        uint256 playWei = ethConsumed + sellEthGross; // ETH notional traded
        uint256 want = openMax == 0 ? type(uint256).max : openMax;
        //  Expressed in the hook's odds-curve unit (audit Q-02) — see {oracle}.
        //  The EVENT below still reports the honest ETH notional actually traded.
        opened = hook.commitCrystals(msg.sender, want, _playInCurveUnits(playWei));
        hook.resolveTickets(MAX_MINTS_PER_CALL);

        // INTERACTIONS: refund unused sell input, pay sell proceeds + ETH refund.
        if (tokenIn > tokenConsumed) {
            _safeTransfer(Currency.unwrap(key.currency1), msg.sender, tokenIn - tokenConsumed);
        }
        uint256 ethOut = sellEthGross + (msg.value - ethConsumed); // proceeds + refund
        if (ethOut > 0) {
            (bool ok,) = msg.sender.call{value: ethOut}("");
            if (!ok) revert RefundFailed();
        }
        emit Played(msg.sender, playWei, opened);
    }

    /// @notice Open crystals from ALREADY-earned credit (no fresh buy). Odds are
    ///         derived on-chain from the credit those crystals cost, converted to
    ///         ETH-notional at the buy weight — same fair odds as a live buy.
    function openReady(uint256 maxCount) external nonReentrant returns (uint256 opened) {
        uint256 ready = hook.crystalsReady(msg.sender);
        if (ready > MAX_MINTS_PER_CALL) ready = MAX_MINTS_PER_CALL;
        if (maxCount != 0 && maxCount < ready) ready = maxCount;
        if (ready == 0) return 0;

        uint256 creditToOpen = hook.costOfNextCrystals(ready);
        uint256 bw = hook.buyWeightBps();
        uint256 playWei = bw > 0 ? (creditToOpen * 10_000) / bw : creditToOpen;

        //  DELIBERATELY NOT converted through {_playInCurveUnits} (audit Q-02).
        //  Unlike the two swap paths, this size is derived from `costOfNextCrystals`
        //  — the hook's own curve — so it is ALREADY in curve units. Running it
        //  through the oracle would convert a USD figure a second time and inflate
        //  the odds by the ETH price. The unit follows where the number came from.
        opened = hook.commitCrystals(msg.sender, ready, playWei);
        hook.resolveTickets(MAX_MINTS_PER_CALL);
        emit Played(msg.sender, playWei, opened);
    }

    /// @notice Volume amplifier: crank buy→sell→…→buy in one tx so a small spend
    ///         generates a multiple of itself in volume (each leg credited to you).
    ///         Ends in a buy, so leftover creature-tokens are sent to your wallet.
    function playChurn(uint256 loops, uint256 openMax)
        external
        payable
        nonReentrant
        returns (uint256 opened)
    {
        if (msg.value == 0) revert NothingSupplied();
        if (loops == 0 || loops > MAX_LOOPS) revert BadLoops();

        bytes memory ret = poolManager.unlock(
            abi.encode(uint8(1), abi.encode(ChurnData({player: msg.sender, ethIn: msg.value, loops: loops})))
        );
        (uint256 playWei, uint256 ethLeftover) = abi.decode(ret, (uint256, uint256));

        uint256 want = openMax == 0 ? type(uint256).max : openMax;
        //  Churn's play size is also an ETH notional summed from the swap deltas,
        //  so it needs the same curve-unit conversion (audit Q-02) — see {oracle}.
        opened = hook.commitCrystals(msg.sender, want, _playInCurveUnits(playWei));
        hook.resolveTickets(MAX_MINTS_PER_CALL);

        if (ethLeftover > 0) {
            (bool ok,) = msg.sender.call{value: ethLeftover}("");
            if (!ok) revert RefundFailed();
        }
        emit Churned(msg.sender, loops, playWei, opened);
    }

    // ---------------------------------------------------------------------
    // Unlock callback — runs the swap legs and settles deltas
    // ---------------------------------------------------------------------

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (uint8 tag, bytes memory payload) = abi.decode(raw, (uint8, bytes));
        if (tag == 1) return _churn(abi.decode(payload, (ChurnData)));

        PlayData memory d = abi.decode(payload, (PlayData));
        PoolKey memory key = _key();
        // Credit the player (first word) + carry the optional perp liqHint (second
        // word) so an underwater position can be auto-liquidated inside this swap.
        // Consumers that only read the player decode the first word, unaffected.
        bytes memory hookData = abi.encode(d.player, d.liqHints);

        Currency eth = key.currency0;
        Currency tok = key.currency1;

        uint256 ethConsumed;
        uint256 tokenConsumed;
        uint256 sellEthGross;

        // BUY leg: ETH -> creature token
        if (d.ethIn > 0) {
            BalanceDelta delta = poolManager.swap(
                key,
                SwapParams({zeroForOne: true, amountSpecified: -int256(d.ethIn), sqrtPriceLimitX96: _limit(true)}),
                hookData
            );
            uint256 outAmount = uint256(uint128(delta.amount1()));
            if (outAmount < d.minTokenOut) revert Slippage();
            ethConsumed = uint256(uint128(-delta.amount0()));
            _settle(eth, ethConsumed, true);
            _take(tok, d.player, outAmount);
        }

        // SELL leg: creature token -> ETH
        if (d.tokenIn > 0) {
            BalanceDelta delta = poolManager.swap(
                key,
                SwapParams({zeroForOne: false, amountSpecified: -int256(d.tokenIn), sqrtPriceLimitX96: _limit(false)}),
                hookData
            );
            uint256 outAmount = uint256(uint128(delta.amount0()));
            tokenConsumed = uint256(uint128(-delta.amount1()));
            _settle(tok, tokenConsumed, false);
            _take(eth, address(this), outAmount); // held; play() pays the player
            sellEthGross = outAmount;
        }

        return abi.encode(ethConsumed, tokenConsumed, sellEthGross);
    }

    function _churn(ChurnData memory c) private returns (bytes memory) {
        PoolKey memory key = _key();
        bytes memory hookData = abi.encode(c.player);
        Currency eth = key.currency0;
        Currency tok = key.currency1;

        uint256 ethBal = c.ethIn;
        uint256 tokBal;
        uint256 playWei;

        uint256 loops = c.loops;
        for (uint256 i = 0; i < loops;) {
            if (ethBal > 0) {
                BalanceDelta delta = poolManager.swap(
                    key,
                    SwapParams({zeroForOne: true, amountSpecified: -int256(ethBal), sqrtPriceLimitX96: _limit(true)}),
                    hookData
                );
                uint256 inE = uint256(uint128(-delta.amount0()));
                uint256 outG = uint256(uint128(delta.amount1()));
                _settle(eth, inE, true);
                _take(tok, address(this), outG);
                playWei += inE;
                tokBal += outG;
                ethBal = 0;
            }
            if (i + 1 < loops && tokBal > 0) {
                BalanceDelta delta = poolManager.swap(
                    key,
                    SwapParams({zeroForOne: false, amountSpecified: -int256(tokBal), sqrtPriceLimitX96: _limit(false)}),
                    hookData
                );
                uint256 inG = uint256(uint128(-delta.amount1()));
                uint256 outE = uint256(uint128(delta.amount0()));
                _settle(tok, inG, false);
                _take(eth, address(this), outE);
                playWei += outE;
                ethBal += outE;
                tokBal = 0;
            }
            unchecked { ++i; }
        }

        if (tokBal > 0) _safeTransfer(Currency.unwrap(tok), c.player, tokBal);
        return abi.encode(playWei, ethBal);
    }

    function _limit(bool zeroForOne) private pure returns (uint160) {
        return zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341;
    }

    function _settle(Currency currency, uint256 amount, bool isNative) private {
        if (isNative) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            _safeTransfer(Currency.unwrap(currency), address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _take(Currency currency, address to, uint256 amount) private {
        if (amount > 0) poolManager.take(currency, to, amount);
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }

    function rescueETH(address to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "rescue failed");
    }

    receive() external payable {}
}
