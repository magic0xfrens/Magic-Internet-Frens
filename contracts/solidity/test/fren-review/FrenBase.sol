// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "../attacks/YBase.sol";

/// @title Fren Review base — the real protocol on a local Uniswap v4 PoolManager
///
/// The same bring-up as `LocalLifecycleBoot` (test/audit_full_scope/
/// LocalLifecycleAdapters.t.sol), without importing the fork attack suites that
/// file wraps: those suites would come along into the Fren Review repo and turn
/// an offline `forge test` red.
///
/// YBase._boot needs FORK_RPC and returns SILENTLY without it (`active == false`),
/// so a PoC built on YBase directly "passes" having executed nothing. This base
/// deploys PoolManager, Permit2 and PositionManager from compiled artifacts and
/// asserts the stack came up.
abstract contract FrenBase is YBase {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal virtual override {
        address manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        address positions = deployCode(
            "out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0))
        );
        _bootWithManagers(seedEth, genesisFrens, manager, positions);
        // An empty manager cannot advance a large swap's launch fee (beforeSwap
        // takes fees before the caller settles input); model the native inventory
        // a shared production PoolManager holds for other pools.
        vm.deal(manager, manager.balance + 10_000 ether);
        assertTrue(active, "local production managers must boot");
    }
}
