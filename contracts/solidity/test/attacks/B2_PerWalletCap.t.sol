// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

/**
 *  B-2 — the anti-whale cap shipped as `MAX_PER_WALLET == GENESIS_SUPPLY`, i.e.
 *  a cap that could never bind, on an `immutable` that could only be fixed by a
 *  redeploy. A live `cast call` on the Sepolia genesis returned
 *  `MAX_PER_WALLET() = GENESIS_SUPPLY() = 1111`.
 *
 *  These tests pin the remedy AND its limits:
 *    - a non-binding cap can be corrected after deploy,
 *    - it can never be RE-ENTERED through the setter,
 *    - and once anyone has minted the cap can only ratchet DOWN, so a cap a
 *      buyer relied on cannot be widened out from under them.
 */
contract B2_PerWalletCap is Test {
    MiFrensGenesis internal g;

    uint256 constant SUPPLY = 1111;
    uint256 constant PRICE = 0.0062 ether;

    address internal whale = address(0xBEEF);

    function setUp() public {
        // Deployed exactly as the live one was: a cap equal to the whole tranche.
        g = new MiFrensGenesis("MiFrens", "MIFREN", SUPPLY, 2 * SUPPLY, PRICE, SUPPLY, "ipfs://x/");
    }

    /// The defect itself, still reproducible on a fresh deploy that passes a
    /// non-binding cap: one wallet can take the entire genesis tranche.
    function test_B2_nonBindingCapLetsOneWalletTakeEverything() public {
        assertEq(g.MAX_PER_WALLET(), g.GENESIS_SUPPLY(), "precondition: the cap cannot bind");

        vm.deal(whale, PRICE * SUPPLY);
        vm.prank(whale);
        g.mint{value: PRICE * SUPPLY}(SUPPLY);

        assertEq(g.balanceOf(whale), SUPPLY, "one wallet holds the whole genesis");
    }

    /// The remedy: the deployer can correct it, and 7 then actually binds.
    function test_B2_capIsCorrectableBeforeMintingAndThenBinds() public {
        g.setMaxPerWallet(7);
        assertEq(g.MAX_PER_WALLET(), 7, "cap was corrected after deploy");

        vm.deal(whale, PRICE * 8);
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: PRICE * 8}(8);

        vm.prank(whale);
        g.mint{value: PRICE * 7}(7);
        assertEq(g.balanceOf(whale), 7, "exactly the cap is mintable");

        vm.deal(whale, PRICE);
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.mint{value: PRICE}(1);
    }

    /// The bad state cannot be re-entered through the setter.
    function test_B2_setterRefusesANonBindingCap() public {
        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.setMaxPerWallet(SUPPLY);

        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.setMaxPerWallet(SUPPLY + 1);

        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.setMaxPerWallet(0);
    }

    /// Once minting has begun the cap may only ratchet DOWN — a buyer who relied
    /// on a cap of 7 cannot have it widened underneath them.
    function test_B2_capOnlyRatchetsDownOnceMintingStarted() public {
        g.setMaxPerWallet(7);

        vm.deal(whale, PRICE * 3);
        vm.prank(whale);
        g.mint{value: PRICE * 3}(3);

        vm.expectRevert(MiFrensGenesis.PerWalletCap.selector);
        g.setMaxPerWallet(8);

        g.setMaxPerWallet(5); // tightening is still allowed
        assertEq(g.MAX_PER_WALLET(), 5, "cap may always be tightened");
    }

    /// Only the deployer may move it.
    function test_B2_setterIsDeployerOnly() public {
        vm.prank(whale);
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        g.setMaxPerWallet(7);
    }
}
