// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {YBase} from "../attacks/YBase.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {MetadataMode, BrewSpec} from "../../cauldron/ICauldron.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-09 — THE PROPOSAL PAYLOAD IS AN UNBOUNDED GAS BOMB  (High)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  THE PROPERTY UNDER TEST is the one B07_RelaunchTotality states:
 *
 *      `relaunch()` must never revert in a way that rolls back
 *      `governor.markConsumed(winId)`.
 *
 *  B07 defends that property against hostile CALLEES — a vault whose `close`
 *  reverts, a hook that cannot pay its reserve — by moving `markConsumed` as late
 *  as the logic allows and wrapping the callees in try/catch. Every one of its
 *  tests supplies the proposal itself through `BGov07`, a stub whose `winner()`
 *  returns hardcoded 8-byte strings. The one genuinely attacker-controlled input
 *  to a rebirth is therefore never exercised.
 *
 *  `CauldronGovernor.propose` bounds `nftSupply` (:182) and `quote` (:204)
 *  precisely because they flow into `relaunch()`. It applies NO bound to `name`,
 *  `symbol`, `baseURI`, `website` or `socials` — only a non-empty check
 *  (:171-173). Nothing anywhere else in the protocol bounds them either.
 *
 *  Neither of B07's two defences can help. Moving `markConsumed` later does not
 *  matter, because the transaction never reaches it. try/catch does not matter
 *  either: an OUT-OF-GAS is not a catchable revert of a sub-call, it is the whole
 *  transaction failing. The consumption never commits, `_bestUnconsumed()` keeps
 *  returning the same poisoned proposal, and every future rebirth dies
 *  identically — the exact permanent-freeze shape B07 exists to prevent, reached
 *  on an axis its markConsumed-ordering fix does not cover.
 *
 *  WHY IT IS CHEAP. The payload is zero bytes. Writing a zero word to a fresh slot
 *  is a 100-gas no-op SSTORE; reading it back is a full 2100-gas COLD SLOAD.
 *  Measured marginal cost (test_PoC_B09b): the attacker pays ~74 gas/byte to
 *  author once, the protocol pays ~87 gas/byte to replay on EVERY rebirth.
 *
 *  That asymmetry is the structural defect, and it does not care what the block
 *  limit is: an attacker who can afford one block of authoring always produces a
 *  replay that exceeds one block.
 *
 *  Two of the five unbounded fields — `website` and `socials` — are never read by
 *  `relaunch()` at all. `CauldronGovernor.winner()` (:288-300) copies them from
 *  storage into the returned `BrewSpec` regardless: cost with no purpose.
 *
 *  MEASURED, on the Sepolia fork, against a 30M-gas block:
 *    honest rebirth                     5,297,638 gas
 *    attacker authors 320KB (one tx)   24,262,961 gas
 *    poisoned rebirth                  29,288,732 gas  -> OUT OF GAS, reverts
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B09_ProposalPayloadGasBrick is Test {
    CauldronGovernor internal governor;
    CauldronFactory internal factory;

    function setUp() public {
        governor = new CauldronGovernor(address(new VotesStubB09()));
        factory = new CauldronFactory();
    }

    /// @dev Zero-filled: the cheapest payload to store and the most expensive to
    ///      read back. Built in MEMORY, so the ~128KB geth mempool transaction cap
    ///      never applies — the attacker's own transaction is a few hundred bytes
    ///      calling a contract that expands the string on-chain.
    function _blob(uint256 n) internal pure returns (string memory) {
        return string(new bytes(n));
    }

    /// @dev Author a proposal whose `baseURI` carries the payload, then elect it.
    ///      `baseURI` is the worst field: `relaunch()` both READS it
    ///      (CauldronGovernor.winner) and RE-STORES it in the new collection
    ///      (CauldronFactory.deployBrew -> new CauldronCollection). Election needs
    ///      one vote and one settled window — there is no quorum, no minimum
    ///      turnout, and no deposit.
    function _proposeAndElect(uint256 n) internal returns (uint256 id) {
        // Native quote: no registry lookup, so this measures payload cost alone.
        id = governor.propose(
            "B", "X", MetadataMode.BaseURI, _blob(n), address(0), "w", "s", 1000, 0, address(0)
        );
        vm.roll(vm.getBlockNumber() + 1); // snapshot must be in the past to vote
        governor.vote(id);
        // `via_ir` CSEs repeated TIMESTAMP reads, so route the warp through the
        // cheatcode getter rather than `block.timestamp` (same reason as YBase).
        vm.warp(vm.getBlockTimestamp() + governor.VOTING_PERIOD() + 1);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  1. THE WEAKNESS, DEMONSTRATED  (passes — exhibits the defect)
    // ───────────────────────────────────────────────────────────────────────

    /// @notice FIXED: the payload is refused at the boundary, where refusing costs
    ///         one proposal and freezes nothing. Pre-fix this returned id 1 and the
    ///         full 320KB survived into `winner()`.
    function test_FIXED_B09a_ProposeRefusesAnOversizedPayload() public {
        vm.expectRevert(CauldronGovernor.FieldTooLong.selector);
        governor.propose(
            "B", "X", MetadataMode.BaseURI, _blob(320_000), address(0), "w", "s", 1000, 0, address(0)
        );
    }

    /// @notice The bound is on SIZE, not on the proposer or the content: a normal
    ///         brew still proposes, and the refusal cannot be used to grief an
    ///         address out of governance.
    function test_FIXED_B09a_HonestProposalStillFits() public {
        uint256 id = _proposeAndElect(200); // a real IPFS metadata root
        assertEq(id, 1, "an honest proposal is accepted");

        (uint256 winId, BrewSpec memory spec) = governor.winner();
        assertEq(winId, id, "and still wins");
        assertEq(bytes(spec.baseURI).length, 200, "carried intact: bounded, not truncated");
    }

    /// @notice Every one of the five free-text fields is bounded. `website` and
    ///         `socials` matter even though `relaunch()` never reads them:
    ///         {winner} copies them out of storage on every rebirth regardless,
    ///         so they were pure amplification.
    function test_FIXED_B09a_EveryFreeTextFieldIsBounded() public {
        string memory big = _blob(1_000);
        string[5] memory field = ["name", "symbol", "baseURI", "website", "socials"];
        for (uint256 i; i < 5; ++i) {
            vm.expectRevert(CauldronGovernor.FieldTooLong.selector);
            governor.propose(
                i == 0 ? big : "B",
                i == 1 ? big : "X",
                MetadataMode.BaseURI,
                i == 2 ? big : "ipfs://b/",
                address(0),
                i == 3 ? big : "w",
                i == 4 ? big : "s",
                1000,
                0,
                address(0)
            );
            assertEq(governor.proposalCount(), 0, string.concat("unbounded field: ", field[i]));
        }
    }

    /// @notice INVARIANT: the replay cost of the WORST proposal the governor will
    ///         now accept is bounded and small.
    ///
    ///  This is the property the bound actually buys. The per-byte asymmetry is
    ///  unchanged and unfixable — a cold SLOAD costs 2100 whatever wrote it — so
    ///  the defence has to be on the byte count, and this asserts the resulting
    ///  ceiling directly rather than the mechanism that produces it.
    ///
    ///  Pre-fix there was no ceiling: measured 72 gas/byte to author against 83
    ///  gas/byte to replay, unbounded in both directions.
    function test_INVARIANT_B09_WorstLegalProposalReplaysCheaply() public {
        (, uint256 replay) = _measureMaxLegal();
        emit log_named_uint("worst legal proposal replay gas", replay);

        // The honest rebirth measured 5.3M against a 30M block. A legal proposal
        // must not be able to claim a meaningful slice of that headroom.
        assertLt(replay, 4_000_000, "worst legal payload must stay a rounding error");
    }

    /// @dev (author gas, replay gas) for the largest proposal `propose()` accepts:
    ///      every free-text field at its cap. A FRESH governor per measurement:
    ///      `vote()` only replaces the cached leader on a STRICT majority
    ///      (CauldronGovernor.sol:271), so reusing one would leave the first
    ///      proposal cached and silently measure it twice.
    function _measureMaxLegal() internal returns (uint256 author, uint256 replay) {
        governor = new CauldronGovernor(address(new VotesStubB09()));
        // Built outside both measured regions.
        string memory nm = _blob(governor.MAX_NAME_BYTES());
        string memory sy = _blob(governor.MAX_SYMBOL_BYTES());
        string memory uri = _blob(governor.MAX_URI_BYTES());
        string memory lnk = _blob(governor.MAX_LINK_BYTES());

        uint256 g0 = gasleft();
        uint256 id = governor.propose(
            nm, sy, MetadataMode.BaseURI, uri, address(0), lnk, lnk, 1000, 0, address(0)
        );
        author = g0 - gasleft();

        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id);
        vm.warp(vm.getBlockTimestamp() + governor.VOTING_PERIOD() + 1);

        uint256 g1 = gasleft();
        (, BrewSpec memory spec) = governor.winner();
        factory.deployBrew(
            CauldronFactory.Config({
                name: spec.name,
                symbol: spec.symbol,
                hook: address(this),
                registry: address(this),
                maxSupply: spec.nftSupply,
                mode: spec.mode,
                baseURI: spec.baseURI,
                renderer: spec.renderer,
                royaltyReceiver: address(this),
                royaltyBps: 500
            })
        );
        replay = g1 - gasleft();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  END-TO-END: the payload actually stops `relaunch()` from fitting in a block.
//  Fork-gated (repo convention) — needs the real V4 PoolManager.
// ═══════════════════════════════════════════════════════════════════════════

contract B09_RelaunchPayloadBrick is YBase {
    CauldronGovernor internal gov;

    /// @dev Mainnet-class block gas limit. The attack is not sensitive to this
    ///      value: see test_PoC_B09b — replay costs more per byte than authoring,
    ///      so a larger block buys the attacker more than it buys the protocol.
    uint256 internal constant BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev Sized from the measured marginal rate (~87 gas/byte replayed) to exceed
    ///      a block on top of the ~5.3M honest rebirth, while the authoring
    ///      transaction (24.3M) still fits inside one.
    uint256 internal constant PAYLOAD = 320_000;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        gov = new CauldronGovernor(address(new VotesStubB09()));
        gov.setRegistry(address(registry));
        registry.setGovernor(address(gov));
    }

    /// @dev Dead + past the minimum lifetime + past the anti-snipe window.
    function _arm() internal {
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        vm.roll(vm.getBlockNumber() + 60);
    }

    /// @dev Author + elect a brew whose `baseURI` is `n` zero bytes.
    function _elect(uint256 n) internal {
        string memory big = string(new bytes(n));
        uint256 gp = gasleft();
        uint256 id = gov.propose(
            "B", "X", MetadataMode.BaseURI, big, address(0), "w", "s", 1000, 0, address(0)
        );
        emit log_named_uint("propose() gas          ", gp - gasleft());
        vm.roll(vm.getBlockNumber() + 1);
        gov.vote(id);
        _warp(gov.VOTING_PERIOD() + 1);
    }

    /// @dev The largest `baseURI` the governor accepts.
    function _maxUri() internal view returns (uint256) {
        return gov.MAX_URI_BYTES();
    }

    /// @notice BASELINE: what an honest rebirth costs, establishing the headroom
    ///         the payload has to eat.
    function test_PoC_B09c_BaselineRelaunchGas() public {
        vm.skip(!active);
        _elect(32);
        _arm();

        uint256 g0 = gasleft();
        registry.relaunch();
        emit log_named_uint("honest relaunch() gas  ", g0 - gasleft());

        assertEq(registry.currentGeneration(), 2, "honest rebirth succeeds");
    }

    /// @notice INVARIANT: a proposal one guild member can author must not make
    ///         `relaunch()` unexecutable. Real governor, real registry, end to end,
    ///         with the rebirth given a full block of gas.
    ///
    ///  On current code the call runs out of gas. Because it reverts, the
    ///  `markConsumed` inside it never commits, so `_bestUnconsumed()` hands the
    ///  same poisoned proposal to the next caller, and to every caller after that.
    ///  The dead generation can never be replaced: holders cannot migrate and the
    ///  reserve never redeploys.
    ///
    ///  Recovery requires the guild to elect a competing proposal with STRICTLY
    ///  more votes (CauldronGovernor.sol:271), so an attacker holding a voting
    ///  plurality made the freeze permanent and unrecoverable.
    ///
    ///  FIXED at the boundary: the payload can no longer be authored, so it can
    ///  never reach a vote, let alone a rebirth. Both halves are asserted — that
    ///  the bomb is refused, AND that the largest still-legal proposal relaunches
    ///  inside a block with room to spare. Delete the bound and the first half
    ///  fails here.
    function test_INVARIANT_B09_RebirthSurvivesAHostilePayload() public {
        vm.skip(!active);

        // 1. The bomb cannot be authored.
        vm.expectRevert(CauldronGovernor.FieldTooLong.selector);
        gov.propose(
            "B", "X", MetadataMode.BaseURI, string(new bytes(PAYLOAD)),
            address(0), "w", "s", 1000, 0, address(0)
        );

        // 2. The worst proposal that IS legal still rebirths inside one block.
        _elect(_maxUri());
        _arm();

        uint256 g0 = gasleft();
        (bool ok, ) = address(registry).call{gas: BLOCK_GAS_LIMIT}(
            abi.encodeWithSignature("relaunch()")
        );
        uint256 used = g0 - gasleft();
        emit log_named_uint("worst-legal relaunch() gas", used);

        assertTrue(ok, "rebirth must fit in one block whatever the proposal carries");
        assertEq(registry.currentGeneration(), 2, "and must actually advance");
        assertLt(used, BLOCK_GAS_LIMIT / 2, "with real headroom, not a hair's breadth");
    }
}

/// @dev Everyone holds voting power, so `propose` reaches the payload path.
///      The real gate is one MiFren (CauldronGovernor.sol:170).
contract VotesStubB09 {
    function getVotes(address) external pure returns (uint256) { return 1; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1; }
}
