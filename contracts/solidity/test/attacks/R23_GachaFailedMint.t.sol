// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {R2EHarness} from "./R2E_GachaSeedPin.t.sol";

contract R23PityHarness is R2EHarness {
    function arrangeEarnedPity(address player) external {
        pityThreshold = 8;
        missStreak[player] = 8;
    }
}
contract R23RejectingCollection {
    function totalMinted() external pure returns (uint256) { return 0; }
    function maxSupply() external pure returns (uint256) { return 100; }
    function mint(address) external pure returns (uint256) { revert("validator rejects"); }
}
contract R23GachaFailedMint is Test {
    function test_failedForcedMintMustPreserveEarnedPity() public {
        R23PityHarness h = new R23PityHarness();
        R23RejectingCollection col = new R23RejectingCollection();
        address player = address(0xBEEF);
        vm.roll(100);
        h.arrangeEarnedPity(player);
        h.commit(player, address(col), 1, 0);
        vm.roll(101);
        vm.setBlockhash(100, bytes32(uint256(123)));
        (uint256 processed, uint256 won) = h.resolve(1);
        assertEq(processed, 1, "queue progresses despite rejection");
        assertEq(won, 0);
        assertEq(h.pendingOf(player), 0);
        assertEq(h.missStreak(player), 8, "no NFT delivered: earned pity must survive");
    }
}
