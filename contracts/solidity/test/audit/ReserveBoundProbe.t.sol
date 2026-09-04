// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ReserveLib} from "../../cauldron/ReserveLib.sol";

/// Probe: at which launch tick does `liquidityForTokenOut(777M tokens)` overflow
/// uint128? Establishes whether the revert is reachable for real Cauldron pools.
contract ReserveBoundProbe is Test {
    function test_Probe_OverflowBoundary() public pure {
        uint256 amount = 777_000_000e18;
        int24 lastOk = type(int24).min;
        for (int24 t = -880_000; t <= 400_000; t += 20_000) {
            (int24 lo, int24 hi) = ReserveLib.reserveTicks(t, 200, 42_400);
            uint256 code;
            // try/catch does not work on internal library calls; emulate by checking
            // the magnitude first.
            uint256 num = uint256(TickMath.getSqrtPriceAtTick(hi)) - uint256(TickMath.getSqrtPriceAtTick(lo));
            if (num == 0) continue;
            // L = amount * 2^96 / num  (mulDiv). Overflow iff L > type(uint128).max.
            // amount * 2^96 fits in 256 bits here, so compare directly.
            uint256 L = (amount / num) * 0x1000000000000000000000000
                + ((amount % num) * 0x1000000000000000000000000) / num;
            code = L > type(uint128).max ? 1 : 0;
            if (code == 0 && lastOk == type(int24).min) {
                lastOk = t;
                console2.log("first SAFE launch tick:");
                console2.logInt(int256(t));
            }
        }
        console2.log("Cauldron gen-1 launch tick for 777M tokens : 1 ETH is ~ +204,000");
    }
}
