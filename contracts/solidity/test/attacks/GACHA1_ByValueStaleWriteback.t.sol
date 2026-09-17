// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GachaLib} from "../../cauldron/GachaLib.sol";

/**
 * GACHA1-g — FIXED: the loop's scalars are written IN PLACE, so a re-entrant
 * resolve cannot rewind the batch or desync the counters.
 *
 * Originally this PoC showed the by-value extraction's failure mode: one
 * requested crystal minted THREE NFTs, `outstandingCrystals` desynced from
 * `pendingOf`, and the queue bricked. The scalars now live in `GachaLib.State`
 * and cross as a storage reference; `b.resolved` and the counters are updated
 * BEFORE the mint (checks-effects-interactions); the cursor write is monotonic.
 * The same hostile host — no reentrancy guard, a collection whose mint re-enters
 * with write access — must now resolve exactly the crystals it was asked to,
 * once each.
 *
 * GachaLib.sol:66-68 take `batchCursor` and `outstandingCrystals` BY VALUE; the
 * caller stores the return values afterwards (CauldronHook.sol:2446-2447). Inside
 * the loop the per-batch progress marker is ALSO only flushed after the inner
 * `while` finishes:
 *
 *      GachaLib.sol:98   uint256 tokenId = ICauldronCollection(col).mint(player);
 *      GachaLib.sol:107  b.resolved = uint16(r);
 *
 * So during the mint call, `b.resolved`, `batchCursor` and `outstandingCrystals`
 * are ALL stale, while `pendingOf` / `outstandingOf` are already decremented.
 *
 * This host is the hook's gacha state with the SAME library call and NO
 * reentrancy guard — i.e. exactly what the hook would be if `nonReentrant` were
 * dropped from {resolveTickets}/{nativeGachaStep}, or if a second (unguarded)
 * caller of GachaLib were ever added. The collection is one whose `mint` yields
 * control with write access — which {CauldronCollection} does NOT do today
 * (it uses `_mint`, and its ERC-721C validator hook is a STATICCALL:
 * ICreatorToken.sol:8 `external view`). Precondition, therefore, is a future
 * collection / renderer / safe-mint, not today's.
 */
contract GACHA1_ByValueStaleWriteback is Test {
    GachaHost internal host;
    ReenterCollection internal col;
    address internal player = address(0xF00D);

    function setUp() public {
        host = new GachaHost();
        col = new ReenterCollection(address(host));
        vm.roll(1000);
    }

    function _run() internal returns (uint256 minted, uint256 outstanding, uint256 pending, bool drainBricked) {
        host.commit(player, address(col), 8, 10_000); // 8 crystals, always-win odds
        vm.roll(vm.getBlockNumber() + 1);
        col.arm(2); // the first mint re-enters and resolves 2 more tickets
        host.resolve(1); // outer: "resolve exactly one crystal"
        minted = col.totalMinted();
        outstanding = host.outstandingCrystals();
        pending = host.pendingOf(player);
        try host.resolve(30) { drainBricked = false; }
        catch { drainBricked = true; }
    }

    function test_GACHA1g_FIXED_reentrantMintCannotRewindOrDesync() public {
        (uint256 minted, uint256 outstanding, uint256 pending, bool bricked) = _run();

        emit log_named_uint("NFTs minted (1 outer + 2 re-entrant, each a DISTINCT crystal)", minted);
        emit log_named_uint("outstandingCrystals (written in place)", outstanding);
        emit log_named_uint("pendingOf[player] (written in the loop)", pending);
        emit log_named_string("drain of the remaining queue reverts", bricked ? "YES" : "no");

        //  Three crystals were consumed (outer's one, inner's two), no crystal
        //  rolled twice: 8 - 3 = 5 remain, and BOTH counters agree.
        assertEq(minted, 3, "re-entry duplicated or lost a mint");
        assertEq(outstanding, 5, "outstandingCrystals was rewound by a stale write-back");
        assertEq(pending, 5, "pendingOf drifted");
        assertEq(outstanding, pending, "counters desynced");
        //  `_run` drains after capturing the counters above, so by here the batch
        //  is complete. The "flushed BEFORE the mint" property is what
        //  `minted == 3` already proves: a late flush would have let the
        //  re-entrant frame re-roll crystal 0 and mint a 4th.
        assertEq(host.resolvedOf(0), 8, "drain did not complete the batch");
        assertFalse(bricked, "the queue bricked");
        //  And the drain finishes the batch: 8 crystals, all-win odds, 8 NFTs.
        assertEq(col.totalMinted(), 8, "drain did not resolve exactly the remaining crystals");
        assertEq(host.outstandingCrystals(), 0, "leftover outstanding after a full drain");
        assertEq(host.pendingOf(player), 0, "leftover pending after a full drain");
    }
}

/// @notice The hook's gacha storage + the exact library call, minus nonReentrant.
contract GachaHost {
    GachaLib.Batch[] public batches;
    mapping(address => uint256) public missStreak;
    mapping(address => uint256) public pendingOf;
    mapping(address => uint256) public outstandingOf;
    mapping(address => uint256) public opened;
    GachaLib.State internal gacha;
    uint256 public pityThreshold = 8;
    function batchCursor() external view returns (uint256) { return gacha.batchCursor; }
    function outstandingCrystals() external view returns (uint256) { return gacha.outstandingCrystals; }

    function commit(address player, address col, uint16 count, uint16 odds) external {
        pendingOf[player] += count;
        gacha.outstandingCrystals += count;
        outstandingOf[col] += count;
        batches.push(
            GachaLib.Batch({
                player: player,
                collection: col,
                commitBlock: uint48(block.number),
                oddsBps: odds,
                count: count,
                resolved: 0
            })
        );
    }

    function resolve(uint256 maxCount) external returns (uint256 processed, uint256 won) {
        (processed, won) = GachaLib.resolveTickets(
            batches, missStreak, pendingOf, outstandingOf, opened, gacha, pityThreshold, maxCount
        );
    }

    function resolvedOf(uint256 i) external view returns (uint16) { return batches[i].resolved; }
}

/// @notice A collection whose mint hands control back with WRITE access — a
///         safe-mint receiver hook, a stateful renderer, or a non-view validator.
contract ReenterCollection {
    uint256 public totalMinted;
    uint256 public maxSupply = 1000;
    GachaHost internal immutable host;
    uint256 internal armedFor;

    constructor(address h) { host = GachaHost(h); }

    function arm(uint256 n) external { armedFor = n; }

    function mint(address) external returns (uint256 tokenId) {
        tokenId = ++totalMinted;
        uint256 n = armedFor;
        if (n != 0) {
            armedFor = 0; // one re-entry only
            host.resolve(n);
        }
    }
}
