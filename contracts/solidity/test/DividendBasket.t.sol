// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../cauldron/MiFrensDividend.sol";

contract Stable is Test {
    string public constant name = "USDG";
    uint8 public constant decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) { balanceOf[msg.sender] -= a; balanceOf[to] += a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/**
 * @dev The genesis dividend, once fees stop being only ETH.
 *
 *  A generation can trade in several quotes, so a USDG-quoted pool pays USDG
 *  fees. The take was already currency-agnostic; the DISTRIBUTION was not — five
 *  routing sites and the dividend itself were `.call{value:}` / `receive()`, so
 *  a non-ETH generation would collect fees it could never pay out.
 *
 *  These tests pin the accounting, because getting a dividend subtly wrong pays
 *  someone else's money to the wrong holder and nothing reverts.
 */
contract DividendBasketTest is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;
    Stable usdg;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address treasury = address(0x7EA);

    function setUp() public {
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div));
        usdg = new Stable();
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        usdg.mint(address(this), 1_000_000e6);
        usdg.approve(address(div), type(uint256).max);
    }

    function _mintTo(address who, uint256 n) internal {
        vm.prank(who);
        mifrens.mint{value: 0.01 ether * n}(n);
    }

    /// The basic property: an ERC20 fee is shared like an ETH one.
    function test_TokenFeesAreSharedAmongTheEnchanted() public {
        _mintTo(alice, 1);
        _mintTo(bob, 1);
        vm.prank(alice); div.castSpell(1);
        vm.prank(bob); div.castSpell(2);

        div.fundToken(address(usdg), 1000e6);

        assertApproxEqAbs(div.pendingToken(1, address(usdg)), 500e6, 1, "half each");
        assertApproxEqAbs(div.pendingToken(2, address(usdg)), 500e6, 1, "half each");

        vm.prank(alice); div.claimTokens(1);
        assertApproxEqAbs(usdg.balanceOf(alice), 500e6, 1, "alice is paid in USDG");
        assertEq(div.pendingToken(1, address(usdg)), 0, "and cannot claim twice");
    }

    /**
     * THE BUG THIS DESIGN INVITES. A fren enchanted AFTER a deposit starts with
     * a zero debt marker, and would claim the entire historical accumulator —
     * fees earned before it was ever enchanted, taken from everyone else. The
     * ETH path has always set that marker on enchant; the basket has to match,
     * and this is the test that proves it does.
     */
    function test_LateJoinerCannotClaimHistoricalFees() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        div.fundToken(address(usdg), 1000e6); // alice alone is entitled

        // BOB enchants only now.
        _mintTo(bob, 1);
        vm.prank(bob); div.castSpell(2);

        assertEq(div.pendingToken(2, address(usdg)), 0, "a late joiner is owed nothing yet");
        assertApproxEqAbs(div.pendingToken(1, address(usdg)), 1000e6, 1, "alice keeps all of it");

        // From here they share.
        div.fundToken(address(usdg), 1000e6);
        assertApproxEqAbs(div.pendingToken(2, address(usdg)), 500e6, 1, "and shares what comes after");
    }

    /// ETH and tokens are separate ledgers, so claiming one must not touch the
    /// other — and a token that reverts cannot block an ETH claim.
    function test_EthAndTokenLedgersAreIndependent() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        (bool ok, ) = address(div).call{value: 1 ether}("");
        assertTrue(ok);
        div.fundToken(address(usdg), 1000e6);

        vm.prank(alice); div.claimTokens(1);
        assertApproxEqAbs(usdg.balanceOf(alice), 1000e6, 1, "token claimed");
        assertApproxEqAbs(div.pending(1), 1 ether, 1, "the ETH claim is untouched");
    }

    /// The asset list is looped on claim, so it must be bounded — an unbounded
    /// list eventually costs more gas than a block allows, which is a permanent
    /// lockout rather than an inconvenience.
    function test_AssetListIsBounded() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        for (uint256 i; i < 8; ++i) {
            Stable t = new Stable();
            t.mint(address(this), 1000e6);
            t.approve(address(div), type(uint256).max);
            div.fundToken(address(t), 100e6);
        }
        assertEq(div.assetCount(), 8, "eight assets tracked");

        Stable extra = new Stable();
        extra.mint(address(this), 1000e6);
        extra.approve(address(div), type(uint256).max);
        vm.expectRevert(MiFrensDividend.NotShare.selector);
        div.fundToken(address(extra), 100e6);
    }

    /// With nobody enchanted an ERC20 deposit is refused rather than swept: a
    /// sweep needs a transfer that can fail, and a failure here would revert the
    /// swap that produced the fee.
    function test_TokenFundRefusedWithNobodyEnchanted() public {
        vm.expectRevert(MiFrensDividend.NotEnchanted.selector);
        div.fundToken(address(usdg), 100e6);
    }
}
