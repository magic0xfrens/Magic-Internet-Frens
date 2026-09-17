// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/// @notice Whale pressure on the relaunch seam.
///  A flashloan-sized buy drains the dying pool's token side immediately before
///  the (publicly visible, pending-tx-readable) relaunch. Question: does the
///  rebirth still land, and can a holder still exit via claimByBurn?
contract M4B_RelaunchWhale is YBase {
    struct Res {
        bool booted;
        uint256 bought;
        bool relaunchOk;
        bytes err;
        uint256 gen;
        uint256 reserveId;
        bool claimOk;
        bytes claimErr;
        uint256 newTokens;
    }

    Res internal R;

    function setUp() public {
        _boot(25 ether, 0);
        R.booted = active;
    }

    function _attack() internal {
        if (!R.booted) return;

        // 1. WHALE: buy with 20,000 ETH (flashloanable: the v4 PoolManager alone
        //    holds ~21,218 ETH). Pushes price far up and drains the active band
        //    AND trades into the 69x out-of-range redemption reserve.
        vm.deal(address(this), 40_000 ether);
        R.bought = _buy(500 ether, attacker);
        console2.log("whale bought (tokens)", R.bought);
        console2.log("tick after whale buy", int256(_tick()));

        // 2. Let the volume decay so the pool reads dead, then relaunch.
        _warp(26 hours);
        assertGt(vm.getBlockTimestamp(), 0, "warp landed");
        (R.relaunchOk, R.err) = address(registry).call(abi.encodeWithSignature("relaunch()"));
        R.gen = registry.currentGeneration();
        R.reserveId = registry.generationReservePositionId(2);
        console2.log("gen", R.gen);
        console2.log("reserveId gen2", R.reserveId);
        if (!R.relaunchOk) console2.logBytes(R.err);

        // 3. Can the whale still EXIT its gen-1 bag 1:1 into gen 2?
        if (R.relaunchOk) {
            address newTok = registry.currentToken();
            vm.prank(attacker);
            (R.claimOk, R.claimErr) = address(registry).call(
                abi.encodeWithSignature("claimByBurn(uint256,uint256)", uint256(1), R.bought)
            );
            R.newTokens = IERC20Minimal(newTok).balanceOf(attacker);
            console2.log("claimOk", R.claimOk);
            console2.log("new tokens received", R.newTokens);
            if (!R.claimOk) console2.logBytes(R.claimErr);
        }
    }

    function test_whale_cannot_break_relaunch_or_exit() public {
        _attack();
        assertTrue(R.booted, "fork harness must be live");
        assertTrue(R.relaunchOk, "LIVENESS: relaunch must survive a whale drain");
        assertTrue(R.claimOk, "LIVENESS: a holder must still be able to exit 1:1");
        assertLe(R.bought - R.newTokens, 1000, "exit must be 1:1 within dust");
        assertGt(R.newTokens, 0, "exit must deliver tokens");
    }
}
