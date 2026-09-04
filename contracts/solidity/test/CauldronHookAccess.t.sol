// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../vendor/HookMiner.sol";
import {CauldronHook} from "../CauldronHook.sol";
import {IDeathChecker} from "../cauldron/IDeathChecker.sol";
import {ISurtaxPolicy, IOddsPolicy, ICurvePolicy} from "../cauldron/IPolicies.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

// Policy mocks: fixed returns so we can assert delegation + clamp + fallback.
contract FixedSurtax is ISurtaxPolicy {
    uint256 immutable v; constructor(uint256 _v){v=_v;}
    function surtaxBps(PoolId, uint256, uint256, uint256) external view returns (uint256){return v;}
}
contract FixedOdds is IOddsPolicy {
    uint256 immutable v; constructor(uint256 _v){v=_v;}
    function oddsBps(uint256, uint256, uint256) external view returns (uint256){return v;}
}
contract FixedCurve is ICurvePolicy {
    uint256 immutable v; constructor(uint256 _v){v=_v;}
    function priceAt(uint256, uint256, uint256) external view returns (uint256){return v;}
}

/// Always-dead checker (for testing the module override).
contract AlwaysDeadChecker is IDeathChecker {
    function isDead(PoolId, uint256, uint256) external pure returns (bool) { return true; }
}
/// Always-alive checker.
contract NeverDeadChecker is IDeathChecker {
    function isDead(PoolId, uint256, uint256) external pure returns (bool) { return false; }
}
/// Reverting checker — must fall back to the built-in rule, never brick.
contract BrokenChecker is IDeathChecker {
    function isDead(PoolId, uint256, uint256) external pure returns (bool) { revert("boom"); }
}

/**
 * Regression (audit F1): the hook's `registry` — the only address allowed to
 * pull the relaunch ETH reserve — must be settable ONCE. A mutable setter let
 * the hook owner repoint it to an address they control and drain relaunchETH via
 * releaseRelaunchETH(). setRegistry is now one-time + non-zero.
 */
contract CauldronHookAccessTest is Test {
    CauldronHook hook;

    function setUp() public {
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        // poolManager can be any address for this test — we never swap; the
        // BaseHook constructor only validates the address's permission bits.
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(1)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(address(1)), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");
    }

    function test_SetRegistry_IsOneTime() public {
        hook.setRegistry(address(0xBEEF));
        assertEq(hook.registry(), address(0xBEEF), "first set");

        // A second set — the drain vector — must revert.
        vm.expectRevert(CauldronHook.RegistryAlreadySet.selector);
        hook.setRegistry(address(0xDEAD));
        assertEq(hook.registry(), address(0xBEEF), "registry unchanged");
    }

    function test_SetRegistry_RejectsZero() public {
        vm.expectRevert(CauldronHook.ZeroAddress.selector);
        hook.setRegistry(address(0));
    }

    function test_SetRegistry_OnlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(); // Ownable: caller is not the owner
        hook.setRegistry(address(0xBEEF));
    }

    // Tax exemption (deployer snipe): owner can flag/unflag; others cannot.
    function test_TaxExempt_OwnerOnly() public {
        address snipe = address(0x51195E);
        assertFalse(hook.taxExempt(snipe));
        hook.setTaxExempt(snipe, true);
        assertTrue(hook.taxExempt(snipe), "exempt set");
        hook.setTaxExempt(snipe, false);
        assertFalse(hook.taxExempt(snipe), "exempt cleared");

        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronHook.OnlyRegistry.selector);
        hook.setTaxExempt(snipe, true);
    }

    // F-13: fee exemption must ONLY be honoured for swaps routed through a trusted
    // opener. A direct swap can't dodge the fee by tagging an exempt address in
    // hookData. We assert the gate via the router registry: exemption requires
    // isOpener[sender], which _isExemptPlayer enforces (private, so we assert the
    // observable pieces: an exempt address is set, but no opener is trusted yet).
    function test_ExemptionGatedToOpener() public {
        address exemptWallet = address(0xE7);
        hook.setTaxExempt(exemptWallet, true);
        assertTrue(hook.taxExempt(exemptWallet), "wallet flagged exempt");

        // With NO opener registered, even a hookData tag can't be trusted — the
        // fee path is only skipped when isOpener[sender]. A non-opener router
        // (address(0xF00)) is not trusted:
        assertFalse(hook.isOpener(address(0xF00)), "arbitrary sender is not an opener");

        // Registering the honest router as an opener is what enables the exempt
        // launch buy — the intended, gated path.
        hook.setOpener(address(0xF00), true);
        assertTrue(hook.isOpener(address(0xF00)), "router opener trusted");
    }

    // Pluggable death module: overrides the built-in rule, falls back safely, and
    // is owner/registry-gated.
    function test_DeathChecker_Module() public {
        PoolId id = PoolId.wrap(bytes32(uint256(0xABCD)));
        hook.trackPool(id); // owner-tracked; 0 volume < 1e18 threshold -> dead by default
        assertTrue(hook.isDead(id), "built-in: 0 volume is dead");

        // Override: NeverDead flips it alive even at 0 volume.
        hook.setDeathChecker(address(new NeverDeadChecker()));
        assertFalse(hook.isDead(id), "module overrides -> alive");

        // Override: AlwaysDead.
        hook.setDeathChecker(address(new AlwaysDeadChecker()));
        assertTrue(hook.isDead(id), "module overrides -> dead");

        // A reverting module must NOT brick isDead -> falls back to built-in rule.
        hook.setDeathChecker(address(new BrokenChecker()));
        assertTrue(hook.isDead(id), "broken module -> built-in fallback (0 vol = dead)");

        // Clear -> back to built-in.
        hook.setDeathChecker(address(0));
        assertEq(address(hook.deathChecker()), address(0));
        assertTrue(hook.isDead(id));

        // Only owner/registry may set.
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronHook.OnlyRegistry.selector);
        hook.setDeathChecker(address(0xDEAD));
    }

    // Policy modules: delegate, clamp to hard caps, safe fallback, access-gated.
    function test_PolicyModules() public {
        PoolId id = PoolId.wrap(bytes32(uint256(0x1)));
        hook.trackPool(id);

        // ── Surtax: module overrides, and is CLAMPED to MAX_SNIPE_BPS ──
        hook.setPolicies(address(new FixedSurtax(1234)), address(0), address(0));
        assertEq(hook.snipeSurtaxBps(id), 1234, "surtax module delegated");
        hook.setPolicies(address(new FixedSurtax(99999)), address(0), address(0));
        assertEq(hook.snipeSurtaxBps(id), hook.MAX_SNIPE_BPS(), "surtax clamped to cap");

        // ── Odds: module overrides, CLAMPED to ODDS_HARD_CAP_BPS ──
        hook.setPolicies(address(0), address(new FixedOdds(4000)), address(0));
        assertEq(hook.oddsForPlay(1 ether), 4000, "odds module delegated");
        hook.setPolicies(address(0), address(new FixedOdds(99999)), address(0));
        assertEq(hook.oddsForPlay(1 ether), hook.ODDS_HARD_CAP_BPS(), "odds clamped to cap");

        // ── Curve: module overrides; a ZERO cost is ignored (guard) → built-in ──
        hook.setPolicies(address(0), address(0), address(new FixedCurve(7e15)));
        assertEq(hook.nftPriceAt(0), 7e15, "curve module delegated");
        hook.setPolicies(address(0), address(0), address(new FixedCurve(0)));
        assertEq(hook.nftPriceAt(3), hook.volumePerNFT() + 3 * hook.nftPriceStep(), "zero-cost guard -> built-in");

        // ── clear all → back to built-in ──
        hook.setPolicies(address(0), address(0), address(0));
        assertEq(address(hook.surtaxPolicy()), address(0));
        assertEq(address(hook.oddsPolicy()), address(0));
        assertEq(address(hook.curvePolicy()), address(0));

        // access-gated
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronHook.OnlyRegistry.selector);
        hook.setPolicies(address(1), address(2), address(3));
    }
}
