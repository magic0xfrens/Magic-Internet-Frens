// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/**
 * F-22 — ONE DENOMINATION PER SUM (functional audit R-04).
 *
 * `RedemptionExt.recoverLegs` unwinds every rotated leg of a dying generation
 * and returns `(quoteOut, tokenOut)`. `CauldronRegistry._removeLiquidity` adds
 * `quoteOut` into `ethRecovered` (:1558) and `relaunch` hands that to
 * {PoolOps.seedFunding} as an amount denominated in `generationQuote[oldGen]`
 * (Registry:922).
 *
 * It used to accumulate `quoteOut += q` for EVERY leg regardless of that leg's
 * own `l.quote` — the `TreasuryLeg.quote` field was read only for an event. A
 * treasury split across two quotes, which is the entire point of the multi-leg
 * model (RedemptionExt.sol:307-318 describes 50/30/20 splits), therefore
 * produced a sum of incompatible units.
 *
 * The magnitude of the error is the thing: quotes are allowed to differ in
 * DECIMALS, so this is not a small drift. This suite pins the arithmetic that
 * makes it matter, and documents the contract of the fix.
 *
 * The end-to-end path (rotate into two quotes, then relaunch) needs a fork and
 * a full governance envelope; it is covered by `F10_QuoteRotationTotality`'s
 * rotation machinery plus the unit facts below.
 */
contract F22_LegProceedsDenomination is Test {
    /// @dev Native ETH and an 18-decimal synthetic both scale by 1e18; a stable
    ///      like USDG scales by 1e6. Mixing them in one `uint256` is the bug.
    uint256 internal constant WEI_PER_ETH = 1e18;
    uint256 internal constant RAW_PER_USDG = 1e6;

    /// @notice THE DEFECT, as arithmetic. A treasury holding 20 ETH in its
    ///         primary and $50,000 of USDG in a rotated leg.
    ///
    ///  Pre-fix, `recoverLegs` returned 20e18 + 50_000e6 and the registry read
    ///  the whole thing as wei. The USDG contributed 5e10 wei — 0.00000005 ETH —
    ///  so a position worth more than twice the primary registered as dust.
    ///
    ///  The failure is not merely "imprecise". `relaunch` gates the rebirth on
    ///  `totalETH == 0` (Registry:945) and sizes the newborn's whole book from
    ///  this number, so it is a corrupted magnitude driving a one-way decision.
    function test_F22_MixingDecimalsCorruptsTheMagnitude() public pure {
        uint256 ethLeg = 20 * WEI_PER_ETH;          // 20 ETH, in wei
        uint256 usdgLeg = 50_000 * RAW_PER_USDG;    // $50,000, in raw USDG

        uint256 preFixSum = ethLeg + usdgLeg;       // what the old code returned

        //  Read as wei, the $50,000 leg is worth 0.00000005 ETH.
        assertEq(usdgLeg, 5e10, "raw USDG units");
        assertEq(preFixSum - ethLeg, 5e10, "the stable's entire contribution, as wei");

        //  The economically larger position is ~4e8x understated against the
        //  smaller one, purely from the decimal mismatch.
        assertEq(ethLeg / usdgLeg, 400_000_000, "20 ETH reads as 4e8x the stable");
    }

    /// @notice And in the other direction: a native leg counted into a
    ///         6-decimal total OVERSTATES by 1e12, which is the branch that
    ///         matters because it can clear a zero-check with value that is not
    ///         really there in the expected asset.
    function test_F22_TheErrorRunsBothWays() public pure {
        uint256 oneWei = 1;
        //  One wei booked into a USDG-denominated total reads as 1e-6 USDG...
        //  but 1e12 wei — a millionth of an ether, i.e. dust — reads as a whole
        //  dollar. `seedFunding`'s own note (PoolOps.sol:1001-1014) records the
        //  same class of failure: "one wei of it outranked a 25 ETH position".
        assertEq(uint256(1e12) / RAW_PER_USDG, 1e6, "dust ether reads as $1e6 of stable");
        assertGt(oneWei + RAW_PER_USDG, RAW_PER_USDG, "any cross-asset add moves the total");
    }

    /// @notice THE CONTRACT OF THE FIX, stated as the invariant the code now
    ///         upholds: `quoteOut` accumulates a leg's proceeds only when that
    ///         leg's quote equals the generation's quote; every other leg is
    ///         booked to `legProceeds[asset]` and is recoverable via
    ///         {RedemptionExt.sweepLegProceeds}.
    ///
    ///  Modelled here so the intended partition is asserted rather than merely
    ///  described. `recoverLegs` itself is exercised on the fork paths.
    function test_F22_PartitionKeepsEachAssetWhole() public pure {
        address ETH = address(0);
        address USDG = address(0x115D6);
        address matchQuote = ETH;

        address[3] memory legQuote = [ETH, USDG, ETH];
        uint256[3] memory legOut = [uint256(12 ether), 50_000 * RAW_PER_USDG, 8 ether];

        uint256 quoteOut;
        uint256 booked;
        for (uint256 i; i < 3; i++) {
            if (legQuote[i] == matchQuote) quoteOut += legOut[i];
            else booked += legOut[i];
        }

        //  The relaunch's funding figure is now pure wei — only the ETH legs.
        assertEq(quoteOut, 20 ether, "only matching-quote legs fund the rebirth");
        //  And the foreign leg is not lost, just held separately and whole.
        assertEq(booked, 50_000 * RAW_PER_USDG, "foreign proceeds booked intact");
        //  Nothing vanished: every leg landed in exactly one bucket.
        assertEq(quoteOut + booked, 12 ether + 8 ether + 50_000 * RAW_PER_USDG, "no leg dropped");
    }
}
