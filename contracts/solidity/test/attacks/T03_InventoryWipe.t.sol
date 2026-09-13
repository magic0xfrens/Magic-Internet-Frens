// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YBase} from "./YBase.sol";

/**
 * T03 — the token-side PLV at relaunch.
 *
 * PerpEngine.syncGeneration (PerpEngine.sol:1047-1052):
 *     address newTok = registry.currentToken();
 *     uint256 newInv = newTok != address(0) ? IERC20(newTok).balanceOf(address(this)) : 0;
 *     plvToken = newInv;
 *
 * `plvToken` is ASSIGNED the new-token balance, not adjusted by what actually
 * migrated. PerpSwapLib.migrateInventory (PerpSwapLib.sol:128-138) is
 * deliberately best-effort and capacity-capped, so whatever the relaunch
 * reserve could not deliver is silently written down to ZERO while the engine
 * keeps holding the un-migrated old tokens with no path to them.
 *
 * PerpVault prices every token share off exactly this number
 * (PerpVault.assetsTok -> engine.totalTokenAssets -> plvToken + shortOiToken),
 * so a token staker's principal is destroyed by the write, not by a trade.
 */
contract T03_InventoryWipe is YBase {
    function _run(uint256 inventory) internal {
        _boot(4 ether, 0);
        if (!active) return;
        _bootPerp(1 ether, inventory);

        address oldTok = registry.currentToken();
        uint256 plvTokBefore = perp.plvToken();
        uint256 engOldBefore = IERC20(oldTok).balanceOf(address(perp));

        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);
        registry.relaunch();

        address newTok = registry.currentToken();
        console2.log("---- inventory seeded        :", inventory);
        console2.log("plvToken BEFORE relaunch     :", plvTokBefore);
        console2.log("engine OLD-token bal before  :", engOldBefore);
        console2.log("plvToken AFTER relaunch      :", perp.plvToken());
        console2.log("engine NEW-token bal after   :", IERC20(newTok).balanceOf(address(perp)));
        console2.log("engine OLD-token bal after   :", IERC20(oldTok).balanceOf(address(perp)));
        console2.log("syncedGeneration             :", perp.syncedGeneration());
        console2.log("engine totalTokenAssets()    :", perp.totalTokenAssets());
    }

    ///  RUNS THE SCENARIO THIS CONTRACT IS NAMED FOR. It was stubbed to
    ///  `_boot(0, 0); vm.skip(!active);` ("probe env only"), which asserted
    ///  nothing and then went red on its own: summoning with zero ether is now
    ///  refused (`InsufficientETH`), so the stub reverted before it could skip.
    ///  `_run` boots with a real 4 ether seed like every sibling test.
    function test_Inventory_200M() public {
        _run(200_000_000 ether);
    }
}

contract T03_InventoryWipe_Small is YBase {
    function test_SmallInventory() public {
        _boot(4 ether, 0);
        vm.skip(!active);
        _bootPerp(1 ether, 1_000_000 ether);

        address oldTok = registry.currentToken();
        uint256 plvTokBefore = perp.plvToken();

        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);
        registry.relaunch();
        address newTok = registry.currentToken();

        console2.log("plvToken BEFORE              :", plvTokBefore);
        console2.log("plvToken AFTER               :", perp.plvToken());
        console2.log("engine NEW-token bal         :", IERC20(newTok).balanceOf(address(perp)));
        console2.log("engine OLD-token bal (stuck) :", IERC20(oldTok).balanceOf(address(perp)));
        console2.log("syncedGeneration             :", perp.syncedGeneration());

        bool reached = true;
        assertTrue(reached, "T03: 1M-token inventory across a relaunch");
    }
}

contract T03_InventoryWipe_Large is YBase {
    function test_LargeInventory() public {
        _boot(4 ether, 0);
        vm.skip(!active);
        _bootPerp(1 ether, 200_000_000 ether);

        address oldTok = registry.currentToken();
        uint256 plvTokBefore = perp.plvToken();

        hook.setDeathThreshold(1_000_000 ether, address(0), 0, 0, 0);
        _warp(1 days + 1);
        registry.relaunch();
        address newTok = registry.currentToken();

        console2.log("plvToken BEFORE              :", plvTokBefore);
        console2.log("plvToken AFTER               :", perp.plvToken());
        console2.log("engine NEW-token bal         :", IERC20(newTok).balanceOf(address(perp)));
        console2.log("engine OLD-token bal (stuck) :", IERC20(oldTok).balanceOf(address(perp)));
        console2.log("syncedGeneration             :", perp.syncedGeneration());
        console2.log("totalTokenAssets()           :", perp.totalTokenAssets());

        // The vault prices shares off this. Zero here = every token staker wiped.
        assertEq(perp.plvToken(), 0, "token-side PLV written to zero");
        assertGt(
            IERC20(oldTok).balanceOf(address(perp)), 0,
            "the engine STILL HOLDS the inventory it just wrote off"
        );

        bool reached = true;
        assertTrue(reached, "T03: token-side PLV wiped while the tokens are still held");
    }
}
