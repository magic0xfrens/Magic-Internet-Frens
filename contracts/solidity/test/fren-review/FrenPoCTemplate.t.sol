// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FrenBase} from "./FrenBase.sol";

/// @title Fren Review PoC template
///
/// Copy to test/scratch/<YourFinding>.t.sol (hunt) or test/fren-review/<ID>/
/// (prove / fix) and replace the body. It boots the REAL protocol — registry,
/// hook, perp engine — on a freshly deployed local Uniswap v4 PoolManager: no
/// fork, no RPC, no network. Keep the `active` assertion in every test.
///
/// Harness surface (test/attacks/YBase.sol): `registry`, `hook`, `perp`, `pm`,
/// `token`, `attacker`, `victim`, `trader`; `_buy(ethIn, to)` pays from THIS
/// contract, `_sell(tokenIn, payer)`, `_warp(dt)` (uses vm.getBlockTimestamp —
/// never read block.timestamp after vm.warp under via_ir), `_bootPerp(...)`.
/// For the nft cluster, deploy `MiFrensGenesis` directly instead (YBase ships a
/// mock collection): see test/GenesisDiscountMint.t.sol.
contract FrenPoCTemplate is FrenBase {
    function setUp() public {
        _boot(25 ether, 0); // seed ETH, genesis frens
    }

    function test_FrenTemplate_StackBootsAndTrades() public {
        assertTrue(active, "local stack booted - a PoC on an empty setup proves nothing");

        vm.deal(address(this), 10 ether);
        uint256 before = IERC20(token).balanceOf(attacker);
        uint256 got = _buy(1 ether, attacker);

        // Assert the EFFECT, never just that calls returned.
        assertGt(got, 0, "a real swap went through the hook");
        assertEq(IERC20(token).balanceOf(attacker) - before, got, "attacker received exactly what the swap reported");
    }
}
