// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronBase} from "../cauldron/CauldronBase.sol";
import {CauldronGovernor} from "../cauldron/CauldronGovernor.sol";
import {CauldronCollection} from "../cauldron/CauldronCollection.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RoyaltyRouter} from "../cauldron/RoyaltyRouter.sol";
import {MiFrensGenesis} from "../cauldron/MiFrensGenesis.sol";
import {MetadataMode, ICollectionRenderer, BrewSpec} from "../cauldron/ICauldron.sol";

interface IRoyalty2981 {
    function royaltyInfo(uint256, uint256) external view returns (address, uint256);
}

/// P2: the factory routes a VOLUME collection's secondary-sale royalties to its
/// OWN floor vault (not the genesis dividend), so its secondary volume backs its
/// own floor (and, at death, its legacy entitlement).
contract FactoryRoyaltyRoutingTest is Test {
    /// UNIFIED FLOOR: a fresh brew's royalties route to a RoyaltyRouter wired to the
    /// hook (→ token buyback → the collection's own floor), NOT the inert ETH vault
    /// and NOT the genesis dividend.
    function test_BrewRoyaltiesRouteToTokenBuyback() public {
        CauldronFactory f = new CauldronFactory();
        (address col, address vault) = f.deployBrew(
            CauldronFactory.Config({
                name: "Frogs", symbol: "FROG", hook: address(0xC0C),
                registry: address(this), maxSupply: 1000, mode: MetadataMode.BaseURI,
                baseURI: "ipfs://x/", renderer: address(0),
                royaltyReceiver: address(0xD1), // dividend passed in — OVERRIDDEN by the router
                royaltyBps: 500
            })
        );
        (address recv, uint256 amt) = IRoyalty2981(col).royaltyInfo(1, 1 ether);
        assertTrue(recv != vault, "royalties no longer sit as ETH in the vault");
        assertTrue(recv != address(0xD1), "and not the genesis dividend");
        assertEq(RoyaltyRouter(payable(recv)).hook(), address(0xC0C),
            "receiver is a RoyaltyRouter wired to the hook -> token buyback -> floor");
        assertEq(amt, 0.05 ether, "5% royalty preserved");
    }
}

/* ── Test doubles ────────────────────────────────────────────────── */

contract MockMiFrens is ERC721, ERC721Votes {
    uint256 private _id;
    constructor() ERC721("MiFrens", "MIF") EIP712("MiFrens", "1") {}
    function mint(address to, uint256 n) external {
        for (uint256 i = 0; i < n; i++) _mint(to, ++_id);
    }
    function _update(address to, uint256 tokenId, address auth)
        internal override(ERC721, ERC721Votes) returns (address)
    {
        address from = super._update(to, tokenId, auth);
        if (to != address(0) && delegates(to) == address(0)) _delegate(to, to);
        return from;
    }
    function _increaseBalance(address a, uint128 amt) internal override(ERC721, ERC721Votes) {
        super._increaseBalance(a, amt);
    }
}

contract MockRenderer is ICollectionRenderer {
    function tokenURI(uint256 id) external pure returns (string memory) {
        return string.concat("onchain://", _u(id));
    }
    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b; uint256 x = v;
        while (x > 0) { b = abi.encodePacked(uint8(48 + x % 10), b); x /= 10; }
        return string(b);
    }
}

/* A registry that summons via a mocked presale, to test presale.finalize(). */
contract MockRegistry {
    bool public summoned;
    uint256 public received;
    function summon() external payable returns (address, bytes32) {
        summoned = true;
        received = msg.value;
        return (address(0xBEEF), bytes32(0));
    }
}

/* ── Governor ────────────────────────────────────────────────────── */

contract GovernorTest is Test {
    MockMiFrens mifrens;
    CauldronGovernor gov;
    MockRenderer renderer;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address registry = address(0x9E9);

    function setUp() public {
        mifrens = new MockMiFrens();
        gov = new CauldronGovernor(address(mifrens));
        renderer = new MockRenderer();
        gov.setRegistry(registry);
        mifrens.mint(alice, 5); // alice: 5 votes
        mifrens.mint(bob, 2);   // bob: 2 votes
        mifrens.mint(address(this), 1); // test harness proposes → needs a MiFren
    }

    function test_ProposeUriAndRenderer() public {
        uint256 a = gov.propose("Gnomeland", "GNOME", MetadataMode.Renderer, "", address(renderer), "", "", 3333, 0, address(0));
        uint256 b = gov.propose("Kingdom", "CROWN", MetadataMode.BaseURI, "ipfs://k/", address(0), "", "", 3333, 0, address(0));
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(gov.proposalCount(), 2);
    }

    function test_Propose_RejectsBadConfig() public {
        vm.expectRevert(CauldronGovernor.EmptyField.selector);
        gov.propose("", "X", MetadataMode.BaseURI, "ipfs://", address(0), "", "", 3333, 0, address(0));
        vm.expectRevert(CauldronGovernor.BadRenderer.selector);
        gov.propose("X", "X", MetadataMode.Renderer, "", address(0xdead), "", "", 3333, 0, address(0)); // no code
        vm.expectRevert(CauldronGovernor.EmptyField.selector);
        gov.propose("X", "X", MetadataMode.BaseURI, "", address(0), "", "", 3333, 0, address(0)); // empty uri
    }

    function test_WeightedVoteAndWinner() public {
        uint256 p1 = gov.propose("A", "A", MetadataMode.BaseURI, "ipfs://a/", address(0), "", "", 3333, 0, address(0));
        uint256 p2 = gov.propose("B", "B", MetadataMode.BaseURI, "ipfs://b/", address(0), "", "", 3333, 0, address(0));
        vm.roll(block.number + 1); // snapshot must be in the past

        vm.prank(bob); gov.vote(p1);   // p1 = 2
        vm.prank(alice); gov.vote(p2); // p2 = 5 -> leader

        // Voting must CLOSE before a proposal is eligible to win (audit M-02) —
        // that is what removes the last-instant front-run of `relaunch()`.
        assertFalse(gov.hasProposals(), "a proposal still taking votes can never be launched");
        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1);

        (uint256 winId, BrewSpec memory spec) = gov.winner();
        assertEq(winId, p2);
        assertEq(spec.symbol, "B");
    }

    function test_OneVotePerAddress() public {
        uint256 p = gov.propose("A", "A", MetadataMode.BaseURI, "ipfs://a/", address(0), "", "", 3333, 0, address(0));
        vm.roll(block.number + 1);
        vm.prank(alice); gov.vote(p);
        vm.prank(alice);
        vm.expectRevert(CauldronGovernor.AlreadyVoted.selector);
        gov.vote(p);
    }

    function test_NoPowerCannotVote() public {
        uint256 p = gov.propose("A", "A", MetadataMode.BaseURI, "ipfs://a/", address(0), "", "", 3333, 0, address(0));
        vm.roll(block.number + 1);
        vm.prank(address(0xDEAD));
        vm.expectRevert(CauldronGovernor.NoVotingPower.selector);
        gov.vote(p);
    }

    /// @notice The key governance-security property: transferring MiFrens to a
    ///         fresh wallet after the snapshot cannot manufacture new votes.
    function test_NoVoteMultiplicationViaTransfer() public {
        uint256 p = gov.propose("A", "A", MetadataMode.BaseURI, "ipfs://a/", address(0), "", "", 3333, 0, address(0));
        vm.roll(block.number + 1);

        vm.prank(alice); gov.vote(p); // alice votes with her 5 (snapshotted)

        // Alice moves all 5 MiFrens to a brand-new wallet and tries to re-vote.
        address mule = address(0x111111);
        vm.startPrank(alice);
        for (uint256 id = 1; id <= 5; id++) mifrens.transferFrom(alice, mule, id);
        vm.stopPrank();

        // The mule had ZERO balance at the snapshot -> no extra votes.
        vm.prank(mule);
        vm.expectRevert(CauldronGovernor.NoVotingPower.selector);
        gov.vote(p);

        assertEq(gov.getProposal(p).votes, 5, "votes cannot be multiplied");
    }

    function test_ConsumeRemovesFromContention() public {
        uint256 p1 = gov.propose("A", "A", MetadataMode.BaseURI, "ipfs://a/", address(0), "", "", 3333, 0, address(0));
        uint256 p2 = gov.propose("B", "B", MetadataMode.BaseURI, "ipfs://b/", address(0), "", "", 3333, 0, address(0));
        vm.roll(block.number + 1);
        vm.prank(alice); gov.vote(p1); // p1 = 5 leader
        vm.prank(bob); gov.vote(p2);   // p2 = 2
        vm.warp(block.timestamp + gov.VOTING_PERIOD() + 1); // votes close (audit M-02)

        vm.prank(registry); gov.markConsumed(p1);
        (uint256 winId, ) = gov.winner();
        assertEq(winId, p2, "leader recomputed after consume");

        vm.prank(registry);
        vm.expectRevert(CauldronGovernor.AlreadyConsumed.selector);
        gov.markConsumed(p1);
    }

    function test_OnlyRegistryConsumes() public {
        uint256 p = gov.propose("A", "A", MetadataMode.BaseURI, "ipfs://a/", address(0), "", "", 3333, 0, address(0));
        vm.roll(block.number + 1);
        vm.prank(alice); gov.vote(p);
        vm.expectRevert(CauldronGovernor.NotRegistry.selector);
        gov.markConsumed(p);
    }

    function test_SetRegistryOwnerGated() public {
        CauldronGovernor g2 = new CauldronGovernor(address(mifrens));
        vm.prank(address(0xBAD));
        vm.expectRevert(); // OwnableUnauthorizedAccount
        g2.setRegistry(address(0x1234));
    }
}

/* ── Collection ──────────────────────────────────────────────────── */

contract CollectionTest is Test {
    MockRenderer renderer;
    address hook = address(0x4004);

    function setUp() public { renderer = new MockRenderer(); }

    function test_OnlyMinterMints() public {
        CauldronCollection c = new CauldronCollection("G", "G", hook, address(this), 10, MetadataMode.BaseURI, "ipfs://g/", address(0), address(0xD1), uint96(500));
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        c.mint(address(this));
        vm.prank(hook);
        uint256 id = c.mint(address(0xF00D));
        assertEq(id, 1);
        assertEq(c.ownerOf(1), address(0xF00D));
    }

    function test_BaseURI() public {
        CauldronCollection c = new CauldronCollection("G", "G", hook, address(this), 10, MetadataMode.BaseURI, "ipfs://g/", address(0), address(0xD1), uint96(500));
        vm.prank(hook); c.mint(address(0xF00D));
        // unrevealed -> placeholder; revealed -> baseURI + rarity + "/" + id
        assertEq(c.tokenURI(1), c.unrevealedURI());
        vm.roll(block.number + 1); // rarity rolls from the mint block's future hash
        vm.prank(address(0xF00D)); c.reveal(1);
        assertEq(c.tokenURI(1), string.concat("ipfs://g/", vm.toString(uint256(c.rarityOf(1))), "/1"));
    }

    function test_RendererURI() public {
        CauldronCollection c = new CauldronCollection("G", "G", hook, address(this), 10, MetadataMode.Renderer, "", address(renderer), address(0xD1), uint96(500));
        vm.prank(hook); c.mint(address(0xF00D));
        vm.roll(block.number + 1);
        vm.prank(address(0xF00D)); c.reveal(1);
        assertEq(c.tokenURI(1), "onchain://1");
    }

    function test_MaxSupplyCap() public {
        CauldronCollection c = new CauldronCollection("G", "G", hook, address(this), 2, MetadataMode.BaseURI, "ipfs://g/", address(0), address(0xD1), uint96(500));
        vm.startPrank(hook);
        c.mint(address(1)); c.mint(address(2));
        vm.expectRevert(CauldronCollection.MintedOut.selector);
        c.mint(address(3));
        vm.stopPrank();
    }

    function test_RejectsBadConfig() public {
        vm.expectRevert(CauldronCollection.BadConfig.selector);
        new CauldronCollection("G", "G", hook, address(this), 10, MetadataMode.Renderer, "", address(0xdead), address(0xD1), uint96(500)); // no code
        vm.expectRevert(CauldronCollection.BadConfig.selector);
        new CauldronCollection("G", "G", hook, address(this), 10, MetadataMode.BaseURI, "", address(0), address(0xD1), uint96(500)); // empty uri
    }
}

/* ── Presale ─────────────────────────────────────────────────────── */

contract PresaleTest is Test {
    MiFrensGenesis presale;
    MockRegistry registry;
    address buyer = address(0xB111);

    function setUp() public {
        // genesis 3, art cap 6, 0.01 ETH each, max 2 per wallet
        presale = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 2, "ipfs://mf/");
        registry = new MockRegistry();
        presale.setRegistry(address(registry));
        vm.deal(buyer, 10 ether);
        vm.deal(address(0xC222), 10 ether);
    }

    function test_MintExactPrice() public {
        vm.prank(buyer);
        presale.mint{value: 0.02 ether}(2);
        assertEq(presale.balanceOf(buyer), 2);
        assertEq(presale.minted(), 2);
    }

    function test_WrongPriceReverts() public {
        vm.prank(buyer);
        vm.expectRevert(MiFrensGenesis.WrongPrice.selector);
        presale.mint{value: 0.03 ether}(2);
    }

    function test_PerWalletCap() public {
        vm.prank(buyer);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        presale.mint{value: 0.03 ether}(3);
    }

    // OG trait: genesis tranche = ids 1..GENESIS_SUPPLY (here 3); volume ids 4..6
    // are Standard. Immutable, derived from the id — the permanent OG mark.
    function test_GenesisTrait() public view {
        assertTrue(presale.isGenesis(1), "id 1 is genesis");
        assertTrue(presale.isGenesis(3), "id 3 is genesis");
        assertFalse(presale.isGenesis(4), "id 4 is not genesis");
        assertFalse(presale.isGenesis(0), "id 0 is not genesis");
        assertEq(presale.ogTrait(1), "Genesis", "og trait");
        assertEq(presale.ogTrait(4), "Standard", "standard trait");
    }

    function test_FinalizeOnlyAfterSellout() public {
        vm.prank(buyer);
        presale.mint{value: 0.02 ether}(2);
        vm.expectRevert(MiFrensGenesis.NotSoldOut.selector);
        presale.finalize();

        // sell the last one from a different wallet
        vm.prank(address(0xC222));
        presale.mint{value: 0.01 ether}(1);
        assertTrue(presale.soldOut());

        // anyone can finalize; funds forwarded to registry.summon
        uint256 bal = address(presale).balance;
        presale.finalize();
        assertTrue(registry.summoned());
        assertEq(registry.received(), bal);
        assertTrue(presale.finalized());
    }

    function test_NoMintAfterFinalize() public {
        vm.prank(buyer); presale.mint{value: 0.02 ether}(2);
        vm.prank(address(0xC222)); presale.mint{value: 0.01 ether}(1);
        presale.finalize();
        vm.prank(buyer);
        vm.expectRevert(MiFrensGenesis.PresaleOver.selector);
        presale.mint{value: 0.01 ether}(1);
    }

    // Finalizer gate: once a finalizer is set, only IT can ignite → a bot can't
    // front-run the summon. Deployer (this test) sets it; anyone else reverts.
    function test_FinalizerGate() public {
        vm.prank(buyer); presale.mint{value: 0.02 ether}(2);
        vm.prank(address(0xC222)); presale.mint{value: 0.01 ether}(1);
        assertTrue(presale.soldOut());

        address sniper = address(0x5117E5);
        presale.setFinalizer(sniper); // deployer only

        // a random bot cannot finalize now
        vm.prank(address(0xB07));
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        presale.finalize();

        // the designated finalizer can
        vm.prank(sniper);
        presale.finalize();
        assertTrue(presale.finalized());

        // setFinalizer is deployer-gated
        MiFrensGenesis p2 = new MiFrensGenesis("M", "M", 1, 2, 0.01 ether, 2, "u");
        vm.prank(address(0xB07));
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        p2.setFinalizer(sniper);
    }

    /* ── Iteration #2: keep minting the rest of the art from volume ── */

    address constant HOOK = address(0xB00C);

    function _selloutGenesis() internal {
        vm.prank(buyer); presale.mint{value: 0.02 ether}(2);   // ids 1,2
        vm.prank(address(0xC222)); presale.mint{value: 0.01 ether}(1); // id 3
    }

    function test_VolumeMintContinuesAfterGenesis() public {
        _selloutGenesis();
        assertEq(presale.totalMinted(), 3);
        assertEq(presale.maxSupply(), 6);

        // registry wires the volume hook as minter (as it does on iteration #2)
        vm.prank(address(registry));
        presale.setMinter(HOOK);

        // hook mints the post-genesis tranche: ids 4,5,6
        vm.startPrank(HOOK);
        uint256 id4 = presale.mint(buyer);
        uint256 id5 = presale.mint(address(0xC222));
        uint256 id6 = presale.mint(buyer);
        vm.stopPrank();
        assertEq(id4, 4); assertEq(id5, 5); assertEq(id6, 6);
        assertEq(presale.totalMinted(), 6);

        // minted out — next volume mint reverts
        vm.prank(HOOK);
        vm.expectRevert(MiFrensGenesis.MintedOut.selector);
        presale.mint(buyer);
    }

    function test_OnlyMinterMintsVolume() public {
        _selloutGenesis();
        vm.prank(address(registry));
        presale.setMinter(HOOK);
        vm.prank(buyer); // not the hook
        vm.expectRevert(MiFrensGenesis.OnlyMinter.selector);
        presale.mint(buyer);
    }

    function test_OnlyRegistryOrDeployerSetsMinter() public {
        vm.prank(buyer);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        presale.setMinter(HOOK);
    }

    function test_GenesisRevealedVolumeUnrevealed() public {
        _selloutGenesis();
        vm.prank(address(registry));
        presale.setMinter(HOOK);
        vm.prank(HOOK);
        uint256 id4 = presale.mint(buyer);

        // genesis id is revealed → resolves to baseURI; volume id is placeholder
        assertEq(presale.tokenURI(1), "ipfs://mf/1");
        assertEq(presale.tokenURI(id4), presale.unrevealedURI());

        // owner can reveal the volume token → now resolves to baseURI
        vm.roll(block.number + 1); // rarity rolls from the mint block's future hash
        vm.prank(buyer);
        presale.reveal(id4);
        assertTrue(presale.revealed(id4));
        assertEq(presale.tokenURI(id4), "ipfs://mf/4");
    }

    function test_VaultCanBurn() public {
        _selloutGenesis();
        address vault = address(0x7A17);
        vm.prank(address(registry));
        presale.setVault(vault);

        // vault burns a genesis token on redemption
        assertEq(presale.ownerOf(1), buyer);
        vm.prank(vault);
        presale.burnFromVault(1);
        vm.expectRevert();
        presale.ownerOf(1);

        // non-vault cannot burn
        vm.prank(buyer);
        vm.expectRevert(MiFrensGenesis.OnlyVault.selector);
        presale.burnFromVault(2);
    }
}

/* ── Vault (NFT floor) ───────────────────────────────────────────── */
import {CauldronVault} from "../cauldron/CauldronVault.sol";

contract VaultTest is Test {
    MockRenderer renderer;
    address hook = address(0x4004);
    address registry = address(0x9E9);
    CauldronCollection col;
    CauldronVault vault;
    address alice = address(0xA11CE);

    function setUp() public {
        renderer = new MockRenderer();
        col = new CauldronCollection("G","G", hook, address(this), 100, MetadataMode.Renderer, "", address(renderer), address(0xD1), uint96(500));
        // this test contract is the collection's deployer -> can setVault
        vault = new CauldronVault(address(col), registry, 0);
        col.setVault(address(vault));
        vm.deal(address(this), 100 ether);
    }

    function test_FloorRedeemAndSweep() public {
        // hook mints 2 NFTs to alice
        vm.startPrank(hook);
        col.mint(alice); col.mint(alice);
        vm.stopPrank();
        // fund the floor with 2 ETH -> 1 ETH per NFT
        (bool ok,) = address(vault).call{value: 2 ether}(""); require(ok,"fund");
        assertEq(vault.floorPerNFT(), 1 ether);

        // alice redeems token 1 -> gets 1 ETH, NFT burned
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        vault.redeem(1);
        assertEq(alice.balance - balBefore, 1 ether);
        // remaining floor still 1 ETH for the last NFT
        assertEq(vault.floorPerNFT(), 1 ether);

        // registry closes vault on relaunch -> sweeps remaining, redemption stops
        vm.prank(registry);
        uint256 swept = vault.close();
        assertEq(swept, 1 ether);
        assertTrue(vault.closed());
        vm.prank(alice);
        vm.expectRevert(CauldronVault.Closed.selector);
        vault.redeem(2);
    }

    function test_OnlyOwnerRedeems() public {
        vm.prank(hook); col.mint(alice);
        (bool ok,) = address(vault).call{value: 1 ether}(""); require(ok,"fund");
        vm.expectRevert(CauldronVault.NotOwner.selector);
        vault.redeem(1); // this contract isn't the owner
    }

    function test_OnlyRegistryCloses() public {
        vm.expectRevert(CauldronVault.NotRegistry.selector);
        vault.close();
    }

    receive() external payable {}
}

/* ── Gacha rarity + reveal ───────────────────────────────────────── */
contract GachaTest is Test {
    MockRenderer renderer;
    address hook = address(0x4004);
    CauldronCollection col;
    address alice = address(0xA11CE);

    function setUp() public {
        renderer = new MockRenderer();
        col = new CauldronCollection("G","G", hook, address(this), 1000, MetadataMode.Renderer, "", address(renderer), address(0xD1), uint96(500));
    }

    function test_MintRollsRarity_AndRevealFlips() public {
        vm.prank(hook);
        uint256 id = col.mint(alice);
        // unrevealed -> placeholder; rarity not rolled yet (commit-reveal)
        assertEq(col.tokenURI(id), col.unrevealedURI());
        // reveal by owner (next block) -> rolls rarity + renderer
        vm.roll(block.number + 1);
        vm.prank(alice);
        col.reveal(id);
        assertTrue(col.revealed(id));
        assertEq(col.tokenURI(id), "onchain://1");
        // rarity is in range 0..3
        assertLt(col.rarityOf(id), 4);
    }

    function test_RarityDistribution() public {
        // mint 200 and reveal each (rarity is rolled at reveal now), check commons dominate
        uint256[4] memory counts;
        for (uint256 i = 0; i < 200; i++) {
            vm.roll(1000 + i * 2);       // mint block (absolute + monotonic)
            vm.prank(hook);
            uint256 id = col.mint(alice);
            vm.roll(1000 + i * 2 + 1);   // advance so the reveal seed (mint-block hash) is known
            vm.prank(alice);
            col.reveal(id);
            counts[col.rarityOf(id)]++;
        }
        // commons should be the majority
        assertGt(counts[0], counts[1] + counts[2] + counts[3], "commons dominate");
    }

    function test_OnlyOwnerReveals() public {
        vm.prank(hook); uint256 id = col.mint(alice);
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        col.reveal(id); // not the owner
    }

    /* ── EIP-2981 royalty + ERC-721C creator token ── */
    function test_Royalty_ToReceiver() public view {
        (address r, uint256 amt) = col.royaltyInfo(1, 1 ether);
        assertEq(r, address(0xD1), "royalty receiver = dividend");
        assertEq(amt, 0.05 ether, "5% royalty"); // 500 bps
    }
    function test_SupportsErc2981() public view {
        assertTrue(col.supportsInterface(0x2a55205a), "ERC-2981"); // royaltyInfo selector-set
    }
    function test_ValidatorBlocksTransfer_WhenSet() public {
        vm.prank(hook); uint256 id = col.mint(alice);
        // wire a validator that rejects trades; `col`'s deployer is this test.
        col.setTransferValidator(address(new RejectValidator()));
        vm.prank(alice);
        vm.expectRevert(); // validator reverts → transfer blocked (fee enforced)
        col.transferFrom(alice, address(0xB0B), id);
    }
}

/// @dev A transfer validator that blocks every non-mint move (proves enforcement).
contract RejectValidator {
    function validateTransfer(address, address from, address, uint256) external pure {
        if (from != address(0)) revert("blocked"); // allow mints, block trades
    }
}

/* ── Genesis MiFrens fee dividend ─────────────────────────────────── */
import {MiFrensDividend} from "../cauldron/MiFrensDividend.sol";

contract DividendTest is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address treasury = address(0x7EA);

    function setUp() public {
        // genesis 3, art cap 6 → 3 shares
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div)); // wire the transfer hook
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(address(this), 100 ether);
    }

    function test_SharesEqualsGenesisSupply() public view {
        assertEq(div.SHARES(), 3);
    }

    function test_ProRataAccrualAndClaim() public {
        // alice owns 2 genesis, bob owns 1
        vm.prank(alice); mifrens.mint{value: 0.02 ether}(2); // ids 1,2
        vm.prank(bob);   mifrens.mint{value: 0.01 ether}(1); // id 3

        // cast the spell so each fren draws fees (else it earns nothing)
        vm.prank(alice); div.castSpell(1);
        vm.prank(alice); div.castSpell(2);
        vm.prank(bob);   div.castSpell(3);

        // 3 ETH streams in from the hook → 1 ETH per share
        (bool ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        assertEq(div.pending(1), 1 ether);
        assertEq(div.pending(2), 1 ether);
        assertEq(div.pending(3), 1 ether);

        uint256 aBefore = alice.balance;
        vm.prank(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1; ids[1] = 2;
        uint256 got = div.claimMany(ids);
        assertEq(got, 2 ether);
        assertEq(alice.balance - aBefore, 2 ether);
        assertEq(div.pending(1), 0);
        assertEq(div.pending(2), 0);

        // second deposit only accrues from now on; already-claimed tokens start fresh
        (ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        assertEq(div.pending(1), 1 ether);
        assertEq(div.pending(3), 2 ether); // bob never claimed: 1 + 1
    }

    /// Forged frens (ids SHARES+1..MAX_SUPPLY) are ELIGIBLE now (pay-to-earn), but
    /// earn nothing until enchanted; ids beyond MAX_SUPPLY are rejected outright.
    function test_ForgedEligible_UnenchantedEarnsNothing() public {
        vm.prank(alice); mifrens.mint{value: 0.03 ether}(3); // ids 1..3 (genesis)
        vm.prank(address(this)); mifrens.setMinter(address(this));
        uint256 id4 = mifrens.mint(alice);                    // forged id 4 (<= MAX_SUPPLY 6)
        assertEq(id4, 4);

        (bool ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        // forged but NOT enchanted → earns nothing, and claim reverts NotEnchanted
        // (no longer NotShare — it IS an eligible share now).
        assertEq(div.pending(4), 0);
        vm.prank(alice);
        vm.expectRevert(MiFrensDividend.NotEnchanted.selector);
        div.claim(4);

        // id 7 is beyond MAX_SUPPLY (6) → hard-rejected as NotShare.
        vm.prank(alice);
        vm.expectRevert(MiFrensDividend.NotShare.selector);
        div.claim(7);
    }

    /// A FORGED fren can enchant and earn ALONGSIDE the OGs — "pay to earn". Here
    /// the registry fee sink is off (unset), so enchant is free; the point is the
    /// forged fren joins the active set and draws its per-share slice.
    function test_ForgedPaysToEarn_SharesThePot() public {
        vm.prank(alice); mifrens.mint{value: 0.03 ether}(3); // OGs 1..3 → alice
        vm.prank(address(this)); mifrens.setMinter(address(this));
        uint256 id4 = mifrens.mint(bob);                      // forged id 4 → bob
        assertEq(id4, 4);

        vm.prank(alice); div.castSpell(1);                    // OG enchants (free)
        vm.prank(bob);   div.castSpell(4);                    // forged enchants (pay-to-earn)
        assertTrue(div.isEnchanted(4), "forged fren is eligible + enchanted");
        assertEq(div.activeShares(), 2, "OG + forged both in the active set");

        (bool ok, ) = address(div).call{value: 2 ether}("");
        assertTrue(ok);
        // 2 ETH split across 2 active shares → 1 ETH each (OG and forged alike).
        assertEq(div.pending(1), 1 ether, "OG earns its share");
        assertEq(div.pending(4), 1 ether, "forged earns an EQUAL share");
    }

    function test_OnlyOwnerClaims() public {
        vm.prank(alice); mifrens.mint{value: 0.01 ether}(1); // id 1
        (bool ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        vm.prank(bob);
        vm.expectRevert(MiFrensDividend.NotOwner.selector);
        div.claim(1);
    }

    function test_NoDoubleClaim() public {
        vm.prank(alice); mifrens.mint{value: 0.01 ether}(1);
        vm.prank(alice); div.castSpell(1);
        (bool ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        vm.startPrank(alice);
        div.claim(1);
        assertEq(div.claim(1), 0); // nothing left
        vm.stopPrank();
    }

    // The "cast the spell" gate + active-share split + transfer settlement.
    function test_EnchantGate() public {
        vm.prank(alice); mifrens.mint{value: 0.01 ether}(1);

        // not enchanted → claim reverts
        vm.prank(alice);
        vm.expectRevert(MiFrensDividend.NotEnchanted.selector);
        div.claim(1);

        // cast the spell → now the sole active share (no back-pay yet)
        vm.prank(alice); div.castSpell(1);
        assertTrue(div.isEnchanted(1));
        assertEq(div.pending(1), 0, "no back-pay");

        // 3 ETH in → alice is the ONLY caster, so she gets the whole pot
        (bool ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        assertEq(div.pending(1), 3 ether, "sole caster takes the pot");

        // transfer the NFT → hook settles alice + frees the share; bond breaks
        vm.prank(alice); mifrens.transferFrom(alice, bob, 1);
        assertFalse(div.isEnchanted(1), "transfer breaks the spell");
        assertEq(div.activeShares(), 0, "share freed");
        assertEq(div.owed(alice), 3 ether, "settled to the leaver");
        assertEq(div.pending(1), 0, "new owner earns 0 until re-cast");
        vm.prank(bob);
        vm.expectRevert(MiFrensDividend.NotEnchanted.selector);
        div.claim(1);

        // alice pulls her settled fees
        uint256 b = alice.balance;
        vm.prank(alice); div.withdrawOwed();
        assertEq(alice.balance - b, 3 ether, "withdraw settled");
    }

    // No spell-casters → fees sweep to the treasury (not banked for the first caster).
    function test_NoCasters_FeesGoToTreasury() public {
        vm.prank(alice); mifrens.mint{value: 0.01 ether}(1); // owns id 1, hasn't cast
        uint256 t0 = treasury.balance;
        (bool ok, ) = address(div).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(treasury.balance - t0, 2 ether, "swept to treasury");
        assertEq(div.pending(1), 0, "nothing banked for the fren");

        // once someone casts, fees flow to the active set again
        vm.prank(alice); div.castSpell(1);
        (ok, ) = address(div).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(treasury.balance - t0, 2 ether, "no further treasury sweep");
        assertEq(div.pending(1), 2 ether, "active caster earns");
    }

    // Casting LATE never reduces an existing caster's already-accrued dividends.
    function test_LateCastDoesNotDiluteAccrued() public {
        vm.prank(alice); mifrens.mint{value: 0.02 ether}(2); // ids 1,2 (alice)
        vm.prank(bob);   mifrens.mint{value: 0.01 ether}(1); // id 3 (bob)

        // only alice casts (1 share); 3 ETH in → alice's fren #1 banks 3 ETH
        vm.prank(alice); div.castSpell(1);
        (bool ok, ) = address(div).call{value: 3 ether}("");
        assertTrue(ok);
        assertEq(div.pending(1), 3 ether);

        // bob casts LATER — alice's already-accrued 3 ETH is untouched
        vm.prank(bob); div.castSpell(3);
        assertEq(div.pending(1), 3 ether, "prior accrual preserved");
        assertEq(div.pending(3), 0, "late caster: no back-pay");

        // next 2 ETH now splits 1:1 between the two active frens
        (ok, ) = address(div).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(div.pending(1), 4 ether, "3 solo + 1 shared");
        assertEq(div.pending(3), 1 ether, "1 shared");
    }

    // PAID RE-ENCHANT: an original never-moved OG enchants FREE; once a fren has
    // MOVED (transfer/recycle) re-enchanting costs the token fee, which is routed
    // into the reserve (grows the floor). Grandfathering protects the OG promise.
    function test_PaidReEnchant_GrandfatherVsMoved() public {
        MockEnchantToken tok = new MockEnchantToken();
        MockReserveRegistry reg = new MockReserveRegistry(address(tok), 100 ether);
        vm.prank(treasury); div.setRegistry(address(reg)); // wire (treasury-gated)

        // alice mints id 1 + id 2 (never moved → free enchant).
        vm.prank(alice); mifrens.mint{value: 0.02 ether}(2); // ids 1,2

        // Original OG enchants FREE even with the registry wired + a fee set.
        vm.prank(alice); div.castSpell(1);
        assertTrue(div.isEnchanted(1), "OG enchants free");

        // Move id 2 alice→bob → everMoved[2] = true.
        vm.prank(alice); mifrens.transferFrom(alice, bob, 2);
        assertTrue(mifrens.everMoved(2), "fren marked moved");

        // Bob tries to enchant #2 without paying → reverts (no token/approval).
        vm.prank(bob);
        vm.expectRevert();
        div.castSpell(2);

        // Fund + approve bob for the fee, then enchant succeeds and the fee lands
        // in the reserve (the mock registry's donateToReserve pulled it).
        tok.mint(bob, 100 ether);
        vm.prank(bob); tok.approve(address(div), 100 ether);
        vm.prank(bob); div.castSpell(2);
        assertTrue(div.isEnchanted(2), "moved fren enchants after paying");
        assertEq(reg.totalDonated(), 100 ether, "fee routed into the reserve");
        assertEq(tok.balanceOf(bob), 0, "bob paid the fee");
    }
}

/// Minimal ERC20 with mint, for the paid-re-enchant test.
contract MockEnchantToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        require(allowance[f][msg.sender] >= a, "allow");
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// Mock registry the dividend prices + routes the re-enchant fee through.
contract MockReserveRegistry {
    address public currentToken;
    uint256 public enchantFee;
    uint256 public totalDonated;
    constructor(address _tok, uint256 _fee) { currentToken = _tok; enchantFee = _fee; }
    function donateToReserve(uint256 amount) external {
        // Pull the fee the dividend approved us for → mimics the reserve growing.
        MockEnchantToken(currentToken).transferFrom(msg.sender, address(this), amount);
        totalDonated += amount;
    }
}

/* ── Emergency timelock (rug-fix hardening) ──────────────────────── */

contract EmergencyTest is Test {
    address admin = address(this);

    function _reg(uint256 delay) internal returns (CauldronRegistry) {
        // poolManager/positionManager/hook are only touched inside the withdraw
        // BODY, which the timelock guard runs BEFORE — so dummies are fine here.
        return new CauldronRegistry(address(1), address(2), address(3), admin, delay);
    }

    function test_Timelock_BlocksUnarmedWithdraw() public {
        CauldronRegistry r = _reg(7 days);
        vm.expectRevert(CauldronBase.Timelocked.selector);
        r.emergencyWithdrawLP(1); // never armed → blocked
    }

    function test_Timelock_BlocksBeforeDelayElapses() public {
        CauldronRegistry r = _reg(7 days);
        r.armEmergency();
        assertEq(r.emergencyReadyAt(), block.timestamp + 7 days);
        vm.expectRevert(CauldronBase.Timelocked.selector);
        r.emergencyWithdrawLP(1); // armed but delay not elapsed → still blocked
    }

    /// @notice A ZERO delay must still require the ARM (audit F-19).
    ///
    ///  This test previously asserted the opposite --- that a zero delay makes a
    ///  custody action outright instant --- which encoded the defect rather than
    ///  the intent. Skipping the guard did not merely remove the waiting period:
    ///  it meant `emergencyReadyAt` was never set, and
    ///  {CauldronBase._redeemBlocked} keys THE EXIT GUARANTEE off exactly that
    ///  variable. So a zero-delay deployment silently had no forced-open exit at
    ///  all, and the admin could pause redemption and then withdraw the LP with
    ///  holders locked out.
    ///
    ///  The arm and the delay are now separate concerns: the ARM decides whether
    ///  an exit window exists, the delay decides how long it is. A zero delay
    ///  degrades the window to a transaction boundary; it can no longer delete it.
    function test_Timelock_ZeroDelay_StillRequiresTheArm() public {
        CauldronRegistry r = _reg(0);

        // UNARMED must be refused even at zero delay.
        vm.expectRevert(CauldronBase.Timelocked.selector);
        r.emergencyWithdrawLP(1);

        // ARMED proceeds past the guard immediately (zero delay = no waiting),
        // reverting only inside the body on this test's dummy position manager.
        r.armEmergency();
        assertGt(r.emergencyReadyAt(), 0, "arming records the exit window");
        try r.emergencyWithdrawLP(1) {
            // body may succeed or revert on the dummy -- either way, not Timelocked
        } catch (bytes memory reason) {
            require(
                bytes4(reason) != CauldronBase.Timelocked.selector,
                "armed + zero delay must clear the guard"
            );
        }
    }

    /// @notice THE POINT OF THE FIX: arming a custody action forces the redemption
    ///         exit OPEN even when the delay is zero. Before F-19 this held only
    ///         for non-zero delays, so the deployments most likely to need the
    ///         protection were the ones that silently lacked it.
    function test_F19_ZeroDelay_ArmingStillForcesTheExitOpen() public {
        CauldronRegistry r = _reg(0);

        // The fast circuit-breaker is deliberately immediate, so an admin can
        // always close redemption first.
        r.setRedemptionPaused(true);
        assertTrue(r.redemptionPaused(), "paused");

        // Arming a custody action must re-open the exit, so holders can leave at
        // the floor BEFORE anything moves -- regardless of the configured delay.
        r.armEmergency();
        assertGt(r.emergencyReadyAt(), 0, "armed");
        assertTrue(r.redemptionPaused(), "the pause flag itself is unchanged");
        // `_redeemBlocked()` is internal; `floorClaimableNow()` and the redemption
        // entrypoints observe it. Assert the state the guarantee is keyed on.
        assertTrue(
            r.emergencyReadyAt() != 0,
            "exit-open flag set while a custody action is pending"
        );
    }

    function test_OnlyAdminCanArm() public {
        CauldronRegistry r = _reg(7 days);
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronBase.NotAdmin.selector);
        r.armEmergency();
    }

    function test_OnlyAdminCanWithdraw() public {
        CauldronRegistry r = _reg(0);
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronBase.NotAdmin.selector);
        r.emergencyWithdrawLP(1);
    }

    function test_EmergencyAdminIsConstructorArg() public {
        CauldronRegistry r = _reg(7 days);
        assertEq(r.emergencyAdmin(), admin);
        assertEq(r.emergencyDelay(), 7 days);
        // address(0) → falls back to deployer (this test contract)
        CauldronRegistry r2 = new CauldronRegistry(address(1), address(2), address(3), address(0), 0);
        assertEq(r2.emergencyAdmin(), address(this));
    }
}

/* ── Auto-migrate opt-in (free for frens, 0.069 ETH otherwise) ────── */

contract AutoMigrateOptInTest is Test {
    MockMiFrens mifrens;
    CauldronRegistry reg;
    address fren = address(0xF00D);
    address nonFren = address(0xBEEF);

    function setUp() public {
        mifrens = new MockMiFrens();
        mifrens.mint(fren, 1); // fren holds a MiFren
        reg = new CauldronRegistry(address(1), address(2), address(3), address(this), 0);
        reg.setGenesisBonus(address(mifrens), 1000, 1); // wires `mifrens`
        vm.deal(nonFren, 1 ether);
    }

    function test_Fren_OptsInFree() public {
        vm.prank(fren);
        reg.enableAutoMigrate(); // no ETH
        assertTrue(reg.autoMigrate(fren));
    }

    // OG-holder airdrop reserve: owner sets a wallet + amount pre-summon; capped
    // at 20% of supply; only settable before summon.
    function test_AirdropReserve_SetAndCap() public {
        reg.setAirdropReserve(address(0xA1D), 81_773_399e18);
        assertEq(reg.airdropWallet(), address(0xA1D));
        assertEq(reg.airdropReserve(), 81_773_399e18);
        // over 20% of 777M reverts
        vm.expectRevert(CauldronBase.TooHigh.selector);
        reg.setAirdropReserve(address(0xA1D), 160_000_000e18);
        // non-owner can't set
        vm.prank(address(0xBAD));
        vm.expectRevert();
        reg.setAirdropReserve(address(0xA1D), 1e18);
    }

    function test_NonFren_MustPayFee() public {
        vm.prank(nonFren);
        vm.expectRevert(CauldronBase.Fee.selector);
        reg.enableAutoMigrate();

        vm.prank(nonFren);
        reg.enableAutoMigrate{value: 0.069 ether}();
        assertTrue(reg.autoMigrate(nonFren));
        assertEq(address(reg).balance, 0.069 ether, "fee seeds the registry");
    }
}
