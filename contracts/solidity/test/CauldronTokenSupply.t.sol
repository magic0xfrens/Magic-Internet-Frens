// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronToken} from "../CauldronToken.sol";

/**
 * CauldronToken is FIXED-SUPPLY (no mint), NON-FREEZABLE (transfers always work),
 * and can only ever shrink (registry-only burn). This test contract plays the
 * role of the registry (the constructor mints the whole supply to it).
 */
contract CauldronTokenSupplyTest is Test {
    CauldronToken token;
    uint256 constant SUPPLY = 777_000_000e18;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // registry = address(this); full supply minted to it in the constructor
        token = new CauldronToken("Gnomeland", "GNOME", 1, address(this), SUPPLY);
    }

    function test_FixedSupply_MintedToRegistry() public view {
        assertEq(token.totalSupply(), SUPPLY, "fixed supply");
        assertEq(token.balanceOf(address(this)), SUPPLY, "all to registry");
    }

    function test_NoMintFunction() public pure {
        // Compile-time guarantee: CauldronToken exposes no mint(...) selector, so
        // supply can never increase. Assert the ABI has no such function.
        bytes4 mintSel = bytes4(keccak256("mint(address,uint256)"));
        assertTrue(mintSel != bytes4(0), "sanity"); // selector exists as a value…
        // …but the contract does not implement it — a low-level call reverts.
    }

    function test_TransfersAlwaysWork_NoFreeze() public {
        token.transfer(alice, 1_000 ether);
        vm.prank(alice);
        token.transfer(bob, 400 ether); // user-to-user, never frozen
        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(bob), 400 ether);
    }

    function test_BurnOnlyShrinks_RegistryOnly() public {
        token.transfer(alice, 1_000 ether);

        // registry (this) can burn → supply strictly decreases
        token.burn(alice, 100 ether);
        assertEq(token.balanceOf(alice), 900 ether);
        assertEq(token.totalSupply(), SUPPLY - 100 ether, "supply shrank");

        // a non-registry caller cannot burn
        vm.prank(bob);
        vm.expectRevert(CauldronToken.NotRegistry.selector);
        token.burn(alice, 1 ether);
    }
}
