// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../cauldron/MiFrensGenesis.sol";

/// Accepts the whole treasury on ignition so a mixed-price raise can be
/// followed end to end without a PoolManager.
contract DiscountRegistryStub {
    uint256 public received;

    function summon() external payable returns (address token, bytes32 poolId) {
        received = msg.value;
        return (address(0xC0FFEE), bytes32(uint256(1)));
    }
}

/// @title Frenlist — a (wallet, allowance) Merkle list at a tenth of PRICE
///
/// A trusted setter re-publishes the root as new frens join (frenlist members
/// and Identity.md workers who earned a spot). Allowances are cumulative; what
/// a wallet already minted lives on-chain in `discountMinted`.
///
/// Fork-free: the real MiFrensGenesis, deployed directly.
contract GenesisDiscountMintTest is Test {
    uint256 constant PRICE = 0.1111 ether;
    uint256 constant DISCOUNT = 0.01111 ether;

    MiFrensGenesis g;

    address fren = makeAddr("fren");     // allowance 2
    address pepe = makeAddr("pepe");     // IMD worker with three earning NFTs -> allowance 3
    address setter = makeAddr("setter");
    address stranger = makeAddr("stranger");

    address[] wallets;
    uint256[] allowances;

    function setUp() public {
        g = new MiFrensGenesis("MiFrens", "MIFREN", 1111, 2222, PRICE, 100, "ipfs://x/");
        g.setMaxPerWallet(20);
        vm.deal(fren, 10 ether);
        vm.deal(pepe, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    // ------------------------------------------------------------------
    // Merkle helpers — sorted-pair hashing, the scheme OZ MerkleProof checks.
    // ------------------------------------------------------------------

    function _leaf(address wallet, uint256 allowance) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(wallet, allowance))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function _leaves() internal view returns (bytes32[] memory l) {
        l = new bytes32[](wallets.length);
        for (uint256 i; i < wallets.length; ++i) l[i] = _leaf(wallets[i], allowances[i]);
    }

    function _up(bytes32[] memory layer) internal pure returns (bytes32[] memory next) {
        next = new bytes32[]((layer.length + 1) / 2);
        for (uint256 i; i < layer.length; i += 2) {
            next[i / 2] = i + 1 < layer.length ? _hashPair(layer[i], layer[i + 1]) : layer[i];
        }
    }

    function _root() internal view returns (bytes32) {
        bytes32[] memory layer = _leaves();
        while (layer.length > 1) layer = _up(layer);
        return layer[0];
    }

    function _proofFor(address wallet) internal view returns (bytes32[] memory) {
        bytes32[] memory layer = _leaves();
        uint256 idx = type(uint256).max;
        for (uint256 i; i < wallets.length; ++i) if (wallets[i] == wallet) idx = i;
        require(idx != type(uint256).max, "not listed");
        bytes32[] memory tmp = new bytes32[](32);
        uint256 depth;
        while (layer.length > 1) {
            if ((idx ^ 1) < layer.length) tmp[depth++] = layer[idx ^ 1];
            layer = _up(layer);
            idx /= 2;
        }
        bytes32[] memory p = new bytes32[](depth);
        for (uint256 i; i < depth; ++i) p[i] = tmp[i];
        return p;
    }

    function _list(address wallet, uint256 allowance) internal {
        wallets.push(wallet);
        allowances.push(allowance);
    }

    function _publish() internal {
        g.setDiscountRoot(_root());
    }

    /// fren x2, pepe x3, plus filler so proofs have real depth.
    function _standardList() internal {
        _list(fren, 2);
        _list(pepe, 3);
        for (uint256 i; i < 5; ++i) _list(address(uint160(0xF00 + i)), 1);
        _publish();
    }

    // ------------------------------------------------------------------
    // Price and defaults
    // ------------------------------------------------------------------

    function test_DiscountPriceIsATenthOfThePublicPrice() public view {
        assertEq(g.DISCOUNT_PRICE(), DISCOUNT);
    }

    function test_PublicMintIsUnchangedAndTheFrenlistIsClosedByDefault() public {
        vm.prank(stranger);
        g.mint{value: PRICE}(1);
        assertEq(g.paid(stranger), PRICE);

        // No root yet: even a correct-looking leaf with an empty proof fails.
        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT}(1, 1, new bytes32[](0));
    }

    // ------------------------------------------------------------------
    // Spending an allowance
    // ------------------------------------------------------------------

    function test_FrenlistMintsAtTheDiscountUntilTheAllowanceIsSpent() public {
        _standardList();
        bytes32[] memory proof = _proofFor(fren);

        vm.expectEmit(address(g));
        emit MiFrensGenesis.DiscountMinted(fren, 1, 1);
        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT}(1, 2, proof);

        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT}(1, 2, proof);
        assertEq(g.discountMinted(fren), 2);
        assertEq(g.balanceOf(fren), 2);
        assertEq(g.paid(fren), DISCOUNT * 2, "refund ledger records what was actually paid");
        assertTrue(g.isGenesis(1) && g.isGenesis(2), "frenlist frens are ordinary genesis frens");

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT}(1, 2, proof);

        // The public door stays open to them at the public price.
        vm.prank(fren);
        g.mint{value: PRICE}(1);
        assertEq(g.balanceOf(fren), 3);
    }

    function test_AWorkerWithThreeEarningImdNftsMintsThreeInOneTransaction() public {
        _standardList();
        vm.prank(pepe);
        g.mintDiscounted{value: DISCOUNT * 3}(3, 3, _proofFor(pepe));
        assertEq(g.balanceOf(pepe), 3);
        assertEq(g.genesisMintedBy(pepe), 3, "counts against the lifetime cap");
        assertEq(address(g).balance, DISCOUNT * 3);
    }

    function test_ExactDiscountPaymentOnly() public {
        _standardList();
        bytes32[] memory proof = _proofFor(fren);

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.WrongPrice.selector);
        g.mintDiscounted{value: PRICE}(1, 2, proof);

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.WrongPrice.selector);
        g.mintDiscounted{value: DISCOUNT - 1}(1, 2, proof);

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.ExceedsSupply.selector);
        g.mintDiscounted{value: 0}(0, 2, proof);
    }

    // ------------------------------------------------------------------
    // Proofs are bound to the wallet and its allowance
    // ------------------------------------------------------------------

    function test_ProofsCannotBeUsedByAnotherWalletOrInflated() public {
        _standardList();

        vm.prank(stranger);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT}(1, 2, _proofFor(fren));

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT * 5}(5, 5, _proofFor(fren));
    }

    // ------------------------------------------------------------------
    // Re-publishing as new frens come
    // ------------------------------------------------------------------

    function test_RepublishingAddsNewFrensAndRaisesAllowancesCumulatively() public {
        _standardList();
        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT * 2}(2, 2, _proofFor(fren));

        // New list: fren 2 -> 3, and a brand-new fren joins.
        allowances[0] = 3;
        _list(stranger, 1);
        _publish();

        // fren only gets the ONE new mint, not three more.
        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT * 2}(2, 3, _proofFor(fren));
        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT}(1, 3, _proofFor(fren));
        assertEq(g.discountMinted(fren), 3);

        vm.prank(stranger);
        g.mintDiscounted{value: DISCOUNT}(1, 1, _proofFor(stranger));
        assertEq(g.balanceOf(stranger), 1);
    }

    function test_OldProofsStopWorkingWhenTheRootChangesAndZeroCloses() public {
        _standardList();
        bytes32[] memory oldProof = _proofFor(fren);

        _list(stranger, 1);
        _publish();
        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT}(1, 2, oldProof);

        g.setDiscountRoot(bytes32(0));
        bytes32[] memory proof = _proofFor(fren);
        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.NoDiscount.selector);
        g.mintDiscounted{value: DISCOUNT}(1, 2, proof);
    }

    // ------------------------------------------------------------------
    // The trusted setter
    // ------------------------------------------------------------------

    function test_OnlyTheDeployerOrTheNamedSetterEditsTheList() public {
        vm.prank(setter);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        g.setDiscountRoot(keccak256("x"));

        vm.prank(setter);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        g.setDiscountSetter(setter);

        g.setDiscountSetter(setter);
        _list(fren, 1);
        _list(pepe, 1);
        vm.prank(setter);
        g.setDiscountRoot(_root());
        assertEq(g.discountRoot(), _root());

        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT}(1, 1, _proofFor(fren));

        // Revoking the setter leaves the deployer in charge.
        g.setDiscountSetter(address(0));
        vm.prank(setter);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        g.setDiscountRoot(bytes32(0));
    }

    // ------------------------------------------------------------------
    // Cap, cancel, ignition
    // ------------------------------------------------------------------

    function test_PerWalletCapCountsFrenlistMints() public {
        g.setMaxPerWallet(3);
        _standardList();
        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT * 2}(2, 2, _proofFor(fren));
        vm.prank(fren);
        g.mint{value: PRICE}(1);

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: PRICE}(1);
    }

    function test_CancelRefundsTheDiscountedAmount() public {
        _standardList();
        vm.prank(fren);
        g.mintDiscounted{value: DISCOUNT * 2}(2, 2, _proofFor(fren));
        vm.prank(fren);
        g.mint{value: PRICE}(1);

        g.cancelPresale();
        uint256 before = fren.balance;
        vm.prank(fren);
        assertEq(g.refund(), DISCOUNT * 2 + PRICE);
        assertEq(fren.balance - before, DISCOUNT * 2 + PRICE);
    }

    function test_IgnitionForwardsTheMixedRaise() public {
        MiFrensGenesis small = new MiFrensGenesis("MiFrens", "MIFREN", 4, 8, PRICE, 4, "ipfs://x/");
        DiscountRegistryStub reg = new DiscountRegistryStub();
        small.setRegistry(address(reg));
        _list(pepe, 1);
        _list(fren, 1);
        small.setDiscountRoot(_root());

        vm.prank(pepe);
        small.mintDiscounted{value: DISCOUNT}(1, 1, _proofFor(pepe));
        vm.prank(stranger);
        small.mint{value: PRICE * 3}(3);

        vm.prank(fren);
        vm.expectRevert(MiFrensGenesis.ExceedsSupply.selector);
        small.mintDiscounted{value: DISCOUNT}(1, 1, _proofFor(fren));

        small.igniteCauldron();
        assertEq(reg.received(), DISCOUNT + PRICE * 3, "every wei, both prices, goes to the pool");
    }

    // ------------------------------------------------------------------
    // The list builder's proofs are the contract's proofs.
    // Root and proofs below come from scripts/frenlist/merkle.mjs for the
    // fixture pinned in scripts/frenlist/test-merkle.mjs, so a drift on either
    // side fails a test.
    // ------------------------------------------------------------------

    function test_ProofsFromTheJsListBuilderAreAccepted() public {
        g.setDiscountRoot(JS_ROOT);
        address beef = address(0xBEEF);
        address cafe = address(0xCAFE);
        vm.deal(beef, 1 ether);
        vm.deal(cafe, 1 ether);

        vm.prank(beef);
        g.mintDiscounted{value: DISCOUNT * 2}(2, 2, _jsProofBeef());
        vm.prank(cafe);
        g.mintDiscounted{value: DISCOUNT * 3}(3, 3, _jsProofCafe());
        assertEq(g.balanceOf(beef), 2);
        assertEq(g.balanceOf(cafe), 3);
    }

    bytes32 constant JS_ROOT = 0xbbd259d9a434955807656444a51c8fccf081a20f8f8382e431b24fb515db4e3c;

    function _jsProofBeef() internal pure returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = 0x476f925486c6d0430e1ee8e5bdb91b87fe802bea0b6a1bea169a2d14165fbaf6;
        p[1] = 0xdab4ca0479047cabf8081eea1525ee4856fad22538f2aff011d9e2c94852a020;
    }

    function _jsProofCafe() internal pure returns (bytes32[] memory p) {
        p = new bytes32[](1);
        p[0] = 0xf23335e3ad0be67656e8df0b7335a5bfec934eb706bd11324d579b0b483d95a6;
    }
}
