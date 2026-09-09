// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {PoolOps} from "../cauldron/PoolOps.sol";

/**
 * @dev The watermark invariant, asserted as ONE property across BOTH halves.
 *
 *  "Any allowed quote is adoptable by any generation" rests on two constants in
 *  two different files agreeing with each other:
 *
 *    FLOOR   {PoolOps.QUOTE_WATERMARK}      — every token is mined ABOVE this
 *    CEILING {CauldronBase.QUOTE_WATERMARK} — no quote at/above this is allowed
 *
 *  They are duplicated deliberately: CauldronBase.sol:103 explains that importing
 *  the library constant would give the registry a link-time dependency for a
 *  compile-time value. That comment then says "the invariant test asserts they
 *  match" — and until this file, no such test existed.
 *
 *  The halves are each covered ({MinedTokenAddressTest} mines above a literal,
 *  {QuoteAllowlistTest} refuses above a literal) but both check against their OWN
 *  hardcoded copy of 0xf000…, so there were FOUR copies and nothing comparing
 *  any two of them. Raise the floor without raising the ceiling and every
 *  existing test still passes while quotes in the gap become allowlistable AND
 *  able to sort above a token — inverting currency0/currency1, which is the one
 *  orientation all of PoolOps/ReserveLib/SeedLib is written for.
 *
 *  These tests therefore compare the constants through OBSERVABLE BEHAVIOUR
 *  rather than reading either literal, so they cannot drift with the thing they
 *  are checking.
 */
contract QuoteWatermarkInvariantTest is Test {
    CauldronRegistry registry;

    uint256 constant SUPPLY = 777_000_000e18;

    function setUp() public {
        // Same shape as QuoteAllowlistTest: the allowlist is pure registry state
        // and touches neither the pool manager nor the hook.
        registry = new CauldronRegistry(address(1), address(2), address(3), address(this), 0);
    }

    /// @dev Can this address be allowlisted as a quote? Probed rather than read,
    ///      because the ceiling is `internal` — and because probing tests the
    ///      behaviour the rest of the system actually depends on.
    function _allowlistable(uint160 q) internal returns (bool ok) {
        (ok, ) = address(registry).call(
            abi.encodeWithSelector(registry.setAllowedQuote.selector, address(q), true, uint256(1e18))
        );
    }

    /// @dev The registry's effective ceiling: the LOWEST address it refuses.
    ///      Binary search over the whole address space, so it finds the real
    ///      boundary wherever it moves to.
    function _discoverCeiling() internal returns (uint160) {
        uint160 lo = 1; // trivially allowlistable
        uint160 hi = type(uint160).max; // must be refused
        assertTrue(_allowlistable(lo), "a low address must be allowlistable");
        assertFalse(_allowlistable(hi), "the top of the space must be refused");

        while (hi - lo > 1) {
            uint160 mid = lo + (hi - lo) / 2;
            if (_allowlistable(mid)) lo = mid;
            else hi = mid;
        }
        return hi;
    }

    // ---------------------------------------------------------------------
    // The assertion CauldronBase.sol:105 promises
    // ---------------------------------------------------------------------

    /// The ceiling the registry enforces must be exactly the floor PoolOps mines
    /// above. This is the test that comment refers to.
    function test_TheTwoWatermarksMatch() public {
        uint160 ceiling = _discoverCeiling();
        assertEq(
            ceiling,
            uint160(PoolOps.QUOTE_WATERMARK),
            "registry ceiling must equal the PoolOps mining floor"
        );
    }

    // ---------------------------------------------------------------------
    // The property both halves exist to produce
    // ---------------------------------------------------------------------

    /// The composed invariant: nothing the registry will ever allow can sort
    /// above anything the machine will ever mint. Uses the WORST case the
    /// allowlist permits (ceiling - 1), not a realistic quote, because the
    /// guarantee has to hold at the boundary or it is not a guarantee.
    function test_NoAllowlistableQuoteCanOutsortAnyToken() public {
        uint160 worstQuote = _discoverCeiling() - 1;
        assertTrue(_allowlistable(worstQuote), "the boundary quote must really be allowed");

        // Every generation, not just one — the property must hold for every token
        // the machine will ever mint.
        for (uint256 gen = 2; gen < 14; ++gen) {
            (address token, ) = PoolOps.deployTokenAbove(
                string.concat("Gen", vm.toString(gen)), "G", gen, SUPPLY, address(0)
            );
            assertGt(
                uint160(token),
                worstQuote,
                "an allowlistable quote sorted above an iteration token"
            );
        }
    }

    /// An ETH-launched token is the case the watermark exists for: it is mined
    /// against address(0), so nothing about its launch forces it above a quote
    /// it might adopt LATER. It must still clear the boundary quote.
    function test_EthLaunchedTokenStillClearsTheBoundaryQuote() public {
        uint160 worstQuote = _discoverCeiling() - 1;

        (address token, address quoteUsed) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, SUPPLY, address(0));

        assertEq(quoteUsed, address(0), "it launches against ETH");
        assertGt(uint160(token), worstQuote, "yet remains adoptable by any allowed quote");
    }
}
