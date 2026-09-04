// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {ReserveLib} from "./ReserveLib.sol";

interface IPositionManagerOps {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

interface IPermit2Ops {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// @dev Result of creating + seeding a two-position pool.
struct SeedResult {
    PoolId poolId;
    PoolKey key;
    uint256 activePositionId;
    uint256 reservePositionId;
    int24 reserveTickLower;
    int24 reserveTickUpper;
}

/**
 * @title PoolOps
 * @notice EXTERNAL (linked, delegatecall'd) library holding all V4
 *         PositionManager encoding for the Cauldron registry. Extracted so the
 *         registry stays under the EIP-170 24,576-byte limit while gaining the
 *         two-position (active + out-of-range reserve) launch model.
 *
 *  Because these are delegatecall'd, `address(this)` is the REGISTRY: it holds
 *  the tokens/ETH, owns the position NFTs, and is the msg.sender the
 *  PositionManager and Permit2 see. The library holds no state.
 */
library PoolOps {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    using PoolIdLibrary for PoolKey;

    /// @dev Approve the PositionManager to pull `amount` of `token` via Permit2.
    function _approve(address token, address pm, uint256 amount) private {
        IERC20(token).approve(PERMIT2, amount);
        IPermit2Ops(PERMIT2).approve(token, pm, uint160(amount), uint48(block.timestamp + 300));
    }

    function _sqrtPrice(uint256 tokenAmount, uint256 ethAmount) private pure returns (uint160) {
        uint256 ratio = FullMath.mulDiv(tokenAmount, 1 << 192, ethAmount);
        // Babylonian sqrt.
        uint256 x = ratio;
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
        return uint160(y);
    }

    /**
     * @notice Build the pool, initialize its price from (activeTokens:ETH), and
     *         seed BOTH the active full-range position and the out-of-range
     *         single-sided reserve. One external call keeps the registry lean.
     */
    function createAndSeed(
        IPoolManager poolManager,
        IPositionManagerOps pm,
        address hook,
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        int24 tickSpacing,
        uint24 poolFee,
        int24 ceilingOffset
    ) external returns (SeedResult memory r) {
        r.key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(token),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });
        r.poolId = r.key.toId();

        uint160 sqrtPriceX96 = _sqrtPrice(activeTokens, ethAmount);
        poolManager.initialize(r.key, sqrtPriceX96);
        int24 launchTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        r.activePositionId = _seedActive(pm, r.key, sqrtPriceX96, ethAmount, activeTokens, token, tickSpacing);

        if (reserveTokens > 0) {
            (r.reserveTickLower, r.reserveTickUpper) =
                ReserveLib.reserveTicks(launchTick, tickSpacing, ceilingOffset);
            r.reservePositionId =
                _seedReserve(pm, r.key, r.reserveTickLower, r.reserveTickUpper, reserveTokens, token);
        }
    }

    /// @dev Mint the ACTIVE full-range position (ETH + tradeable token slice).
    function _seedActive(
        IPositionManagerOps pm,
        PoolKey memory key,
        uint160 sqrtPriceX96,
        uint256 ethAmount,
        uint256 tokenAmount,
        address token,
        int24 tickSpacing
    ) private returns (uint256 positionId) {
        _approve(token, address(pm), tokenAmount);

        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(minTick),
            TickMath.getSqrtPriceAtTick(maxTick),
            ethAmount,
            tokenAmount
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key, minTick, maxTick, liquidity,
            uint128(ethAmount), uint128(tokenAmount), address(this), bytes("")
        );
        params[1] = abi.encode(Currency.wrap(address(0)), Currency.wrap(token));
        params[2] = abi.encode(Currency.wrap(address(0)), address(this)); // excess ETH back

        positionId = pm.nextTokenId();
        pm.modifyLiquidities{value: ethAmount}(abi.encode(actions, params), block.timestamp + 120);
    }

    /// @dev Mint the RESERVE single-sided TOKEN position, out of range BELOW the
    ///      launch tick (pure token1 until the token pumps into it).
    function _seedReserve(
        IPositionManagerOps pm,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenAmount,
        address token
    ) private returns (uint256 positionId) {
        uint128 liquidity = ReserveLib.liquidityForTokenOut(tickLower, tickUpper, tokenAmount);
        _approve(token, address(pm), tokenAmount);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](3);
        // Single-sided: max0 (ETH) = 0, max1 (token) = tokenAmount.
        params[0] = abi.encode(
            key, tickLower, tickUpper, liquidity,
            uint128(0), uint128(tokenAmount), address(this), bytes("")
        );
        params[1] = abi.encode(Currency.wrap(address(0)), Currency.wrap(token));
        params[2] = abi.encode(Currency.wrap(address(0)), address(this));

        positionId = pm.nextTokenId();
        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);
    }

    /**
     * @notice Remove 100% of a position and take both currencies to the registry,
     *         burning the NFT. Used at death for BOTH the active + reserve
     *         positions. Returns recovered (eth, tokens) via balance deltas.
     */
    function removeAll(IPositionManagerOps pm, uint256 positionId, PoolKey memory key, address token)
        external
        returns (uint256 ethRecovered, uint256 tokensRecovered)
    {
        uint128 liquidity = pm.getPositionLiquidity(positionId);
        if (liquidity == 0) return (0, 0);

        uint256 ethBefore = address(this).balance;
        uint256 tokBefore = IERC20(token).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR), uint8(Actions.BURN_POSITION)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, address(this));
        params[2] = abi.encode(positionId, uint128(0), uint128(0), bytes(""));

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        ethRecovered = address(this).balance - ethBefore;
        tokensRecovered = IERC20(token).balanceOf(address(this)) - tokBefore;
    }

    /**
     * @notice Claim EXACTLY `amount` token from the out-of-range reserve position
     *         and take it straight to `recipient` — zero ETH, no price move
     *         (the range is fully below spot). Keeps the position open for the
     *         next claimer. Returns the token amount actually taken.
     */
    function claimFromReserve(
        IPositionManagerOps pm,
        uint256 positionId,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount,
        address recipient
    ) external returns (uint256 taken) {
        uint128 liquidity = ReserveLib.liquidityForTokenOut(tickLower, tickUpper, amount);
        if (liquidity == 0) return 0;
        // Don't remove more than the position holds.
        uint128 have = pm.getPositionLiquidity(positionId);
        if (liquidity > have) liquidity = have;
        if (liquidity == 0) return 0;

        uint256 tokBefore = IERC20(Currency.unwrap(key.currency1)).balanceOf(recipient);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](2);
        // amount1Min = 0 (dust rounding); reserve is out of range so ETH out = 0.
        params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, recipient);

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        taken = IERC20(Currency.unwrap(key.currency1)).balanceOf(recipient) - tokBefore;
    }
}
