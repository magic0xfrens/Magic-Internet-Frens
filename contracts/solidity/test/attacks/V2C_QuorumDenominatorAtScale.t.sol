// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

contract V2CRegistry {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @notice V2C — THE QUORUM DENOMINATOR TRAP, AT PRODUCTION SCALE.
 *
 *  V2B proves the shape on a 30-fren toy electorate. This proves it on the real
 *  one: a FULLY SOLD-OUT genesis tranche (1,111 frens across 112 wallets at the
 *  anti-whale cap of 10) plus an absurd 3,000 farmed Liquidatoor badges, against
 *  the REAL {TreasuryGovernor} and the REAL {MiFrensGenesis}. No mocks.
 *
 *  The denominator under test is, verbatim:
 *      TreasuryGovernor.sol:996
 *        uint256 need = (mifrens.getPastTotalSupply(p.snapshot) * QUORUM_BPS) / 10_000;
 *  `getPastTotalSupply` is `Votes._totalCheckpoints`, i.e. the sum of every unit
 *  ever passed to `Votes._transferVotingUnits` (OZ Votes.sol:182-190). The only
 *  caller of that on this collection is `ERC721Votes._update`, and
 *  `MiFrensGenesis._update` routes ONLY ids 1..GENESIS_SUPPLY through it:
 *      MiFrensGenesis.sol:803  bool votable = tokenId != 0 && tokenId <= GENESIS_SUPPLY;
 *      MiFrensGenesis.sol:806      from = super._update(to, tokenId, auth);   // ERC721Votes
 *      MiFrensGenesis.sol:816      from = ERC721._update(to, tokenId, auth);  // no unit
 *  and MiFrensGenesis.sol:734 `_getVotingUnits` returns `genesisBalanceOf[account]`,
 *  so numerator and denominator are the same trace by construction.
 *
 *  If the badge filter had been applied in the governor (numerator only) instead
 *  of at the source, this file would fail: with 1,111 genesis + 3,000 badges the
 *  bar would be 411 votes against an electorate that can only ever cast 1,111,
 *  and it would keep climbing forever because the badge id range has no ceiling.
 *  The test asserts BOTH the true bar and the counterfactual bar so the margin
 *  is visible in the log.
 *
 *  It also covers the two follow-on invariants V2B does not:
 *    * a burn of a GENESIS fren lowers the denominator by exactly one;
 *    * a burn of a BADGE moves the denominator by zero and does not underflow
 *      `_totalCheckpoints` (a badge burn that decremented a total no badge ever
 *      incremented would revert every subsequent transfer).
 */
contract V2C_QuorumDenominatorAtScale is Test {
    MiFrensGenesis internal gen;
    TreasuryGovernor internal gov;
    V2CRegistry internal reg;

    address constant GUARDIAN = address(0x6A2D);
    address constant USDG = address(0x115D);
    address constant FARMER = address(0xFA53E);
    address constant VAULT = address(0x7A017);
    address constant CHAMPION = address(0xC4A19); // delegation sink

    uint256 constant GENESIS = 1111;
    uint256 constant CAP = 10;
    uint256 constant WALLETS = 112; // 111 x 10 + 1 x 1 = 1111
    uint256 constant BADGES = 3000;

    // results, set by helpers, asserted in the test bodies
    uint256 internal unitsAfterSellout;
    uint256 internal unitsAfterBadges;
    uint256 internal barTrue;
    uint256 internal barCounterfactual;
    uint256 internal championVotes;
    bool internal envelopeLive;
    address internal envelopeQuote;

    function _holder(uint256 i) internal pure returns (address) {
        return address(uint160(0x100000 + i));
    }

    function setUp() public {
        vm.roll(1000);
        vm.warp(1_800_000_000);
        gen = new MiFrensGenesis("MiFrens", "MF", GENESIS, 2400, 0.01 ether, CAP, "ipfs://");
        gen.setLiquidatorMinter(address(this));
        gen.setVault(VAULT);

        reg = new V2CRegistry();
        reg.set(USDG, true);
        gov = new TreasuryGovernor(IVotes721(address(gen)), address(reg), GUARDIAN, 0, 0, 0, 0, false);
    }

    /// @dev Sell the whole genesis tranche at the real anti-whale cap.
    function _sellOut() internal {
        uint256 left = GENESIS;
        for (uint256 i; i < WALLETS; ++i) {
            uint256 n = left >= CAP ? CAP : left;
            address who = _holder(i);
            vm.deal(who, 1 ether);
            vm.prank(who);
            gen.mint{value: 0.01 ether * n}(n);
            left -= n;
        }
    }

    function _roll(uint256 n) internal {
        uint256 target = vm.getBlockNumber() + n;
        vm.roll(target);
        assertEq(vm.getBlockNumber(), target, "roll must land");
    }

    function _farmBadges(uint256 n) internal {
        for (uint256 i; i < n; ++i) gen.mintLiquidator(FARMER);
    }

    /// @dev Concentrate enough honest weight to clear quorum, by DELEGATION only
    ///      (no wallet may exceed the cap, so this is the real-world route).
    function _delegateTo(address sink, uint256 wallets) internal {
        for (uint256 i; i < wallets; ++i) {
            vm.prank(_holder(i));
            gen.delegate(sink);
        }
    }

    /// @dev Run a genuine proposal all the way to executed state.
    function _runProposal(address proposer) internal {
        vm.prank(proposer);
        uint256 id = gov.propose(USDG, 2000);
        vm.prank(proposer);
        gov.vote(id, true);

        uint256 t = vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1;
        vm.warp(t);
        assertEq(vm.getBlockTimestamp(), t, "warp must land");

        gov.execute(id);
        (address q,,,, bool live,) = gov.envelope();
        envelopeQuote = q;
        envelopeLive = live;
    }

    // ------------------------------------------------------------------
    // THE HEADLINE: 3,000 badges on a sold-out 1,111 electorate, and a
    // real proposal still executes.
    // ------------------------------------------------------------------
    function test_V2C_quorumSurvivesASoldOutTrancheAndThreeThousandBadges() public {
        _sellOut();
        _roll(1);
        unitsAfterSellout = gen.getPastTotalSupply(vm.getBlockNumber() - 1);

        _farmBadges(BADGES);
        _roll(1);
        unitsAfterBadges = gen.getPastTotalSupply(vm.getBlockNumber() - 1);

        barTrue = (unitsAfterBadges * gov.QUORUM_BPS()) / 10_000;
        // What the bar WOULD be if badge units had stayed in the trace.
        barCounterfactual = ((unitsAfterSellout + BADGES) * gov.QUORUM_BPS()) / 10_000;

        // 12 capped wallets = 120 votes. Enough for the true bar (111), NOT
        // enough for the counterfactual bar (411).
        _delegateTo(CHAMPION, 12);
        _roll(1);
        championVotes = gen.getVotes(CHAMPION);

        _runProposal(CHAMPION);

        console2.log("genesis sold out, voting units      ", unitsAfterSellout);
        console2.log("badges farmed                       ", BADGES);
        console2.log("voting units after badges           ", unitsAfterBadges);
        console2.log("true quorum bar (10%)               ", barTrue);
        console2.log("counterfactual bar if badges counted", barCounterfactual);
        console2.log("champion delegated votes            ", championVotes);
        console2.log("SENTINEL: assertions below");

        assertEq(unitsAfterSellout, GENESIS, "a sold-out tranche is exactly GENESIS voting units");
        assertEq(gen.balanceOf(FARMER), BADGES, "all 3,000 badges exist and are owned");
        assertEq(gen.liquidatorMinted(), BADGES, "and are counted as struck");

        //  THE TRAP, DENIED. The denominator did not move.
        assertEq(unitsAfterBadges, GENESIS, "3,000 badges did not add one unit to the quorum denominator");
        assertEq(barTrue, 111, "the bar is 10% of the genesis tranche, and only that");
        assertEq(barCounterfactual, 411, "and would have been 411 had badges counted");
        assertLt(championVotes, barCounterfactual, "the honest coalition could NOT have cleared the trap bar");
        assertGe(championVotes, barTrue, "but clears the real one");

        //  AND GOVERNANCE ACTUALLY MOVED MONEY.
        assertEq(envelopeQuote, USDG, "the envelope installed");
        assertTrue(envelopeLive, "governance is alive after 3,000 badges were farmed");
    }

    // ------------------------------------------------------------------
    // Burn symmetry: genesis burn moves the denominator, badge burn does not,
    // and a badge burn cannot underflow the voting-unit total.
    // ------------------------------------------------------------------
    function test_V2C_burnMovesTheDenominatorOnlyForGenesis() public {
        // Small electorate is enough here; the burn path is id-keyed.
        address a = _holder(0);
        vm.deal(a, 1 ether);
        vm.prank(a);
        gen.mint{value: 0.01 ether * CAP}(CAP);
        _farmBadges(3);
        _roll(1);

        uint256 before_ = gen.getPastTotalSupply(vm.getBlockNumber() - 1);

        // Burn a BADGE first: if badges were in the trace this would decrement a
        // total they never incremented, or (post-fix, wrongly implemented) revert.
        uint256 badgeId = gen.LIQUIDATOR_ID_BASE() + 1;
        vm.prank(VAULT);
        gen.burnFromVault(badgeId);
        _roll(1);
        uint256 afterBadgeBurn = gen.getPastTotalSupply(vm.getBlockNumber() - 1);

        // Now burn a GENESIS fren.
        vm.prank(VAULT);
        gen.burnFromVault(1);
        _roll(1);
        uint256 afterGenesisBurn = gen.getPastTotalSupply(vm.getBlockNumber() - 1);

        // And the collection still works afterwards (no wedged checkpoint).
        vm.prank(a);
        gen.transferFrom(a, CHAMPION, 2);
        _roll(1);
        uint256 afterTransfer = gen.getPastTotalSupply(vm.getBlockNumber() - 1);

        console2.log("units before burns   ", before_);
        console2.log("after badge burn     ", afterBadgeBurn);
        console2.log("after genesis burn   ", afterGenesisBurn);
        console2.log("after later transfer ", afterTransfer);
        console2.log("SENTINEL: assertions below");

        assertEq(before_, CAP, "10 genesis frens, 3 badges -> 10 voting units");
        assertEq(afterBadgeBurn, CAP, "burning a badge moves the denominator by zero");
        assertEq(afterGenesisBurn, CAP - 1, "burning a genesis fren lowers it by exactly one");
        assertEq(afterTransfer, CAP - 1, "a transfer moves weight, never the total");
        assertEq(gen.genesisBalanceOf(a), CAP - 2, "the genesis counter tracks burn + transfer");
        assertEq(gen.genesisBalanceOf(CHAMPION), 1, "and the receiver's side of it");
        assertEq(gen.getVotes(CHAMPION), 1, "a received genesis fren votes");
        assertEq(gen.balanceOf(FARMER), 2, "the farmer's surviving badges are untouched");
    }
}
