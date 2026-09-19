// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

/// Minimal stand-in for CauldronRegistry: accepts the whole treasury and
/// reports it, so ignition can be executed end to end without a PoolManager.
contract C1RegistryStub {
    bool public summoned;
    uint256 public received;

    function summon() external payable returns (address token, bytes32 poolId) {
        summoned = true;
        received = msg.value;
        return (address(0xC0FFEE), bytes32(uint256(1)));
    }
}

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
    // 5b. END TO END: a BINDING cap must still allow a full sellout and
    //     ignition. `igniteCauldron` refuses unless the tranche mints out, and
    //     there is no recovery but cancel + refund + redeploy — so a cap that
    //     cannot be reached in practice would brick the launch. Executed, not
    //     reasoned about: 60 supply / cap 7 => ceil(60/7) = 9 wallets.
    // ------------------------------------------------------------------
    function test_C1_BindingCapStillSellsOutAndIgnites() public {
        uint256 supply = 60;
        uint256 cap = 7;
        MiFrensGenesis e =
            new MiFrensGenesis("MiFrens", "MF", supply, 2 * supply, PRICE, 1111, "ipfs://x/");
        e.setMaxPerWallet(cap);
        C1RegistryStub reg = new C1RegistryStub();
        e.setRegistry(address(reg));

        uint256 wallets;
        uint256 sold;
        while (sold < supply) {
            uint256 q = supply - sold < cap ? supply - sold : cap;
            address buyer = address(uint160(0x1000 + wallets));
            vm.deal(buyer, PRICE * q);
            vm.prank(buyer);
            e.mint{value: PRICE * q}(q);
            sold += q;
            wallets++;
        }

        assertEq(wallets, 9, "9 distinct wallets sold out 60 at a cap of 7");
        assertEq(e.minted(), supply, "tranche minted out under a BINDING cap");
        assertTrue(e.soldOut(), "sellout reached");
        assertEq(e.remaining(), 0, "nothing left");

        uint256 treasury = address(e).balance;
        assertEq(treasury, PRICE * supply, "whole treasury held");

        // Ignition fires, permissionlessly, and forwards everything.
        vm.prank(sink);
        address token = e.igniteCauldron();
        assertEq(token, address(0xC0FFEE), "gen-1 token returned");
        assertTrue(reg.summoned(), "registry summoned");
        assertEq(reg.received(), treasury, "the WHOLE balance was forwarded");
        assertEq(address(e).balance, 0, "nothing stranded");
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
