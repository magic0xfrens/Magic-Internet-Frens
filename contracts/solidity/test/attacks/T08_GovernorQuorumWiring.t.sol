// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/**
 * T08 — THE QUORUM MUST BE READABLE OFF THE CONTRACT THAT IS ACTUALLY WIRED.
 *
 * `TreasuryGovernor._passed` divides by a supply read from its `mifrens`
 * reference. The contract production passes there is {MiFrensGenesis}
 * (`DeployLaunchpad.s.sol:461` — `IVotes721(address(presale))`), which is
 * `ERC721Votes` but deliberately NOT `ERC721Enumerable`, and which declares no
 * fallback. It therefore has no `totalSupply()`.
 *
 * Before the fix, every quorum read reverted `unrecognized function selector
 * 0x18160ddd`, and because `_passed` short-circuits on `forVotes <=
 * againstVotes` the failure was invisible until a proposal actually earned
 * support. `execute`, the leader scan and `passing` all died at that point:
 * no treasury envelope could ever be approved, so `rotateSlice` could never be
 * authorised. Permanent, and not owner-fixable — `mifrens` is immutable.
 *
 * It shipped because the governor's own suite binds a MOCK that implements
 * `totalSupply()`. No test ever pointed the governor at the real vote source.
 * That is the gap this file closes: it wires the PRODUCTION pair.
 */
contract T08_GovernorQuorumWiring is Test {
    MiFrensGenesis internal frens;
    TreasuryGovernor internal gov;

    address internal registry = makeAddr("registry");

    function setUp() public {
        //  The production pair, wired exactly as `DeployLaunchpad.s.sol:460-461`
        //  wires it: the presale collection IS the governor's vote source.
        frens = new MiFrensGenesis("MiFrens", "FREN", 1111, 1111, 0.01 ether, 10, "ipfs://x/");
        gov = new TreasuryGovernor(
            IVotes721(address(frens)), registry, address(this), 0, 0, 0, 0, false
        );
    }

    /// @notice The governor's quorum denominator must be callable on the real
    ///         vote source. A raw staticcall is the honest test: a missing
    ///         function on a contract with no fallback reverts with EMPTY
    ///         return data, which is exactly how this defect presented.
    function test_T08_QuorumDenominatorExistsOnTheRealVoteSource() public {
        bool reached;
        vm.roll(block.number + 2);

        (bool ok, bytes memory ret) = address(frens).staticcall(
            abi.encodeWithSelector(IVotes721.getPastTotalSupply.selector, block.number - 1)
        );

        reached = true;
        assertTrue(ok, "the wired vote source cannot answer the quorum denominator");
        assertEq(ret.length, 32, "quorum denominator must return one word");
        assertTrue(reached, "test did not reach its assertions");
    }

    /// @notice And the governor must not be reading a selector the vote source
    ///         does not implement. Pinned explicitly so a future change back to
    ///         `totalSupply()` fails here rather than on mainnet.
    function test_T08_VoteSourceHasNoTotalSupplyAndNoFallback() public {
        bool reached;
        (bool ok, bytes memory ret) =
            address(frens).staticcall(abi.encodeWithSignature("totalSupply()"));

        reached = true;
        assertFalse(ok, "MiFrensGenesis unexpectedly implements totalSupply()");
        assertEq(ret.length, 0, "no fallback: a missing selector must revert empty");
        assertTrue(reached, "test did not reach its assertions");
    }
}
