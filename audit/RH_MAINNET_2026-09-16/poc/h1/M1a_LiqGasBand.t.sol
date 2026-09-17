// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/// @notice H1 — the in-swap pre-emptive liquidation sweep is gated by
/// LiqGasStarved on a FIXED ~980k floor (LIQ_GAS_RESERVE 180k + 2*LIQ_GAS_MIN
/// 400k, CauldronHook.sol:799-835), independent of how many positions the trade
/// endangers. One in-swap kill costs ~500k forwarded (SWEEP_KILL_RESERVE 420k +
/// settlement). So a trade that a big buy will bankrupt N shorts is allowed
/// through with gas for only ~1 pre-emptive kill; the other N-1 are never closed
/// at the pre-trade price and become PLV bad debt. Attacker cost: gas of one
/// ordinary buy. Damage: (N-1) x per-short bad debt to PLV stakers.
contract M1a_LiqGasBand is YBase {
    uint256[] shortIds;
    uint256 bigBuy;

    function _openShort() internal returns (uint256 id) {
        vm.prank(victim);
        id = perp.openShort{value: 0.5 ether}(2, 0, 0, 0.5 ether);
    }

    function _setup() internal returns (bool ready) {
        _boot(60 ether, 0);
        if (!active) return false;
        _bootPerp(30 ether, 0);
        deal(token, address(this), 2_000_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), type(uint256).max);
        perp.fundPlvToken(1_000_000_000 ether);

        // Four independent 2x shorts (max leverage). A big buy bankrupts all four.
        for (uint256 i = 0; i < 4; i++) shortIds.push(_openShort());
        bigBuy = 40 ether; // ~2.7x token price move -> every short insolvent
        ready = true;
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
        (ok, ) = address(this).call{gas: gasCap}(abi.encodeWithSignature("extBuy(uint256)", bigBuy));
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
        bool ready = _setup();
        if (!ready) { assertTrue(true, "no fork"); return; }

        uint256 backing0 = perp.plv() + perp.insuranceEth();

        // (1) Positive liveness control: a sub-gate trade FAILS LOUDLY.
        (bool okStarved, ) = address(this).call{gas: 850_000}(
            abi.encodeWithSignature("extBuy(uint256)", bigBuy));

        // (2) Gas-limited attack: passes the gate, affords ~1 pre-emptive kill.
        (bool okAtk, uint256 backingAtk, uint256 openAtk) = _run(1_350_000);

        // (3) Ample-gas control: pre-emptive sweep closes all four at pre-trade price.
        (bool okAmple, uint256 backingAmple, uint256 openAmple) = _run(8_000_000);

        emit log_named_uint("backing0             ", backing0);
        emit log_named_uint("open after ATK buy   ", openAtk);
        emit log_named_uint("open after AMPLE buy ", openAmple);
        emit log_named_uint("backing after ATK    ", backingAtk);
        emit log_named_uint("backing after AMPLE  ", backingAmple);
        emit log_named_uint("extra PLV bad debt   ", backingAmple - backingAtk);

        assertFalse(okStarved, "sub-gate trade must be refused (LiqGasStarved)");
        assertTrue(okAtk, "gas-limited attack trade must PASS the gate");
        assertTrue(okAmple, "ample-gas trade passes");
        // The attack strands positions the ample path pre-emptively closed.
        assertGt(openAtk, openAmple, "attack leaves more positions open in-swap");
        // And those stranded positions are realized as extra PLV bad debt.
        assertGt(backingAmple, backingAtk + 0.1 ether,
            "fixed gate floor lets a multi-short trade strand PLV bad debt");
    }
}
