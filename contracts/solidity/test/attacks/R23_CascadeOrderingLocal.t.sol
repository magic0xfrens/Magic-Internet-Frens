// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PreSweepLargeBookLocalTest} from "../audit_full_scope/PreSweepLargeBookLocal.t.sol";

/// Local integration property for R23-L1. No target storage is force-written.
/// The inherited fixture explicitly supplies ambient manager ETH inventory.
contract R23CascadeOrderingLocal is PreSweepLargeBookLocalTest {
    function testFuzz_R23_HealthyMixedBookIsSafeOrTradeRollsBack(uint256 seed, uint96 amountSeed) public {
        uint256[] memory ids = new uint256[](24);
        for (uint256 i; i < ids.length; ++i) {
            uint256 choice = uint256(keccak256(abi.encode(seed, i)));
            uint256 collateral = (1 + choice % 4) * 0.01 ether;
            address account = address(uint160(0xC000 + i));
            vm.deal(account, 1 ether);
            vm.prank(account);
            ids[i] = choice & 4 == 0
                ? perp.openShort{value: collateral}(2, 0, 0, collateral)
                : perp.openLong{value: collateral}(2, 0, 0, collateral);
        }
        assertEq(perp.openCount(), 24, "all intended positions opened");
        for (uint256 i; i < ids.length; ++i) {
            assertFalse(perp.isLiquidatable(ids[i]), "no pre-existing liquidation backlog");
        }
        uint256 plvBefore = perp.plv();
        bytes32 bookBefore = _bookHash(ids);
        uint160 priceBefore = _sqrtP();
        uint256 payerBefore = address(this).balance;
        uint256 keeperBefore = attacker.balance;
        uint256 amount = bound(uint256(amountSeed), 5 ether, 50 ether);
        (bool filled,) = address(this).call(
            abi.encodeCall(this.r23Buy, (amount))
        );
        if (!filled) {
            assertEq(_bookHash(ids), bookBefore, "failed trade restores positions");
            assertEq(perp.openCount(), 24, "failed trade restores open count");
            assertEq(_sqrtP(), priceBefore, "failed trade restores price");
            assertEq(perp.plv(), plvBefore, "failed trade restores PLV");
            assertEq(address(this).balance, payerBefore, "failed trade restores payer");
            assertEq(attacker.balance, keeperBefore, "failed trade restores keeper");
        }
        _assertSafe(ids, plvBefore);
    }

    function r23Buy(uint256 amount) external {
        require(msg.sender == address(this), "self only");
        _buy(amount, attacker);
    }
}
