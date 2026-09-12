// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {MockQuoteToken} from "../cauldron/MockQuoteToken.sol";
import {QuoteRotator} from "../cauldron/QuoteRotator.sol";
import {IPositionManagerOps} from "../cauldron/PoolOps.sol";
import {VenueSeeder} from "./DeployRotationStack.s.sol";

/**
 * @notice Give the LIVE ETH/USDG rotation venue enough depth for a rotation to
 *         actually clear its price floor, without redeploying anything.
 *
 *  ── WHY THIS EXISTS ──────────────────────────────────────────────────────
 *  Round 40 is wired correctly: the venue is curated, the oracle prices both
 *  legs, the governor is reachable, and `rotateSliceFrom` reverts with exactly
 *  `NoRotationApproved` — i.e. the only thing missing is a vote. But a vote
 *  would then have produced a slice that could not fill:
 *
 *      generation LP, quote side   0.251335 ETH
 *      one 25% slice               0.062834 ETH   ($159)
 *      venue depth                 0.005    ETH   ($15 of USDG)
 *
 *  The slice is TWELVE TIMES the entire book it is swapping into. `rotateSlice`
 *  floors the fill at the ORACLE's valuation ({QuoteRotator._oracleFloor}), so
 *  this does not execute badly — it reverts `SlippageTooHigh`, which reads like
 *  a governance failure and is really a liquidity one.
 *
 *  The venue positions are FULL RANGE (PoolOps._seedActive spans
 *  MIN_TICK..MAX_TICK), so the book behaves like constant product and the
 *  slippage of a trade `x` into reserve `X` is `x/(X+x)`. Clearing a 3% floor
 *  therefore needs `X >= 32x` — about 2 ETH for the slice above. VENUE_TOPUP_ETH
 *  defaults to that.
 *
 *  ── THE ETH IS RECOVERABLE, AND THAT IS NOT INCIDENTAL ───────────────────
 *  The deployed VenueSeeder had no withdraw path at all: it minted a position,
 *  stored the id and exposed nothing, so its 0.005 ETH is stranded permanently.
 *  That is survivable at 0.005 and not at 2. This script deploys a FRESH seeder
 *  carrying `recover()`, and prints its address — run {RecoverVenue} against it
 *  to pull the position and both token sides back to the deployer.
 *
 *  USDG is over-supplied on purpose. `_seedActive` sizes liquidity from the
 *  pool's LIVE price and consumes only what that ratio needs; anything left over
 *  sits in the seeder and comes back with `recover()`. Under-supplying instead
 *  reverts the mint, so the asymmetry is deliberate.
 */
contract TopUpVenue is Script {
    uint24 internal constant VENUE_FEE = 3000;
    int24 internal constant VENUE_SPACING = 60;

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address usdg = vm.envAddress("USDG");
        address rotator = vm.envAddress("QUOTE_ROTATOR");

        //  2 ETH clears a 3% floor for a 0.063 ETH slice with headroom for the
        //  cumulative drift across all twelve slices of an envelope — by the
        //  last one the venue has already absorbed eleven buys.
        uint256 topUpEth = vm.envOr("VENUE_TOPUP_ETH", uint256(2 ether));
        //  Deliberately generous; the remainder is recoverable. At the pool's
        //  live price (~$3000/ETH) 2 ETH pairs with ~6,000 USDG.
        uint256 mintUsdg = vm.envOr("VENUE_TOPUP_USDG", uint256(20_000e6));
        uint256 slipBps = vm.envOr("ROTATION_SLIP_BPS", uint256(0));

        vm.startBroadcast();

        VenueSeeder vs = new VenueSeeder();
        MockQuoteToken(usdg).mint(address(vs), mintUsdg);
        vs.seed{value: topUpEth}(
            IPoolManager(poolManager), IPositionManagerOps(positionManager),
            usdg, topUpEth, mintUsdg, VENUE_SPACING, VENUE_FEE
        );

        //  Widening the floor is OPTIONAL and separate. Depth is the real fix;
        //  a wider floor just buys margin. Left untouched unless asked, because
        //  a 20% floor is a 20% haircut an unlucky slice is permitted to take.
        if (slipBps != 0) {
            QuoteRotator(payable(rotator)).setRotationSlipBps(uint16(slipBps));
            console2.log("rotationSlipBps set to:", slipBps);
        }

        vm.stopBroadcast();

        console2.log("VenueSeeder (RECOVERABLE):", address(vs));
        console2.log("  position id            :", vs.positionId());
        console2.log("  eth added              :", topUpEth);
        console2.log("  usdg supplied          :", mintUsdg);
        console2.log("KEEP THIS ADDRESS - it holds the venue LP and the USDG remainder.");
    }
}

/**
 * @notice Pull a {VenueSeeder}'s position and balances back to the deployer.
 * @dev Separate contract so recovery never needs the seeding parameters.
 */
contract RecoverVenue is Script {
    function run() external {
        address seeder = vm.envAddress("VENUE_SEEDER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address usdg = vm.envAddress("USDG");

        //  currency0 is native, currency1 is USDG: USDG sorts above address(0),
        //  and the allowlist pins fee/spacing/hooks, so this key is the venue's
        //  by construction rather than by convention.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(usdg),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        vm.startBroadcast();
        (uint256 ethOut, uint256 usdgOut) =
            VenueSeeder(payable(seeder)).recover(IPositionManagerOps(positionManager), key, usdg);
        vm.stopBroadcast();

        console2.log("recovered eth :", ethOut);
        console2.log("recovered usdg:", usdgOut);
    }
}
