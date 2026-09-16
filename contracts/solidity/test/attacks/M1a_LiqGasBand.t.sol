// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/// @notice H1 REGRESSION (was an attack PoC).
///
/// BEFORE: the in-swap pre-emptive liquidation sweep was gated by
/// `LiqGasStarved` on a FIXED ~980k `gasleft` floor (LIQ_GAS_RESERVE 180k +
/// 2*LIQ_GAS_MIN 400k, CauldronHook.sol:799-835) that did not depend on how many
/// positions the incoming trade would bankrupt. One in-swap kill costs a measured
/// ~440k, so a buy that sinks four 2x shorts cleared the gate with gas for one
/// kill and left the other three open and insolvent at the price it had just set:
/// measured 4.360256 ETH of bad debt to PLV on a 30 ETH vault (~14.5%), at the
/// gas cost of an ordinary buy, repeatable. Griefing, not theft.
///
/// AFTER: `PerpEngine._doSweep` reports whether its pass over the book finished
/// (`complete`), and `CauldronHook._liqSweep` turns `complete == false` on the
/// PRE-trade sweep into the same loud `LiqGasStarved` revert. The floor cannot
/// know N; the loop that does the work does.
///
/// PROPERTY ASSERTED: across the whole dose-response band, a trade that bankrupts
/// N positions either REVERTS or leaves ZERO stranded insolvent positions — and
/// PLV backing is never written down below the ample-gas outcome.
contract M1a_LiqGasBand is YBase {
    uint256[] shortIds;
    uint256 bigBuy;

    function _openShort() internal returns (uint256 id) {
        vm.prank(victim);
        id = perp.openShort{value: 0.5 ether}(2, 0, 0, 0.5 ether);
    }

    function _setup() internal {
        _boot(60 ether, 0);
        assertTrue(active, "fork must be live for this regression");
        _bootPerp(30 ether, 0);
        deal(token, address(this), 2_000_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), type(uint256).max);
        perp.fundPlvToken(1_000_000_000 ether);

        // Four independent 2x shorts (max leverage). A big buy bankrupts all four.
        for (uint256 i = 0; i < 4; i++) shortIds.push(_openShort());
        bigBuy = 40 ether; // ~2.7x token price move -> every short insolvent
    }

    function extBuy(uint256 ethIn) external {
        require(msg.sender == address(this), "self");
        _buy(ethIn, address(this));
    }

    /// Run the price-moving buy under `gasCap`, then REALIZE every position the
    /// in-swap sweeps left open via keeper close (at whatever price now stands).
    /// Returns (buySucceeded, staker backing after full realization, openAfterBuy).
    function _run(uint256 gasCap) internal returns (bool ok, uint256 backing, uint256 openAfterBuy) {
        uint256 snap = vm.snapshot();
        (ok,) = address(this).call{gas: gasCap}(abi.encodeWithSignature("extBuy(uint256)", bigBuy));
        if (ok) {
            openAfterBuy = perp.openCount();
            for (uint256 i = 0; i < shortIds.length; i++) {
                try perp.liquidate(shortIds[i]) {} catch (bytes memory) {}
            }
            backing = perp.plv() + perp.insuranceEth();
        }
        vm.revertTo(snap);
    }

    function test_gate_affords_only_one_kill_strands_the_rest() public {
        _setup();

        uint256 backing0 = perp.plv() + perp.insuranceEth();

        // (1) Positive liveness control: a sub-gate trade FAILS LOUDLY.
        (bool okStarved,) = address(this).call{gas: 850_000}(abi.encodeWithSignature("extBuy(uint256)", bigBuy));
        assertFalse(okStarved, "sub-gate trade must be refused (LiqGasStarved)");

        // (2) Ample-gas control: the pre-emptive sweep closes all four at the
        //     pre-trade price and charges the stakers nothing.
        (bool okAmple, uint256 backingAmple, uint256 openAmple) = _run(8_000_000);
        assertTrue(okAmple, "ample-gas trade passes");
        assertEq(openAmple, 0, "ample gas closes every bankrupted short in-swap");
        assertEq(backingAmple, backing0, "ample gas charges PLV nothing");

        // (3) DOSE-RESPONSE: every cap that used to strand positions. Each one
        //     must now EITHER revert OR leave ZERO positions open after the buy.
        uint256 passes;
        uint256[10] memory caps = [
            uint256(1_000_000),
            1_070_000,
            1_100_000,
            1_200_000,
            1_300_000,
            1_350_000,
            1_400_000,
            1_500_000,
            1_600_000,
            1_900_000
        ];
        for (uint256 i = 0; i < caps.length; i++) {
            (bool ok, uint256 backing, uint256 open) = _run(caps[i]);
            emit log_named_uint("cap        ", caps[i]);
            emit log_named_uint("  filled   ", ok ? 1 : 0);
            emit log_named_uint("  open     ", open);
            emit log_named_uint("  backing  ", backing);
            if (ok) {
                passes++;
                assertEq(open, 0, "a filled trade must strand ZERO insolvent positions");
                assertEq(backing, backingAmple, "a filled trade must charge PLV no more than the ample path");
            }
        }
        emit log_named_uint("caps that filled", passes);

        // The gate must still be a GATE, not a brick: the ample path fills, so
        // the band above is a genuine refusal band and not a dead pool.
        assertEq(backingAmple, backing0, "no PLV write-down on the honest path");
    }
}
