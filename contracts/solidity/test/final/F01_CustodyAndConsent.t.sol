// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FinalAuditBase, FinalMockToken} from "./FinalAuditBase.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";

/**
 * @title F01 — custody, consent and fee-accounting attacks (no fork required)
 * @notice Every test here drives PRODUCTION bytecode and asserts that the
 *         protocol now PREVENTS the exploit. A failing test means the defect is
 *         back.
 *
 *  Covered findings:
 *    F-02  irrevocable auto-migrate consent  (registry)
 *    F-03  legacy sweep silently forgets owed tokens (hook)
 *    F-09  dividend enchantment hook is gas-starvable (MiFrensGenesis)
 */
contract F01_CustodyAndConsent is FinalAuditBase {
    FinalMockToken internal tok;

    function setUp() public {
        _deployOffchain(address(0xBEEFCAFE));
        tok = new FinalMockToken();
    }

    // ---------------------------------------------------------------------
    // F-02 — auto-migrate consent must be revocable
    // ---------------------------------------------------------------------

    /// @notice ATTACK: a holder opts in to hands-off migration, then changes their
    ///         mind — they now prefer the iteration they hold. Before the fix there
    ///         was no `disableAutoMigrate`, so the flag that authorises ANY keeper to
    ///         burn their entire old-generation balance (via the registry-only
    ///         `CauldronToken.burn`, which needs no allowance) was permanent.
    ///         Consent must be withdrawable; assert it now is.
    function test_F02_AutoMigrateConsentIsRevocable() public {
        address holder = address(0xA11CE);
        // NOTE: read the fee FIRST — an inline `registry.AUTO_MIGRATE_FEE()` inside
        // the argument list would consume the `vm.prank`.
        uint256 fee = registry.AUTO_MIGRATE_FEE();
        vm.deal(holder, 1 ether);

        vm.prank(holder);
        registry.enableAutoMigrate{value: fee}();
        assertTrue(registry.autoMigrate(holder), "opted in");

        // THE FIX: the holder can withdraw the standing authorisation, for free.
        vm.prank(holder);
        registry.disableAutoMigrate();
        assertFalse(registry.autoMigrate(holder), "consent revoked");

        // And re-opting in still costs the fee (revocation is not a fee bypass).
        vm.prank(holder);
        vm.expectRevert();
        registry.enableAutoMigrate{value: 0}();
    }

    /// @notice Revocation must not be gated behind the emergency/owner roles — a
    ///         permission you granted yourself must be yours to withdraw.
    function test_F02_RevocationIsSelfServiceOnly() public {
        address holder = address(0xA11CE);
        address other = address(0xB0B);
        uint256 fee = registry.AUTO_MIGRATE_FEE();
        vm.deal(holder, 1 ether);
        vm.prank(holder);
        registry.enableAutoMigrate{value: fee}();

        // A third party revoking `other` must not touch `holder` (per-caller flag).
        vm.prank(other);
        registry.disableAutoMigrate();
        assertTrue(registry.autoMigrate(holder), "third party cannot revoke for you");
        assertFalse(registry.autoMigrate(other), "and only clears their own");
    }

    // ---------------------------------------------------------------------
    // F-03 — the legacy sweep must debit only what actually moved
    // ---------------------------------------------------------------------

    /// @notice ATTACK / BUG: `sweepLegacyReserve` zeroed `legacyOwedToReserve`
    ///         unconditionally and only then clamped the transfer to the live
    ///         balance. Any state with `balance < owed` therefore destroyed the
    ///         difference: those tokens sit in the hook, are credited to no
    ///         collection's floor, and no later sweep can find them because the
    ///         counter that remembered them is gone.
    ///
    ///         We stage `owed = 100e18` with only `40e18` actually held (the shape a
    ///         partially-filled buyback or a token-mismatched sweep produces) and
    ///         assert the remainder survives.
    function test_F03_PartialSweepKeepsTheRemainderClaimable() public {
        // The registry is the only address allowed to sweep; point the hook's
        // legacy registry at this test so we can call it directly.
        hook.setLegacyBuyback(address(this), 4000, 0.02 ether);

        vm.store(address(hook), bytes32(SLOT_LEGACY_OWED), bytes32(uint256(100e18)));
        tok.mint(address(hook), 40e18);

        uint256 moved = hook.sweepLegacyReserve(address(tok), address(this));

        assertEq(moved, 40e18, "sweeps exactly what it holds");
        assertEq(tok.balanceOf(address(this)), 40e18, "registry received it");
        // THE FIX: the un-transferred 60e18 is still owed, not forgotten.
        assertEq(hook.legacyOwedToReserve(), 60e18, "remainder still owed to the reserve");

        // A second sweep, once the balance is topped up, recovers the rest — proof
        // the value was never lost.
        tok.mint(address(hook), 60e18);
        uint256 moved2 = hook.sweepLegacyReserve(address(tok), address(this));
        assertEq(moved2, 60e18, "remainder recoverable");
        assertEq(hook.legacyOwedToReserve(), 0, "fully settled");
    }

    /// @notice The happy path is unchanged: a fully-backed sweep still clears the
    ///         counter exactly, so the "credit never out-runs the reserve" property
    ///         (the registry credits exactly the returned amount) is preserved.
    function testFuzz_F03_SweepDebitsExactlyWhatMoved(uint128 owed, uint128 bal) public {
        hook.setLegacyBuyback(address(this), 4000, 0.02 ether);
        vm.store(address(hook), bytes32(SLOT_LEGACY_OWED), bytes32(uint256(owed)));
        tok.mint(address(hook), bal);

        uint256 before = hook.legacyOwedToReserve();
        uint256 moved = hook.sweepLegacyReserve(address(tok), address(this));

        assertEq(moved, owed < bal ? owed : bal, "moved == min(owed, balance)");
        assertEq(hook.legacyOwedToReserve(), before - moved, "counter debited by exactly the move");
        assertEq(tok.balanceOf(address(this)), moved, "recipient got exactly the move");
    }

    /// @notice Only the wired legacy registry may sweep the hook's held tokens.
    function test_F03_SweepIsRegistryGated() public {
        hook.setLegacyBuyback(address(this), 4000, 0.02 ether);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        hook.sweepLegacyReserve(address(tok), address(0xBAD));
    }

    // ---------------------------------------------------------------------
    // F-09 — the dividend enchantment hook must not be gas-starvable
    // ---------------------------------------------------------------------

    /// @notice ATTACK: `_update` wrapped the dividend's `onMiFrenTransfer` in a bare
    ///         `try/catch`. EIP-150 forwards 63/64 of the remaining gas, so a seller
    ///         who sizes the transaction's gas precisely can make that child call run
    ///         out of gas while the transfer itself still completes — and `try/catch`
    ///         swallows an OOG exactly like a revert.
    ///
    ///         The pay-off is threefold and is precisely what the M-06 comment in
    ///         that function says it prevents: the sold fren stays in `activeShares`
    ///         (diluting every honest holder while earning for nobody), the accrual
    ///         over the BUYER's ownership is later paid to the SELLER via the stale
    ///         branch of `_castSpell`, and that branch skips `_collectEnchantFee` so
    ///         the buyer re-enchants free.
    ///
    ///         After the fix the transfer REVERTS rather than silently proceeding
    ///         with broken accounting, so the attacker cannot choose failure.
    /// @dev The exploit window, measured by sweeping the gas budget in 2.5k steps
    ///      against the PRE-FIX contract: at 117,500–130,000 the transfer SETTLES
    ///      while the dividend hook is starved; from 132,500 up the hook runs. Any
    ///      value inside that band reproduces the attack, so we pick its middle.
    uint256 internal constant GRIEF_GAS = 125_000;

    function test_F09_GasStarvedTransferIsRefused() public {
        (MiFrensGenesis frens, MiFrensDividend div, address seller, uint256 id) = _wireDividend();

        // The spell is cast: the fren is in the earning set.
        assertTrue(div.isEnchanted(id), "enchanted");
        assertEq(div.activeShares(), 1, "one active share");

        // The attacker transfers with a hand-picked gas budget from the measured
        // window. Pre-fix this SUCCEEDED with `activeShares` left at 1 — the sold
        // fren kept diluting everyone while earning for nobody, its accrual was
        // later paid to the SELLER through `_castSpell`'s stale branch, and that
        // branch skipped `_collectEnchantFee` so the buyer re-enchanted free.
        vm.prank(seller);
        (bool ok,) = address(frens).call{gas: GRIEF_GAS}(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", seller, address(0xB0B), id)
        );
        assertFalse(ok, "gas-starved transfer must not settle");

        // State is untouched: the seller still owns it and the share is intact.
        assertEq(frens.ownerOf(id), seller, "transfer rolled back");
        assertEq(div.activeShares(), 1, "active share accounting intact");
        assertTrue(div.isEnchanted(id), "still enchanted by its real owner");
    }

    /// @notice The whole measured window must be closed, not just its midpoint —
    ///         otherwise the attacker simply retunes their gas.
    function test_F09_TheEntireGriefWindowIsClosed() public {
        for (uint256 g = 110_000; g <= 132_000; g += 2_000) {
            (MiFrensGenesis frens, MiFrensDividend div, address seller, uint256 id) = _wireDividend();
            vm.prank(seller);
            (bool ok,) = address(frens).call{gas: g}(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", seller, address(0xB0B), id)
            );
            // Either the transfer did not settle, or it settled WITH the hook having
            // run. What must never happen is "settled but the share is still active".
            if (ok) {
                assertEq(div.activeShares(), 0, "a settled transfer always breaks the spell");
            } else {
                assertEq(div.activeShares(), 1, "a refused transfer changes nothing");
            }
        }
    }

    /// @notice CONTROL: the same transfer with a normal gas budget succeeds AND
    ///         settles the enchantment — the fix must not break the ordinary path.
    function test_F09_NormalTransferStillBreaksTheSpell() public {
        (MiFrensGenesis frens, MiFrensDividend div, address seller, uint256 id) = _wireDividend();

        vm.prank(seller);
        frens.transferFrom(seller, address(0xB0B), id);

        assertEq(frens.ownerOf(id), address(0xB0B), "transferred");
        assertEq(div.activeShares(), 0, "spell broken, share freed");
        assertFalse(div.isEnchanted(id), "no longer earning");
    }

    /// @notice A dividend that genuinely REVERTS must still never brick a transfer —
    ///         the fix tightens the gas contract, it does not remove the try/catch.
    function test_F09_RevertingDividendStillCannotBrickTransfers() public {
        (MiFrensGenesis frens,, address seller, uint256 id) = _wireDividend();
        // Repoint the dividend at a contract whose hook always reverts.
        frens.setDividend(address(new RevertingDividend()));

        vm.prank(seller);
        frens.transferFrom(seller, address(0xB0B), id);
        assertEq(frens.ownerOf(id), address(0xB0B), "transfer survives a hostile dividend");
    }

    /// @dev Presale + dividend wired, with an enchanted FORGED-tranche fren
    ///      (id > GENESIS_SUPPLY) held by `seller` and real fee value deposited.
    ///
    ///      The forged tranche is the exploitable one: `_update` only pays for the
    ///      `everMoved` SSTORE when `tokenId <= GENESIS_SUPPLY`, so for a forged id
    ///      the work AFTER the dividend call is nearly free — and it is precisely
    ///      that post-call work which otherwise consumes the 1/64 of gas the parent
    ///      retains, making the outer transfer fail alongside the starved child.
    ///      It is also the tranche that PAYS the re-enchant fee, so it is exactly
    ///      where dodging `_collectEnchantFee` is worth something.
    function _wireDividend()
        private
        returns (MiFrensGenesis frens, MiFrensDividend div, address seller, uint256 id)
    {
        frens = new MiFrensGenesis("MiFrens", "MIFREN", 4, 8, 0.01 ether, 10, "ipfs://f/");
        div = new MiFrensDividend(address(frens), address(this));
        frens.setDividend(address(div));

        seller = address(0xA11CE);
        vm.deal(seller, 1 ether);
        vm.prank(seller);
        frens.mint{value: 0.04 ether}(4); // sell out the genesis tranche (ids 1..4)

        // Mint one FORGED fren by volume (this test stands in for the hook).
        frens.setMinter(address(this));
        id = frens.mint(seller);

        vm.prank(seller);
        div.castSpell(id);

        // Fee inflow so `owed`/`debtOf` writes are the expensive non-zero case.
        (bool ok,) = address(div).call{value: 0.05 ether}("");
        require(ok, "fund");
    }
}

/// @notice A dividend whose transfer hook always reverts — used to prove the
///         try/catch still protects transfers after the gas-floor fix.
contract RevertingDividend {
    function onMiFrenTransfer(uint256, address) external pure {
        revert("nope");
    }
}
