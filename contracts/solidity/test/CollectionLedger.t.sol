// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CollectionLedger} from "../cauldron/CollectionLedger.sol";

/**
 * @notice Unit + INVARIANT/fuzz coverage for the CollectionLedger cap table.
 *
 *  The whole collection-floor system's safety rests on ONE property:
 *      totalEntitled == Σ entitledTokens[gen]      (and payouts never exceed it)
 *  If that ever drifts, a collection could redeem tokens the reserve doesn't hold.
 *  Proven two ways: hand-written unit tests for each op (LIVE + crystallized) + the
 *  recycle-ratchet arithmetic, and a stateful fuzz handler that hammers random op
 *  sequences and asserts the invariants after every one.
 */
contract CollectionLedgerTest is Test {
    CollectionLedger ledger;
    address registry = address(this); // this test acts as the registry for unit tests

    function setUp() public {
        ledger = new CollectionLedger(registry);
    }

    // ── LIVE (pre-death) redemption — the new capability ──────────────────────

    /// A live collection: credit accrues the floor, redeem pays it, and every OTHER
    /// NFT's floor is unchanged — all WITHOUT crystallizing (brew still alive).
    function test_Live_CreditRedeem_NoCrystallize() public {
        ledger.credit(3, 1_000e18);            // fees/royalties bought 1000 token
        uint256 minted = 10;                    // collection.totalMinted()
        assertEq(ledger.outstanding(3, minted), 10);
        assertEq(ledger.floorPerNFT(3, minted), 100e18);
        assertFalse(ledger.crystallized(3), "redeemable while alive");

        uint256 payout = ledger.redeem(3, minted);
        assertEq(payout, 100e18, "paid the floor");
        assertEq(ledger.retired(3), 1);
        assertEq(ledger.outstanding(3, minted), 9);
        assertEq(ledger.entitledTokens(3), 900e18);
        assertEq(ledger.totalEntitled(), 900e18);
        assertEq(ledger.floorPerNFT(3, minted), 100e18, "remaining floor UNCHANGED (900/9)");
    }

    /// A new gacha mint (mintedNow grows) DILUTES the live floor, as it should.
    function test_Live_MintDilutesFloor() public {
        ledger.credit(3, 1_000e18);
        assertEq(ledger.floorPerNFT(3, 10), 100e18);
        assertEq(ledger.floorPerNFT(3, 20), 50e18, "20 minted halves the floor");
    }

    /// Buyback for 2× floor un-retires the NFT and RATCHETS the floor up — live.
    function test_Live_Buyback_RatchetsFloor() public {
        ledger.credit(3, 1_000e18);
        uint256 minted = 10;
        uint256 payout = ledger.redeem(3, minted);   // 900/9 = 100, retired=1
        uint256 floorMid = ledger.floorPerNFT(3, minted);

        ledger.buyback(3, minted, 2 * payout);        // pay 200, retired→0 → 1100/10 = 110
        assertEq(ledger.retired(3), 0);
        assertEq(ledger.entitledTokens(3), 1_100e18);
        assertEq(ledger.totalEntitled(), 1_100e18);
        assertGt(ledger.floorPerNFT(3, minted), floorMid);
        assertEq(ledger.floorPerNFT(3, minted), 110e18);
    }

    function test_Buyback_NothingRetiredReverts() public {
        ledger.credit(3, 1_000e18);
        vm.expectRevert(CollectionLedger.NothingRetired.selector);
        ledger.buyback(3, 10, 100e18);
    }

    // ── Crystallize (death) — freezes the supply, redemption unchanged ─────────

    /// Crystallize snapshots the mint count; post-death reads ignore mintedNow and
    /// use the frozen supply. Live redemptions before death carry over via `retired`.
    function test_Crystallize_FreezesSupply_CarriesRetired() public {
        ledger.credit(3, 1_000e18);
        ledger.redeem(3, 10);                 // one recycled live → retired=1
        ledger.crystallize(3, 10, 0);         // brew dies with 10 minted
        assertTrue(ledger.crystallized(3));
        assertEq(ledger.frozenSupply(3), 10);
        // mintedNow is now IGNORED — uses frozenSupply(10) − retired(1) = 9.
        assertEq(ledger.outstanding(3, 999999), 9, "frozen supply, not live mint count");
        assertEq(ledger.floorPerNFT(3, 0), 100e18, "900/9");
    }

    function test_Crystallize_FoldsExtraEntitled() public {
        ledger.credit(3, 1_000e18);
        ledger.crystallize(3, 10, 500e18);    // final sizing folds in
        assertEq(ledger.entitledTokens(3), 1_500e18);
        assertEq(ledger.totalEntitled(), 1_500e18);
        assertEq(ledger.floorPerNFT(3, 0), 150e18);
    }

    function test_Crystallize_TwiceReverts() public {
        ledger.crystallize(3, 10, 1_000e18);
        vm.expectRevert(CollectionLedger.AlreadyCrystallized.selector);
        ledger.crystallize(3, 5, 500e18);
    }

    // ── Cross-cutting ─────────────────────────────────────────────────────────

    function test_Credit_GrowsFloor() public {
        ledger.crystallize(3, 10, 1_000e18);
        ledger.credit(3, 500e18);             // royalty/fee inflow, post-death
        assertEq(ledger.entitledTokens(3), 1_500e18);
        assertEq(ledger.totalEntitled(), 1_500e18);
        assertEq(ledger.floorPerNFT(3, 0), 150e18);
    }

    /// Multiple collections share the pot independently; totalEntitled == Σ.
    function test_MultiCollection_SumsHold() public {
        ledger.credit(3, 1_000e18);           // live
        ledger.crystallize(4, 6, 600e18);     // dead, floor 100
        ledger.credit(5, 1e18);               // tiny live
        ledger.redeem(3, 10);                 // live redeem
        ledger.redeem(4, 0);                  // dead redeem → retired 1
        ledger.buyback(4, 0, 300e18);         // now there's a retired NFT to buy
        ledger.credit(5, 20e18);
        assertEq(
            ledger.totalEntitled(),
            ledger.entitledTokens(3) + ledger.entitledTokens(4) + ledger.entitledTokens(5),
            "sum invariant holds across collections + ops"
        );
    }

    function test_Redeem_NothingOutstandingReverts() public {
        // no credit, no mints → outstanding 0
        vm.expectRevert(CollectionLedger.NothingOutstanding.selector);
        ledger.redeem(9, 0);
    }

    function test_Redeem_FullyDrained_ThenReverts() public {
        ledger.credit(3, 30e18);
        ledger.redeem(3, 3); ledger.redeem(3, 3); ledger.redeem(3, 3);
        assertEq(ledger.outstanding(3, 3), 0);
        vm.expectRevert(CollectionLedger.NothingOutstanding.selector);
        ledger.redeem(3, 3);
    }

    function test_OnlyRegistry() public {
        ledger.credit(3, 100e18);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CollectionLedger.OnlyRegistry.selector);
        ledger.redeem(3, 2);
    }
}

/**
 * @notice Stateful INVARIANT test — its own ledger whose `registry` IS the handler,
 *         so the fuzzer drives every op across thousands of random sequences and we
 *         assert the invariants after each.
 */
contract CollectionLedgerInvariant is Test {
    CollectionLedger ledger;
    LedgerHandler handler;

    function setUp() public {
        handler = new LedgerHandler();
        ledger = handler.ledger();
        targetContract(address(handler));
    }

    /// totalEntitled must always equal the sum of every collection's entitlement.
    function invariant_TotalEntitledEqualsSum() public view {
        uint256 sum;
        uint256[] memory gens = handler.gens();
        for (uint256 i = 0; i < gens.length; i++) sum += ledger.entitledTokens(gens[i]);
        assertEq(ledger.totalEntitled(), sum, "totalEntitled must equal sum of entitledTokens");
    }

    /// Conservation: tokens ever put in minus tokens ever paid out == the pot.
    function invariant_ConservationOfTokens() public view {
        assertEq(ledger.totalEntitled(), handler.ghost_in() - handler.ghost_out(), "in minus out == pot");
    }
}

/**
 * @notice Fuzz handler: the ledger's `registry` is this handler, so it drives every
 *         op with random inputs while tracking ghost totals + a per-gen live mint
 *         count (only grows) so `outstanding` is always well-formed.
 */
contract LedgerHandler is Test {
    CollectionLedger public ledger;
    uint256 public ghost_in;
    uint256 public ghost_out;
    uint256[] private _gens;
    mapping(uint256 => bool) private _seen;
    mapping(uint256 => uint256) public minted; // live mint count per gen (monotonic)

    constructor() {
        ledger = new CollectionLedger(address(this));
    }

    function gens() external view returns (uint256[] memory) {
        return _gens;
    }

    function _track(uint256 gen) private {
        if (!_seen[gen]) { _seen[gen] = true; _gens.push(gen); }
    }

    function _mintedNow(uint256 gen) private view returns (uint256) {
        return ledger.crystallized(gen) ? ledger.frozenSupply(gen) : minted[gen];
    }

    function hMint(uint256 genSeed, uint256 n) external {
        uint256 gen = bound(genSeed, 1, 20);
        if (ledger.crystallized(gen)) return;
        minted[gen] += bound(n, 1, 100);
        _track(gen);
    }

    function hCredit(uint256 genSeed, uint256 amt) external {
        uint256 gen = bound(genSeed, 1, 20);
        amt = bound(amt, 1, 1e28);
        ledger.credit(gen, amt);
        ghost_in += amt;
        _track(gen);
    }

    function hRedeem(uint256 genSeed) external {
        uint256 gen = bound(genSeed, 1, 20);
        uint256 m = _mintedNow(gen);
        if (ledger.outstanding(gen, m) == 0) return;
        ghost_out += ledger.redeem(gen, m);
    }

    function hBuyback(uint256 genSeed, uint256 paid) external {
        uint256 gen = bound(genSeed, 1, 20);
        if (ledger.retired(gen) == 0) return;
        paid = bound(paid, 1, 1e28);
        ledger.buyback(gen, _mintedNow(gen), paid);
        ghost_in += paid;
    }

    function hCrystallize(uint256 genSeed, uint256 extra) external {
        uint256 gen = bound(genSeed, 1, 20);
        if (ledger.crystallized(gen)) return;
        extra = bound(extra, 0, 1e28);
        // freeze at the current live mint count (>= retired by construction)
        ledger.crystallize(gen, minted[gen], extra);
        if (extra != 0) ghost_in += extra;
        _track(gen);
    }
}
