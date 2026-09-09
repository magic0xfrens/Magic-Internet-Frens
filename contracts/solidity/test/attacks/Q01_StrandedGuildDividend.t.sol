// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {FeeRouteLib} from "../../cauldron/FeeRouteLib.sol";

/// @dev A 6-decimal stable (USDG), standing in as a non-ETH quote.
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

/**
 * Q-01 — The ERC20 GUILD DIVIDEND is never funded, so it is stranded forever.
 *
 *  The multi-quote remediation generalised the TAKE (fees are collected in the
 *  quote asset, USDG/xNVDA) and the ROUTING ({FeeRouteLib} moves any asset). It
 *  did NOT bring the dividend LEDGER along.
 *
 *  `CauldronHook` routes the guild's share of every swap fee through
 *  `FeeRouteLib.routeSplit` (base guild share, CauldronHook.sol:1233) and again
 *  for the anti-snipe surtax (CauldronHook.sol:1339). `routeSplit` -> `_move`
 *  (FeeRouteLib.sol:89-95), which for an ERC20 does a **plain `transfer`** to the
 *  guild. But `MiFrensDividend` only CREDITS a deposit made through `fundToken`
 *  (MiFrensDividend.sol:273) — a push is explicitly treated as a stray transfer
 *  it must ignore ("A push model would have no way to tell a fee from a stray
 *  transfer", MiFrensDividend.sol:264-271).
 *
 *  The hook NEVER calls `fundToken`. `grep -rn 'fundToken' .` over the
 *  non-test tree finds only the definition and `setFunder(address(hook))` in
 *  DeployLaunchpad.s.sol:248 — the funder is wired, the call is missing. So for
 *  any non-ETH generation the entire genesis-dividend share of trading fees
 *  (guildBps = 15% + 100% of the surtax) lands in the dividend contract with
 *  zero accounting and NO exit path (MiFrensDividend has no rescue, and
 *  `fundToken` pulls NEW tokens from the hook — it cannot adopt a balance that
 *  is already sitting in the contract).
 *
 *  This is the exact failure class of R-1/V-1/D-3: the ledger was not updated to
 *  match the generalised money-movement. R-1 fixed the RELAUNCH reserve side;
 *  the GUILD dividend side was left behind.
 *
 *  INVARIANT (should hold): every ERC20 fee the hook routes to the guild becomes
 *  claimable by the enchanted holders (or at minimum recoverable). The PoC shows
 *  it is neither.
 */
contract Q01_StrandedGuildDividend is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;
    Stable usdg;

    address alice = address(0xA11CE);
    address treasury = address(0x7EA);

    function setUp() public {
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div));

        //  THIS CONTRACT STANDS IN AS THE HOOK: it is the wired `funder`, and it
        //  holds and routes the collected fee exactly as the hook does.
        vm.prank(treasury);
        div.setFunder(address(this));

        usdg = new Stable();
        usdg.mint(address(this), 1_000_000e6);

        //  Alice owns and enchants a genesis fren — a real dividend claimant.
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        mifrens.mint{value: 0.01 ether}(1);
        vm.prank(alice);
        div.castSpell(1);
        assertEq(div.activeShares(), 1, "alice is enchanted");
    }

    /// POSITIVE CONTROL: the path the hook SHOULD use (`fundToken`) distributes
    /// the ERC20 fee correctly — so the bug is purely that the hook uses the
    /// wrong primitive, not that the dividend is incapable.
    function test_PoC_Q01_CorrectPathFundsTheBasket() public {
        usdg.approve(address(div), type(uint256).max);
        div.fundToken(address(usdg), 1000e6);
        assertApproxEqAbs(div.pendingToken(1, address(usdg)), 1000e6, 1, "the lone enchanted fren is owed all of it");
        assertEq(div.assetCount(), 1, "and the asset is registered");
    }

    /// REGRESSION (Q-01 fix): routing the fee the way the hook actually does
    /// (`FeeRouteLib.routeSplit`, CauldronHook.sol:1233) now goes through the
    /// ACCOUNTED `fundToken` path — the asset is registered, the accumulator
    /// moves, and the enchanted holder can claim. No stranding, no missing exit.
    ///
    /// Pre-fix this asserted the opposite (assetCount 0, pending 0); the fix was
    /// `FeeRouteLib._fundGuild` calling `fundToken` for an ERC20 guild.
    function test_Fixed_Q01_GuildErc20FeeIsDistributed() public {
        //  The hook must approve the dividend to pull (pull-based fundToken), and
        //  must be the wired funder — both true for the real hook. This test
        //  contract IS the funder (set in setUp); it just needs the allowance the
        //  hook would grant. `_fundGuild` approves internally, so nothing extra is
        //  needed here — the library sets the allowance in the hook's context.
        uint256 fee = 1000e6;

        //  Route it EXACTLY as CauldronHook._routeEthFee does at :1233.
        uint256 leftover = FeeRouteLib.routeSplit(address(usdg), address(div), address(0), fee, 0);

        //  Delivered AND accounted.
        assertEq(leftover, 0, "guild fee delivered");
        assertEq(usdg.balanceOf(address(div)), fee, "the fee reached the dividend");
        assertEq(div.assetCount(), 1, "the asset is now registered");
        assertGt(div.accPerShareOf(address(usdg)), 0, "the accumulator moved");
        assertApproxEqAbs(div.pendingToken(1, address(usdg)), fee, 1, "alice is owed the whole guild fee");

        //  And she can actually collect it.
        vm.prank(alice);
        div.claimTokens(1);
        assertApproxEqAbs(usdg.balanceOf(alice), fee, 1, "alice claims the guild fee in USDG");
    }

    /// REGRESSION: the surtax leg (CauldronHook.sol:1339 also routeSplit→guild)
    /// is distributed identically now.
    function test_Fixed_Q01_SurtaxLegIsDistributed() public {
        uint256 surtax = 500e6;
        FeeRouteLib.routeSplit(address(usdg), address(div), address(0), surtax, 0);
        assertApproxEqAbs(div.pendingToken(1, address(usdg)), surtax, 1, "surtax credited the holder");
    }

    /// REGRESSION — QUOTE ROTATION BEYOND THE BASKET CAP. `MAX_ASSETS` is 3 and
    /// there is deliberately no `removeAsset` (audit S-1: removal re-opens the
    /// historical over-claim hole). So a generation that rotates into a FOURTH
    /// distinct non-ETH quote cannot register it — and the important property is
    /// that this degrades to the relaunch reserve rather than stranding value or
    /// reverting the swap. Value is never lost; it stops being a direct dividend
    /// and becomes reserve that seeds the next generation.
    function test_Fixed_Q01_FourthQuoteFallsBackToTheReserveNotStranded() public {
        // Fill the basket with three quotes.
        for (uint256 i; i < 3; ++i) {
            Stable t = new Stable();
            t.mint(address(this), 1000e6);
            FeeRouteLib.routeSplit(address(t), address(div), address(0), 100e6, 0);
        }
        assertEq(div.assetCount(), 3, "basket full at MAX_ASSETS");

        // A FOURTH quote's guild fee arrives.
        Stable fourth = new Stable();
        fourth.mint(address(this), 1000e6);
        uint256 fee = 100e6;
        uint256 leftover = FeeRouteLib.routeSplit(address(fourth), address(div), address(0), fee, 0);

        // Refused by the cap -> reported as leftover, which the hook credits to
        // `relaunchAsset` (it has an exit via releaseRelaunchAsset). Not stranded,
        // not reverted.
        assertEq(leftover, fee, "the fourth quote's guild share falls back to the reserve");
        assertEq(fourth.balanceOf(address(div)), 0, "nothing was pushed into the dividend");
        assertEq(fourth.balanceOf(address(this)), 1000e6, "the hook still holds it for the reserve");
        assertEq(div.assetCount(), 3, "and the basket is unchanged");
    }

    /// REGRESSION: with NOBODY enchanted, `fundToken` reverts (no claimants), so
    /// `_fundGuild` reports failure and the caller buffers the share as leftover —
    /// it must NEVER revert the swap. The tokens stay with the hook (here, this
    /// contract) for the reserve, not lost.
    function test_Fixed_Q01_NoEnchantedBuffersInsteadOfReverting() public {
        //  Break Alice's enchantment so activeShares == 0.
        vm.prank(alice);
        mifrens.transferFrom(alice, address(0xBEEF), 1); // onMiFrenTransfer frees her share
        assertEq(div.activeShares(), 0, "nobody enchanted");

        uint256 fee = 1000e6;
        uint256 before = usdg.balanceOf(address(this));
        uint256 leftover = FeeRouteLib.routeSplit(address(usdg), address(div), address(0), fee, 0);

        //  fundToken reverted (NotEnchanted) → reported as leftover, not thrown.
        assertEq(leftover, fee, "the whole guild share is buffered for the reserve");
        assertEq(usdg.balanceOf(address(div)), 0, "nothing was pushed to the dividend");
        assertEq(usdg.balanceOf(address(this)), before, "the hook keeps the fee");
    }
}
