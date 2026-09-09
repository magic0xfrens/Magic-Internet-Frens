// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";

/**
 * @dev REGRESSION tests for the fee basket in {MiFrensDividend}, added by
 *      "feat(dividend): pay the fee basket, not just ETH".
 *
 *  The basket introduced a permissionless, bounded, append-only asset list that
 *  a claim looped over and pushed from. Each of those four properties is fine
 *  alone; together they were three distinct denial-of-service and value-loss
 *  bugs. `DividendBasket.t.sol::test_AssetListIsBounded` asserted the bound
 *  existed but never asked WHO was allowed to consume it — the bound was being
 *  read as a safety property when it was the attack surface.
 *
 *  Each test below FAILS against the pre-fix contract and passes now.
 */

// A cooperative 6-decimal stable, same shape as the one in DividendBasket.t.sol.
contract Stable {
    uint8 public constant decimals = 6;
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

/// A token that accepts a deposit and then refuses every outbound transfer.
/// Nothing exotic: a pausable token, a blacklisting stablecoin, or any token
/// whose owner turns hostile after listing behaves exactly like this.
contract TrapToken {
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public armed;
    function arm() external { armed = true; }
    function armFalse() external { armed = false; }
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        require(!armed, "trapped");
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract AuditPoC5_DividendBasket is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;
    Stable usdg;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address attacker = address(0xBAD);
    address treasury = address(0x7EA);

    function setUp() public {
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div));
        // This contract stands in as the hook — the sole permitted funder.
        vm.prank(treasury);
        div.setFunder(address(this));
        usdg = new Stable();
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(attacker, 1 ether);
        usdg.mint(address(this), 1_000_000e6);
        usdg.approve(address(div), type(uint256).max);
    }

    function _mintTo(address who, uint256 n) internal {
        vm.prank(who);
        mifrens.mint{value: 0.01 ether * n}(n);
    }

    // ───────────────────────────────────────────────────────────────────────
    // D-1 (High) — the basket cannot be filled with junk by a stranger.
    //
    // `fundToken` had no access control. `assets` is capped and has no removal
    // path a stranger can reach, so an attacker spent a few token deployments
    // and a few wei to close the basket permanently, after which every genuine
    // quote asset was refused and the hook's fee route to the dividend returned
    // false forever.
    // ───────────────────────────────────────────────────────────────────────
    function test_D1_StrangersCannotConsumeBasketSlots() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        // The attacker is not the funder, not the treasury, not a holder.
        for (uint256 i; i < 4; ++i) {
            Stable junk = new Stable();
            junk.mint(attacker, 1);
            vm.startPrank(attacker);
            junk.approve(address(div), type(uint256).max);
            vm.expectRevert(MiFrensDividend.NotOwner.selector);
            div.fundToken(address(junk), 1);
            vm.stopPrank();
        }
        assertEq(div.assetCount(), 0, "no slot was consumed");

        // USDG — a real, treasury-approved quote asset — still gets in.
        div.fundToken(address(usdg), 1000e6);
        assertEq(div.assetCount(), 1, "the protocol's own fee route is open");
        assertApproxEqAbs(div.pendingToken(1, address(usdg)), 1000e6, 1, "and pays holders");
    }

    // ───────────────────────────────────────────────────────────────────────
    // D-2 (High) — one hostile asset can no longer brick every token claim.
    //
    // `claimTokens` looped the whole list and pushed with a REVERTING helper, so
    // a single token that stopped transferring locked every other asset's
    // accrued dividends in the contract forever, for every holder.
    // ───────────────────────────────────────────────────────────────────────
    function test_D2_AHostileAssetCannotBrickOtherClaims() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        div.fundToken(address(usdg), 1000e6);

        // A token that is fine at funding time and hostile at claim time. Only
        // the funder can introduce it now, so this models the quote asset itself
        // turning hostile rather than an outsider planting one.
        TrapToken trap = new TrapToken();
        trap.mint(address(this), 1e18);
        trap.approve(address(div), type(uint256).max);
        div.fundToken(address(trap), 1e18);
        trap.arm();

        // The claim SUCCEEDS. The good asset is delivered; the bad one is banked
        // rather than reverting the whole call.
        vm.prank(alice);
        div.claimTokens(1);

        assertApproxEqAbs(usdg.balanceOf(alice), 1000e6, 1, "USDG was paid");
        assertApproxEqAbs(
            div.owedAsset(alice, address(trap)), 1e18, 1,
            "the undeliverable asset is banked, not lost"
        );

        // And it stays claimable: once the token behaves, she can pull it.
        vm.prank(alice);
        vm.expectRevert(MiFrensDividend.TransferFailed.selector);
        div.withdrawOwedToken(address(trap));

        trap.armFalse();
        vm.prank(alice);
        div.withdrawOwedToken(address(trap));
        assertApproxEqAbs(trap.balanceOf(alice), 1e18, 1, "recovered after the trap lifts");
        assertEq(div.owedAsset(alice, address(trap)), 0, "and cannot be drawn twice");
    }

    // ───────────────────────────────────────────────────────────────────────
    // D-3 (Medium) — a transfer no longer forfeits accrued ERC20 dividends.
    //
    // `onMiFrenTransfer` settled the ETH ledger into `owed[cur]` but never
    // touched `debtOfAsset`, and there was no mapping to settle into. The next
    // caster's `_castSpell` reset the marker over the top, so the leaver's
    // basket entitlement was not paid, not credited and not reclaimable.
    // ───────────────────────────────────────────────────────────────────────
    function test_D3_TransferSettlesTokenDividendsToTheLeaver() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        (bool ok, ) = address(div).call{value: 1 ether}("");
        assertTrue(ok);
        div.fundToken(address(usdg), 1000e6);

        assertApproxEqAbs(div.pendingToken(1, address(usdg)), 1000e6, 1, "1000 USDG accrued");
        assertApproxEqAbs(div.pending(1), 1 ether, 1, "1 ETH accrued");

        // Alice sells the fren.
        vm.prank(alice);
        mifrens.transferFrom(alice, bob, 1);

        // BOTH ledgers survive the transfer now — this is the symmetry that was
        // missing.
        assertApproxEqAbs(div.owed(alice), 1 ether, 1, "ETH settled, as it always was");
        assertApproxEqAbs(
            div.owedAsset(alice, address(usdg)), 1000e6, 1,
            "and the basket is settled with it"
        );

        // Bob correctly starts from zero.
        vm.prank(bob); div.castSpell(1);
        assertEq(div.pendingToken(1, address(usdg)), 0, "the buyer earns only from here");

        // Alice can actually collect what she earned.
        vm.prank(alice);
        div.withdrawOwedToken(address(usdg));
        assertApproxEqAbs(usdg.balanceOf(alice), 1000e6, 1, "paid to the fren who earned it");
    }

    /// The basket walk runs inside the collection's `_update` under a fixed
    /// forwarded gas budget. With the list full, that settlement must still fit
    /// — otherwise it fails silently inside the try/catch and D-3 returns.
    function test_D3_SettlementFitsTheGasBudgetWithAFullBasket() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);

        address[3] memory toks;
        for (uint256 i; i < 3; ++i) {
            Stable t = new Stable();
            t.mint(address(this), 1000e6);
            t.approve(address(div), type(uint256).max);
            div.fundToken(address(t), 100e6);
            toks[i] = address(t);
        }
        assertEq(div.assetCount(), 3, "basket is full");

        uint256 g0 = gasleft();
        vm.prank(alice);
        mifrens.transferFrom(alice, bob, 1);
        emit log_named_uint("full-basket transfer gas", g0 - gasleft());

        // Every one of the four was settled to Alice, not dropped.
        for (uint256 i; i < 3; ++i) {
            assertApproxEqAbs(
                div.owedAsset(alice, toks[i]), 100e6, 1,
                "each basket asset settled within the gas budget"
            );
        }
        assertEq(div.activeShares(), 0, "and the share was still freed");
    }

    // ───────────────────────────────────────────────────────────────────────
    // INVARIANT I-13 — per-asset solvency.
    //
    // The audit listed this as UNENFORCED, and the first attempt at a fix
    // proved why it matters: a `removeAsset` helper (since dropped) let a fren
    // that cast AFTER an asset was retired keep a zero debt marker, so when the
    // asset was re-added its accumulator resumed from the old high-water mark
    // and that fren was owed the entire history it was never part of — 1005
    // USDG against a pot holding 10.
    //
    // The property that catches the whole class, stated directly: for every
    // asset, what every enchanted fren can claim must be backed by what the
    // contract actually holds. No oracle, no prices — just the identity that
    // per-asset accounting exists to give us.
    // ───────────────────────────────────────────────────────────────────────
    function _assertAssetSolvency(address asset) internal view {
        uint256 claimable;
        for (uint256 id = 1; id <= 6; ++id) {
            try mifrens.ownerOf(id) returns (address) {
                claimable += div.pendingToken(id, asset);
            } catch { /* not minted */ }
        }
        for (uint256 i; i < 3; ++i) {
            claimable += div.owedAsset([alice, bob, attacker][i], asset);
        }
        assertLe(
            claimable, Stable(asset).balanceOf(address(div)),
            "I-13: entitlement exceeds the asset actually held"
        );
    }

    function test_I13_EntitlementNeverExceedsWhatIsHeld() public {
        _mintTo(alice, 1);
        _mintTo(bob, 1);
        vm.prank(alice); div.castSpell(1);

        div.fundToken(address(usdg), 1000e6);
        _assertAssetSolvency(address(usdg));

        // A late joiner must not dilute backing.
        vm.prank(bob); div.castSpell(2);
        _assertAssetSolvency(address(usdg));

        div.fundToken(address(usdg), 500e6);
        _assertAssetSolvency(address(usdg));

        // A claim moves value out; entitlement must fall with it.
        vm.prank(alice); div.claimTokens(1);
        _assertAssetSolvency(address(usdg));

        // A transfer banks the leaver's share — still backed.
        vm.prank(bob); mifrens.transferFrom(bob, attacker, 2);
        _assertAssetSolvency(address(usdg));

        vm.prank(attacker); div.castSpell(2);
        _assertAssetSolvency(address(usdg));

        div.fundToken(address(usdg), 250e6);
        _assertAssetSolvency(address(usdg));
    }
}
