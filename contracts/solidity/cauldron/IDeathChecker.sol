// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/src/types/PoolId.sol";

/**
 * @title IDeathChecker
 * @notice Pluggable death-detection module for the CauldronHook.
 *
 *  The hook's built-in rule is "24h volume < deathThreshold". This interface lets
 *  the protocol UPGRADE that rule — to unique-trader counts, liquidity depth, a
 *  time-based schedule, an EMA, etc. — WITHOUT an upgradeable proxy on the money
 *  contracts. The hook owner (behind the emergency timelock on mainnet) can point
 *  the hook at a new IDeathChecker; if none is set, the built-in rule is used.
 *
 *  A checker is a pure read: given a pool, is its token dead? It receives the
 *  hook's live 24h volume + death threshold so simple checkers can reuse them,
 *  and can read any additional on-chain state it needs itself.
 */
interface IDeathChecker {
    /**
     * @param id           the pool being evaluated.
     * @param volume24h    the hook's current 24h volume for the pool (currency0 terms).
     * @param deathThreshold the hook's configured threshold.
     * @return dead        true if the pool's token should be considered dead.
     */
    function isDead(PoolId id, uint256 volume24h, uint256 deathThreshold)
        external
        view
        returns (bool dead);
}
