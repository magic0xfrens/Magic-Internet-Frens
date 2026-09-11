// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/**
 * T02 — PerpMarkSource's "fail-soft by construction" claim, tested.
 *
 * The header (PerpMarkSource.sol:56-60) promises:
 *   "With no pools registered, one pool registered, or no in-range liquidity
 *    anywhere, this returns the PRIMARY's tick — exactly today's behaviour. The
 *    engine additionally treats a revert or a malformed answer here as 'use the
 *    primary', so wiring this can never be worse than not wiring it."
 *
 * The UNARMED case is neither a revert nor a malformed answer. It is a
 * perfectly-formed one-word `0` (PerpMarkSource.sol:159), and
 * `PerpEngine._currentTick` (:534-551) accepts any full word:
 *
 *     ok := and(ok, eq(returndatasize(), 0x20))
 *     v  := mload(0x00)
 *     ...
 *     if (ok) return int24(v);
 *
 * Tick 0 is price 1.0000 — one raw token unit per one raw quote unit. There is
 * no fallback, because nothing failed.
 */
contract T02_MarkSourceUnarmed is Test {
    PerpMarkSource internal src;

    function setUp() public {
        // The PoolManager is never reached on the unarmed path, which is the
        // point: this answers without consulting any pool at all.
        src = new PerpMarkSource(IPoolManager(address(0xDEAD)), address(this));
    }

    function test_T02_POC_UnarmedMarkSourceAnswersTickZeroInsteadOfFailing() public {
        assertFalse(src.armed(), "precondition: setPrimary has not been called");

        // Does NOT revert, and does NOT return a short word. Both of the
        // engine's fail-soft triggers are missed.
        int24 t = src.weightedTick();
        console2.log("weightedTick() while unarmed:", int256(t));
        assertEq(int256(t), 0, "a confident, wrong answer");

        // Reproduce the engine's acceptance test byte for byte.
        (bool ok, bytes memory ret) =
            address(src).staticcall(abi.encodeWithSelector(PerpMarkSource.weightedTick.selector));
        assertTrue(ok, "the engine's `ok` is TRUE");
        assertEq(ret.length, 32, "the engine's returndatasize check PASSES");
        console2.log("engine would adopt tick     :", abi.decode(ret, (int256)));

        // Tick 0 means sqrtPriceX96 == Q96 == price 1.0 — every perp mark in the
        // protocol becomes "one raw token unit is worth one raw quote unit".
        // `setRouting` (PerpEngine.sol:1720) accepts a mark source with no
        // ordering requirement against `setPrimary`, and the deploy script's
        // ordering note (deploy/DeployPerp.s.sol:140-143) is the only thing
        // standing between a live engine and this value.
        bool reached = true;
        assertTrue(reached, "T02 unarmed-mark-source reached its assertions");
    }

    /// @notice And the armed-but-empty case IS handled, for contrast: with a
    /// primary set, the answer comes from the pool. (Here the stub
    /// PoolManager has no code, so the call reverts — which is the
    /// shape the engine's fallback actually catches.)
    function test_T02_CONTROL_ArmedGoesToThePool() public {
        PoolKey memory k = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0xBEEF)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        src.setPrimary(k);
        assertTrue(src.armed(), "armed");
        (bool ok,) =
            address(src).staticcall(abi.encodeWithSelector(PerpMarkSource.weightedTick.selector));
        assertFalse(ok, "armed: the answer comes from the PoolManager, and can fail loudly");
        bool reached = true;
        assertTrue(reached, "T02 control reached its assertions");
    }
}
