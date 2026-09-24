// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice D-04 REGRESSION (was a functional-conformance PoC).
///
/// BEFORE: `PerpEngine._rebook` — the partial-close path a band-refused
/// buy-back takes — folded all remaining backing into `principal` and set
/// `collateral = 0`. `collateral` is the BASIS of three separate quantities:
///   * the funding notional AND the funding cap (`_fundingDelta`, PerpEngine
///     .sol:931-936), so funding became exactly zero for the rest of the
///     position's life, in BOTH directions;
///   * the liquidation penalty (`_settle`, MODE_LIQUIDATION);
///   * the keeper cut and the badge's `bountyWei`, both derived from it.
/// One permissionless `liquidate()` on a position the mark band cannot buy back
/// therefore left a position that pays no funding ever again, no liquidation
/// penalty when it finally closes, and a zero bounty to every later keeper —
/// while `_rebook`'s own NatSpec promised the opposite twice ("funding settles
/// in full", "the keeper IS paid ... on the piece that finally closes").
///
/// AFTER: `_rebook` PRESERVES `collateral` and spends `principal` (the borrowed
/// short proceeds) first, dipping into `collateral` only once `principal` is
/// exhausted. `collateral + principal` — the solvency basis `_underwaterVal`
/// reads at PerpEngine.sol:1701 — is exactly the same sum it was, so no
/// closeability or liquidatability boundary moves.
///
/// PROPERTY ASSERTED: after a partial close, (1) the trader's stake survives as
/// `collateral`, (2) the backing SUM never grows, (3) funding still accrues
/// against the position, and (4) the final liquidation still charges the
/// penalty and pays the keeper on the piece that closes it.
contract D04_RebookErasesFundingAndPenalty is YBase {
    // Position(trader, isLong, collateral, size, principal, openedAt, leverage, entryFunding)
    function _posOf(uint256 id) internal view returns (uint128 coll, uint256 size, uint256 prin) {
        (,, coll, size, prin,,,) = perp.positions(id);
    }

    /// Warp + poke so the 5-minute TWAP mark converges onto the live spot. Each
    /// `poke` writes one observation; no price moves here.
    function _convergeMark() internal {
        for (uint256 i = 0; i < 12; i++) {
            _warp(60);
            vm.roll(block.number + 1);
            perp.poke();
        }
    }

    /// Move spot with the engine UNWIRED from the hook, i.e. with no in-swap
    /// sweep. That is not a contrivance: the sweep is bounded (a gas reserve,
    /// <= MAX_LIQ_PER_SWAP = 8 kills per swap, a rotating cursor over the book),
    /// and permissionless {liquidate} exists precisely as the backstop for the
    /// position it declined to take — PerpEngine.sol:1066-1071 says so by name.
    /// This puts the book in that state deterministically, in one line.
    function _moveSpotUnswept(bool buy, uint256 amount) internal {
        hook.setPerpEngine(address(0));
        if (buy) _buy(amount, address(this));
        else _sell(amount, address(this));
        hook.setPerpEngine(address(perp));
    }

    function test_D04_RebookedPositionStillOwesFundingAndPenalty() public {
        _boot(60 ether, 0);
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        assertTrue(active, "fork must be live for this regression");
        _bootPerp(30 ether, 0);
        deal(token, address(this), 2_000_000_000 ether, true);
        IERC20Minimal(token).approve(address(perp), type(uint256).max);
        perp.fundPlvToken(1_000_000_000 ether);

        uint8 lev = perp.maxLeverage();
        vm.prank(victim);
        uint256 id = perp.openShort{value: 0.5 ether}(lev, 0, 0, 0.5 ether);

        uint160 sp0 = _sqrtP();
        (uint128 coll0, uint256 size0, uint256 prin0) = _posOf(id);
        uint256 backing0 = uint256(coll0) + prin0;
        emit log_named_uint("collateral at open", coll0);
        emit log_named_uint("principal  at open", prin0);
        emit log_named_uint("size       at open", size0);
        assertGt(coll0, 0, "control: the short opened with a real stake");

        // ── 1. Spot runs away from the (lagging) mark. The short is now
        //       insolvent at raw live spot, so the permissionless {liquidate}
        //       condemns it — but the settlement still prices the buy-back
        //       inside the MARK band, which at this distance fills ~nothing.
        //       That is the `_rebook` partial-close path.
        uint256 tokBefore = IERC20Minimal(token).balanceOf(address(this));
        _moveSpotUnswept(true, 12 ether);
        uint256 tokBought = IERC20Minimal(token).balanceOf(address(this)) - tokBefore;

        vm.recordLogs();
        perp.liquidate(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool partialled;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PartiallyClosed(uint256,uint256,uint256,uint256)")) {
                partialled = true;
            }
        }
        assertTrue(partialled, "control: the band-refused buy-back must rebook the position");

        (uint128 coll1, uint256 size1, uint256 prin1) = _posOf(id);
        emit log_named_uint("collateral after rebook", coll1);
        emit log_named_uint("principal  after rebook", prin1);
        emit log_named_uint("size       after rebook", size1);
        assertGt(size1, 0, "control: the position is still open after the partial close");

        // (1) The stake survives — this is the line the defect zeroed.
        assertEq(coll1, coll0, "the trader's stake must survive a partial close");
        // (2) ...and the solvency basis is the SAME SUM, never inflated.
        assertLe(uint256(coll1) + prin1, backing0, "the backing sum must never grow");

        // ── 2. Spot comes part of the way back: still far enough above entry to
        //       condemn the position once the mark catches up, but close enough
        //       that the buy-back fits inside its own backing.
        uint160 target = uint160((uint256(sp0) * 9129) / 10_000); // ~1.20x in value
        for (uint256 i = 0; i < 20 && _sqrtP() < target; i++) {
            _moveSpotUnswept(false, tokBought / 12);
        }
        emit log_named_uint("sqrtP at open ", sp0);
        emit log_named_uint("sqrtP at close", _sqrtP());

        // ── 3. Funding. The book is all-short, so the short side is crowded and
        //       PAYS. With `collateral == 0` the notional AND the cap are zero,
        //       so this is exactly 0 in either direction, forever.
        _convergeMark();
        _warp(1 days);
        vm.roll(block.number + 1);
        perp.poke();
        int256 fd = perp.fundingDelta(id);
        emit log_named_int("fundingDelta after rebook", fd);
        assertTrue(fd != 0, "a rebooked position must still accrue funding");

        // ── 4. The piece that finally closes the position. The mark has caught
        //       up, so the buy-back fits inside the band and the settlement
        //       reaches the MODE_LIQUIDATION tail.
        address keeper = address(0xBEEEEE);
        uint256 keeperBefore = keeper.balance;
        vm.recordLogs();
        vm.prank(keeper);
        perp.liquidate(id);
        logs = vm.getRecordedLogs();
        uint256 penalty;
        bool sawLiquidated;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Liquidated(uint256,address,uint256)")) {
                sawLiquidated = true;
                penalty = abi.decode(logs[i].data, (uint256));
            }
        }
        (, uint256 sizeEnd,) = _posOf(id);
        emit log_named_uint("size after final liquidate", sizeEnd);
        emit log_named_uint("penalty charged", penalty);
        emit log_named_uint("keeper paid", keeper.balance - keeperBefore);
        assertTrue(sawLiquidated, "the final close must reach the liquidation tail");
        assertGt(penalty, 0, "the liquidation penalty must be charged on the closing piece");
        assertGt(keeper.balance - keeperBefore, 0, "the keeper must be paid on the closing piece");
    }
}
