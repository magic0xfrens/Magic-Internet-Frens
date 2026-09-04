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

interface IHookView {
    // Renamed on-chain: the hook exposes `crystalsReady`, not `openableNFTs`.
    // The stale selector reverted at the END of this script, which made Foundry
    // abort the whole run AFTER the swaps had simulated — so the broadcast was
    // silently dropped and the swaps never landed.
    function crystalsReady(address player) external view returns (uint256);
    function getVolume24h(bytes32 id) external view returns (uint256);
    function nftCredit(uint256 epoch, address player) external view returns (uint256);
    function creditEpoch() external view returns (uint256);
}
interface ICollView {
    function totalMinted() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

/**
 * @notice Generate swap volume on the GnomeLand pool → accrue NFT credit →
 *         mint collection NFTs. Buys ETH->GNOME carrying the player in hookData.
 *
 *  Env: PRIVATE_KEY, POOL_MANAGER, GNOME (token), HOOK, COLLECTION, SWAPS, SWAP_ETH
 */
contract SwapVolume is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address player = vm.addr(pk);
        IPoolManager pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address gnome = vm.envAddress("GNOME");
        address hook = vm.envAddress("HOOK");
        address collection = vm.envAddress("COLLECTION");
        uint256 swaps = vm.envOr("SWAPS", uint256(5));
        uint256 swapEth = vm.envOr("SWAP_ETH", uint256(0.05 ether));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(gnome),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(hook)
        });

        vm.startBroadcast(pk);
        PoolSwapTest router = new PoolSwapTest(pm);
        bytes memory hookData = abi.encode(player);

        for (uint256 i = 0; i < swaps; i++) {
            // Exact-input ETH -> GNOME (zeroForOne, negative amountSpecified).
            SwapParams memory sp = SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapEth),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            });
            PoolSwapTest.TestSettings memory ts =
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
            router.swap{value: swapEth}(key, sp, ts, hookData);
            console2.log("swap", i + 1, "done");
        }

        // Report the credit these swaps banked. We do NOT force-open crystals
        // here any more: the hook forges them IN-SWAP for router-less buys (the
        // native gacha path), and the old `openNFTs(player, n)` entrypoint no
        // longer exists. Calling it reverted at the very END of this script,
        // which made Foundry abort AFTER the swaps had simulated -- so the whole
        // broadcast was silently dropped and no volume ever landed on-chain.
        IHookView hv = IHookView(hook);
        console2.log("crystals ready :", hv.crystalsReady(player));
        vm.stopBroadcast();

        console2.log("collection totalMinted:", ICollView(collection).totalMinted());
        console2.log("player NFT balance   :", ICollView(collection).balanceOf(player));
    }
}
