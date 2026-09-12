// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronVault} from "../../cauldron/CauldronVault.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {PoolOps} from "../../cauldron/PoolOps.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * @notice Z-02 — REGRESSION. A stranger's ether donation to a LIVE floor vault
 *         used to inflate the dead collection's crystallised entitlement toward
 *         100% of the newborn's entire active tranche, one-shot and permanent.
 *
 *  THE CHAIN, as the production code runs it:
 *    CauldronVault.receive()          — open to anyone
 *    CauldronVault.close()            — swept = address(this).balance
 *    PoolOps.seedFunding branch 2     — totalETH = recovered + vaultSwept + hookPull
 *                                       (PoolOps.sol:1082-1084), and it reports
 *                                       `vaultSwept` as the third return
 *    CauldronRegistry.sol:1080-1082   — feeds both into crystallizeCollection
 *    PoolOps.sol:1380                 — entitled = swept * activeBase / totalETH
 *    CollectionLedger.crystallize     — ONE-SHOT (AlreadyCrystallized), and nothing
 *                                       in the ledger ever lowers totalEntitled
 *    CauldronRegistry.sol:1057-1063   — subtracts totalEntitled from newActive at
 *                                       EVERY future relaunch
 *
 *  Because the numerator sits INSIDE the denominator, a donation D drives
 *  (V+D)/(L+V+D) -> 1. This test drives the real contracts through that chain and
 *  asserts the donation now changes NOTHING about the entitlement — while still
 *  reaching the registry, so no value is stranded.
 *
 *  The fix is in {CauldronVault}: `close()` reports PROTOCOL-ACCOUNTED deposits
 *  (clamped to the live balance) instead of the raw balance. PoolOps was NOT
 *  edited — its formula is correct once its numerator stops being third-party
 *  controlled.
 */
contract Z2VaultDonationEntitlement is Test {
    /// The newborn's whole tradeable tranche, the thing being claimed a share of.
    uint256 internal constant ACTIVE_BASE = 800_000_000e18;
    /// Funding for the newborn that did NOT come out of the dying vault
    /// (`recovered` from the dead LP + the hook's relaunch reserve).
    uint256 internal constant OTHER_FUNDING = 9 ether;
    /// What the protocol itself routed into the floor vault over the generation.
    uint256 internal constant PROTOCOL_FEES = 1 ether;

    address internal constant HOOK = address(0x400C);
    address internal constant ALICE = address(0xA11CE);
    address internal constant DONOR = address(0xD0405);

    CollectionLedger internal ledger;
    uint256 internal genCounter;

    receive() external payable {}

    function setUp() public {
        // This test contract stands in for the registry: it owns the ledger, it is
        // the collection's controller, and it is the only address that may close a
        // vault — exactly the three roles CauldronRegistry holds in production.
        ledger = new CollectionLedger(address(this));
        vm.deal(HOOK, 10_000 ether);
        vm.deal(DONOR, 10_000 ether);
        vm.deal(address(this), 10_000 ether);
    }

    /// @dev A live brew: a collection whose minter is the hook, its floor vault,
    ///      and `mintCount` NFTs in circulation.
    function _brew(uint256 mintCount)
        internal
        returns (CauldronCollection col, CauldronVault vault)
    {
        col = new CauldronCollection(
            "Gen", "GEN", HOOK, address(this), 1000,
            MetadataMode.BaseURI, "ipfs://gen/", address(0), address(0), uint96(0)
        );
        vault = new CauldronVault(address(col), address(this), 0);
        col.setVault(address(vault));
        vm.startPrank(HOOK);
        for (uint256 i; i < mintCount; ++i) col.mint(ALICE);
        vm.stopPrank();
    }

    /// @dev Fee ether routed in by the hook — the collection's `minter`, which is
    ///      the only address that does this in production (FeeRouteLib._move).
    function _protocolFund(CauldronVault vault, uint256 amount) internal {
        vm.prank(HOOK);
        (bool ok, ) = address(vault).call{value: amount}("");
        assertTrue(ok, "protocol deposit");
    }

    /// @dev Anyone at all, through the open `receive()`.
    function _donate(CauldronVault vault, uint256 amount) internal {
        vm.prank(DONOR);
        (bool ok, ) = address(vault).call{value: amount}("");
        assertTrue(ok, "donation accepted");
    }

    /// @dev Replays `seedFunding` branch 2 + `crystallizeCollection` exactly:
    ///      `totalETH` is the sum the branch returns, which INCLUDES the reported
    ///      sweep, and the same reported sweep is the numerator.
    function _dieAndCrystallize(CauldronCollection col, CauldronVault vault)
        internal
        returns (uint256 swept, uint256 entitled)
    {
        swept = vault.close();
        uint256 totalETH = OTHER_FUNDING + swept;
        entitled = PoolOps.crystallizeCollection(
            address(ledger), address(col), address(vault), ++genCounter, swept, ACTIVE_BASE, totalETH
        );
    }

    // ── the attack ─────────────────────────────────────────────────────────

    function test_DonationCannotInflateTheCrystallisedEntitlement() public {
        // ---- CONTROL: an honestly funded vault crystallizes its true share ----
        (CauldronCollection colA, CauldronVault vaultA) = _brew(4);
        _protocolFund(vaultA, PROTOCOL_FEES);
        assertEq(vaultA.accountedDeposits(), PROTOCOL_FEES, "protocol deposit is accounted");
        (uint256 sweptA, uint256 entitledA) = _dieAndCrystallize(colA, vaultA);

        assertEq(sweptA, PROTOCOL_FEES, "control: the whole protocol deposit is reported");
        uint256 honestShare = (PROTOCOL_FEES * ACTIVE_BASE) / (OTHER_FUNDING + PROTOCOL_FEES);
        assertEq(entitledA, honestShare, "control: 1 of 10 ether bought 10% of the tranche");
        assertEq(entitledA * 10, ACTIVE_BASE, "control: exactly one tenth");

        // ---- ATTACK: the identical brew, plus a stranger's 999 ether ----------
        uint256 donation = 999 ether;
        (CauldronCollection colB, CauldronVault vaultB) = _brew(4);
        _protocolFund(vaultB, PROTOCOL_FEES);
        _donate(vaultB, donation);

        assertEq(address(vaultB).balance, PROTOCOL_FEES + donation, "the donation really is in the vault");
        assertEq(vaultB.accountedDeposits(), PROTOCOL_FEES, "FIXED: a donation is not accounted");

        uint256 registryBalBefore = address(this).balance;
        (uint256 sweptB, uint256 entitledB) = _dieAndCrystallize(colB, vaultB);

        // What the OLD code would have crystallized from the same state, from the
        // same formula with the raw balance as the numerator. This is the attack.
        uint256 rawSweep = PROTOCOL_FEES + donation;
        uint256 oldEntitled = (rawSweep * ACTIVE_BASE) / (OTHER_FUNDING + rawSweep);
        assertGt(oldEntitled * 100, ACTIVE_BASE * 99,
            "the attack was real: the raw-balance numerator crystallized >99% of the tranche");

        // The fix.
        assertEq(sweptB, PROTOCOL_FEES, "FIXED: close() reports only protocol-accounted ether");
        assertEq(entitledB, entitledA, "FIXED: 999 ether of donation moved the entitlement by zero");
        assertLt(entitledB * 9, ACTIVE_BASE, "FIXED: still barely a tenth of the newborn tranche");

        // NOTHING IS STRANDED: every wei, donation included, left for the registry.
        assertEq(address(vaultB).balance, 0, "vault emptied");
        assertEq(address(this).balance - registryBalBefore, rawSweep,
            "the registry received the donation too - it is liquidity, just not a claim");

        // AND THE DAMAGE THAT MADE THIS A HIGH IS GONE: totalEntitled is what the
        // registry subtracts from every future generation's active tranche.
        assertEq(ledger.totalEntitled(), entitledA + entitledB, "no phantom legacy claim");
        assertLt(ledger.totalEntitled(), ACTIVE_BASE, "future generations are not capped out");
    }

    /// A donation still does what a donation should: it lifts the redeemable floor
    /// for every holder while the brew is alive. The fix bounds what is COUNTED,
    /// not what may arrive — `selfdestruct` and coinbase payments cannot be gated.
    function test_DonationStillRaisesTheLiveFloorForHolders() public {
        (, CauldronVault vault) = _brew(4);
        _protocolFund(vault, PROTOCOL_FEES);
        assertEq(vault.floorPerNFT(), PROTOCOL_FEES / 4, "floor from protocol fees");

        _donate(vault, 3 ether);
        assertEq(vault.floorPerNFT(), (PROTOCOL_FEES + 3 ether) / 4, "the donation lifts the floor");

        uint256 before = ALICE.balance;
        vm.prank(ALICE);
        uint256 paid = vault.redeem(1);
        assertEq(paid, (PROTOCOL_FEES + 3 ether) / 4, "a holder really can take it");
        assertEq(ALICE.balance - before, paid, "and it arrives");
    }

    /// Redemptions before death must not leave `close()` over-reporting: the
    /// accounted high-water mark is clamped to the live balance.
    function test_AccountedSweepIsClampedByRedemptions() public {
        (CauldronCollection col, CauldronVault vault) = _brew(4);
        _protocolFund(vault, 4 ether);

        vm.prank(ALICE);
        vault.redeem(1); // takes 1 ether
        assertEq(address(vault).balance, 3 ether, "one quarter redeemed");
        assertEq(vault.accountedDeposits(), 4 ether, "the high-water mark does not fall");

        (uint256 swept, ) = _dieAndCrystallize(col, vault);
        assertEq(swept, 3 ether, "reported sweep is clamped to what is actually there");
    }
}
