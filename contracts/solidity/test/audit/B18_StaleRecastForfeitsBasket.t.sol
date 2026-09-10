// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-18 — a stale re-cast settled the ETH dividend and FORFEITED the basket
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `MiFrensDividend._castSpell` has two branches. A FRESH enchant joins the
 *  earning set; a STALE re-cast (the prior holder's transfer hook was skipped,
 *  which the code documents as a live scenario) settles the PRIOR caster and
 *  re-points the fren without changing the share count.
 *
 *  The stale branch settled ETH:
 *      owed[cur] += (accPerShare - debtOf[tokenId]) / ACC;
 *  and then advanced every basket marker with no matching credit:
 *      debtOfAsset[tokenId][a] = accPerShareOf[a];
 *
 *  So the prior caster's accrued USDG/xNVDA was destroyed — the marker moved,
 *  the value did not, and there is no sweep that recovers it. The sibling path
 *  `onMiFrenTransfer` has always settled BOTH sides; this one never mirrored it.
 *
 *  A dividend that is correct in ETH and lossy in every other asset is precisely
 *  what the multi-quote work exists to eliminate.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B18_StaleRecastForfeitsBasket is Test {
    MiFrensDividend internal div;
    MockQuoteToken internal usdg;
    FrensStub internal frens;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        frens = new FrensStub();
        div = new MiFrensDividend(address(frens), address(this));
        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        // `fundToken` is closed until the funder is wired (one-time, treasury).
        // This test IS the funder, standing in for the hook.
        div.setFunder(address(this));
    }

    /// @notice INVARIANT: a stale re-cast must preserve the prior caster's
    ///         entitlement in EVERY basket asset, exactly as it preserves ETH.
    function test_INVARIANT_B18_StaleRecastPreservesTheBasket() public {
        // Alice enchants and the basket accrues USDG while she holds it.
        frens.setOwner(1, alice);
        vm.prank(alice);
        div.castSpell(1);

        usdg.mint(address(this), 1_000e6);
        usdg.approve(address(div), 1_000e6);
        div.fundToken(address(usdg), 1_000e6);

        // Also accrue ETH, so the two sides can be compared directly.
        (bool ok, ) = address(div).call{value: 1 ether}("");
        assertTrue(ok, "eth funding");

        // The fren moves to Bob WITHOUT the transfer hook firing — the stale
        // case the branch exists for — and Bob re-casts.
        frens.setOwner(1, bob);
        vm.prank(bob);
        div.castSpell(1);

        uint256 ethOwed = div.owed(alice);
        uint256 usdgOwed = div.owedAsset(alice, address(usdg));

        emit log_named_uint("alice ETH  owed after stale re-cast", ethOwed);
        emit log_named_uint("alice USDG owed after stale re-cast", usdgOwed);

        assertGt(ethOwed, 0, "the ETH side was always settled");
        assertGt(
            usdgOwed, 0,
            "the basket must be settled too - pre-fix this was 0 and the value was destroyed"
        );
    }

    /// @notice REGRESSION: a FRESH enchant must still get nothing back-paid.
    ///         The fix must not turn "settle the prior caster" into "back-pay
    ///         whoever enchants next".
    function test_B18_FreshEnchantIsStillNotBackPaid() public {
        usdg.mint(address(this), 1_000e6);
        usdg.approve(address(div), 1_000e6);

        // Someone must be earning, or fundToken has no one to credit.
        frens.setOwner(2, bob);
        vm.prank(bob);
        div.castSpell(2);
        div.fundToken(address(usdg), 1_000e6);

        // Alice enchants AFTER the deposit — she must not claim any of it.
        frens.setOwner(1, alice);
        vm.prank(alice);
        div.castSpell(1);

        assertEq(
            div.owedAsset(alice, address(usdg)), 0,
            "a fresh enchant must never be back-paid historical fees"
        );
    }

    receive() external payable {}
}

/// @dev Minimal MiFrens stand-in: ownership only, and no transfer hook — which
///      is the condition that produces the stale re-cast in the first place.
contract FrensStub {
    mapping(uint256 => address) public ownerOf;
    function setOwner(uint256 id, address who) external { ownerOf[id] = who; }
    function everMoved(uint256) external pure returns (bool) { return false; }
    // The dividend reads both at construction to size its share cap.
    function GENESIS_SUPPLY() external pure returns (uint256) { return 1111; }
    function MAX_SUPPLY() external pure returns (uint256) { return 2222; }
}
