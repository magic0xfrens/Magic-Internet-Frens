// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "../attacks/YBase.sol";
import {F14_RotationTotality} from "../functional/F14_RotationTotality.t.sol";
import {F14c_D1ForceCloseAfterDrain} from "../functional/F14c_D1ForceCloseAfterDrain.t.sol";

/// Fresh-review harness: replace only fork bring-up with actual local managers.
/// Inherited assertions retain their original meaning; passing characterisation
/// tests are not automatically evidence that the characterised behaviour is safe.
abstract contract ReauditLocalManagers is YBase {
    function _boot(uint256 seedEth, uint256 genesisFrens) internal virtual override {
        address manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        address positions = deployCode(
            "out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0))
        );
        _bootWithManagers(seedEth, genesisFrens, manager, positions);
        require(active, "local managers must activate fixture");
    }
}

contract ReauditRotationTotalityLocal is F14_RotationTotality, ReauditLocalManagers {
    function _boot(uint256 seedEth, uint256 genesisFrens)
        internal override(YBase, ReauditLocalManagers)
    {
        ReauditLocalManagers._boot(seedEth, genesisFrens);
    }
}

contract ReauditOpenBookRotationLocal is F14c_D1ForceCloseAfterDrain, ReauditLocalManagers {
    function _boot(uint256 seedEth, uint256 genesisFrens)
        internal override(YBase, ReauditLocalManagers)
    {
        ReauditLocalManagers._boot(seedEth, genesisFrens);
    }
}
