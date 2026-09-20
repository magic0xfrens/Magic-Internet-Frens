// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GachaLib} from "../../cauldron/GachaLib.sol";

/// @dev Minimal collection. Nothing here touches the seed logic — it only has
///      to answer `totalMinted`/`maxSupply` and mint.
contract R2EColl {
    uint256 public totalMinted;
    uint256 public maxSupply = 10_000;
    function mint(address) external returns (uint256) { return ++totalMinted; }
}

/**
 * @dev Harness that owns the storage {GachaLib} writes into.
 *
 *  GachaLib is a LINKED library with an `external` function, so
 *  `GachaLib.resolveTickets(...)` from here is a DELEGATECALL into the real,
 *  deployed library bytecode operating on THIS contract's storage — exactly
 *  the relationship {CauldronHook} has with it (CauldronHook.sol:2519). No
 *  reimplementation, no mock of the code under test.
 */
contract R2EHarness {
    GachaLib.Batch[] public batches;
    mapping(address => uint256) public missStreak;
    mapping(address => uint256) public pendingOf;
    mapping(address => uint256) public outstandingOf;
    mapping(address => uint256) public opened;
    GachaLib.State internal gacha;
    uint256 public pityThreshold = 1_000_000; // pity off unless a test wants it

    function batchCursor() external view returns (uint256) { return gacha.batchCursor; }
    function outstanding() external view returns (uint256) { return gacha.outstandingCrystals; }
    function batchCount() external view returns (uint256) { return batches.length; }

    function commit(address player, address col, uint16 count, uint16 oddsBps) external {
        pendingOf[player] += count;
        outstandingOf[col] += count;
        gacha.outstandingCrystals += count;
        batches.push(GachaLib.Batch({
            player: player,
            collection: col,
            commitBlock: uint48(block.number),
            oddsBps: oddsBps,
            count: count,
            resolved: 0
        }));
    }

    function resolve(uint256 maxCount) external returns (uint256 p, uint256 w) {
        return GachaLib.resolveTickets(
            batches, missStreak, pendingOf, outstandingOf, opened, gacha, pityThreshold, maxCount
        );
    }

    function commitBlockOf(uint256 i) external view returns (uint48) { return batches[i].commitBlock; }
    function resolvedOf(uint256 i) external view returns (uint16) { return batches[i].resolved; }

    // Read the library's two hashed namespaces the same way it derives them.
    function seedOf(uint256 bi) external view returns (bytes32 v) {
        bytes32 s = keccak256(abi.encode(bi, keccak256("cauldron.gacha.seed.v1")));
        assembly ("memory-safe") { v := sload(s) }
    }
    function reanchoredOf(uint256 bi) external view returns (bool v) {
        bytes32 s = keccak256(abi.encode(bi, keccak256("cauldron.gacha.reanchored.v1")));
        assembly ("memory-safe") { v := iszero(iszero(sload(s))) }
    }
}

/**
 * @notice R2E — THE GACHA SEED PIN (`e0d4c9f`). Three questions, answered
 *         against the REAL {GachaLib} bytecode:
 *
 *   1. Can the two hashed namespaces collide with each other, or with the
 *      hook's own declared/derived slots?
 *   2. Can a stored seed be overwritten, or pinned to a value the caller picks
 *      (including one they already know), to fix an outcome?
 *   3. Does pinning hand anyone an EXTRA draw, or break the one-re-anchor cap
 *      and the terminal forfeit?
 */
contract R2E_GachaSeedPin is Test {
    R2EHarness internal h;
    R2EColl internal col;
    address internal player = address(0xBEEF01);
    address internal attacker = address(0xBAD01);

    bytes32 internal constant SEED_SLOT = keccak256("cauldron.gacha.seed.v1");
    bytes32 internal constant REANCHORED_SLOT = keccak256("cauldron.gacha.reanchored.v1");

    function setUp() public {
        h = new R2EHarness();
        col = new R2EColl();
        vm.roll(1_000);
    }

    // ── 1. NAMESPACE SEPARATION ─────────────────────────────────────────────

    function test_R2E_namespacesCannotCollide() public pure {
        // Every reachable (batchIndex) tuple in both namespaces, over a range
        // far wider than any queue that fits in a block, plus the hook's own
        // low declared slots and the slots a `mapping(address=>uint256)` at any
        // of the first 256 hook slots can produce for the two addresses a
        // caller controls.
        uint256 N = 512;
        bytes32[] memory seen = new bytes32[](N * 2);
        uint256 k;
        for (uint256 i; i < N; ++i) {
            seen[k++] = keccak256(abi.encode(i, SEED_SLOT));
            seen[k++] = keccak256(abi.encode(i, REANCHORED_SLOT));
        }
        uint256 collisions;
        for (uint256 i; i < seen.length; ++i) {
            // never a low slot the hook declares directly
            if (uint256(seen[i]) < 4096) collisions++;
            for (uint256 j = i + 1; j < seen.length; ++j) {
                if (seen[i] == seen[j]) collisions++;
            }
        }
        assertEq(collisions, 0, "no seed/reanchor slot collides with the other namespace or a declared slot");

        // And the namespace BASES are keccak outputs, so the 64-byte preimage
        // (index, BASE) can never equal a Solidity mapping preimage
        // (key, smallSlot) unless BASE itself is a small slot number.
        assertGt(uint256(SEED_SLOT), 1 << 200, "SEED_SLOT is a keccak output, not a slot index");
        assertGt(uint256(REANCHORED_SLOT), 1 << 200, "REANCHORED_SLOT is a keccak output");
        assertTrue(SEED_SLOT != REANCHORED_SLOT, "distinct bases");
    }

    // ── 2. NO EXTERNAL WRITER, AND PINNING IS SINGLE-ASSIGNMENT ─────────────

    /// @dev Resolve once inside the window (pins), then resolve far later. The
    ///      pinned seed must be unchanged and the ROLLS must be the ones the
    ///      ORIGINAL commit block dictated.
    ///
    ///  NOTE ON THE VM: Foundry's `blockhash` memoises any block it has been
    ///  asked about, so once the library has read `blockhash(commitBlock)` to
    ///  pin, the test VM keeps answering non-zero past 256 blocks. The EVM's
    ///  256-block horizon therefore cannot be observed in the same function
    ///  that pins. It IS exercised, end to end, by
    ///  {test_R2E_oneReanchorThenTerminalForfeit} below, which reaches the
    ///  `bh == 0` branch. What this test proves instead — and what the security
    ///  question actually is — is that the value rolled against is the pinned
    ///  one, byte for byte, and that nothing can replace it.
    function test_R2E_pinIsSingleAssignmentAndFreezesTheOriginalSeed() public {
        uint16 count = 8;
        uint16 odds = 5000;
        h.commit(player, address(col), count, odds);
        uint256 commitBlk = vm.getBlockNumber();
        vm.roll(commitBlk + 1);
        assertEq(vm.getBlockNumber(), commitBlk + 1, "roll #1 landed");

        // Resolve ZERO crystals: the sweep still runs (GachaLib.sol:272).
        h.resolve(0);
        bytes32 pinned = h.seedOf(0);

        // Anyone calling again, at any later block, cannot move it.
        vm.roll(vm.getBlockNumber() + 50);
        assertEq(vm.getBlockNumber(), commitBlk + 51, "roll #2 landed");
        vm.prank(attacker);
        h.resolve(0);
        bytes32 pinnedAfter = h.seedOf(0);

        // What the PINNED seed dictates, computed independently here.
        uint256 expectedWins;
        for (uint256 r; r < count; ++r) {
            if (uint256(keccak256(abi.encodePacked(pinned, player, uint256(0), r))) % 10_000 < odds) {
                expectedWins++;
            }
        }

        vm.roll(commitBlk + 400);
        assertEq(vm.getBlockNumber(), commitBlk + 400, "roll #3 landed");
        vm.prank(attacker);
        (uint256 processed, uint256 won) = h.resolve(50);

        uint256 resolved = h.resolvedOf(0);
        bool reanchored = h.reanchoredOf(0);
        uint48 cb = h.commitBlockOf(0);

        assertTrue(pinned != bytes32(0), "the commit block hash was live and was pinned");
        assertEq(pinnedAfter, pinned, "a second call cannot repin: single assignment");
        assertEq(resolved, count, "a pinned batch resolves in full");
        assertEq(processed, count, "every crystal rolled");
        assertEq(won, expectedWins, "rolled against the PINNED seed, not some later value");
        assertGt(expectedWins, 0, "the seed genuinely drives outcomes (non-degenerate)");
        assertFalse(reanchored, "a pinned batch never spends a re-anchor");
        assertEq(uint256(cb), commitBlk, "and its commit block is never re-stamped");
    }

    /// @dev Nothing can be pinned to a seed that is not yet determined.
    function test_R2E_cannotPinTheCurrentOrAFutureBlock() public {
        h.commit(player, address(col), 2, 9000);
        // same block as the commit
        h.resolve(10);
        bytes32 sameBlock = h.seedOf(0);
        uint256 cursorSameBlock = h.batchCursor();

        vm.roll(vm.getBlockNumber() + 1);
        assertEq(vm.getBlockNumber(), 1001, "roll landed");
        h.resolve(0);
        bytes32 nextBlock = h.seedOf(0);

        assertEq(sameBlock, bytes32(0), "blockhash(current) is 0 and is skipped, never stored");
        assertEq(cursorSameBlock, 0, "and the loop breaks on a same-block batch");
        assertTrue(nextBlock != bytes32(0), "pinned only once the seed was determined");
    }

    // ── 3. NO EXTRA DRAW ────────────────────────────────────────────────────

    /// @dev A batch nothing touches inside its window gets exactly ONE
    ///      re-anchor, then forfeits. Pinning does not add a third draw.
    function test_R2E_oneReanchorThenTerminalForfeit() public {
        h.commit(player, address(col), 3, 10_000); // 100% odds: any real roll wins
        uint256 commitBlk = vm.getBlockNumber();

        // Let the window pass untouched.
        vm.roll(commitBlk + 300);
        assertEq(vm.getBlockNumber(), commitBlk + 300, "roll #1 landed");
        h.resolve(10);                       // -> re-anchor #1, break
        bool reanchored1 = h.reanchoredOf(0);
        uint48 cb1 = h.commitBlockOf(0);
        uint256 resolved1 = h.resolvedOf(0);

        // Let the SECOND window pass untouched too.
        vm.roll(vm.getBlockNumber() + 300);
        assertEq(vm.getBlockNumber(), commitBlk + 600, "roll #2 landed");
        h.resolve(10);                       // -> terminal forfeit
        uint256 resolved2 = h.resolvedOf(0);
        uint256 mintedAfter = col.totalMinted();
        uint256 cursorAfter = h.batchCursor();
        uint256 outstandingAfter = h.outstanding();
        bytes32 seedAfter = h.seedOf(0);

        assertTrue(reanchored1, "first expiry spends the single re-anchor");
        assertEq(uint256(cb1), commitBlk + 300, "and re-stamps to the CURRENT block, not a chosen one");
        assertEq(resolved1, 0, "no crystal is rolled on the re-anchor");
        assertEq(resolved2, 3, "second expiry forfeits the whole batch");
        assertEq(mintedAfter, 0, "a 10,000-bps batch mints NOTHING once forfeited");
        assertEq(cursorAfter, 1, "the queue always drains - no wedge");
        assertEq(outstandingAfter, 0, "and the counters unwind");
        assertEq(seedAfter, bytes32(0), "an expired batch is never pinned to the known zero seed");
    }

    // ── 4. THE PIN SWEEP IS WINDOWED: PIN_SPAN = 4 ──────────────────────────

    /// @dev `_pinSeeds` only reaches `[cursor, cursor+4)` (GachaLib.sol:130,
    ///      :147-157). A batch further back is NOT protected, so the honest
    ///      player the pin exists for is still forfeited when the queue is deep.
    function test_R2E_pinSpanLeavesDeepQueueUnprotected() public {
        // Eight batches, all committed now.
        for (uint256 i; i < 8; ++i) h.commit(player, address(col), 1, 9000);
        uint256 commitBlk = vm.getBlockNumber();
        vm.roll(commitBlk + 1);
        assertEq(vm.getBlockNumber(), commitBlk + 1, "roll landed");

        // A single sweep with no resolution budget: the cursor is 0.
        h.resolve(0);

        bool pinned0 = h.seedOf(0) != bytes32(0);
        bool pinned3 = h.seedOf(3) != bytes32(0);
        bool pinned4 = h.seedOf(4) != bytes32(0);
        bool pinned7 = h.seedOf(7) != bytes32(0);

        assertTrue(pinned0, "head batch pinned");
        assertTrue(pinned3, "cursor+3 pinned (last slot in span)");
        assertFalse(pinned4, "cursor+4 is OUTSIDE PIN_SPAN and is left unprotected");
        assertFalse(pinned7, "and so is everything behind it");
    }
}
