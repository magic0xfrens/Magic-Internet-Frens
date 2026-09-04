// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/**
 * @notice Shared surface for the progressive launch seeder, so PoolOps (which
 *         does the delegatecalled handoff at summon) and CauldronSeeder (the
 *         implementation) reference ONE struct/interface — no drift between two
 *         copies. See CauldronSeeder for the mechanics.
 */
struct SeederConfig {
    PoolKey key;
    address token;
    uint256 gen;
    int24 spacing;
    int24 bandWidth;      // ticks per mini-band (concentration knob)
    uint64 window;        // launch window (0 = atomic: one full placement)
    uint256 seedFloorWad; // initial deployed fraction (e.g. 0.1e18)
    uint256 minStepWad;   // poke throttle (e.g. 0.02e18); 0 → every poke places
    uint256 baseWad;      // fraction placed ONCE at summon as a two-sided full-range
                          // BASE (spot-straddling → perps get depth + no teleport);
                          // the rest streams single-sided for anti-snipe. 0 = pure
                          // single-sided (perps need a spot-straddling gen elsewhere).
    uint256 ethTotal;     // ledger-A ETH (== msg.value)
    uint256 tokenTotal;   // ledger-A token (pulled via transferFrom registry)
}

interface ISeeder {
    function startSeed(SeederConfig calldata cfg) external payable;
    function poke() external;
    function withdrawAll(address to) external returns (uint256 ethOut, uint256 tokenOut);
    /// @notice Break-glass return of loose ledger-A funds for an ABORTED campaign.
    ///         Reachable via {CauldronRegistry.rescueSeeder} (audit I-03).
    function rescue(address to) external;
    function isComplete() external view returns (bool);
    function seeding() external view returns (bool);
}
