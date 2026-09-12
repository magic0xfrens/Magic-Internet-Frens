// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";

contract Coin {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract Sock { }

contract T9aGenesisDividendHunt is Test {
    MiFrensGenesis col;
    MiFrensDividend div;
    Coin usdg;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address treasury = address(0x7EA);

    function setUp() public {
        // genesisSupply 6, maxSupply 12 so there is a VOLUME tranche (ids 7..12).
        col = new MiFrensGenesis("MiFrens", "MIF", 6, 12, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(col), treasury);
        col.setDividend(address(div));
        col.setMinter(address(this));       // stand in for the volume hook
        usdg = new Coin();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  A.  POSITIVE CONTROL: an honest reveal is final.
    // ───────────────────────────────────────────────────────────────────────
    function test_A_HonestRevealIsFinal() public {
        uint256 id = col.mint(alice);
        vm.roll(block.number + 1);
        vm.prank(alice); col.reveal(id);
        uint8 first = col.rarityOf(id);
        assertTrue(col.revealed(id), "revealed");
        vm.roll(block.number + 400);
        vm.prank(alice); col.reveal(id);   // no-op, already revealed
        assertEq(col.rarityOf(id), first, "a committed roll never changes");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  B.  REGRESSION (Z-08, fixed): the seed-expiry RE-ANCHOR is capped at one.
    //
    //      `_reveal` (MiFrensGenesis.sol) rolls from blockhash(mintBlockOf), which
    //      becomes PUBLIC one block after the mint, and nothing forces the holder
    //      to reveal. When the hash fell out of the 256-block window the contract
    //      RE-ANCHORED without committing, so the holder peeked at the pending
    //      roll, revealed only when it was good, and otherwise waited out 256
    //      blocks for a brand-new draw — repeatable forever. Measured before the
    //      fix: tier 0 ground up to tier 3 in 3 re-anchors.
    //
    //      Now one re-anchor is granted per token, ever; declining that one too
    //      COMMITS the base tier, so waiting costs the draw instead of buying
    //      another. Grind ceiling: best-of-two.
    // ───────────────────────────────────────────────────────────────────────
    function test_B_ExpiryReanchorIsAnUnlimitedGachaReroll() public {
        uint256 id = col.mint(alice);
        uint256 mb0 = col.mintBlockOf(id);
        vm.roll(mb0 + 1);
        uint8 honest = _peek(id, mb0);            // the one draw the design intends
        assertLt(uint256(honest), 3, "control: the honest single draw was NOT ultra");

        // DECLINE #1 — let the seed rot and call reveal(). This is the one
        // re-anchor an honest holder who missed the window is entitled to.
        vm.roll(mb0 + 258);
        vm.prank(alice); col.reveal(id);
        assertFalse(col.revealed(id), "the one allowed re-anchor does not commit");
        assertTrue(col.reanchored(id), "and it is now spent");
        assertGt(col.mintBlockOf(id), mb0, "re-anchored to a fresh future block");

        uint256 mb1 = col.mintBlockOf(id);
        vm.roll(mb1 + 1);
        uint8 second = _peek(id, mb1);            // a genuinely fresh, fair draw

        // DECLINE #2 — the move that used to buy an unlimited third, fourth, ...
        vm.roll(mb1 + 258);
        vm.prank(alice); col.reveal(id);
        assertTrue(col.revealed(id), "FIXED: the second expiry COMMITS instead of re-rolling");
        assertEq(uint256(col.rarityOf(id)), 0, "FIXED: declining twice costs the draw - base tier");
        assertEq(col.mintBlockOf(id), mb1, "FIXED: no further re-anchor");

        emit log_named_uint("honest (single-draw) tier", honest);
        emit log_named_uint("the one fair second draw  ", second);

        // And a grinder who asks 3000 times gets no more than that one re-anchor.
        uint256 id2 = col.mint(alice);
        (uint8 got, uint256 rerolls) = _grindToUltra(id2, 3000);
        emit log_named_uint("re-anchors a 3000-attempt grinder got", rerolls);
        assertLe(rerolls, 1, "FIXED: at most ONE re-anchor, whatever the grinder asks for");
        assertTrue(col.revealed(id2), "the token is never left unrevealable");
        assertTrue(got == 0 || rerolls == 1,
            "a non-base tier can only have come from one of the two honest draws");
    }

    /// @dev Peek at the roll `_reveal` would produce right now, exactly as
    ///      MiFrensGenesis.sol:537 computes it. Pure off-chain knowledge — the
    ///      attacker needs no privilege to do this.
    function _peek(uint256 id, uint256 mb) internal view returns (uint8) {
        bytes32 bh = blockhash(mb);
        uint256 seed = uint256(keccak256(abi.encodePacked(bh, id, address(col))));
        uint16 r = uint16(seed % 10_000);
        for (uint8 i = 0; i < 4; ++i) if (r < col.rarityCumBps(i)) return i;
        return 0;
    }

    /// @dev All the branching lives here so the test body stays assertion-only.
    function _grindToUltra(uint256 id, uint256 cap)
        internal
        returns (uint8 got, uint256 rerolls)
    {
        while (rerolls < cap) {
            if (col.revealed(id)) break;               // the draw is spent - stop
            uint256 mb = col.mintBlockOf(id);
            if (block.number <= mb) vm.roll(mb + 1);
            if (_peek(id, mb) == 3) {
                vm.prank(alice); col.reveal(id);       // commit the good draw
                break;
            }
            // Bad draw: let the seed expire and try to take a fresh one.
            vm.roll(mb + 258);
            vm.prank(alice); col.reveal(id);
            // Only count it if it really bought another draw. After the fix the
            // second expiry COMMITS, so this stops incrementing at 1.
            if (!col.revealed(id)) rerolls++;
        }
        got = col.rarityOf(id);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  C.  REGRESSION (Z-10, fixed): ERC20 royalties PUSHED to MiFrensDividend are
    //      recoverable. DeployLaunchpad.s.sol:336 sets the collection's EIP-2981
    //      receiver to the dividend; a WETH/USDC-denominated marketplace sale pays
    //      the royalty as a plain ERC20 `transfer`. `fundToken` is PULL-based, so
    //      it structurally cannot see such a balance — before `adopt` existed, 5%
    //      of every non-native secondary sale was credited to nobody and reachable
    //      by nobody at any privilege level.
    // ───────────────────────────────────────────────────────────────────────
    function test_C_PushedErc20RoyaltyIsPermanentlyStranded() public {
        col.setRoyalty(address(div), 500);
        (address recv, uint256 amt) = col.royaltyInfo(1, 1 ether);
        assertEq(recv, address(div), "royalty receiver IS the dividend");
        assertEq(amt, 0.05 ether, "5%");

        // A genesis holder who has cast the spell — the only claimant there is.
        vm.prank(alice); col.mint{value: 0.01 ether}(1);
        vm.prank(alice); div.castSpell(1);

        // Seaport pays a WETH-denominated sale's royalty by plain transfer.
        usdg.mint(address(this), 1_000e6);
        usdg.transfer(address(div), 1_000e6);

        // The pull path still cannot see it — that part is unchanged and correct.
        assertEq(usdg.balanceOf(address(div)), 1_000e6, "the royalty really arrived");
        assertEq(div.accPerShareOf(address(usdg)), 0, "no accumulator moved on its own");
        assertEq(div.pendingToken(1, address(usdg)), 0, "so no holder is owed it yet");
        assertEq(div.assetCount(), 0, "and it is not yet a known asset");

        // A STRANGER CANNOT APPEND TO THE BOUNDED BASKET (audit D-1 preserved).
        vm.prank(bob);
        vm.expectRevert(MiFrensDividend.NotOwner.selector);
        div.adopt(address(usdg));

        // The treasury (the deploy wirer) adopts it. One call, no redeploy.
        vm.prank(treasury);
        uint256 delta = div.adopt(address(usdg));
        assertEq(delta, 1_000e6, "FIXED: the pushed balance is credited");
        assertEq(div.assetCount(), 1, "and the asset joins the basket");
        assertEq(div.pendingToken(1, address(usdg)), 1_000e6, "the holder it was meant for is owed it");

        // And it really comes out.
        vm.prank(alice); div.claimTokens(1);
        assertEq(usdg.balanceOf(alice), 1_000e6, "FIXED: the holder got the royalty");
        assertEq(usdg.balanceOf(address(div)), 0, "nothing stranded");
        assertEq(div.accountedOf(address(usdg)), 0, "the book follows the balance out");

        // Adopting nothing is refused, so a second call cannot double-credit.
        vm.expectRevert(MiFrensDividend.NotShare.selector);
        div.adopt(address(usdg));

        // ONCE IN THE BASKET, ANYONE MAY ADOPT: a repair path only the hook can
        // reach is a repair path nobody ever calls.
        usdg.mint(address(this), 500e6);
        usdg.transfer(address(div), 500e6);
        vm.prank(bob);
        assertEq(div.adopt(address(usdg)), 500e6, "permissionless top-up for a known asset");
        assertEq(div.pendingToken(1, address(usdg)), 500e6, "credited to the holder");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  D.  MAX_PER_WALLET is a balance check, so one buyer takes the whole
    //      genesis tranche by parking each batch in a fresh sock.
    // ───────────────────────────────────────────────────────────────────────
    function test_D_PerWalletCapEvadedByParkingTokens() public {
        uint256 cap = col.MAX_PER_WALLET();
        assertEq(cap, 3, "cap");

        uint256 controlled = _sweepWholeTranche();

        assertEq(controlled, col.GENESIS_SUPPLY(), "one buyer took the entire OG tranche");
        assertGt(controlled, cap, "far above the advertised per-wallet cap");
        assertTrue(col.soldOut(), "and ignition is armed by a single entity");
    }

    function _sweepWholeTranche() internal returns (uint256 controlled) {
        uint256 supply = col.GENESIS_SUPPLY();
        uint256 cap = col.MAX_PER_WALLET();
        uint256 next = 1;
        while (next <= supply) {
            uint256 q = supply - next + 1 < cap ? supply - next + 1 : cap;
            vm.prank(alice); col.mint{value: 0.01 ether * q}(q);
            address sock = address(new Sock());
            for (uint256 i; i < q; ++i) {
                vm.prank(alice); col.transferFrom(alice, sock, next + i);
                controlled++;
            }
            next += q;
        }
    }
}
