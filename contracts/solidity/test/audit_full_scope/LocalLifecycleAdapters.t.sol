// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "../attacks/YBase.sol";
import {D04_RebookErasesFundingAndPenalty} from "../attacks/D04_RebookErasesFundingAndPenalty.t.sol";
import {LIQ02_PreemptiveProjection} from "../attacks/LIQ02_PreemptiveProjection.t.sol";
import {LIQ03_PreemptiveLiquidation} from "../attacks/LIQ03_PreemptiveLiquidation.t.sol";
import {M4A_RelaunchSeam} from "../attacks/M4A_RelaunchSeam.t.sol";
import {M4B_RelaunchWhale} from "../attacks/M4B_RelaunchWhale.t.sol";

/// Local integration lane, NOT fork/deployed-state parity. Original inherited
/// test bodies and assertions are unchanged. Only manager bring-up differs.
abstract contract LocalLifecycleBoot is YBase {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal virtual override {
        address manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        address positions = deployCode(
            "out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0))
        );
        _bootWithManagers(seedEth, genesisFrens, manager, positions);
        // These inherited fork tests assume a shared PoolManager with other
        // pools' native inventory. beforeSwap takes fees before the caller
        // settles input; an empty manager cannot advance a 500/1000 ETH swap's
        // launch fee. Model that external inventory explicitly, not protocol
        // reserve counters. No claim about empty-manager liveness is made.
        vm.deal(manager, manager.balance + 10_000 ether);
        assertTrue(active, "local production managers must boot");
    }
}

contract LocalD04RebookTest is D04_RebookErasesFundingAndPenalty, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}
contract LocalLIQ02ProjectionTest is LIQ02_PreemptiveProjection, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}
contract LocalLIQ03LiquidationTest is LIQ03_PreemptiveLiquidation, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}
contract LocalM4ARelaunchTest is M4A_RelaunchSeam, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}
contract LocalM4BWhaleTest is M4B_RelaunchWhale, LocalLifecycleBoot {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal override(YBase, LocalLifecycleBoot) {
        LocalLifecycleBoot._boot(seedEth, genesisFrens);
    }
}
