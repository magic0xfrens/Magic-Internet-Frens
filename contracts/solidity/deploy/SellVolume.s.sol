// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

interface IERC20Min {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/**
 * @notice Sell GNOME -> ETH to verify the hook charges its fee in ETH on the
 *         OUTPUT (afterSwap) leg. Env: PRIVATE_KEY, POOL_MANAGER, GNOME, HOOK,
 *         SELLS, SELL_TOKENS.
 */
contract SellVolume is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        IPoolManager pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address gnome = vm.envAddress("GNOME");
        address hook = vm.envAddress("HOOK");
        uint256 sells = vm.envOr("SELLS", uint256(3));
        uint256 sellTokens = vm.envOr("SELL_TOKENS", uint256(20000 ether));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(gnome),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(hook)
        });

        vm.startBroadcast(pk);
        PoolSwapTest router = new PoolSwapTest(pm);
        IERC20Min(gnome).approve(address(router), type(uint256).max);

        for (uint256 i = 0; i < sells; i++) {
            // Exact-input GNOME -> ETH (zeroForOne = false, negative specified).
            SwapParams memory sp = SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(sellTokens),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            });
            PoolSwapTest.TestSettings memory ts =
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
            router.swap(key, sp, ts, bytes(""));
            console2.log("sell", i + 1, "done");
        }
        vm.stopBroadcast();
    }
}
