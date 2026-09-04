// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";

/**
 * @title LedgerInvariants
 * @notice Stateful INVARIANT suite for {CollectionLedger} — the cap table that
 *         decides how much of the shared redemption reserve every dead brew's NFT
 *         collection may claim.
 *
 *  Invariants under test (see the audit report, §Invariants):
 *    L-1  totalEntitled == Σ_gen entitledTokens[gen]            (accounting closure)
 *    L-2  a `redeem` never changes the floor of the REMAINING NFTs by more than
 *         integer dust                                          (no floor theft)
 *    L-3  entitledTokens[gen] never exceeds what was ever credited to it
 *         (the ledger can never invent a claim on the reserve)  (Invariant R feeder)
 *    L-4  outstanding(gen) is monotone-consistent with retired[] (no underflow)
 *
 *  Run:
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract LedgerInvariants
 *  (No fork required.)
 */
contract LedgerHandler is Test {
    CollectionLedger public ledger;

    uint256 public constant GENS = 4;
    /// ghost: everything ever credited into a generation (credit + buyback + crystallize)
    mapping(uint256 => uint256) public ghostCreditedIn;
    /// ghost: everything ever paid out of a generation (redeem)
    mapping(uint256 => uint256) public ghostPaidOut;
    /// ghost: live mint count the registry would report for a generation
    mapping(uint256 => uint256) public ghostMinted;

    uint256 public calls;

    constructor() {
        ledger = new CollectionLedger(address(this));
    }

    function _gen(uint256 seed) internal pure returns (uint256) {
        return (seed % GENS) + 1;
    }

    function mintNfts(uint256 seed, uint256 n) external {
        uint256 g = _gen(seed);
        n = bound(n, 1, 50);
        ghostMinted[g] += n;
        calls++;
    }

    function credit(uint256 seed, uint256 amount) external {
        uint256 g = _gen(seed);
        amount = bound(amount, 1, 1_000_000e18);
        ledger.credit(g, amount);
        ghostCreditedIn[g] += amount;
        calls++;
    }

    function redeem(uint256 seed) external {
        uint256 g = _gen(seed);
        if (ledger.outstanding(g, ghostMinted[g]) == 0) return;
        uint256 payout = ledger.redeem(g, ghostMinted[g]);
        ghostPaidOut[g] += payout;
        calls++;
    }

    function buyback(uint256 seed, uint256 paid) external {
        uint256 g = _gen(seed);
        if (ledger.retired(g) == 0) return;
        paid = bound(paid, 1, 1_000_000e18);
        ledger.buyback(g, ghostMinted[g], paid);
        ghostCreditedIn[g] += paid;
        calls++;
    }

    function crystallize(uint256 seed, uint256 extra) external {
        uint256 g = _gen(seed);
        if (ledger.crystallized(g)) return;
        extra = bound(extra, 0, 1_000_000e18);
        ledger.crystallize(g, ghostMinted[g], extra);
        ghostCreditedIn[g] += extra;
        calls++;
    }
}

contract LedgerInvariants is StdInvariant, Test {
    LedgerHandler handler;
    CollectionLedger ledger;

    function setUp() public {
        handler = new LedgerHandler();
        ledger = handler.ledger();
        targetContract(address(handler));
    }

    /// L-1: the global sum equals the per-generation sum, always.
    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 64
    function invariant_totalEntitledEqualsSum() public view {
        uint256 sum;
        for (uint256 g = 1; g <= handler.GENS(); g++) sum += ledger.entitledTokens(g);
        assertEq(ledger.totalEntitled(), sum, "L-1: totalEntitled drifted from the per-gen sum");
    }

    /// L-3: a generation can never be entitled to more than was credited to it.
    ///      This is what makes the registry's reserve sizing sufficient — the
    ///      ledger cannot invent a claim on the shared reserve LP.
    function invariant_entitlementNeverExceedsCredited() public view {
        for (uint256 g = 1; g <= handler.GENS(); g++) {
            assertLe(
                ledger.entitledTokens(g) + handler.ghostPaidOut(g),
                handler.ghostCreditedIn(g),
                "L-3: entitlement exceeds everything ever credited"
            );
        }
    }

    /// L-4: `outstanding` is well-formed (no underflow, never above supply).
    function invariant_outstandingWellFormed() public view {
        for (uint256 g = 1; g <= handler.GENS(); g++) {
            uint256 minted = handler.ghostMinted(g);
            uint256 o = ledger.outstanding(g, minted);
            uint256 supply = ledger.crystallized(g) ? ledger.frozenSupply(g) : minted;
            assertLe(o, supply, "L-4: outstanding above supply");
            if (supply >= ledger.retired(g)) {
                assertEq(o, supply - ledger.retired(g), "L-4: outstanding != supply - retired");
            } else {
                assertEq(o, 0, "L-4: outstanding must floor at zero");
            }
        }
    }
}

/**
 * @notice Pure FUZZ tests for the ledger's floor arithmetic — the property that a
 *         recycle must not move anyone else's floor (beyond integer dust), which
 *         is the economic promise of the legacy-floor design.
 */
contract LedgerFloorFuzz is Test {
    CollectionLedger ledger;

    function setUp() public {
        ledger = new CollectionLedger(address(this));
    }

    /// L-2: after a redeem, the floor of the remaining NFTs is unchanged up to
    ///      integer division dust (strictly: it never DECREASES).
    function testFuzz_RedeemDoesNotLowerTheFloorForOthers(uint256 minted, uint256 entitled) public {
        minted = bound(minted, 2, 100_000);
        entitled = bound(entitled, 1e18, 1e30);
        ledger.credit(1, entitled);

        uint256 floorBefore = ledger.floorPerNFT(1, minted);
        vm.assume(floorBefore > 0);
        uint256 payout = ledger.redeem(1, minted);
        uint256 floorAfter = ledger.floorPerNFT(1, minted);

        assertEq(payout, floorBefore, "payout must equal the pre-redeem floor");
        assertGe(floorAfter, floorBefore, "L-2: a recycle must never dilute the remaining holders");
    }

    /// A buyback at 2x floor strictly RATCHETS the floor up (the design claim).
    function testFuzz_BuybackRatchetsTheFloorUp(uint256 minted, uint256 entitled) public {
        minted = bound(minted, 3, 100_000);
        entitled = bound(entitled, 1e21, 1e30);
        ledger.credit(1, entitled);

        uint256 f0 = ledger.floorPerNFT(1, minted);
        vm.assume(f0 > 0);
        ledger.redeem(1, minted);              // one NFT into the treasury
        uint256 f1 = ledger.floorPerNFT(1, minted);
        ledger.buyback(1, minted, 2 * f1);     // resold at 2x floor
        uint256 f2 = ledger.floorPerNFT(1, minted);

        assertGe(f2, f0, "buyback must ratchet the floor at or above where it started");
    }

    /// The accounting closure holds for any sequence of credit/redeem/buyback.
    function testFuzz_ClosureUnderRandomOps(uint96[8] calldata amounts, uint8 opBits, uint256 minted) public {
        minted = bound(minted, 1, 10_000);
        uint256 credited;
        uint256 paid;
        for (uint256 i; i < 8; i++) {
            uint256 a = uint256(amounts[i]);
            if (a == 0) a = 1;
            if ((opBits >> (i % 8)) & 1 == 1 && ledger.outstanding(1, minted) > 0 && ledger.entitledTokens(1) > 0) {
                paid += ledger.redeem(1, minted);
            } else {
                ledger.credit(1, a);
                credited += a;
            }
        }
        assertEq(ledger.totalEntitled(), ledger.entitledTokens(1), "single-gen closure");
        assertEq(ledger.entitledTokens(1) + paid, credited, "credit == entitled + paid out");
    }
}
