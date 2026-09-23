// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SurtaxLib} from "../../cauldron/SurtaxLib.sol";
import {MintCurvePolicy} from "../../cauldron/MintCurvePolicy.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract R23SurtaxResponse {
    uint256 immutable mode;
    constructor(uint256 m) { mode = m; }
    function surtaxBps(PoolId, uint256, uint256, uint256) external view returns (uint256) {
        if (mode == 0) revert("unavailable");
        if (mode == 1) { assembly ("memory-safe") { return(0, 0) } }
        return type(uint256).max;
    }
}

contract R23PolicyBoundaries is Test {
    function _rate(address policy) internal view returns (uint256) {
        return SurtaxLib.surtaxBps(policy, PoolId.wrap(bytes32(uint256(1))), 10, 9000, 100, 9600);
    }
    function test_revertingSurtaxPolicyFallsBack() public {
        vm.roll(20);
        assertEq(_rate(address(new R23SurtaxResponse(0))), _rate(address(0)));
    }
    function test_emptySurtaxPolicyFallsBack() public {
        vm.roll(20);
        assertEq(_rate(address(new R23SurtaxResponse(1))), _rate(address(0)));
    }
    function test_validSurtaxPolicyIsCapped() public {
        vm.roll(20);
        assertEq(_rate(address(new R23SurtaxResponse(2))), 9600);
    }
    function testFuzz_actualDefaultStaysWithinDecayAndPeak(uint16 peak, uint16 window, uint16 elapsed) public {
        uint256 p = bound(peak, 1, 9600);
        uint256 w = bound(window, 1, 10000);
        uint256 e = bound(elapsed, 0, w);
        vm.roll(100 + e);
        uint256 rate = SurtaxLib.defaultSurtaxBps(PoolId.wrap(bytes32(uint256(1))), p, w, 100);
        assertGe(rate, p * (w - e) / w);
        assertLe(rate, p);
    }
    // Characterization, not a failing deployed-calibration claim.
    function test_acceptedTinyCalibrationCanHaveEqualAdjacentPrices() public {
        MintCurvePolicy policy = new MintCurvePolicy(1, 1, 100, 3333);
        assertEq(policy.priceAt(0, 0, 0), policy.priceAt(1, 0, 0));
    }
}
