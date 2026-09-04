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

    struct PlayData {
        address player;
        uint256 ethIn;      // ETH to spend on a buy leg (0 to skip)
        uint256 gnomeIn;    // token to spend on a sell leg (0 to skip)
        uint256 minGnomeOut;
        uint256 minEthOut;
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

    /// @notice One-click play. Send ETH to buy and/or approve+pass `gnomeIn` to
    ///         sell; the volume is credited to you and your crystals opened.
    function play(uint256 gnomeIn, uint256 minGnomeOut, uint256 minEthOut, uint256 openMax)
        external
        payable
        nonReentrant
        returns (uint256 opened)
    {
        if (msg.value == 0 && gnomeIn == 0) revert NothingSupplied();
        PoolKey memory key = _key();

        if (gnomeIn > 0) {
            _safeTransferFrom(Currency.unwrap(key.currency1), msg.sender, address(this), gnomeIn);
        }

        bytes memory ret = poolManager.unlock(
            abi.encode(
                uint8(0),
                abi.encode(PlayData({
                    player: msg.sender,
                    ethIn: msg.value,
                    gnomeIn: gnomeIn,
                    minGnomeOut: minGnomeOut,
                    minEthOut: minEthOut
                }))
            )
        );
        (uint256 ethConsumed, uint256 gnomeConsumed, uint256 sellEthGross) =
            abi.decode(ret, (uint256, uint256, uint256));

        // Slippage guard on the sell proceeds before any external send.
        if (sellEthGross > 0 && sellEthGross < minEthOut) revert Slippage();

        // EFFECTS first: commit + resolve the gacha, THEN pay the player out
        // (audit L3 — external ETH/token sends happen last, after all state).
        uint256 playWei = ethConsumed + sellEthGross; // ETH notional traded
        uint256 want = openMax == 0 ? type(uint256).max : openMax;
        opened = hook.commitCrystals(msg.sender, want, playWei);
        hook.resolveTickets(MAX_MINTS_PER_CALL);

        // INTERACTIONS: refund unused sell input, pay sell proceeds + ETH refund.
        if (gnomeIn > gnomeConsumed) {
            _safeTransfer(Currency.unwrap(key.currency1), msg.sender, gnomeIn - gnomeConsumed);
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
        opened = hook.commitCrystals(msg.sender, want, playWei);
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
        bytes memory hookData = abi.encode(d.player); // credit the player

        Currency eth = key.currency0;
        Currency gnome = key.currency1;

        uint256 ethConsumed;
        uint256 gnomeConsumed;
        uint256 sellEthGross;

        // BUY leg: ETH -> creature token
        if (d.ethIn > 0) {
            BalanceDelta delta = poolManager.swap(
                key,
                SwapParams({zeroForOne: true, amountSpecified: -int256(d.ethIn), sqrtPriceLimitX96: _limit(true)}),
                hookData
            );
            uint256 outAmount = uint256(uint128(delta.amount1()));
            if (outAmount < d.minGnomeOut) revert Slippage();
            ethConsumed = uint256(uint128(-delta.amount0()));
            _settle(eth, ethConsumed, true);
            _take(gnome, d.player, outAmount);
        }

        // SELL leg: creature token -> ETH
        if (d.gnomeIn > 0) {
            BalanceDelta delta = poolManager.swap(
                key,
                SwapParams({zeroForOne: false, amountSpecified: -int256(d.gnomeIn), sqrtPriceLimitX96: _limit(false)}),
                hookData
            );
            uint256 outAmount = uint256(uint128(delta.amount0()));
            gnomeConsumed = uint256(uint128(-delta.amount1()));
            _settle(gnome, gnomeConsumed, false);
            _take(eth, address(this), outAmount); // held; play() pays the player
            sellEthGross = outAmount;
        }

        return abi.encode(ethConsumed, gnomeConsumed, sellEthGross);
    }

    function _churn(ChurnData memory c) private returns (bytes memory) {
        PoolKey memory key = _key();
        bytes memory hookData = abi.encode(c.player);
        Currency eth = key.currency0;
        Currency gnome = key.currency1;

        uint256 ethBal = c.ethIn;
        uint256 gnomeBal;
        uint256 playWei;

        for (uint256 i = 0; i < c.loops; i++) {
            if (ethBal > 0) {
                BalanceDelta delta = poolManager.swap(
                    key,
                    SwapParams({zeroForOne: true, amountSpecified: -int256(ethBal), sqrtPriceLimitX96: _limit(true)}),
                    hookData
                );
                uint256 inE = uint256(uint128(-delta.amount0()));
                uint256 outG = uint256(uint128(delta.amount1()));
                _settle(eth, inE, true);
                _take(gnome, address(this), outG);
                playWei += inE;
                gnomeBal += outG;
                ethBal = 0;
            }
            if (i + 1 < c.loops && gnomeBal > 0) {
                BalanceDelta delta = poolManager.swap(
                    key,
                    SwapParams({zeroForOne: false, amountSpecified: -int256(gnomeBal), sqrtPriceLimitX96: _limit(false)}),
                    hookData
                );
                uint256 inG = uint256(uint128(-delta.amount1()));
                uint256 outE = uint256(uint128(delta.amount0()));
                _settle(gnome, inG, false);
                _take(eth, address(this), outE);
                playWei += outE;
                ethBal += outE;
                gnomeBal = 0;
            }
        }

        if (gnomeBal > 0) _safeTransfer(Currency.unwrap(gnome), c.player, gnomeBal);
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
