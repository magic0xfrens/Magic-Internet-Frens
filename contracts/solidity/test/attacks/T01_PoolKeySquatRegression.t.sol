// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {CauldronToken} from "../../CauldronToken.sol";

/**
 * @title T01 — a permissionless `initialize` on the NEXT generation's pool key
 * permanently bricks `relaunch`.
 *
 * The next iteration token is deployed with CREATE2 (PoolOps.deployTokenAbove),
 * salted `keccak256(abi.encode(gen, i))` over an initcode hash built only from
 * (name, symbol, gen, registry, TOTAL_SUPPLY) — every one of which is public
 * before the rebirth transaction exists. So the address of the token that does
 * not exist yet is computable by anybody.
 *
 * Uniswap v4 lets ANYONE initialize a pool, and does not require either currency
 * to have code. The hook's `_afterInitialize` deliberately does NOT revert for a
 * foreign sender (it just declines to track). So the key the rebirth is about to
 * create can be occupied in advance, for the price of one `initialize`.
 *
 * `PoolOps._greenCandle` then calls `poolManager.initialize` bare — and that call
 * sits AFTER `governor.markConsumed(winId)` in `relaunch`.
 */
contract T01_PoolKeySquatRegression is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address internal constant WATERMARK = 0xf000000000000000000000000000000000000000;

    /// @dev Reproduce PoolOps.deployTokenAbove's CREATE2 search from public data.
    function _predictToken(uint256 gen, string memory name, string memory symbol)
        internal
        view
        returns (address)
    {
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(CauldronToken).creationCode,
                abi.encode(name, symbol, gen, address(registry), registry.TOTAL_SUPPLY())
            )
        );
        for (uint256 i; i < 1024; ++i) {
            bytes32 salt = keccak256(abi.encode(gen, i));
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(registry), salt, initHash))))
            );
            if (predicted > WATERMARK) return predicted;
        }
        return address(0);
    }

    function _gen2Key(address tok) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(tok),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    // ------------------------------------------------------------------
    // 1. CONTROL — the rebirth works, and the token lands exactly where a
    //    stranger could have predicted it would.
    // ------------------------------------------------------------------
    function test_T01_control_relaunchWorks_andAddressIsPredictable() public {
        bool reached;
        _boot(20 ether, 0);
        if (!active) {
            console2.log("FORK_RPC unset - test did not run");
            assertTrue(true);
            return;
        }

        // YGov's winning spec: name "Shadow Wraith" -> branded on-chain.
        address predicted = _predictToken(2, "Shadow Wraith by Magic Internet Frens", "WRAITH");
        console2.log("predicted gen-2 token :", predicted);
        assertTrue(predicted != address(0), "no salt found");

        // The summon's own green candle counts as volume, so let the hook's 24h
        // window roll over before the brew reads dead.
        _warp(25 hours);
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen 1 not dead");
        registry.relaunch();

        address real = registry.generationToken(2);
        console2.log("actual    gen-2 token :", real);
        assertEq(real, predicted, "token address is NOT publicly predictable");
        assertEq(registry.currentGeneration(), 2, "did not reach gen 2");

        reached = true;
        assertTrue(reached, "control did not reach the end");
    }

    // ------------------------------------------------------------------
    // 2. THE ATTACK, NOW CLOSED — the squat itself is rejected, and the
    //    rebirth it was meant to kill still lands.
    //
    //    Before the fix this test asserted the opposite and passed: the
    //    attacker's `initialize` went through for 33,077 gas (the hook merely
    //    declined to TRACK a foreign pool), and every subsequent `relaunch()`
    //    reverted `PoolAlreadyInitialized()` (0x7983c051) forever — verified on
    //    a Sepolia fork, including a retry 30 days later.
    //
    //    `_afterInitialize` now reverts for any sender that is not the
    //    registry. Because the squatted key NAMES this hook, every initialize
    //    of it must pass through that callback, so the key is unsquattable.
    // ------------------------------------------------------------------
    function test_T01_squatIsRejected_andRelaunchStillLands() public {
        bool reached;
        _boot(20 ether, 0);
        if (!active) {
            console2.log("FORK_RPC unset - test did not run");
            assertTrue(true);
            return;
        }

        address predicted = _predictToken(2, "Shadow Wraith by Magic Internet Frens", "WRAITH");
        assertTrue(predicted != address(0), "no salt found");
        PoolKey memory k = _gen2Key(predicted);

        // ---- the attack: one permissionless initialize on the key the rebirth
        //      is about to create. It must not succeed.
        bool squatted;
        vm.prank(attacker);
        try pm.initialize(k, 79228162514264337593543950336) {
            squatted = true;
        } catch {
            console2.log("squat rejected at the hook's adoption gate");
        }
        assertFalse(squatted, "REGRESSION: a foreign initialize on the hook's key succeeded");

        // The key is still virgin, so nothing is holding the rebirth back.
        assertFalse(hook.trackedPools(k.toId()), "squatted pool must not be tracked");

        _warp(25 hours);
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen 1 not dead");

        // ---- the rebirth lands despite the attempt.
        registry.relaunch();

        assertEq(registry.currentGeneration(), 2, "relaunch did not advance the generation");
        assertEq(registry.generationToken(2), predicted, "gen 2 token is not at the mined address");
        assertTrue(hook.trackedPools(k.toId()), "the registry's own pool was not adopted");

        reached = true;
        assertTrue(reached, "regression path did not reach the end");
    }
}
