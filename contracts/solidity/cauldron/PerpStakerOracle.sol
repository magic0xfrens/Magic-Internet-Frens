// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakerOracle} from "./MigrationVesting.sol";

/// @dev Minimal view onto the PerpVault's per-user share accounting.
interface IPerpShares {
    function ethShareOf(address who) external view returns (uint256);
    function tokShareOf(address who) external view returns (uint256);
}

/**
 * @title PerpStakerOracle — "stake & chill" instant tier for {MigrationVesting}
 * @notice Marks a wallet INSTANT (unvested migration) iff it holds a live share
 *         in the community PerpVault (ETH-side or token-side). This ties the
 *         instant reward to the perp-autostake crowd that already commits capital
 *         across a relaunch — they get their new alloc at once; everyone else
 *         drips. Swap this out via {MigrationVesting.setStakerOracle} to widen the
 *         tier (e.g. add enchanted-genesis holders) without a redeploy.
 */
contract PerpStakerOracle is IStakerOracle {
    IPerpShares public immutable perpVault;

    constructor(address _perpVault) {
        perpVault = IPerpShares(_perpVault);
    }

    /// @inheritdoc IStakerOracle
    function isInstant(address who) external view returns (bool) {
        return perpVault.ethShareOf(who) > 0 || perpVault.tokShareOf(who) > 0;
    }
}
