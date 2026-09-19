// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

/// @title C1 — MAX_PER_WALLET is a LIFETIME allowance, not a current holding
///
/// Regression for red-team finding L1-C. The presale cap used to test
/// `balanceOf(msg.sender)`; one actor with one funding source minted 40 under a
/// cap of 20 purely by transferring the first 20 out between mints. The cap is
/// the protocol's only per-actor limit, so a cap that does not cap is the whole
/// defence.
///
/// Fork-free by construction: `MiFrensGenesis` is deployed directly, no
/// PoolManager, no FORK_RPC. Uses the REAL contract — the shared `YBase`
/// harness ships a mock with no `mintLiquidator*`, so it is structurally blind
/// to the badge interaction asserted below.
contract C1_GenesisCapCumulative is Test {
    uint256 constant PRICE = 0.05 ether;
    uint256 constant CAP = 20;

    MiFrensGenesis g;
    address whale = makeAddr("c1_whale");
    address sink = makeAddr("c1_sink");
    address honest = makeAddr("c1_honest");

    function setUp() public {
        g = new MiFrensGenesis("MiFrens", "MF", 1111, 2400, PRICE, 1111, "ipfs://x/");
        g.setMaxPerWallet(CAP); // pre-mint window; ratchet semantics untouched
        // This test contract is the badge minter, so `mintLiquidator` is callable.
        g.setLiquidatorMinter(address(this));
        vm.deal(whale, 100 ether);
        vm.deal(honest, 100 ether);
    }

    // ------------------------------------------------------------------
    // 1. L1's exact attack — mint, transfer out, mint again — now reverts.
    // ------------------------------------------------------------------
    function test_C1_TransferringOutDoesNotRefreshTheGenesisAllowance() public {
        vm.startPrank(whale);
        g.mint{value: PRICE * CAP}(CAP);
        vm.stopPrank();

        assertEq(g.balanceOf(whale), CAP, "cap reached honestly");
        assertEq(g.genesisMintedBy(whale), CAP, "lifetime counter recorded the mint");

        // Park the whole inventory in a second wallet the same actor controls.
        vm.startPrank(whale);
        for (uint256 i = 1; i <= CAP; i++) {
            g.transferFrom(whale, sink, i);
        }
        vm.stopPrank();

        // `balanceOf` IS zero again — that is exactly what the old check read.
        assertEq(g.balanceOf(whale), 0, "balanceOf reset, as before");
        // The lifetime counter is not fooled.
        assertEq(g.genesisMintedBy(whale), CAP, "lifetime counter never decrements");
        assertEq(g.remainingGenesisAllowance(whale), 0, "allowance still exhausted");

        // THE ATTACK: the second mint now reverts. Even for a single token.
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: PRICE * CAP}(CAP);

        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: PRICE}(1);

        assertEq(g.minted(), CAP, "ONE actor still bounded at the cap");
    }

    // ------------------------------------------------------------------
    // 2. A honest buyer can still mint up to the cap, incrementally.
    // ------------------------------------------------------------------
    function test_C1_HonestBuyerCanStillMintUpToTheCap() public {
        uint256 got;
        vm.startPrank(honest);
        for (uint256 i = 0; i < CAP; i++) {
            assertEq(g.remainingGenesisAllowance(honest), CAP - i, "allowance counts down");
            g.mint{value: PRICE}(1);
            got++;
        }
        vm.stopPrank();

        assertEq(got, CAP, "20 separate mints all succeeded");
        assertEq(g.balanceOf(honest), CAP, "honest buyer holds a full allocation");
        assertEq(g.genesisMintedBy(honest), CAP, "lifetime counter agrees");
        assertEq(g.remainingGenesisAllowance(honest), 0, "and is now spent");

        // The cap binds on the very next token.
        vm.prank(honest);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: PRICE}(1);
    }

    // ------------------------------------------------------------------
    // 3. A Liquidatoor badge does NOT consume genesis allowance.
    //    Badges live at LIQUIDATOR_ID_BASE and are uncapped by design; the old
    //    `balanceOf` check counted them, so a badge holder lost genesis room.
    // ------------------------------------------------------------------
    function test_C1_BadgeMintDoesNotConsumeGenesisAllowance() public {
        uint256 badge1 = g.mintLiquidator(honest);
        uint256 badge2 = g.mintLiquidator(honest);
        uint256 badge3 = g.mintLiquidator(honest);
        assertGe(badge1, g.LIQUIDATOR_ID_BASE(), "badge is in the uncapped id range");
        assertEq(badge3, badge1 + 2, "three badges struck");

        assertEq(g.balanceOf(honest), 3, "balanceOf DOES count badges");
        assertEq(g.genesisMintedBy(honest), 0, "badges consumed no genesis allowance");
        assertEq(g.remainingGenesisAllowance(honest), CAP, "full allowance intact");

        // With the badges held, a FULL genesis allocation is still mintable.
        vm.prank(honest);
        g.mint{value: PRICE * CAP}(CAP);
        assertEq(g.genesisMintedBy(honest), CAP, "full cap minted on top of 3 badges");
        assertEq(g.balanceOf(honest), CAP + 3, "holds genesis + badges");

        // Voting units are the GENESIS trace only — badges stay out of it.
        assertEq(g.genesisBalanceOf(honest), CAP, "badges carry no voting weight");
        assertEq(g.getVotes(honest), CAP, "auto-delegated: 20 genesis, 0 from 3 badges");

        // Badges still mint after the genesis allowance is spent.
        uint256 badge4 = g.mintLiquidator(honest);
        assertEq(badge4, badge1 + 3, "badges remain uncapped");
    }

    // ------------------------------------------------------------------
    // 4. genesisBalanceOf (the VOTING counter) is untouched by this fix: it
    //    still decrements on transfer. The two counters are not the same thing.
    // ------------------------------------------------------------------
    function test_C1_VotingCounterStillDecrementsOnTransfer() public {
        vm.startPrank(whale);
        g.mint{value: PRICE * CAP}(CAP);
        assertEq(g.genesisBalanceOf(whale), CAP, "voting units minted");
        for (uint256 i = 1; i <= CAP; i++) {
            g.transferFrom(whale, sink, i);
        }
        vm.stopPrank();

        assertEq(g.genesisBalanceOf(whale), 0, "voting units FOLLOW the token");
        assertEq(g.genesisBalanceOf(sink), CAP, "and land on the new holder");
        assertEq(g.genesisMintedBy(whale), CAP, "the cap counter does NOT follow");
        assertEq(g.genesisMintedBy(sink), 0, "the receiver gained no mint allowance debt");
    }

    // ------------------------------------------------------------------
    // 5. The ratchet is unchanged: down-only, must bind, non-zero.
    // ------------------------------------------------------------------
    function test_C1_RatchetSemanticsUnchanged() public {
        MiFrensGenesis h =
            new MiFrensGenesis("MiFrens", "MF", 1111, 2400, PRICE, 7, "ipfs://x/");

        // Pre-mint: widening 7 -> 100 succeeds.
        h.setMaxPerWallet(100);
        assertEq(h.MAX_PER_WALLET(), 100, "pre-mint widening allowed");

        // A non-binding cap is refused.
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        h.setMaxPerWallet(1111);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        h.setMaxPerWallet(0);

        // Once anyone mints, it only goes down.
        vm.deal(honest, 10 ether);
        vm.prank(honest);
        h.mint{value: PRICE}(1);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        h.setMaxPerWallet(101);
        h.setMaxPerWallet(7);
        assertEq(h.MAX_PER_WALLET(), 7, "ratcheted down");

        // Non-deployer cannot touch it.
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        h.setMaxPerWallet(5);
    }
}
