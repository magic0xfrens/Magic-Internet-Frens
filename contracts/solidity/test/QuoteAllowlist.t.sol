// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronBase} from "../cauldron/CauldronBase.sol";

/// @dev Phase 1 of the choosable-quote work: the allowlist itself. Nothing reads
///      it yet, so these tests are entirely about the PERMISSION MODEL — who may
///      curate the set, and what can never be removed from it.
contract QuoteAllowlistTest is Test {
    CauldronRegistry registry;

    address constant STRANGER = address(0xDEAD);
    address constant USDG = address(0x5060);
    address constant XNVDA = address(0x6070);

    function setUp() public {
        // poolManager/positionManager/hook are irrelevant here — the allowlist is
        // pure registry state and touches none of them.
        registry = new CauldronRegistry(address(1), address(2), address(3), address(this), 0);
    }

    /// ETH must be usable as a quote from the moment the registry exists, so a
    /// fresh deployment behaves exactly as it did before this feature landed.
    function test_NativeEthAllowedFromConstruction() public view {
        assertTrue(registry.allowedQuote(address(0)), "ETH must be allowed at construction");
    }

    /// The guardrail: ETH can never be removed. It is the fallback every
    /// generation can launch against and the sink a failed non-ETH payout rolls
    /// into, so disallowing it would leave a generation with no valid quote.
    function test_NativeEthCannotBeRemoved() public {
        vm.expectRevert(CauldronBase.NativeQuoteRequired.selector);
        registry.setAllowedQuote(address(0), false);
        assertTrue(registry.allowedQuote(address(0)), "ETH must survive the attempt");
    }

    /// Re-allowing ETH is a no-op rather than an error, so a script that sets the
    /// full desired set each run does not have to special-case it.
    function test_NativeEthCanBeReAllowed() public {
        registry.setAllowedQuote(address(0), true);
        assertTrue(registry.allowedQuote(address(0)));
    }

    function test_OwnerCanCurate() public {
        assertFalse(registry.allowedQuote(USDG), "unknown quote starts disallowed");
        registry.setAllowedQuote(USDG, true);
        assertTrue(registry.allowedQuote(USDG), "owner may add");
        registry.setAllowedQuote(USDG, false);
        assertFalse(registry.allowedQuote(USDG), "owner may remove a non-native quote");
    }

    /// The capture vector this exists to close: a proposer who could curate the
    /// set would add a token they control and drain the pool into it.
    function test_StrangerCannotCurate() public {
        vm.prank(STRANGER);
        vm.expectRevert();
        registry.setAllowedQuote(USDG, true);
        assertFalse(registry.allowedQuote(USDG), "a stranger must not widen the set");
    }

    function test_EmitsOnChange() public {
        vm.expectEmit(true, false, false, true);
        emit CauldronRegistry.QuoteAllowed(XNVDA, true);
        registry.setAllowedQuote(XNVDA, true);
    }

    /// Quotes are independent: allowing one must not implicitly allow another.
    function test_QuotesAreIndependent() public {
        registry.setAllowedQuote(USDG, true);
        assertTrue(registry.allowedQuote(USDG));
        assertFalse(registry.allowedQuote(XNVDA), "allowing one must not allow another");
    }

    // -----------------------------------------------------------------------
    // Phase 2 — a proposal names the quote, and the registry records it
    // -----------------------------------------------------------------------

    /// Generation 1 launches from the presale, before any proposal exists to
    /// name a quote, so it must read as native ETH.
    function test_GenerationOneIsNativeEth() public view {
        assertEq(registry.generationQuote(1), address(0), "gen 1 must be ETH");
    }

    /// An un-set generation reads as ETH rather than reverting, so an existing
    /// deployment that predates this feature behaves exactly as before.
    function test_UnknownGenerationReadsAsEth() public view {
        assertEq(registry.generationQuote(999), address(0), "default must be ETH");
    }

    /// The allowlist is what a proposal is checked against — so a quote the
    /// treasury has not vetted must not be proposable in the first place.
    function test_AllowlistGatesWhatCanBeProposed() public {
        assertFalse(registry.allowedQuote(USDG), "not vetted yet");
        registry.setAllowedQuote(USDG, true);
        assertTrue(registry.allowedQuote(USDG), "now proposable");
    }

    // -----------------------------------------------------------------------
    // The watermark ceiling — the other half of the adoptability invariant
    // -----------------------------------------------------------------------

    address constant WATERMARK = 0xf000000000000000000000000000000000000000;

    /// Tokens are mined ABOVE the watermark, so a quote at or above it could
    /// sort above the token and invert the pool. Refusing it here is what makes
    /// "any allowed quote is adoptable by any generation" an invariant rather
    /// than a hope.
    function test_QuoteAtOrAboveWatermarkIsRefused() public {
        vm.expectRevert(CauldronBase.QuoteAboveWatermark.selector);
        registry.setAllowedQuote(WATERMARK, true);

        vm.expectRevert(CauldronBase.QuoteAboveWatermark.selector);
        registry.setAllowedQuote(address(type(uint160).max), true);

        assertFalse(registry.allowedQuote(WATERMARK), "must not be allowed");
    }

    /// Every real quote asset sits far below the watermark, so the ceiling costs
    /// nothing in practice.
    function test_RealQuoteAssetsAreUnaffected() public {
        address[3] memory real = [
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            0xdAC17F958D2ee523a2206206994597C13D831ec7  // USDT
        ];
        for (uint256 i; i < real.length; ++i) {
            registry.setAllowedQuote(real[i], true);
            assertTrue(registry.allowedQuote(real[i]), "a real quote must be allowlistable");
        }
    }

    /// DISALLOWING must never be blocked by the ceiling — otherwise a quote that
    /// somehow got in could never be removed.
    function test_CeilingNeverBlocksRemoval() public {
        registry.setAllowedQuote(USDG, true);
        registry.setAllowedQuote(USDG, false);
        assertFalse(registry.allowedQuote(USDG));
        // Removing something above the watermark is a no-op, not a revert.
        registry.setAllowedQuote(WATERMARK, false);
    }
}
