// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "../attacks/YBase.sol";
import {LocalLifecycleBoot} from "./LocalLifecycleAdapters.t.sol";
import {LIQ04_CascadeStaleProjection} from "../attacks/LIQ04_CascadeStaleProjection.t.sol";
import {LIQ04_ExactOutBypass} from "../attacks/LIQ04_ExactOutBypass.t.sol";
import {LIQ04_GasStarve} from "../attacks/LIQ04_GasStarve.t.sol";
import {LIQ05_CascadeLossMechanism} from "../attacks/LIQ05_CascadeLossMechanism.t.sol";

/// Executes existing assertions against production local managers. Inherits the
/// explicitly documented ambient-manager-inventory assumption; NOT fork parity.
contract LocalCascadeProjectionTest is LIQ04_CascadeStaleProjection, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}

contract LocalExactOutputPreemptionTest is LIQ04_ExactOutBypass, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}

contract LocalLiquidationGasTest is LIQ04_GasStarve, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}

contract LocalCascadeLossTest is LIQ05_CascadeLossMechanism, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}
