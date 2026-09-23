// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {T9bDividendConservation} from "./T9b_DividendConservation.t.sol";

contract R23DividendConservationSequence is T9bDividendConservation {
    function testFuzz_R23_NativeBackingAcrossDepositsJoinTransferAndClaims(uint256 seed) public {
        _mint(alice, 1); _mint(bob, 1); _mint(carol, 1);
        vm.prank(alice); div.castSpell(1);
        vm.prank(bob); div.castSpell(2);
        vm.deal(address(this), 1 ether);
        uint256 funded = address(div).balance;
        uint256 paid;
        for (uint256 i; i < 24; ++i) {
            if (i == 8) { vm.prank(carol); div.castSpell(3); }
            if (i == 16) { vm.prank(bob); col.transferFrom(bob, carol, 2); }
            uint256 amount = uint256(keccak256(abi.encode(seed, i))) % 1001;
            (bool ok,) = address(div).call{value: amount}("");
            assertTrue(ok);
            funded += amount;
            uint256 liabilities = div.pending(1) + div.pending(2) + div.pending(3) + div.owed(bob);
            assertLe(liabilities, address(div).balance, "entitlements remain backed at every step");
            vm.prank(alice);
            paid += div.claim(1);
            assertEq(address(div).balance + paid, funded, "custody plus paid equals funding");
        }
        vm.prank(bob); paid += div.withdrawOwed();
        vm.prank(carol); paid += div.claim(3);
        assertLe(paid, funded);
        assertEq(address(div).balance + paid, funded);
        assertEq(div.activeShares(), 2, "transferred fren no longer active");
    }
}
