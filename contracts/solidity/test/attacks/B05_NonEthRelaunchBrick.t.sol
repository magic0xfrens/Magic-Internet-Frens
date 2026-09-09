// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {YBase} from "./YBase.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-05 — NON-ETH RELAUNCH PERMANENTLY BRICKED THE MACHINE   [CRITICAL — FIXED]
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  ── THE BUG (as found, on the pre-fix tree) ───────────────────────────────
 *
 *  The multi-quote relaunch path was UNIMPLEMENTED, and every way it failed was
 *  an unguarded revert sitting BEHIND `governor.markConsumed(winId)`
 *  (CauldronRegistry.sol:825). Three independent walls; the machine died on
 *  whichever it reached first, and clearing one only advanced it to the next:
 *
 *    WALL 1 — CauldronRegistry.sol:787,920. `relaunch()` accumulates the dead
 *      generation's value as NATIVE WEI (`ethFromLP + ethFromHook + vaultSwept`)
 *      and hands that number straight to the seeder as the QUOTE amount. Nothing
 *      converts it (QuoteRotator exists for exactly that and is never called),
 *      nothing rescales it. The registry holds none of the quote, so the
 *      PositionManager's pull reverted. Measured, pre-fix:
 *          ERC20InsufficientBalance(registry, 0, 19999999999999987150)
 *      — the 20 ETH recovered from the dead pool, requested verbatim as USDG.
 *      (Live USDG is 6 decimals, so a funded registry would have asked for
 *      20 trillion USDG and priced the newborn pool from it.)
 *
 *    WALL 1b — `PoolOps.createAndSeedWithBuy`. Fund the registry and the pull
 *      succeeds; the green-candle buy then settles NATIVE ether into a pool whose
 *      currency0 is an ERC20, leaving a currency delta open →
 *      `CurrencyNotSettled()`. The hook guards this exact limitation on its own
 *      buyback with an early return (CauldronHook.sol:950-960, "ETH-LAYOUT ONLY,
 *      for now"); the seeder did not guard it at all.
 *
 *    WALL 2 — CauldronHook.sol:1642. `setLiveKey` reverted unless
 *      `currency0 == address(0)`, but `PoolOps` puts the quote at currency0 by
 *      construction (:194/250/324) and mines the token above it
 *      (`deployTokenAbove`), so an ERC20-quoted generation always tripped it.
 *
 *  Because the revert rolled `markConsumed` back, the poisoned proposal stayed
 *  unconsumed, kept winning `CauldronGovernor._bestUnconsumed()`, and EVERY
 *  later `relaunch()` died at the same line. Permanent and unrecoverable except
 *  by a privileged, timelocked de-listing — which then launched the generation
 *  against ETH anyway, not the pair the frens voted for.
 *
 *  Reachable with NO ATTACKER: `indexer/deployments/round.json` ships USDG
 *  (0xeDFd2eA3…) and xNVDA (0x4F3Df1F4…) as live `quoteAssets` with UI copy
 *  inviting the choice. A proposer picking an offered option froze the protocol.
 *
 *  ── THE FIX ───────────────────────────────────────────────────────────────
 *
 *  Defence in depth, all three layers asserted below:
 *
 *    1. {CauldronGovernor.propose} REFUSES a non-native quote outright, at the
 *       boundary where a revert is free (it rejects one proposal and freezes
 *       nothing) — the same discipline the `nftSupply` bound above it already
 *       applies, citing audit C-02.
 *    2. {CauldronRegistry.relaunch} forces `specQuote = address(0)` at
 *       consumption. The governor is swappable, so it cannot be the only line of
 *       defence. This is the same clamp-never-revert pattern used for
 *       `nftSupply` (:817-820), `newActive` (:902-910) and the mining fallback
 *       (PoolOps:493-496).
 *    3. {CauldronHook.setLiveKey} no longer asserts a native currency0. That
 *       check could only ever fire on the mandatory rebirth path, where its
 *       failure mode was "the protocol can never be reborn" — a landmine, not a
 *       guard. It is a plain storage write again.
 *
 *  SCOPE, STATED HONESTLY: this does NOT implement a non-ETH rebirth. It makes
 *  the unsupported case DEGRADE (to a native relaunch) instead of BRICKING. A
 *  generation may still be quoted in any approved asset via the deliberate,
 *  reversible `RedemptionExt.rotateSlice`. Lifting layers 1+2 requires building
 *  all three legs — convert `totalETH` through the rotator, give PoolOps a
 *  non-native settle, keep `setLiveKey` general.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B05_NonEthRelaunchBrick is YBase {
    MockQuoteToken internal usdg;
    BGovQuoted internal gov;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        // A quote asset that sorts BELOW PoolOps.QUOTE_WATERMARK (0xf000…), which
        // is what `setAllowedQuote` requires. Deployment addresses are effectively
        // random in the low 93.75% of the space, so the first candidate all but
        // always qualifies; loop defensively rather than rely on it.
        for (uint256 i; i < 32; ++i) {
            MockQuoteToken c = new MockQuoteToken("Magic USD", "USDG", 6);
            if (uint160(address(c)) < uint160(0xf000000000000000000000000000000000000000)) {
                usdg = c;
                break;
            }
        }
        require(address(usdg) != address(0), "no sub-watermark quote");

        // Vet the quote exactly as the live deployment does (round.json lists it).
        registry.setAllowedQuote(address(usdg), true, 1e18);

        // A governor whose winning proposal names that vetted quote — the UI's
        // "park the LP in the stable pair" path. This mock bypasses the real
        // governor's propose-time refusal on purpose: it models a SWAPPED
        // governor, which is exactly the case the registry-side clamp exists for.
        gov = new BGovQuoted(address(usdg));
        registry.setGovernor(address(gov));

        // Make the generation genuinely dead and past its minimum lifetime, so
        // `relaunch()` clears every gate ahead of the seed.
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        vm.roll(block.number + 60);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  THE INVARIANT — the protocol must always be able to be reborn
    // ───────────────────────────────────────────────────────────────────────

    /// @notice INVARIANT (the whole point of the fix): a dead generation whose
    ///         winning proposal names a NON-NATIVE quote must still relaunch, and
    ///         the winning proposal must be CONSUMED so it cannot be re-elected
    ///         forever. Pre-fix this reverted `TRANSFER_FROM_FAILED` and the
    ///         proposal survived to brick every retry.
    function test_FIXED_B05_NonNativeProposalStillRelaunches() public {
        vm.skip(!active);

        registry.relaunch();

        assertEq(registry.currentGeneration(), 2, "the machine must be able to rebirth");
        assertEq(gov.consumedCount(), 1, "and the proposal must be CONSUMED, not re-elected");
    }

    /// @notice The registry-side clamp: the generation is seeded NATIVE regardless
    ///         of what the (swapped) governor named. This is the documented
    ///         degrade — not a silent success at building a USDG pool.
    function test_FIXED_B05_QuoteIsClampedToNative() public {
        vm.skip(!active);

        registry.relaunch();

        assertEq(
            registry.generationQuote(2),
            address(0),
            "relaunch must seed native - the value it seeds with IS native wei"
        );
    }

    /// @notice REGRESSION: the brick was permanent because `markConsumed` rolled
    ///         back with the revert. Drive several rebirths back to back; each must
    ///         consume its proposal and advance the generation. If the fix were
    ///         reverted, the first call here would revert and the count would stick.
    function test_FIXED_B05_RepeatedRebirthsNeverStick() public {
        vm.skip(!active);

        for (uint256 i; i < 3; ++i) {
            uint256 genBefore = registry.currentGeneration();
            registry.relaunch();
            assertEq(registry.currentGeneration(), genBefore + 1, "generation must advance");

            // Re-arm the death + lifetime gates for the next cycle.
            hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
            _warp(registry.minLifetime() + 1 days + 1);
            vm.roll(block.number + 60);
        }
        assertEq(registry.currentGeneration(), 4, "three consecutive rebirths");
        assertEq(gov.consumedCount(), 3, "each one consumed its proposal");
    }

    /// @notice WALL 2, isolated: `setLiveKey` must accept a key whose currency0 is
    ///         an ERC20 quote — the shape every pool `PoolOps` builds. The old
    ///         assertion could only fire on the mandatory rebirth path, so its
    ///         failure mode was a permanent freeze.
    ///
    ///  Safe to generalise on its own terms: `_afterSwap`'s credit gate compares
    ///  `key.currency1` against `_liveKey.currency1`, and the iteration token is at
    ///  currency1 in EVERY pool PoolOps constructs (:195/251/325/672) because
    ///  `deployTokenAbove` mines it above QUOTE_WATERMARK and no quote at or above
    ///  that watermark can be allowlisted. The gate keeps comparing the unique
    ///  per-generation token, never a shared quote.
    function test_FIXED_B05_SetLiveKeyAcceptsANonNativeKey() public {
        vm.skip(!active);

        PoolKey memory usdgKey = PoolKey({
            currency0: Currency.wrap(address(usdg)), // the quote, per PoolOps:194
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });

        vm.prank(address(registry));
        hook.setLiveKey(usdgKey); // must not revert

        assertEq(
            Currency.unwrap(hook.liveKey().currency0),
            address(usdg),
            "the key must be recorded verbatim"
        );
    }

    /// @notice Still gated: only the registry may set the live key. Generalising
    ///         the currency check must not have widened the authority.
    function test_SetLiveKeyStillRegistryOnly() public {
        vm.skip(!active);

        PoolKey memory k = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });

        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronHook.OnlyRegistry.selector);
        hook.setLiveKey(k);
    }

    /// @notice Control: the ETH-quoted path — the one that always worked — is
    ///         untouched by the fix.
    function test_Control_EthQuotedProposalRelaunchesFine() public {
        vm.skip(!active);

        registry.setGovernor(address(new BGovQuoted(address(0))));

        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "an ETH-quoted rebirth completes");
        assertEq(registry.generationQuote(2), address(0), "and is native");
    }
}

/// @dev A governor whose winning proposal names an arbitrary quote, and which
///      COUNTS consumption so the tests can prove the proposal is retired rather
///      than rolled back. Deliberately does NOT implement the real governor's
///      propose-time refusal — it models a SWAPPED governor, which is precisely
///      the scenario the registry-side clamp is the belt-and-braces for.
///      YBase.YGov and ZAuditBase.ZMockGovernor both hardcode
///      `quote: address(0)`, which is why this path went untested for four passes.
contract BGovQuoted is ICauldronGovernor {
    address public immutable quote;
    uint256 public consumedCount;

    constructor(address _quote) {
        quote = _quote;
    }

    function hasProposals() external pure returns (bool) {
        return true;
    }

    function markConsumed(uint256) external {
        consumedCount += 1;
    }

    function winner() external view returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Stable Wraith",
            symbol: "SWRAITH",
            mode: MetadataMode.BaseURI,
            baseURI: "ipfs://swraith/",
            renderer: address(0),
            website: "w.xyz",
            socials: "x.com/w",
            quote: quote,
            nftSupply: 1000,
            volumePerNFT: 0,
            proposer: address(0xBEEF)
        });
        id = 1;
    }
}
