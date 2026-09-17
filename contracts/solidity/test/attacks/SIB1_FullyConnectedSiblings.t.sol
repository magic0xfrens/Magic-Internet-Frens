// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {IDeathChecker} from "../../cauldron/IDeathChecker.sol";

/**
 * SIB1 — FULLY-CONNECTED SIBLING LINKS (CauldronHook.linkVolume, commit c34a262).
 *
 *   CauldronHook.sol:1683-1689
 *       for (uint256 i; i < sib.length; ++i) {
 *           if (PoolId.unwrap(sib[i]) == PoolId.unwrap(secondary)) return; // already linked
 *           _addSibling(sib[i], secondary);
 *           _addSibling(secondary, sib[i]);
 *       }
 *       _addSibling(primary, secondary);
 *       _addSibling(secondary, primary);
 *
 *   CauldronHook.sol:1694-1702
 *       function _addSibling(PoolId a, PoolId b) private {
 *           PoolId[] storage s = _volumeSiblings[a];
 *           for (uint256 i; i < s.length; ++i) {
 *               if (PoolId.unwrap(s[i]) == PoolId.unwrap(b)) return;
 *           }
 *           if (s.length >= MAX_SIBLINGS) revert OnlyRegistry();
 *           s.push(b);
 *       }
 *
 * `_volumeSiblings` is private with no getter, so the list is observed the only
 * way it can be: through `isDead`, with a checker that reverts carrying the
 * summed volume the hook handed it (CauldronHook.sol:1718-1726). Volume is
 * injected straight into `_volumeBuckets` with `vm.store`; the bucket slot is
 * DISCOVERED at runtime (`_findBucketSlot`) and the discovery is itself
 * asserted, so this file cannot silently degrade into a no-op if the layout
 * moves.
 */
contract SIB1_FullyConnectedSiblings is Test {
    using stdStorage for StdStorage;

    CauldronHook hook;
    SibRecorder rec;
    uint256 bucketSlot = type(uint256).max;

    function setUp() public {
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(1)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(address(1)), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");
        hook.setRegistry(address(this)); // this test IS the registry
        rec = new SibRecorder();
        bucketSlot = _findBucketSlot();
    }

    // ── plumbing ────────────────────────────────────────────────────────────

    function _pid(uint256 n) internal pure returns (PoolId) {
        return PoolId.wrap(keccak256(abi.encode("SIB1", n)));
    }

    function _forceTracked(PoolId id) internal {
        stdstore.target(address(hook)).sig("trackedPools(bytes32)").with_key(PoolId.unwrap(id))
            .checked_write(true);
    }

    /// @dev Locate `mapping(PoolId => uint128[24]) private _volumeBuckets`
    ///      (CauldronHook.sol:277) by probing candidate slots with a throwaway id
    ///      until `getVolume24h` reports the value we wrote.
    function _findBucketSlot() internal returns (uint256) {
        PoolId probe = PoolId.wrap(keccak256("SIB1-probe"));
        for (uint256 s; s < 300; ++s) {
            bytes32 base = keccak256(abi.encode(PoolId.unwrap(probe), s));
            bytes32 prev = vm.load(address(hook), base);
            vm.store(address(hook), base, bytes32(uint256(777e15)));
            if (hook.getVolume24h(probe) == 777e15) {
                vm.store(address(hook), base, prev); // leave no residue
                return s;
            }
            vm.store(address(hook), base, prev);
        }
        revert("SIB1: _volumeBuckets slot not found");
    }

    function _setVolume(PoolId id, uint256 v) internal {
        bytes32 base = keccak256(abi.encode(PoolId.unwrap(id), bucketSlot));
        vm.store(address(hook), base, bytes32(v));
        assertEq(hook.getVolume24h(id), v, "volume injection landed");
    }

    /// @dev What total did the hook hand the death rule for `id`?
    ///      `isDead` swallows a reverting module (CauldronHook.sol:1725-1728), so a
    ///      revert-carrying recorder is invisible. Instead the module ANSWERS
    ///      `volume24h >= t` for a threshold the test moves, and the exact sum is
    ///      recovered by bisection on `t`.
    function _seenVolume(PoolId id) internal returns (uint256) {
        hook.setDeathChecker(address(rec));
        uint256 lo;                 // rec.answer(lo) is always true (vol >= 0)
        uint256 hi = 1 << 80;       // and always false up here
        rec.set(hi);
        require(!hook.isDead(id), "SIB1: bisection upper bound too low");
        rec.set(0);
        require(hook.isDead(id), "SIB1: recorder not wired");
        while (hi - lo > 1) {
            uint256 mid = lo + (hi - lo) / 2;
            rec.set(mid);
            if (hook.isDead(id)) lo = mid; else hi = mid;
        }
        hook.setDeathChecker(address(0));
        return lo;
    }

    // ── POSITIVE: the promise the change was made to keep ────────────────────
    // Every pool in a generation must report the GENERATION's volume, and the
    // number must be the plain sum — no pool counted twice from any start.
    struct Conn { uint256 total; uint256[4] seen; }

    function _buildStar(uint256 n) internal returns (uint256 total) {
        PoolId p = _pid(0);
        _forceTracked(p);
        _setVolume(p, 1e15);
        total = 1e15;
        for (uint256 i = 1; i <= n; ++i) {
            PoolId leg = _pid(i);
            _forceTracked(leg);
            uint256 v = 1e15 << i; // powers of two: any double count is visible
            _setVolume(leg, v);
            total += v;
            hook.linkVolume(p, leg); // the registry's exact call shape (RedemptionExt.sol:473)
        }
    }

    function _connectivity() internal returns (Conn memory c) {
        c.total = _buildStar(3);
        for (uint256 i; i < 4; ++i) c.seen[i] = _seenVolume(_pid(i));
    }

    function test_SIB_everyPoolReportsTheGenerationSumExactlyOnce() public {
        Conn memory c = _connectivity();
        console2.log("expected generation total", c.total);
        for (uint256 i; i < 4; ++i) console2.log("seen from pool", i, c.seen[i]);
        assertEq(c.seen[0], c.total, "primary sees the generation");
        assertEq(c.seen[1], c.total, "leg 1 sees the generation (the fix's whole point)");
        assertEq(c.seen[2], c.total, "leg 2 sees the generation");
        assertEq(c.seen[3], c.total, "leg 3 sees the generation");
    }

    // ── IDEMPOTENCE ──────────────────────────────────────────────────────────
    // `RedemptionExt.rotateSliceFrom` links on EVERY slice, and the early
    // `return` fires INSIDE the cross-link loop after some `_addSibling` calls
    // have already run. Re-linking in every order must not stack anything.
    struct Idem { uint256 before_; uint256 afterRepeats; uint256 afterReverse; }

    function _idem() internal returns (Idem memory r) {
        _buildStar(3);
        r.before_ = _seenVolume(_pid(0));
        PoolId p = _pid(0);
        // Repeat each link three times, in forward and shuffled order.
        for (uint256 k; k < 3; ++k) {
            hook.linkVolume(p, _pid(3));
            hook.linkVolume(p, _pid(1));
            hook.linkVolume(p, _pid(2));
        }
        r.afterRepeats = _seenVolume(p);
        // Asymmetric input: leg-as-primary, and leg-to-leg.
        hook.linkVolume(_pid(2), _pid(0));
        hook.linkVolume(_pid(1), _pid(3));
        hook.linkVolume(_pid(3), _pid(3)); // self-link: must be a silent no-op
        r.afterReverse = _seenVolume(p);
    }

    function test_SIB_relinkingInAnyOrderNeverStacks() public {
        Idem memory r = _idem();
        console2.log("before", r.before_);
        console2.log("after repeats", r.afterRepeats);
        console2.log("after reversed/leg-to-leg/self links", r.afterReverse);
        assertGt(r.before_, 0, "the star carries volume (not a vacuous 0==0 test)");
        assertEq(r.afterRepeats, r.before_, "repeat links double-counted");
        assertEq(r.afterReverse, r.before_, "reversed or self links double-counted");
    }

    // ── CAP: where does MAX_SIBLINGS bind, and is the failure atomic? ────────
    struct Cap {
        bool ninthOk;
        bool relinkAtCapOk;
        bool tenthReverted;
        bytes4 tenthErr;
        uint256 seenBefore;
        uint256 seenAfterFailedTenth;
        uint256 legListIntact;
    }

    function _cap() internal returns (Cap memory c) {
        // 1 primary + 9 legs = 10 pools = every list at exactly MAX_SIBLINGS.
        PoolId p = _pid(0);
        _forceTracked(p);
        _setVolume(p, 1e15);
        for (uint256 i = 1; i <= 9; ++i) {
            PoolId leg = _pid(i);
            _forceTracked(leg);
            _setVolume(leg, 1e15 << i);
            hook.linkVolume(p, leg);
        }
        c.ninthOk = true;

        // The L3 case: re-linking an ALREADY-linked quote while at the cap must
        // still succeed, because RedemptionExt links unconditionally per slice.
        hook.linkVolume(p, _pid(9));
        hook.linkVolume(p, _pid(1));
        c.relinkAtCapOk = true;

        c.seenBefore = _seenVolume(p);

        // A genuinely NEW tenth sibling.
        PoolId tenth = _pid(10);
        _forceTracked(tenth);
        _setVolume(tenth, 1e15 << 10);
        try hook.linkVolume(p, tenth) {
            c.tenthReverted = false;
        } catch (bytes memory err) {
            c.tenthReverted = true;
            c.tenthErr = bytes4(err);
        }
        c.seenAfterFailedTenth = _seenVolume(p);
        // And the revert must have rolled back the cross-links it had already
        // made into leg 1's list before it hit the cap.
        c.legListIntact = _seenVolume(_pid(1));
    }

    function test_SIB_capBindsAtTheTenthDistinctSiblingAndFailsAtomically() public {
        Cap memory c = _cap();
        console2.log("seen before the 10th", c.seenBefore);
        console2.log("seen after the failed 10th", c.seenAfterFailedTenth);
        console2.log("leg-1 view after the failed 10th", c.legListIntact);
        console2.logBytes4(c.tenthErr);
        assertTrue(c.ninthOk, "9 siblings link");
        assertTrue(c.relinkAtCapOk, "a re-link at the cap still succeeds (RedemptionExt:473 depends on it)");
        assertTrue(c.tenthReverted, "the 10th DISTINCT sibling is refused");
        assertEq(c.tenthErr, CauldronHook.OnlyRegistry.selector, "refused with OnlyRegistry()");
        assertEq(c.seenAfterFailedTenth, c.seenBefore, "the failed link left no residue on the primary");
        assertEq(c.legListIntact, c.seenBefore, "and none on the leg it had already cross-linked");
    }

    // ── GAS: linkVolume is now O(n^2) pushes, and runs on EVERY rotation slice ─
    struct GasR { uint256 fresh1; uint256 fresh5; uint256 fresh9; uint256 repeatWorstCase; }

    function _gas() internal returns (GasR memory g) {
        PoolId p = _pid(0);
        _forceTracked(p);
        for (uint256 i = 1; i <= 9; ++i) { _forceTracked(_pid(i)); }

        uint256 t = gasleft();
        hook.linkVolume(p, _pid(1));
        g.fresh1 = t - gasleft();

        for (uint256 i = 2; i <= 4; ++i) hook.linkVolume(p, _pid(i));
        t = gasleft();
        hook.linkVolume(p, _pid(5));
        g.fresh5 = t - gasleft();

        for (uint256 i = 6; i <= 8; ++i) hook.linkVolume(p, _pid(i));
        t = gasleft();
        hook.linkVolume(p, _pid(9));
        g.fresh9 = t - gasleft();

        // The repeat a rotation actually pays every slice: the destination is the
        // LAST entry in the primary's list, so the loop walks the whole list and
        // cross-scans all eight other lists before the early `return`.
        t = gasleft();
        hook.linkVolume(p, _pid(9));
        g.repeatWorstCase = t - gasleft();
    }

    function test_SIB_linkVolumeGasAtOneFiveAndNineSiblings() public {
        GasR memory g = _gas();
        console2.log("linkVolume gas, 1st sibling", g.fresh1);
        console2.log("linkVolume gas, 5th sibling", g.fresh5);
        console2.log("linkVolume gas, 9th sibling", g.fresh9);
        console2.log("linkVolume gas, repeat of the LAST sibling at 9", g.repeatWorstCase);
        assertGt(g.fresh9, g.fresh1, "cost grows with the set (O(n^2) pushes)");
        // A rotation slice must stay far inside a block.
        assertLt(g.fresh9, 3_000_000, "a fresh 9th link must not approach a block");
        assertLt(g.repeatWorstCase, 1_000_000, "the per-slice repeat must not approach a block");
    }

    // ── DEATH SEMANTICS: what changed for a LEG with no volume of its own ────
    // Before the change `isDead(leg)` summed the leg alone, so a freshly rotated
    // leg with zero trading read DEAD while its generation was alive. Assert the
    // new answer, and that nothing was made dead that used to be alive.
    struct Death { bool primaryDead; bool legDead; bool strangerDead; }

    function _death() internal returns (Death memory d) {
        PoolId p = _pid(0);
        PoolId leg = _pid(1);
        PoolId stranger = _pid(77);
        _forceTracked(p); _forceTracked(leg); _forceTracked(stranger);
        _setVolume(p, 5 ether);   // threshold is 1 ether (ctor arg)
        _setVolume(leg, 0);       // a rotated leg with no trading of its own
        hook.linkVolume(p, leg);
        d.primaryDead = hook.isDead(p);
        d.legDead = hook.isDead(leg);
        d.strangerDead = hook.isDead(stranger);
    }

    function test_SIB_aZeroVolumeLegIsNoLongerDeadWhileItsGenerationTrades() public {
        Death memory d = _death();
        console2.log("primary dead?", d.primaryDead);
        console2.log("zero-volume leg dead?", d.legDead);
        console2.log("unlinked stranger dead?", d.strangerDead);
        assertFalse(d.primaryDead, "an alive generation is alive from the primary");
        assertFalse(d.legDead, "and now also from the leg");
        assertTrue(d.strangerDead, "an unlinked tracked pool with no volume is still dead");
    }
}

/// Answers `summed volume >= t` so the test can bisect out the exact figure the
/// hook handed the death rule — the only way to observe the private
/// `_volumeSiblings` walk, since `isDead` catches a reverting module.
contract SibRecorder is IDeathChecker {
    uint256 public t;
    function set(uint256 v) external { t = v; }
    function isDead(PoolId, uint256 volume24h, uint256) external view returns (bool) {
        return volume24h >= t;
    }
}
