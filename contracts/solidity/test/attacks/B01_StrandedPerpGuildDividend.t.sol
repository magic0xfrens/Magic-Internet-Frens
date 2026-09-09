// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {FeeRouteLib} from "../../cauldron/FeeRouteLib.sol";

/// @dev A 6-decimal stable (USDG), standing in as a non-ETH quote — same stand-in
///      the Q-01 regression suite uses.
contract Stable {
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

/// @dev Minimal stand-in for the perp engine's `creditPerpFeeAsset` pull entry, so
///      the STAKERS leg of `routePerp` succeeds and we can isolate the GUILD leg.
contract MockEngine {
    Stable public immutable usdg;
    uint256 public credited;
    constructor(Stable _usdg) { usdg = _usdg; }
    // matches IPerpFeeCredit.creditPerpFeeAsset(address,uint256)
    function creditPerpFeeAsset(address asset, uint256 amount) external {
        require(usdg.transferFrom(msg.sender, address(this), amount), "pull");
        credited += amount;
    }
}

/**
 * B-01 REGRESSION — the Q-01 fix reaches the perp path.
 *
 *  Q-01's fix (`_fundGuild`, the ACCOUNTED route into {MiFrensDividend}) was
 *  originally applied to `routeSplit` (organic swaps) but MISSED on `routePerp`
 *  (perp swaps), even though Pass-4's own writeup listed `routePerp`
 *  (CauldronHook.sol:1134) as one of the three stranding sites. The perp guild
 *  leg still used the bare `_move` transfer (FeeRouteLib.sol:89), so a
 *  non-ETH-quoted perp generation lost the OG-holders' 30% share of every perp
 *  fee to an unaccounted, unrecoverable balance.
 *
 *  Fixed by switching `routePerp`'s guild leg to `_fundGuild`. These tests assert
 *  the fixed behaviour: a routed perp guild fee is registered, accrued, claimable
 *  by the enchanted holder, and handled identically to the organic path.
 */
contract B01_StrandedPerpGuildDividend is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;
    Stable usdg;
    MockEngine engine;

    address alice = address(0xA11CE);
    address treasury = address(0x7EA);

    function setUp() public {
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div));

        //  THIS CONTRACT STANDS IN AS THE HOOK: it is the wired `funder`, it holds
        //  the collected USDG perp fee, and it routes it exactly as the hook does.
        vm.prank(treasury);
        div.setFunder(address(this));

        usdg = new Stable();
        usdg.mint(address(this), 1_000_000e6);
        engine = new MockEngine(usdg);

        //  Alice owns and enchants a genesis fren — a real dividend claimant.
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        mifrens.mint{value: 0.01 ether}(1);
        vm.prank(alice);
        div.castSpell(1);
        assertEq(div.activeShares(), 1, "alice is enchanted");
    }

    /// REGRESSION (was RED pre-fix): the OG-dividend share of a perp fee, routed
    /// the way the hook actually routes it (`routePerp`), is ACCOUNTED and claimable
    /// by the enchanted holders — identically to the organic path.
    function test_Regression_PerpGuildFeeIsClaimable() public {
        uint256 toGuild = 300e6;   // 30% OG share of a 1000e6 perp fee
        uint256 toStakers = 700e6; // 70% stakers share

        //  Route it EXACTLY as CauldronHook._routePerpFee does at :1134.
        uint256 leftover = FeeRouteLib.routePerp(
            address(usdg),
            address(div),
            address(engine),
            toGuild,
            toStakers,
            bytes4(0),                              // nativeSel (unused — ERC20 path)
            MockEngine.creditPerpFeeAsset.selector  // assetSel
        );

        //  The stakers leg was delivered + ACCOUNTED.
        assertEq(engine.credited(), toStakers, "stakers leg accounted");
        //  The guild leg was delivered AND accounted — nothing buffered to reserve.
        assertEq(leftover, 0, "guild + stakers both delivered");
        //  The asset is registered and the accumulator moved.
        assertEq(div.assetCount(), 1, "perp guild asset registered");
        assertGt(div.accPerShareOf(address(usdg)), 0, "accumulator moved");
        //  THE INVARIANT: the enchanted holder is owed (≈) the whole guild share.
        assertApproxEqAbs(
            div.pendingToken(1, address(usdg)), toGuild, 1,
            "holder owed the routed perp guild fee"
        );
    }

    /// REGRESSION: the holder can actually collect it end-to-end.
    function test_Regression_PerpGuildFeeClaimableEndToEnd() public {
        uint256 toGuild = 300e6;

        FeeRouteLib.routePerp(
            address(usdg), address(div), address(engine),
            toGuild, 0, bytes4(0), MockEngine.creditPerpFeeAsset.selector
        );

        vm.prank(alice);
        div.claimTokens(1);
        assertApproxEqAbs(usdg.balanceOf(alice), toGuild, 1, "alice claims the perp guild fee in USDG");
        //  Nothing stranded in the dividend beyond sub-share dust.
        assertApproxEqAbs(usdg.balanceOf(address(div)), 0, 1, "no stranded balance");
    }

    /// REGRESSION: the organic path (`routeSplit`) and the perp path (`routePerp`)
    /// now handle the identical fee identically — both accounted, both claimable.
    function test_Regression_BothPathsAccountGuildFee() public {
        uint256 share = 300e6;

        // Organic guild leg → ACCOUNTED.
        FeeRouteLib.routeSplit(address(usdg), address(div), address(0), share, 0);
        assertApproxEqAbs(div.pendingToken(1, address(usdg)), share, 1, "routeSplit credited the holder");

        // Perp guild leg for a DIFFERENT stable → now ALSO accounted.
        Stable usdg2 = new Stable();
        usdg2.mint(address(this), 1_000e6);
        MockEngine eng2 = new MockEngine(usdg2);
        FeeRouteLib.routePerp(
            address(usdg2), address(div), address(eng2),
            share, 0, bytes4(0), MockEngine.creditPerpFeeAsset.selector
        );
        assertApproxEqAbs(div.pendingToken(1, address(usdg2)), share, 1, "routePerp now credits the holder too");
        assertApproxEqAbs(usdg2.balanceOf(address(div)), share, 1, "perp guild fee sits accounted in the dividend");
    }

    /// REGRESSION: fail-soft preserved — with nobody enchanted, the accounted path
    /// reports failure (fundToken reverts NotEnchanted) and the share is buffered
    /// as leftover for the caller to book to the reserve, NEVER reverting.
    function test_Regression_PerpGuildFailSoftWhenNoClaimants() public {
        vm.prank(alice);
        mifrens.transferFrom(alice, address(0xBEEF), 1); // frees her share
        assertEq(div.activeShares(), 0, "nobody enchanted");

        uint256 toGuild = 300e6;
        uint256 leftover = FeeRouteLib.routePerp(
            address(usdg), address(div), address(engine),
            toGuild, 0, bytes4(0), MockEngine.creditPerpFeeAsset.selector
        );
        assertEq(leftover, toGuild, "guild share buffered to reserve, not stranded, not reverted");
        assertEq(usdg.balanceOf(address(div)), 0, "nothing pushed into the dividend");
    }
}
