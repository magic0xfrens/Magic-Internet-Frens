// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

contract V2BRegistry {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @notice GENESIS-ONLY VOTING WEIGHT, AND THE QUORUM TRAP THAT COMES WITH IT.
 *
 *  The app tells holders "Genesis MiFrens vote" and "forged frens don't vote".
 *  `ERC721Votes` accounts one voting unit per token id with no notion of a
 *  tranche, so both halves of that promise were false, and Liquidatoor badges —
 *  whose id range is unbounded — were votes you could farm for gas (V2A: 64
 *  badges, 64 votes, measured on the real contract).
 *
 *  THE TRAP this file exists to guard. `TreasuryGovernor._passed` measures
 *  quorum as `QUORUM_BPS` of `getPastTotalSupply`, which is the checkpointed
 *  VOTING-UNIT total. Suppressing badge VOTES while leaving badge UNITS in that
 *  total would make every farmed badge raise the quorum bar while adding no
 *  votable weight — with badges unbounded, governance would get steadily harder
 *  to reach and eventually die. That is a worse bug than the one being fixed.
 *
 *  Because the fix suppresses the unit at the source (`MiFrensGenesis._update`
 *  routes only genesis ids through `ERC721Votes._update`), the numerator and the
 *  denominator are the same trace and move together. This proves it end to end
 *  against the REAL governor and the REAL collection, no mocks.
 */
contract V2B_GenesisOnlyQuorum is Test {
    MiFrensGenesis internal gen;
    TreasuryGovernor internal gov;
    V2BRegistry internal reg;

    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA201);
    address constant FARMER = address(0xFA53E);
    address constant GUARDIAN = address(0x6A2D);
    address constant USDG = address(0x115D);

    uint256 constant GENESIS_MINTED = 30; // 3 wallets x MAX_PER_WALLET
    uint256 constant BADGES = 500;

    function setUp() public {
        vm.roll(1000);
        vm.warp(1_800_000_000);
        gen = new MiFrensGenesis("MiFrens", "MF", 1111, 10_000, 0.01 ether, 10, "ipfs://");
        gen.setLiquidatorMinter(address(this));

        reg = new V2BRegistry();
        reg.set(USDG, true);
        gov = new TreasuryGovernor(IVotes721(address(gen)), address(reg), GUARDIAN, 0, 0, 0, 0, false);

        _mintGenesis(ALICE, 10);
        _mintGenesis(BOB, 10);
        _mintGenesis(CAROL, 10);
    }

    function _mintGenesis(address who, uint256 n) internal {
        vm.deal(who, 1 ether);
        vm.prank(who);
        gen.mint{value: 0.01 ether * n}(n);
    }

    function _roll(uint256 n) internal {
        uint256 target = vm.getBlockNumber() + n;
        vm.roll(target);
        assertEq(vm.getBlockNumber(), target, "roll must land");
    }

    // ------------------------------------------------------------------
    // Farmed badges carry no weight; genesis holders keep theirs.
    // ------------------------------------------------------------------
    function test_V2B_badgesCarryNoWeightAndGenesisIsUnchanged() public {
        for (uint256 i; i < BADGES; ++i) gen.mintLiquidator(FARMER);

        //  BADGES STILL MINT AND ARE STILL OWNED — that behaviour is unchanged.
        assertEq(gen.balanceOf(FARMER), BADGES, "badges still mint to the farmer");
        assertEq(gen.liquidatorMinted(), BADGES, "and are still counted as struck");

        //  THEY JUST ARE NOT VOTES.
        assertEq(gen.getVotes(FARMER), 0, "a wallet of farmed badges carries zero voting weight");
        assertEq(gen.genesisBalanceOf(FARMER), 0, "and zero genesis holdings");

        //  GENESIS HOLDERS ARE UNTOUCHED.
        assertEq(gen.getVotes(ALICE), 10, "a genesis holder keeps one vote per genesis fren");
        assertEq(gen.genesisBalanceOf(ALICE), 10, "genesis counter agrees");

        //  E2A: 500 badges cannot even open a proposal (threshold is 5 votes).
        vm.prank(FARMER);
        vm.expectRevert(TreasuryGovernor.BelowProposalThreshold.selector);
        gov.propose(USDG, 2000);
    }

    // ------------------------------------------------------------------
    // THE TRAP: the quorum denominator must not inflate with badges.
    // ------------------------------------------------------------------
    function test_V2B_quorumStaysReachableAfterMassBadgeMinting() public {
        _roll(1);
        uint256 beforeBlock = vm.getBlockNumber() - 1;
        uint256 unitsBefore = gen.getPastTotalSupply(beforeBlock);
        assertEq(unitsBefore, GENESIS_MINTED, "voting-unit total is the genesis tranche");

        for (uint256 i; i < BADGES; ++i) gen.mintLiquidator(FARMER);
        _roll(1);

        uint256 unitsAfter = gen.getPastTotalSupply(vm.getBlockNumber() - 1);
        assertEq(unitsAfter, GENESIS_MINTED, "500 badges did NOT raise the quorum denominator");
        assertEq(gen.balanceOf(FARMER), BADGES, "even though all 500 exist and are owned");

        //  AND A REAL VOTE STILL CLEARS QUORUM. need = 30 * 1000 / 10000 = 3.
        //  Pre-fix the denominator would have been 530 and the bar 53, which
        //  ALICE's 10 genesis frens could never clear — governance dead.
        vm.prank(ALICE);
        uint256 id = gov.propose(USDG, 2000);
        vm.prank(ALICE);
        gov.vote(id, true);

        uint256 t = vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1;
        vm.warp(t);
        assertEq(vm.getBlockTimestamp(), t, "warp must land");
        assertEq(gov.winner(), id, "the proposal is the leader");

        gov.execute(id);
        (address q,,,, bool live,) = gov.envelope();
        assertEq(q, USDG, "quorum was reached and the envelope installed");
        assertTrue(live, "governance is alive after 500 badges were farmed");
    }

    // ------------------------------------------------------------------
    // Delegation still works, and cannot conjure weight from badges.
    // ------------------------------------------------------------------
    function test_V2B_delegationStillWorksAndBadgesCannotConjureVotes() public {
        for (uint256 i; i < BADGES; ++i) gen.mintLiquidator(FARMER);

        //  A badge holder re-delegating moves nothing. `ERC721Votes`'s
        //  `_getVotingUnits` returns `balanceOf`, which would have injected 500
        //  phantom votes here; the override returns genesis holdings only.
        vm.prank(FARMER);
        gen.delegate(BOB);
        assertEq(gen.getVotes(BOB), 10, "BOB still has exactly his own 10 genesis votes");
        assertEq(gen.getVotes(FARMER), 0, "and the farmer still has none");

        //  A genesis holder delegating moves exactly their genesis weight.
        vm.prank(ALICE);
        gen.delegate(BOB);
        assertEq(gen.getVotes(ALICE), 0, "ALICE handed her weight over");
        assertEq(gen.getVotes(BOB), 20, "BOB now carries his 10 plus ALICE's 10");

        //  And it comes back.
        vm.prank(ALICE);
        gen.delegate(ALICE);
        assertEq(gen.getVotes(ALICE), 10, "delegation is reversible");
        assertEq(gen.getVotes(BOB), 10, "and BOB is back to his own");
    }

    // ------------------------------------------------------------------
    // Transferring a genesis fren still moves its vote.
    // ------------------------------------------------------------------
    function test_V2B_transferMovesGenesisWeightButBadgeTransferDoesNot() public {
        gen.mintLiquidator(FARMER);
        uint256 badgeId = gen.LIQUIDATOR_ID_BASE() + 1;

        vm.prank(FARMER);
        gen.transferFrom(FARMER, CAROL, badgeId);
        assertEq(gen.ownerOf(badgeId), CAROL, "the badge moved");
        assertEq(gen.getVotes(CAROL), 10, "but CAROL's weight is still only her genesis frens");

        vm.prank(ALICE);
        gen.transferFrom(ALICE, CAROL, 1); // token id 1 is genesis
        assertEq(gen.getVotes(ALICE), 9, "the seller loses the vote");
        assertEq(gen.getVotes(CAROL), 11, "and the buyer gains it");
        assertEq(gen.genesisBalanceOf(CAROL), 11, "genesis counter tracks the move");
    }
}
