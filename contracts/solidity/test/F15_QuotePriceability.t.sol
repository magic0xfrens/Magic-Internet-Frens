// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TreasuryGovernor, IVotes721} from "../cauldron/TreasuryGovernor.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";

contract Votes15 {
    function getVotes(address) external pure returns (uint256) { return 100; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 100; }
    /// @dev Mirrors `Votes.getPastTotalSupply` — the quorum denominator the
    ///      real vote source ({MiFrensGenesis}) actually implements.
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 100; }
}

contract Reg15 {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

contract Tok15 { function decimals() external pure returns (uint8) { return 6; } }

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-15 — AN UNPRICEABLE QUOTE MUST NOT BECOME A GENERATION'S BASE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  ALLOWLISTING AND PRICING WERE INDEPENDENT. `setQuoteAllowed` checks that an
 *  asset sorts below the token, so `quote == currency0` holds — and nothing
 *  else. An asset could therefore be approved, voted in, and become the base of
 *  a generation while the oracle had no feed for it.
 *
 *  The failure is silent, which is what makes it worth a gate rather than a
 *  comment. `CauldronHook._toUsd` returns 0 for an unpriceable asset, and 0
 *  means CANNOT JUDGE (audit V-1): `_recordVolume` writes nothing — no bucket,
 *  no cumulative total, no crystal credit. A generation rotated onto that quote
 *  trades normally while recording NO volume, and after the grace window built
 *  into that path it reads as dying, with no error anywhere to explain it.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F15_QuotePriceabilityTest is Test {
    TreasuryGovernor internal gov;
    QuoteOracle internal oracle;
    Reg15 internal reg;
    Tok15 internal usdg;

    address constant ALICE = address(0xA11CE);
    address constant XNVDA = address(0x8B0A);

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1000);
        reg = new Reg15();
        oracle = new QuoteOracle(address(this));
        usdg = new Tok15();
        gov = new TreasuryGovernor(
            IVotes721(address(new Votes15())), address(reg), address(this), 0, 0, 0, 0, false
        );
        gov.setQuoteOracle(address(oracle));

        reg.set(address(usdg), true);
        reg.set(XNVDA, true);          // allowlisted but never given a feed
    }

    /// @notice THE HAZARD, closed: an allowlisted asset the oracle cannot value
    ///         is refused as a rotation target.
    function test_F15_UnpriceableQuoteCannotBeProposed() public {
        assertEq(oracle.usdPerRawUnit(XNVDA), 0, "precondition: no feed for it");
        vm.prank(ALICE);
        vm.expectRevert(TreasuryGovernor.QuoteNotPriceable.selector);
        gov.propose(XNVDA, 3000);
    }

    /// @notice And once it CAN be valued, the same proposal goes through — the
    ///         gate is about priceability, not about the asset.
    function test_F15_PricingTheAssetUnblocksIt() public {
        oracle.setPegged(address(usdg), 6);
        vm.prank(ALICE);
        uint256 id = gov.propose(address(usdg), 3000);
        assertGt(id, 0, "a priceable quote proposes normally");
    }

    /// @notice NATIVE IS EXEMPT, deliberately. address(0) is the fallback every
    ///         generation can launch against; refusing it because a feed lapsed
    ///         would leave the treasury nowhere to rotate BACK to and turn a
    ///         price outage into a governance deadlock.
    function test_F15_NativeIsAlwaysProposable() public {
        reg.set(address(0), true);
        assertEq(oracle.usdPerRawUnit(address(0)), 0, "native has no feed here");
        vm.prank(ALICE);
        gov.propose(address(0), 3000);   // must not revert
    }

    /// @notice A deployment with no oracle is measuring volume in raw quote units
    ///         throughout, which is self-consistent — so the gate must not fire
    ///         and brick rotation there.
    function test_F15_NoOracleMeansNoGate() public {
        TreasuryGovernor bare = new TreasuryGovernor(
            IVotes721(address(new Votes15())), address(reg), address(this), 0, 0, 0, 0, false
        );
        vm.prank(ALICE);
        bare.propose(XNVDA, 3000);   // no oracle set -> check skipped
    }

    /// @notice The check runs AGAIN at execution. A feed can be de-configured or
    ///         go stale between the vote and the moment the treasury would move,
    ///         and the check that matters is the later one.
    function test_F15_ReCheckedAtExecution() public {
        oracle.setFeed(address(usdg), address(new StaleFeed()), 1 hours, 6);
        vm.prank(ALICE);
        uint256 id = gov.propose(address(usdg), 3000);
        vm.prank(ALICE);
        gov.vote(id, true);

        // The feed lapses while the vote is running.
        vm.warp(block.timestamp + 3 days + 1);
        assertEq(oracle.usdPerRawUnit(address(usdg)), 0, "feed went stale mid-vote");

        vm.expectRevert(TreasuryGovernor.QuoteNotPriceable.selector);
        gov.execute(id);
    }

    /// @notice Only the guardian may point the governor at an oracle — the same
    ///         tier as the allowlist, because choosing what may be voted in and
    ///         choosing how it is valued are the same decision.
    function test_F15_OracleWiringIsGated() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(TreasuryGovernor.NotGuardian.selector);
        gov.setQuoteOracle(address(0xDEAD));
    }
}

/// @dev Answers once, then never again — the ordinary way a testnet feed fails.
contract StaleFeed {
    uint256 public immutable born = block.timestamp;
    function decimals() external pure returns (uint8) { return 8; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 1e8, born, born, 1);
    }
}
