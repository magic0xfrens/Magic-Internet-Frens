// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";

contract RegStub {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @title B-04 — QuoteRotator.arbStep per-call notional bound
 *
 *  `arbStep` (QuoteRotator.sol) is PERMISSIONLESS and its header promised "size is
 *  bounded per call, so repeated arbs cannot quietly re-allocate the treasury
 *  behind governance's back." No bound existed — `amountIn` was checked only for
 *  `!= 0`, so a keeper could shift an unbounded slice of the treasury from one
 *  quote to another in a single call whenever an oracle-profitable spread existed.
 *
 *  FIX: a governance-tunable `maxArbNotionalUsd` (USD, 1e18; 0 = off), enforced in
 *  `arbStep` as `if (maxArbNotionalUsd != 0 && inUsd > maxArbNotionalUsd) revert
 *  ArbTooLarge()`.
 *
 *  COVERAGE NOTE / GAP: the enforcement branch sits AFTER `poolManager.unlock`, so
 *  reaching it needs a PoolManager that returns real swap deltas plus an oracle.
 *  The rotator test-suite (like this one) runs against a stub PoolManager, so an
 *  end-to-end "over-cap arb reverts" PoC is deferred as a documented gap; the
 *  branch is verified by inspection. What IS pinned here is the config surface: a
 *  sane non-zero default, owner-only tuning, and the 0-disables semantics.
 */
contract B04_ArbNotionalCap is Test {
    QuoteRotator rot;
    RegStub reg;
    address constant STRANGER = address(0xBAD);

    function setUp() public {
        reg = new RegStub();
        rot = new QuoteRotator(address(reg), IPoolManager(address(0xdead)));
    }

    /// @notice REGRESSION — the bound the header promised now EXISTS and defaults
    ///         to a finite value (not the unbounded behaviour the finding flagged).
    function test_B04_DefaultCapIsFiniteAndNonZero() public view {
        uint256 cap = rot.maxArbNotionalUsd();
        assertGt(cap, 0, "default must be bounded, not unlimited");
        assertEq(cap, 25_000e18, "documented $25k default");
    }

    /// @notice REGRESSION — governance can tune it, and 0 is the explicit opt-out.
    function test_B04_OwnerCanTuneIncludingDisable() public {
        rot.setMaxArbNotionalUsd(100_000e18);
        assertEq(rot.maxArbNotionalUsd(), 100_000e18, "raised");

        rot.setMaxArbNotionalUsd(0);
        assertEq(rot.maxArbNotionalUsd(), 0, "0 disables the bound (explicit opt-out)");
    }

    /// @notice REGRESSION — the cap is owner-gated, like every other treasury knob.
    function test_B04_StrangerCannotTuneTheCap() public {
        vm.prank(STRANGER);
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.setMaxArbNotionalUsd(1);
    }

    /// @notice REGRESSION — setting the cap does NOT disturb the other arb params
    ///         (separate setter, so {setArbParams}'s signature/callers are intact).
    function test_B04_CapSetterIsIndependentOfArbParams() public {
        rot.setArbParams(address(0xDEAD), 1000, 5e18);
        rot.setMaxArbNotionalUsd(7_777e18);
        assertEq(rot.arbKeeperBps(), 1000, "keeper bps untouched");
        assertEq(rot.minArbProfitUsd(), 5e18, "min profit untouched");
        assertEq(rot.maxArbNotionalUsd(), 7_777e18, "cap set");
    }
}
