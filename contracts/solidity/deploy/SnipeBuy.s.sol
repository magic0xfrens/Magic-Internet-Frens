// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

interface ISeederView {
    function deployedWad() external view returns (uint256);
    function seeding() external view returns (bool);
    function isComplete() external view returns (bool);
}
interface IERC20View { function balanceOf(address) external view returns (uint256); }

/**
 * @notice SNIPE / BUY probe for the progressive launch window. Buys ETH->token
 *         through the live pool and LOGS the price impact + how many tokens/ETH
 *         the buy got, alongside the seeder's streamed fraction — so you can watch
 *         (on real Sepolia) how a block-0 / early snipe eats far more impact than
 *         the same buy later once the book has streamed in.
 *
 *  Run it from SEVERAL funded wallets at different times across the window (e.g.
 *  t=0, t=window/2, t=window) to compare fills. Optionally poke the seeder here
 *  too (POKE=1) — though in production the hook streams in-swap automatically.
 *
 *  Env:
 *    PRIVATE_KEY   the sniper wallet (required, funded)
 *    POOL_MANAGER  V4 PoolManager (required)
 *    TOKEN         the current brew token (required; registry.currentToken())
 *    HOOK          the CauldronHook (required)
 *    BUY_ETH       ETH to spend (default 0.2 ether)
 *    SEEDER        CauldronSeeder (optional; logs deployedWad + can poke)
 *    POKE          "1" to seeder.poke() before buying (optional)
 *
 *  NOTE: the buyer here is a normal (non-exempt) wallet, so it ALSO pays the
 *  hook's base tax + anti-sniper surtax — i.e. this shows the FULL launch cost
 *  (impact + tax), which is the real sniper experience.
 */
contract SnipeBuy is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address buyer = vm.addr(pk);
        IPoolManager pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address token = vm.envAddress("TOKEN");
        address hook = vm.envAddress("HOOK");
        uint256 buyEth = vm.envOr("BUY_ETH", uint256(0.2 ether));
        address seeder = vm.envOr("SEEDER", address(0));
        bool doPoke = vm.envOr("POKE", uint256(0)) == 1;

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(token),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(hook)
        });
        PoolId pid = key.toId();

        vm.startBroadcast(pk);

        if (seeder != address(0)) {
            console2.log("seeder deployedWad (1e18=100%):", ISeederView(seeder).deployedWad());
            console2.log("seeder complete:", ISeederView(seeder).isComplete());
            if (doPoke && ISeederView(seeder).seeding() && !ISeederView(seeder).isComplete()) {
                (bool ok,) = seeder.call(abi.encodeWithSignature("poke()"));
                console2.log("poked:", ok);
            }
        }

        (, int24 tickBefore,,) = pm.getSlot0(pid);
        uint256 balBefore = IERC20View(token).balanceOf(buyer);

        PoolSwapTest router = new PoolSwapTest(pm);
        SwapParams memory sp = SwapParams({
            zeroForOne: true, // ETH -> token
            amountSpecified: -int256(buyEth), // exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        PoolSwapTest.TestSettings memory ts =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        router.swap{value: buyEth}(key, sp, ts, abi.encode(buyer));

        (, int24 tickAfter,,) = pm.getSlot0(pid);
        uint256 got = IERC20View(token).balanceOf(buyer) - balBefore;

        vm.stopBroadcast();

        console2.log("=== SNIPE/BUY RESULT ===");
        console2.log("buyer            :", buyer);
        console2.log("ETH spent (wei)  :", buyEth);
        console2.log("tokens received  :", got);
        console2.log("tokens per 1 ETH :", buyEth == 0 ? 0 : (got * 1e18) / buyEth);
        // ETH is currency0; a buy pushes the tick DOWN, so tickBefore - tickAfter > 0
        // is the price impact (in ticks) the buy suffered.
        console2.log("tick before      :", _u(tickBefore));
        console2.log("tick after       :", _u(tickAfter));
        console2.log("tick impact      :", _u(tickBefore - tickAfter));
    }

    function _u(int24 v) private pure returns (int256) { return int256(v); }
}
