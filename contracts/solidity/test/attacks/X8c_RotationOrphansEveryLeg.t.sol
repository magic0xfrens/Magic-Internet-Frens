// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "./YBase.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  X-8c — EVERY SLICE AFTER THE FIRST ORPHANED THE LEG BEFORE IT
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  MECHANISM (reproduced live on Sepolia round 40, generation 1, ETH -> USDG).
 *
 *  `RedemptionExt.rotateSliceFrom` redeploys the converted quote through
 *  `PoolOps.openOrAddPair`, whose header claims it "tops up" an existing pair.
 *  It does top up the POOL — but `_seedActive` (PoolOps.sol:759) always issues
 *  `MINT_POSITION`, so every slice gets a BRAND NEW PositionManager NFT. The
 *  leg book then did:
 *
 *      if (legs[i].quote == quote) { legs[i].positionId = positionId; return; }
 *
 *  i.e. it OVERWROTE the id. The previous NFT stayed owned by the registry with
 *  all of its liquidity intact and nothing on chain referencing it.
 *
 *  NO RECOVERY PATH EXISTED. `recoverLegs`, `recoverLegsAtTeardown` and
 *  `_recoverLegs` all iterate `generationLegs[gen]`, which holds exactly ONE
 *  entry per quote — the latest. There is no external function anywhere on
 *  `RedemptionExt` or `CauldronRegistry` that takes an arbitrary `positionId`,
 *  so the orphans could never be unwound, by anyone, at any privilege level.
 *
 *  MEASURED ON SEPOLIA r40 — one full 30,000-bps envelope, 12 slices of 25%:
 *  positions 39263..39273 orphaned (643.02 USDG), position 39274 tracked
 *  (6.32 USDG). 99.0% of the rotated treasury permanently stuck. The defect is
 *  WORSE the better the rotation works: a single-slice rotation is fine.
 *
 *  THIS TEST runs the FULL envelope the governor allows (MAX_ENVELOPE_BPS =
 *  30,000 = 12 slices of 2,500) and asserts the two properties that hold if and
 *  only if no position is orphaned:
 *
 *    A. every PositionManager id `rotateSlice` ever returned, other than the one
 *       the leg book now points at, holds ZERO liquidity; and
 *    B. the liquidity of the leg the recovery path CAN see is the ENTIRE
 *       destination pool — nothing sits beside it.
 *
 *  FIX: the leg's previous position is folded in (`PoolOps.removeAll`, which
 *  burns the NFT and returns both sides by balance delta) before the redeploy,
 *  so the destination always carries exactly ONE live position and the leg book
 *  never loses a reference. See RedemptionExt.sol, step 3 of `rotateSliceFrom`.
 */
contract X8c_RotationOrphansEveryLeg is YBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    QuoteRotator internal rotator;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);
        governor = new TreasuryGovernor(
            IVotes721(address(new XVotes())), address(registry), address(this), 0, 0, 0, 0, false
        );
        registry.setRotationWiring(address(rotator), address(governor));
    }

    /// @notice THE REGRESSION. Run a complete 12-slice envelope and assert that
    ///         every unit of rotated USDG is still reachable through the ONE leg
    ///         the recovery path iterates.
    function test_X8c_FullEnvelopeOrphansNoPosition() public {
        vm.skip(!active);

        PoolKey memory route = _seedVenue();

        // Approve the largest envelope the governor permits, exactly as the guild
        // did on r40: 30,000 bps, which is 12 slices of 2,500.
        uint256 pid = governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS());
        vm.roll(vm.getBlockNumber() + 1);
        governor.vote(pid, true);
        _warp(governor.VOTING_PERIOD() + 1);
        governor.execute(pid);

        uint256[] memory ids = new uint256[](32);
        uint256 slices;
        uint256 totalMoved;
        for (uint256 i; i < 20; ++i) {
            (, uint16 remaining) = governor.allowance();
            if (remaining < 2500) break;
            try registry.rotateSlice(2500, 0, route) returns (uint256 moved, uint256 posId) {
                ids[slices] = posId;
                totalMoved += moved;
                slices++;
            } catch (bytes memory err) {
                console2.log("slice reverted after", slices);
                console2.log(vm.toString(err));
                break;
            }
        }

        //  A one-slice rotation is not a reproduction: the defect only appears
        //  from the SECOND slice into the same destination onward.
        assertGt(slices, 1, "the envelope must run more than one slice");
        console2.log("slices executed:", slices);
        console2.log("total USDG rotated:", totalMoved);

        //  The leg book still holds exactly one entry for the destination quote.
        assertEq(registry.legCount(1), 1, "one leg per quote");
        (address legQuote, uint256 trackedId,) = registry.legAt(1, 0);
        assertEq(legQuote, address(usdg), "the leg is the USDG leg");

        IPositionManagerOps posm_ = IPositionManagerOps(posm);
        uint128 tracked = posm_.getPositionLiquidity(trackedId);
        assertGt(tracked, 0, "the tracked leg holds liquidity");

        //  ── A. NOTHING THE ROTATION MINTED IS UNREFERENCED ─────────────────
        uint256 orphanLiquidity;
        uint256 orphanCount;
        for (uint256 i; i < slices; ++i) {
            if (ids[i] == trackedId) continue;
            uint256 liq = posm_.getPositionLiquidity(ids[i]);
            if (liq > 0) {
                orphanCount++;
                orphanLiquidity += liq;
                console2.log("ORPHANED position", ids[i], liq);
            }
        }
        console2.log("orphan positions:", orphanCount);
        console2.log("orphan liquidity:", orphanLiquidity);
        if (orphanLiquidity + tracked > 0) {
            console2.log(
                "USDG unreachable (pro-rata of rotated):",
                (totalMoved * orphanLiquidity) / (orphanLiquidity + tracked)
            );
        }
        assertEq(
            orphanLiquidity,
            0,
            "a rotated position holds liquidity no recovery path can reach"
        );

        //  ── B. THE LEG IS THE WHOLE POOL ───────────────────────────────────
        //  Nobody else LPs the destination pair and every position the rotation
        //  opens is full-range, so the in-range liquidity of the pool must equal
        //  the liquidity of the single leg the teardown can see. If a slice
        //  orphaned a position this is strictly greater.
        PoolKey memory destKey = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        uint128 poolLiquidity = pm.getLiquidity(destKey.toId());
        console2.log("destination pool liquidity:", poolLiquidity);
        console2.log("recoverable leg liquidity:", tracked);
        assertEq(
            uint256(tracked),
            uint256(poolLiquidity),
            "the recoverable leg must be the entire destination pool"
        );
    }

    /// @dev Stand up and curate the ETH/USDG venue the rotation swaps through.
    function _seedVenue() internal returns (PoolKey memory route) {
        uint256 venueUsdg = 4_000_000e6;
        usdg.mint(address(this), venueUsdg);
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(posm), address(0),
            address(usdg), address(0), 400 ether, venueUsdg, 60, 3000
        );
        route = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        rotator.setVenue(route, true);
    }
}

contract XVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}
