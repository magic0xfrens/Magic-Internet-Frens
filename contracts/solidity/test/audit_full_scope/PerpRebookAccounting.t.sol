// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {Position} from "../../cauldron/PerpSwapLib.sol"; // file-level since the book requote
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract RebookRegistry {
    function currentToken() external pure returns (address) { return address(0); }
    function currentGeneration() external pure returns (uint256) { return 0; }
}

contract RebookPoolState {
    function extsload(bytes32) external pure returns (bytes32) { return bytes32(uint256(1) << 96); }
}

/// Mechanism isolation: exposes the production internal function. It does not
/// claim that a real pool can reach every fuzzed partial-fill state.
contract RebookEngineHarness is PerpEngine {
    constructor(address reg)
        PerpEngine(IPoolManager(address(new RebookPoolState())), address(0), reg, address(0), address(0), address(0), msg.sender)
    {}

    function rebook(uint128 collateral, uint256 principal, uint256 remaining) external {
        Position memory p = Position(msg.sender, false, collateral, 100 ether, principal, 1, 3, 0);
        fundingIndex = -int256(1e16);
        _rebook(1, p, 50 ether, remaining);
    }
}

contract PerpRebookAccountingTest is Test {
    RebookEngineHarness internal engine;

    function setUp() public { engine = new RebookEngineHarness(address(new RebookRegistry())); }

    function test_refusedFillPreservesFundingBasisAndBacking() public {
        engine.rebook(1 ether, 2 ether, 3 ether);
        (,, uint128 collateral, uint256 size, uint256 principal,,,) = engine.positions(1);
        assertEq(collateral, 1 ether);
        assertEq(principal, 2 ether);
        assertEq(size, 50 ether);
        assertGt(engine.fundingDelta(1), 0, "funding must not disappear on a refused fill");
        assertEq(engine.openCount(), 1);
    }

    function test_spentPrincipalDoesNotEraseRemainingCollateral() public {
        engine.rebook(1 ether, 2 ether, 0.5 ether);
        (,, uint128 collateral,, uint256 principal,,,) = engine.positions(1);
        assertEq(collateral, 0.5 ether);
        assertEq(principal, 0);
        assertGt(engine.fundingDelta(1), 0);
    }

    function testFuzz_rebookConservesRemainingBacking(uint128 collateral, uint128 principal, uint256 remaining) public {
        remaining = bound(remaining, 0, uint256(collateral) + principal);
        engine.rebook(collateral, principal, remaining);
        (,, uint128 afterCollateral,, uint256 afterPrincipal,,,) = engine.positions(1);
        assertEq(uint256(afterCollateral) + afterPrincipal, remaining);
        assertLe(afterCollateral, collateral);
        assertEq(uint256(afterCollateral), remaining < collateral ? remaining : collateral);
    }
}
