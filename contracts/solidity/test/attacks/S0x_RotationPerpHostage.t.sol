// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CauldronHook} from "../../CauldronHook.sol";

/**
 *  S-0x — ONE DUST PERP POSITION HOLDS AN APPROVED QUOTE ROTATION HOSTAGE.
 *
 *  `RedemptionExt.rotateSliceFrom` calls `hook.linkVolume` UNCONDITIONALLY
 *  (RedemptionExt.sol:472) and `CauldronHook.linkVolume` reverts `PerpsOpen()`
 *  whenever `openCount > 0` (CauldronHook.sol:1623-1625). Nothing can close a
 *  solvent position except its owner: `forceCloseDead`/`forceCloseAllDead` both
 *  demand `_isDead()` (PerpEngine.sol:1130, :1148).
 *
 *  So any stranger who keeps one minimum-size position open denies every slice
 *  of a governance-approved rotation until the envelope EXPIRES, and the guild
 *  then eats another COOLDOWN before it may even propose again.
 */
contract S0x_RotationPerpHostage is YBase {
    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;

    address internal hostage = address(0xBADBEEF);

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(10 ether, 50_000_000 ether);

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new SVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));
    }

    // -------------------------------------------------------------- positive
    /// @notice LIVENESS CONTROL: with an empty perp book the approved rotation
    ///         runs to completion and the generation re-denominates. This is the
    ///         property the attack below removes.
    function test_S0x_LIVENESS_RotationCompletesWithAnEmptyPerpBook() public {
        assertTrue(active, "fork harness must be live (FORK_RPC)");
        PoolKey memory route = _seedVenue();
        _approveEnvelope();

        uint256 slices = _rotateUntilSpent(route);
        address quoteAfter = registry.generationQuote(1);

        assertGt(slices, 0, "control: no slice executed");
        assertEq(quoteAfter, address(usdg), "control: generation must re-denominate");
    }

    // ---------------------------------------------------------------- attack
    /// @notice ATTACK: a single minimum-size position, opened by a stranger,
    ///         blocks every slice until the envelope dies of old age.
    function test_S0x_DustPerpPositionHoldsTheApprovedRotationHostage() public {
        assertTrue(active, "fork harness must be live (FORK_RPC)");
        PoolKey memory route = _seedVenue();
        _approveEnvelope();

        (, uint16 remAtStart) = governor.allowance();

        vm.deal(hostage, 1 ether);
        uint256 spendBefore = hostage.balance;
        uint256 posId = _openDust();
        uint256 openCount = perp.openCount();

        bool firstSlice = _trySlice(route);
        (, uint16 remAfterBlock) = governor.allowance();

        // Wait out the whole envelope. Nothing in the tree closes a solvent
        // position for the attacker, so the block holds the entire time.
        _warp(uint256(governor.ENVELOPE_LIFETIME()) + 1);
        (address destAfter, uint16 remAfterExpiry) = governor.allowance();
        bool lateSlice = _trySlice(route);

        // The grief is REPEATABLE: the guild votes a second envelope while the
        // same dust position is still open, and that one is blocked too.
        _approveEnvelope();
        (, uint16 remSecond) = governor.allowance();
        bool secondEnvelopeSlice = _trySlice(route);

        // The hostage-taker gets their stake back and walks.
        vm.prank(hostage, hostage);
        perp.close(posId, 0);
        uint256 netCost = spendBefore - hostage.balance;

        console2.log("open positions during the block:", openCount);
        console2.log("attacker net cost (wei):", netCost);
        console2.log("envelope bps unspent:", remAfterBlock);
        console2.log("slice revert selector:", vm.toString(lastSliceRevert));
        console2.log("PerpsOpen selector:", vm.toString(CauldronHook.PerpsOpen.selector));

        assertEq(openCount, 1, "one dust position is open");
        assertFalse(firstSlice, "ATTACK: the approved slice must have been blocked");
        assertEq(remAfterBlock, remAtStart, "the envelope was never spent");
        assertFalse(lateSlice, "ATTACK: still blocked when the envelope expires");
        assertEq(destAfter, address(0), "envelope expired unspent");
        assertEq(remAfterExpiry, 0, "envelope expired unspent");
        assertGt(remSecond, 0, "a second envelope was approved");
        assertFalse(secondEnvelopeSlice, "ATTACK: the second envelope is blocked by the same position");
        assertEq(registry.generationQuote(1), address(0), "no re-denomination happened");
        assertLt(netCost, 0.01 ether, "the whole grief costs less than 0.01 ETH of stake");
    }


    // ------------------------------------------------- second attack surface
    /// @notice The death read is ONE-SIDED. `linkVolume` pushes the destination
    ///         pool onto the PRIMARY's sibling list only
    ///         (CauldronHook.sol:1635 — the single write to `_volumeSiblings`),
    ///         while `isDead` sums `id` plus `_volumeSiblings[id]`
    ///         (CauldronHook.sol:1659-1661). After a completed rotation the perp
    ///         engine's `_pid()` is the DESTINATION pool (PerpEngine.sol:568-575,
    ///         built from the adopted `quote`), whose sibling list is empty — so
    ///         the engine reads its own generation as dead while the generation is
    ///         demonstrably alive on the primary.
    function test_S0x_RotatedLegDeathReadIsOneSided() public {
        assertTrue(active, "fork harness must be live (FORK_RPC)");
        PoolKey memory route = _seedVenue();
        _approveEnvelope();
        uint256 slices = _rotateUntilSpent(route);

        CauldronHook h = registry.hook();
        address token = registry.generationToken(1);
        PoolId legId = PoolIdLibrary.toId(PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(h))
        }));
        PoolId primaryId = registry.generationPoolId(1);

        // Real trading on the primary pair — it still holds the residual tail and
        // is perfectly alive.
        SPrimaryBuyer buyer = new SPrimaryBuyer(pm, CauldronRegistryLike(address(registry)));
        vm.deal(address(buyer), 3 ether);
        buyer.buy(0.5 ether);

        uint256 primaryVol = h.getVolume24h(primaryId);
        uint256 legVol = h.getVolume24h(legId);

        // Any threshold the generation's own trading clears.
        vm.prank(h.owner());
        h.setDeathThreshold(primaryVol, address(0), 0, 0, 0);

        bool genDead = h.isDead(primaryId);
        bool legDead = h.isDead(legId);
        address engineQuote = perp.quote();
        bool openRefused = _openReverts();

        console2.log("slices:", slices);
        console2.log("primary vol24h:", primaryVol);
        console2.log("leg vol24h:", legVol);
        console2.log("engine marks the leg:", engineQuote == address(usdg));

        assertGt(slices, 0, "rotation must have run");
        assertEq(registry.generationQuote(1), address(usdg), "rotation completed");
        assertEq(engineQuote, address(usdg), "engine adopted the destination pool");
        assertGt(primaryVol, 0, "the generation is trading");
        assertEq(legVol, 0, "the destination pool has no volume of its own");
        assertFalse(genDead, "the generation is ALIVE on its primary pool");
        assertTrue(legDead, "ATTACK: the pool the engine now marks reads DEAD");
        console2.logBytes4(lastOpenErr); // 0xefba5120 TokenDead / 0x949682a5 NotWarm
        assertTrue(openRefused, "an open is refused right after the rotation");
        //  THE FIX: the refusal must no longer be TokenDead. `_isDead()` now asks
        //  the hook about the generation's PRIMARY pool, which carries the sibling
        //  list, instead of the leg the engine was re-pointed at — so a live
        //  rotated generation no longer reads as dead. NotWarm is the correct and
        //  self-healing refusal here (the ring was reset by `syncGeneration`).
        assertTrue(lastOpenErr != bytes4(0xefba5120), "FIXED: a live rotated generation must not read TokenDead");
    }

    // --------------------------------------------------------------- helpers
    function _openDust() internal returns (uint256 id) {
        uint256 col = perp.minCollateral() * 2;
        vm.prank(hostage, hostage);
        id = perp.openLong{value: col}(1, 0, 0, col);
    }

    function _trySlice(PoolKey memory route) internal returns (bool ok) {
        try registry.rotateSlice(2500, 0, route) { ok = true; }
        catch (bytes memory err) { ok = false; lastSliceRevert = bytes4(err); }
    }

    bytes4 internal lastSliceRevert;

    //  WHICH refusal, not merely THAT it refused. "open reverted" conflates a
    //  permanent TokenDead (the finding) with a temporary NotWarm — `syncGeneration`
    //  deletes the observation ring, so a rotation legitimately blocks opens until
    //  the ring spans `twapWindow` again (PerpEngine.sol:1704-1713, red-team H-4).
    //  Without the selector the test cannot tell a bug from designed behaviour.
    /**
     * THE FIX, FROM THE OTHER SIDE. The hostage test above proves the block still
     * applies with NO weighted mark armed (fail-closed, unchanged behaviour).
     * This proves the block LIFTS once the guild arms one.
     *
     * `CauldronHook.linkVolume` now asks {PerpEngine.blocksVolumeLink} instead of
     * counting positions itself, and the engine answers
     * `openCount != 0 && markSource == address(0)`. The interlock existed only
     * because a generation split across pools makes a single-pool mark
     * manipulable; a liquidity-weighted mark is exactly the condition the hook's
     * own note named as "the real fix", and it shipped as {PerpMarkSource}.
     */
    function test_S0x_FIXED_WeightedMarkLetsTheApprovedRotationProceed() public {
        assertTrue(active, "fork harness must be live (FORK_RPC)");

        PoolKey memory route = _seedVenue();

        //  Same hostage as the attack test: a stranger's dust position.
        vm.deal(hostage, 1 ether);
        _openDust();
        assertEq(perp.openCount(), 1, "one dust position is open");

        //  Control: with no mark source armed the engine still blocks the link.
        assertTrue(perp.blocksVolumeLink(), "control: blocked while the mark is single-pool");

        //  The guild arms the liquidity-weighted mark for this generation.
        PerpMarkSource ms = new PerpMarkSource(pm, address(this));
        ms.setPrimary(_key());
        perp.setRouting(address(0), address(0), address(0), address(ms), address(0));

        assertFalse(perp.blocksVolumeLink(), "FIXED: a weighted mark lifts the block");

        //  And the approved slice now actually executes over the open book.
        _approveEnvelope();
        bool sliced = _trySlice(route);
        assertTrue(sliced, "FIXED: the governance-approved slice is no longer hostage");
        assertEq(perp.openCount(), 1, "the stranger's position was NOT confiscated");
    }

    bytes4 lastOpenErr;
    /// Opens in whatever currency the engine CURRENTLY quotes. Sending native
    /// value into a rotated (USDG) book reverts `BadParam()` (0xde17a3af) before
    /// any death check runs, so the original native-only helper reported
    /// "refused" for a reason that has nothing to do with the finding.
    function _openReverts() internal returns (bool reverted) {
        uint256 col = perp.minCollateral() * 2;
        lastOpenErr = bytes4(0);
        //  PAST THE RING WARMUP FIRST. `_guardOpen` checks NotWarm BEFORE
        //  TokenDead (PerpEngine.sol:1713-1714), and `syncGeneration` resets the
        //  observation ring, so without this warp every open reports NotWarm and
        //  the death check is never reached — the test cannot see the finding at
        //  all. Warp the ring window, then poke so the ring actually spans it.
        _warp(perp.twapWindow() + 1);
        perp.poke();
        address q = perp.quote();
        if (q == address(0)) {
            vm.deal(hostage, 1 ether);
            vm.prank(hostage, hostage);
            try perp.openLong{value: col}(1, 0, 0, col) { reverted = false; }
            catch (bytes memory e) { reverted = true; if (e.length >= 4) lastOpenErr = bytes4(e); }
        } else {
            MockQuoteToken(q).mint(hostage, col * 10);
            vm.startPrank(hostage, hostage);
            MockQuoteToken(q).approve(address(perp), type(uint256).max);
            try perp.openLong(1, 0, 0, col) { reverted = false; }
            catch (bytes memory e) { reverted = true; if (e.length >= 4) lastOpenErr = bytes4(e); }
            vm.stopPrank();
        }
    }

    function _proposeReverts() internal returns (bool reverted) {
        try governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS()) { reverted = false; }
        catch { reverted = true; }
    }

    function _approveEnvelope() internal {
        uint256 id = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(id, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(id);
    }

    function _rotateUntilSpent(PoolKey memory route) internal returns (uint256 slices) {
        for (uint256 i; i < 20; ++i) {
            (address open,) = governor.allowance();
            if (open == address(0)) break;
            if (!_trySlice(route)) break;
            slices++;
        }
    }

    function _seedVenue() internal returns (PoolKey memory route) {
        uint256 venueUsdg = 400_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 40 ether, venueUsdg, 60, 3000
        );
        route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        rotator.setVenue(route, true);
    }
}

contract SVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}

/// @dev A plain trader on the generation's primary pool.
contract SPrimaryBuyer {
    IPoolManager internal immutable pm;
    CauldronRegistryLike internal immutable reg;
    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;

    constructor(IPoolManager _pm, CauldronRegistryLike _reg) { pm = _pm; reg = _reg; }
    receive() external payable {}

    function buy(uint256 ethIn) external returns (uint256 got) {
        got = abi.decode(pm.unlock(abi.encode(ethIn)), (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        uint256 ethIn = abi.decode(data, (uint256));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(reg.currentToken()),
            fee: reg.POOL_FEE(),
            tickSpacing: reg.TICK_SPACING(),
            hooks: IHooks(address(reg.hook()))
        });
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            abi.encode(address(this))
        );
        pm.settle{value: uint256(uint128(-d.amount0()))}();
        uint256 got = uint256(uint128(d.amount1()));
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }
}

interface CauldronRegistryLike {
    function currentToken() external view returns (address);
    function POOL_FEE() external view returns (uint24);
    function TICK_SPACING() external view returns (int24);
    function hook() external view returns (address);
}
