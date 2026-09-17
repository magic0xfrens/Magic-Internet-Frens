// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {ICauldronCollection} from "../../cauldron/ICauldron.sol";

/// @notice M3A — EXECUTE playChurn. Measure the real volume/credit multiplier,
///         the NFTs it mints, and the ETH it actually costs.
contract M3A_ChurnEconomics is YBase {
    CauldronGachaRouter internal router;

    struct Res {
        uint256 ethSpent;      // net ETH out of the actor's pocket
        uint256 tokensKept;    // creature tokens left holding
        uint256 volume;        // lifetimeVolumeOf delta (never spent, unlike credit)
        uint256 cumDelta;      // protocol cumulativeVolume delta (death oracle)
        uint256 mult;          // volume * 1e4 / ethSpent
        uint256 opened;
        bool ran;
    }

    function setUp() public {
        _boot(50 ether, 0);
        if (!active) return;
        router = new CauldronGachaRouter(pm, address(hook), address(registry), address(this));
        hook.setOpener(address(router), true);
        // Past the anti-snipe surtax window (snipeWindowBlocks = 30) so we are
        // measuring the steady-state economics, not the 99% launch tax.
        vm.roll(block.number + 40);
    }

    function _snapshot(address who) internal view returns (uint256 e, uint256 t, uint256 v, uint256 c) {
        e = who.balance;
        t = IERC20Minimal(token).balanceOf(who);
        v = hook.lifetimeVolumeOf(who);
        c = hook.cumulativeVolume();
    }

    function _churn(address who, uint256 amt, uint256 loops) internal returns (Res memory r) {
        if (!active) return r;
        r.ran = true;
        (uint256 e0, uint256 t0, uint256 v0, uint256 c0) = _snapshot(who);
        vm.prank(who, who);
        r.opened = router.playChurn{value: amt}(0, loops, 0, 1);
        (uint256 e1, uint256 t1, uint256 v1, uint256 c1) = _snapshot(who);
        r.ethSpent = e0 - e1;
        r.tokensKept = t1 - t0;
        r.volume = v1 - v0;
        r.cumDelta = c1 - c0;
        if (r.ethSpent > 0) r.mult = (r.volume * 10_000) / r.ethSpent;
    }

    function _plainBuy(address who, uint256 amt) internal returns (Res memory r) {
        if (!active) return r;
        r.ran = true;
        (uint256 e0, uint256 t0, uint256 v0, uint256 c0) = _snapshot(who);
        vm.prank(who, who);
        r.opened = router.play{value: amt}(0, 0, 0, 0, 1);
        (uint256 e1, uint256 t1, uint256 v1, uint256 c1) = _snapshot(who);
        r.ethSpent = e0 - e1;
        r.tokensKept = t1 - t0;
        r.volume = v1 - v0;
        r.cumDelta = c1 - c0;
        if (r.ethSpent > 0) r.mult = (r.volume * 10_000) / r.ethSpent;
    }

    function test_M3A_churn_multiplier_vs_plain_buy() public {
        Res memory churn = _churn(attacker, 1 ether, 10);
        Res memory plain = _plainBuy(victim, 1 ether);

        console2.log("CHURN  ethSpent ", churn.ethSpent);
        console2.log("CHURN  tokensKept", churn.tokensKept);
        console2.log("CHURN  volume   ", churn.volume);
        console2.log("CHURN  cumDelta ", churn.cumDelta);
        console2.log("CHURN  x1e4     ", churn.mult);
        console2.log("PLAIN  ethSpent ", plain.ethSpent);
        console2.log("PLAIN  tokensKept", plain.tokensKept);
        console2.log("PLAIN  volume   ", plain.volume);
        console2.log("PLAIN  cumDelta ", plain.cumDelta);
        console2.log("PLAIN  x1e4     ", plain.mult);
        console2.log("MINTED  ", ICauldronCollection(hook.collection()).totalMinted());

        assertTrue(churn.ran && plain.ran, "fork inactive: FORK_RPC unset");
        assertGt(churn.volume, 0, "churn credited nothing");
        assertGt(churn.mult, plain.mult, "churn not amplified vs plain buy");
    }
}
