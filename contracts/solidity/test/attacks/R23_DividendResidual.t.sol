// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {T9bDividendConservation} from "./T9b_DividendConservation.t.sol";

contract R23DividendResidual is T9bDividendConservation {
    function test_R23_ZeroValueReceivesCannotCreateUnbackedEntitlement() public {
        _mint(alice, 1); _mint(bob, 1); _mint(carol, 1);
        vm.prank(alice); div.castSpell(1);
        vm.prank(bob); div.castSpell(2);
        vm.prank(carol); div.castSpell(3);
        assertEq(div.activeShares(), 3);
        vm.deal(address(this), 1 ether);
        (bool funded,) = address(div).call{value: 1}("");
        assertTrue(funded);
        uint256 initialAccumulator = div.accPerShare();
        uint256 initialBalance = address(div).balance;
        for (uint256 i; i < 6; ++i) {
            (bool ok,) = address(div).call("");
            assertTrue(ok, "zero-value receive completed");
        }
        assertEq(address(div).balance, initialBalance, "no additional value arrived");
        assertLe(div.pending(1) + div.pending(2) + div.pending(3), address(div).balance,
            "all outstanding claims remain backed");
        assertEq(div.accPerShare(), initialAccumulator, "same residual cannot be credited repeatedly");
    }
}
