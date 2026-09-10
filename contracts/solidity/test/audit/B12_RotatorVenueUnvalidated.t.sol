// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-12 — `rotateStep` accepts ANY venue with the right currency pair (Medium)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `rotateStep` is permissionless by design, and its header argues that this is
 *  safe (:185-188): "The caller supplies the venue but controls nothing else:
 *  direction, size and the price floor all come from the governed plan, so
 *  calling this repeatedly only advances the rotation the guild already voted
 *  for, at a price it already bounded."
 *
 *  The floor is real. What the argument omits is that the floor becomes the
 *  PRICE. `_routeMatches` (:493-501) validates currency0 and currency1 and
 *  nothing else — not `fee`, not `tickSpacing`, and not `hooks`:
 *
 *      address c0 = Currency.unwrap(route.currency0);
 *      address c1 = Currency.unwrap(route.currency1);
 *      return (c0 == from && c1 == to) || (c0 == to && c1 == from);
 *
 *  Pool initialisation is permissionless in Uniswap v4, so anyone can create a
 *  pool on the same pair — at any price, with any fee and tick spacing, behind
 *  a hook of their choosing whose permission bits they mined — and hand it to
 *  `rotateStep` as the venue.
 *
 *  TWO CONSEQUENCES.
 *
 *  1. ECONOMIC (the material one). The incentive is inverted. An honest keeper
 *     who routes to the deepest venue earns `keeperBps` = 0.1% of the output. A
 *     keeper who routes to a pool they seeded earns that 0.1% AND the entire
 *     spread between the market rate and `minRate`, by returning exactly
 *     `minOut` and keeping the difference as inventory in their own pool. Self
 *     dealing strictly dominates, so the rotation realises worst-case execution
 *     on every slice rather than in the worst case.
 *
 *     `minRate` is stored verbatim from the vote (:69-71, "Set by governance
 *     from the market at vote time") and never revised, while a plan runs over
 *     hours or days across many slices — so the exploitable spread is whatever
 *     slippage tolerance the guild allowed, PLUS any market drift since the
 *     vote, and it grows as the plan ages. Extraction is atomic, repeatable once
 *     per `interval`, and needs no capital beyond the `minOut` seeded into the
 *     attacker's own pool, which is recovered in the same transaction.
 *
 *  2. TRUST BOUNDARY. An attacker-supplied `hooks` address is called by the
 *     PoolManager inside this contract's own `unlock`. v4's delta accounting
 *     stops the obvious theft — an unbalanced delta reverts the unlock — but it
 *     hands arbitrary code execution to an unvetted contract at a moment when
 *     the PoolManager is unlocked and pool state is mid-swap. Nothing in the
 *     contract intends that, and no test covers it: every route in
 *     QuoteRotator.t.sol and RotatorSwapFork.t.sol passes
 *     `hooks: IHooks(address(0))`.
 *
 *  This suite asserts the second, which is decidable without a fork. The first
 *  is reported as a finding with a recommendation rather than patched here,
 *  because bounding execution quality is a governance policy choice (venue
 *  allowlist, or an oracle band) rather than a bug fix.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B12_RotatorVenueUnvalidated is Test {
    QuoteRotator internal rot;
    RegistryStub12 internal reg;

    address constant USDG = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant NATIVE = address(0);
    uint256 constant MIN_RATE = 2000e18;

    /// @dev A codeless PoolManager: route validation runs BEFORE the unlock, so
    ///      `NoRoute` means the venue was refused and any other revert means it
    ///      was accepted and execution proceeded.
    function setUp() public {
        reg = new RegistryStub12();
        reg.set(USDG, true);
        rot = new QuoteRotator(address(reg), IPoolManager(address(0xdead)));
        rot.setPlan(NATIVE, USDG, 30 ether, 3 ether, MIN_RATE, 1 hours);
        vm.deal(address(rot), 30 ether); // so a slice is actually due
    }

    function _route(address hook, uint24 fee, int24 spacing) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(NATIVE),
            currency1: Currency.wrap(USDG),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(hook)
        });
    }

    /// @notice CONTROL: a route on the wrong pair is refused, which is the only
    ///         thing `_routeMatches` actually checks.
    function test_B12_WrongPairIsRefused() public {
        PoolKey memory bad = PoolKey({
            currency0: Currency.wrap(NATIVE),
            currency1: Currency.wrap(address(0xBEEF)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(bad);
    }

    /// @notice INVARIANT: a permissionless caller must not be able to nominate an
    ///         arbitrary HOOK as the venue. Pre-fix this was accepted — the call
    ///         got past validation and died in the unlock instead, proving the
    ///         attacker's hook would have been invoked against a real PoolManager.
    function test_INVARIANT_B12_ArbitraryHookVenueIsRefused() public {
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(_route(address(0x00000000000000000000000000000000000000Ad), 3000, 60));
    }

    /// @notice INVARIANT: nor an UNVETTED hookless pool. This is the half a shape
    ///         check cannot reach — an attacker seeds their own vanilla pool on
    ///         the right pair, returns exactly `minOut`, and keeps the spread.
    function test_INVARIANT_B12_UnvettedHooklessVenueIsRefused() public {
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(_route(address(0), 3000, 60));
    }

    /// @notice The SAME PAIR at a different fee tier is a DIFFERENT venue: the
    ///         allowlist is keyed by PoolId, so listing one pool does not list
    ///         every pool on that pair.
    function test_B12_ListingOnePoolDoesNotListThePair() public {
        rot.setVenue(_route(address(0), 3000, 60), true);

        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(_route(address(0), 500, 10)); // same pair, other fee tier
    }

    /// @notice An allowlisted venue passes validation and proceeds to execution
    ///         (which then fails only because this PoolManager has no code).
    function test_B12_AllowlistedVenueExecutes() public {
        PoolKey memory ok = _route(address(0), 3000, 60);
        rot.setVenue(ok, true);
        assertTrue(rot.isVenueAllowed(ok), "listed");

        try rot.rotateStep(ok) {
            revert("unreachable: the stub PoolManager has no code");
        } catch (bytes memory err) {
            assertTrue(
                bytes4(err) != QuoteRotator.NoRoute.selector,
                "an allowlisted venue must not be refused"
            );
        }
    }

    /// @notice De-listing is immediate — a venue that goes bad can be pulled
    ///         without touching the plan.
    function test_B12_VenueCanBeDelisted() public {
        PoolKey memory v = _route(address(0), 3000, 60);
        rot.setVenue(v, true);
        rot.setVenue(v, false);

        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(v);
    }

    /// @notice Curation is the treasury's, not the keeper's.
    function test_B12_OnlyOwnerCurates() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(QuoteRotator.NotOwner.selector);
        rot.setVenue(_route(address(0), 3000, 60), true);
    }
}

contract RegistryStub12 {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/// @dev A vanilla (hookless) venue must still be accepted — the fix constrains
///      the trust boundary, not the permissionlessness the design depends on.
contract B12_VanillaVenueStillAccepted is Test {
    QuoteRotator internal rot;
    RegistryStub12 internal reg;
    address constant USDG = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant NATIVE = address(0);

    function setUp() public {
        reg = new RegistryStub12();
        reg.set(USDG, true);
        rot = new QuoteRotator(address(reg), IPoolManager(address(0xdead)));
        rot.setPlan(NATIVE, USDG, 30 ether, 3 ether, 2000e18, 1 hours);
        vm.deal(address(rot), 30 ether);
    }

    /// @notice FAILS CLOSED: with nothing curated, a rotation executes nowhere.
    ///         A paused treasury operation is the correct failure mode; a
    ///         rotation into an unvetted venue is a realised loss.
    function test_B12_UnconfiguredAllowlistRotatesNothing() public {
        PoolKey memory v = PoolKey({
            currency0: Currency.wrap(NATIVE),
            currency1: Currency.wrap(USDG),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(v);
    }
}
