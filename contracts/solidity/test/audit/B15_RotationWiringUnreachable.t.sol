// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-15 — THE TREASURY ROTATION IS UNREACHABLE: NOTHING WRITES ITS WIRING
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `RedemptionExt.rotateSlice` is the only path that moves treasury liquidity
 *  between quotes. It opens by reading two storage slots:
 *
 *      address rot = quoteRotator;      // RedemptionExt.sol:216
 *      if (rot == address(0)) revert NotConfigured();
 *      address gov = treasuryGovernor;  // RedemptionExt.sol:225
 *      if (gov == address(0)) revert NotConfigured();
 *
 *  Both are declared in `CauldronBase` (`quoteRotator` slot 50, `treasuryGovernor`
 *  slot 51) and are **never assigned anywhere in the codebase**. Grepped across
 *  every non-test `.sol`: the only references are those two declarations and
 *  those two reads.
 *
 *  The intended setter looks like it exists — `CauldronRegistry.sol:235`:
 *
 *      function setRotationWiring(address, address) external { _forwardToExt(); }
 *
 *  but `_forwardToExt` DELEGATECALLs into `RedemptionExt`, and `RedemptionExt`
 *  defines no `setRotationWiring` and carries no fallback. The delegatecall
 *  therefore finds no matching selector and reverts, so the two slots can never
 *  leave zero.
 *
 *  CONSEQUENCE. Every treasury rotation reverts `NotConfigured`, on every
 *  deployment that has ever existed, regardless of governance. The whole
 *  feature — the envelope vote, the slicing, the venue allowlist, the quote
 *  rotation the UI is built around — is unreachable code.
 *
 *  This is why the live deployment shows no rotation activity, and it is not a
 *  deployment oversight: no deploy script could have fixed it.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B15_RotationWiringUnreachable is Test {
    CauldronRegistry internal registry;

    function setUp() public {
        // A bare registry is enough: the wiring setter is reached before any
        // pool state matters.
        registry = new CauldronRegistry(address(this), address(this), address(this), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
    }

    /// @notice THE FINDING. The only setter for the rotation wiring reverts,
    ///         because the facet it forwards to does not implement it.
    function test_INVARIANT_B15_RotationWiringCanBeSet() public {
        address rotator = address(0x1111111111111111111111111111111111111111);
        address governor = address(0x2222222222222222222222222222222222222222);

        (bool ok, ) = address(registry).call(
            abi.encodeWithSignature("setRotationWiring(address,address)", rotator, governor)
        );

        assertTrue(ok, "setRotationWiring must be callable, or rotation can never be enabled");
    }

    /// @notice And because it cannot be set, the rotation itself is dead: it
    ///         reverts on the very first line, before any governance is
    ///         consulted.
    function test_INVARIANT_B15_RotateSliceIsReachable() public {
        // Wire it FIRST — that is the whole point. Pre-fix this call reverted,
        // so the slots stayed zero and the assertion below was unreachable for
        // any caller, not just this test.
        registry.setRotationWiring(
            address(0x1111111111111111111111111111111111111111),
            address(0x2222222222222222222222222222222222222222)
        );

        PoolKey memory route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0x3333333333333333333333333333333333333333)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });

        (bool ok, bytes memory err) = address(registry).call(
            abi.encodeWithSignature(
                "rotateSlice(uint16,uint256,(address,address,uint24,int24,address))",
                uint16(2500), uint256(0), route
            )
        );

        // `NotConfigured()` here means the wiring slots are still zero — which
        // they must be, since nothing can write them.
        assertTrue(
            ok || bytes4(err) != bytes4(keccak256("NotConfigured()")),
            "rotateSlice must not be permanently unconfigured"
        );
    }
}

/**
 * @dev The two failure states must be distinguishable.
 *
 *  Both used to revert `NotConfigured`, so an operator could not tell a
 *  deployment whose rotation wiring was never set (a deploy bug — B-15) from one
 *  simply waiting on a governance vote (normal). That ambiguity is part of why
 *  B-15 survived: a permanently broken deployment looked exactly like a healthy
 *  one with no live mandate.
 */
contract B15_RotationErrorsAreDistinguishable is Test {
    CauldronRegistry internal registry;

    function setUp() public {
        registry = new CauldronRegistry(address(this), address(this), address(this), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
    }

    function test_B15_UnwiredAndUnapprovedAreDifferentErrors() public {
        PoolKey memory route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0x3333333333333333333333333333333333333333)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        bytes memory call_ = abi.encodeWithSignature(
            "rotateSlice(uint16,uint256,(address,address,uint24,int24,address))",
            uint16(2500), uint256(0), route
        );

        // UNWIRED: a deployment problem.
        (bool ok, bytes memory err) = address(registry).call(call_);
        assertFalse(ok, "unwired rotation must revert");
        assertEq(
            bytes4(err), RedemptionExt.RotationNotWired.selector,
            "an unwired registry must say so, not hide behind NotConfigured"
        );

        // WIRED but nothing approved: a governance state, not a bug.
        registry.setRotationWiring(
            address(new NoEnvelopeGovernor()),
            address(new NoEnvelopeGovernor())
        );
        (ok, err) = address(registry).call(call_);
        assertFalse(ok, "unapproved rotation must revert");
        assertEq(
            bytes4(err), RedemptionExt.NoRotationApproved.selector,
            "a wired registry with no envelope must report a governance state"
        );
    }
}

/// @dev Reports no live envelope, which is the normal resting state.
contract NoEnvelopeGovernor {
    function allowance() external pure returns (address, uint16) { return (address(0), 0); }
    function consume(uint16) external {}
}
