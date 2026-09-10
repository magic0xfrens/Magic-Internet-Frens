// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-21 — governance timing: fast on testnet, floored on mainnet
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  The durations were `constant`, on the correct principle that a governor able
 *  to vote its own limits down has no limits. But that made the contract
 *  untestable: exercising a full rotation on a testnet would have needed more
 *  than a week of real waiting.
 *
 *  They are now `immutable` — chosen at construction, unchangeable afterwards by
 *  the vote, the guardian or the treasury. The principle is preserved (nothing
 *  can shorten them post-deploy) and a testnet can still be driven in minutes.
 *
 *  What stops a testnet value reaching mainnet is the FLOOR: 1 day minimum on
 *  the vote, the cooldown and the execution window, waivable only by an explicit
 *  `testnet` flag the mainnet script never passes. This suite asserts the floors
 *  actually bite, because "safe by default" that is only a comment is not a
 *  guardrail.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B21_GovTimingFloors is Test {
    RegStub21 internal reg;
    V21 internal votes;

    function setUp() public {
        reg = new RegStub21();
        votes = new V21();
    }

    function _gov(uint64 voting, uint64 life, uint64 cool, uint64 exec, bool testnet)
        internal returns (TreasuryGovernor)
    {
        return new TreasuryGovernor(
            IVotes721(address(votes)), address(reg), address(this),
            voting, life, cool, exec, testnet
        );
    }

    /// @notice Zero means "mainnet default" — so a deploy that specifies nothing
    ///         gets the safe values without having to know them.
    function test_B21_ZeroMeansMainnetDefaults() public {
        TreasuryGovernor g = _gov(0, 0, 0, 0, false);
        assertEq(g.VOTING_PERIOD(), 3 days, "default vote");
        assertEq(g.ENVELOPE_LIFETIME(), 30 days, "default envelope life");
        assertEq(g.COOLDOWN(), 7 days, "default cooldown");
        assertEq(g.EXECUTION_WINDOW(), 3 days, "default execution window");
    }

    /// @notice INVARIANT: without the testnet flag, sub-floor timing is REFUSED.
    ///         This is what keeps a fast testnet value from reaching mainnet.
    function test_INVARIANT_B21_MainnetRefusesTestnetTiming() public {
        vm.expectRevert(TreasuryGovernor.BadTiming.selector);
        _gov(15 minutes, 30 days, 7 days, 3 days, false);   // vote too short

        vm.expectRevert(TreasuryGovernor.BadTiming.selector);
        _gov(3 days, 30 days, 5 minutes, 3 days, false);    // cooldown too short

        vm.expectRevert(TreasuryGovernor.BadTiming.selector);
        _gov(3 days, 30 days, 7 days, 1 minutes, false);    // exec window too short
    }

    /// @notice And WITH the flag, a full cycle fits in minutes — the point of
    ///         the change.
    function test_B21_TestnetTimingIsAllowedAndFast() public {
        TreasuryGovernor g = _gov(5 minutes, 2 hours, 1 minutes, 30 minutes, true);
        assertEq(g.VOTING_PERIOD(), 5 minutes, "testnet vote");
        assertEq(g.COOLDOWN(), 1 minutes, "testnet cooldown");

        // A whole vote->execute cycle inside 20 minutes.
        assertLt(g.VOTING_PERIOD() + g.COOLDOWN(), 20 minutes, "full cycle under 20 min");
    }

    /// @notice An envelope that expires before its own execution window closes is
    ///         un-executable on arrival. That is an incoherence, not a policy
    ///         choice, so it is refused in BOTH modes.
    function test_INVARIANT_B21_IncoherentTimingRefusedEvenOnTestnet() public {
        vm.expectRevert(TreasuryGovernor.BadTiming.selector);
        _gov(5 minutes, 10 minutes, 1 minutes, 30 minutes, true); // life < exec window
    }

    /// @notice Timing is immutable: there is no setter to find. Asserted by
    ///         probing the ABI rather than by reading the source.
    function test_INVARIANT_B21_NoSetterExists() public {
        TreasuryGovernor g = _gov(0, 0, 0, 0, false);
        for (uint256 i; i < 4; ++i) {
            string memory sig = i == 0 ? "setVotingPeriod(uint64)"
                : i == 1 ? "setCooldown(uint64)"
                : i == 2 ? "setExecutionWindow(uint64)"
                : "setTiming(uint64,uint64,uint64,uint64)";
            (bool ok, ) = address(g).call(abi.encodeWithSignature(sig, uint64(1)));
            assertFalse(ok, "no timing setter may exist - immutability is the guarantee");
        }
    }
}

contract RegStub21 {
    mapping(address => bool) public allowedQuote;
}
contract V21 {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
}
