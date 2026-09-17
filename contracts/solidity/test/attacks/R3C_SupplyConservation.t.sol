// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {FinalAuditBase} from "../final/FinalAuditBase.sol";

/// @dev Tiny collection with a HARD cap, so over-minting is observable.
contract R3CapCol {
    uint256 public totalMinted;
    uint256 public immutable maxSupply;
    mapping(address => uint256) public balanceOf;

    constructor(uint256 cap) {
        maxSupply = cap;
    }

    function mint(address to) external returns (uint256 id) {
        require(totalMinted < maxSupply, "cap");
        totalMinted += 1;
        balanceOf[to] += 1;
        id = totalMinted;
    }

    fallback() external {}
}

/// @notice R3C — supply conservation of the crystal queue: every committed
///         crystal resolves exactly once, and the cap is never exceeded even
///         when many players commit concurrently before anything resolves.
contract R3C_SupplyConservation is FinalAuditBase {
    using stdStorage for StdStorage;

    R3CapCol internal col;
    uint256 internal constant CAP = 12;

    function setUp() public {
        _deployOffchain(address(0xBEEF));
        col = new R3CapCol(CAP);
        vm.prank(address(registry));
        hook.setCollection(address(col));
        hook.setOpener(address(this), true);
    }

    function _fund(address p, uint256 amount) internal {
        stdstore.target(address(hook)).sig("nftCredit(uint256,address)").with_key(hook.creditEpoch())
            .with_key(p).checked_write(amount);
    }

    struct Res {
        uint256 committed;
        uint256 resolved;
        uint256 minted;
        uint256 pendingLeft;
        uint256 outstandingLeft;
    }

    function _run(uint256 players, uint256 perPlayer) internal returns (Res memory r) {
        address[] memory ps = new address[](players);
        for (uint256 i = 0; i < players; ++i) {
            ps[i] = address(uint160(0x1000 + i));
            _fund(ps[i], 1000 ether);
            // 90% odds so wins are frequent and the cap is actually pressured.
            r.committed += hook.commitCrystals(ps[i], perPlayer, 1 ether);
        }
        vm.roll(block.number + 1);
        for (uint256 k = 0; k < 40; ++k) {
            (uint256 p,) = hook.resolveTickets(30);
            r.resolved += p;
            vm.roll(block.number + 1);
        }
        for (uint256 i = 0; i < players; ++i) r.pendingLeft += hook.pendingOf(ps[i]);
        r.minted = col.totalMinted();
        r.outstandingLeft = hook.outstandingTickets();
    }

    function test_R3C_EveryCrystalResolvesOnceAndCapHolds() public {
        Res memory r = _run(8, 5);

        console2.log("committed", r.committed);
        console2.log("resolved", r.resolved);
        console2.log("minted", r.minted);
        console2.log("pending left", r.pendingLeft);

        assertGt(r.committed, 0, "crystals were committed");
        assertEq(r.resolved, r.committed, "each crystal resolved exactly once");
        assertEq(r.pendingLeft, 0, "no player left with a stuck crystal");
        assertEq(r.outstandingLeft, 0, "queue fully drained");
        assertLe(r.minted, CAP, "supply cap never exceeded");
    }
}
