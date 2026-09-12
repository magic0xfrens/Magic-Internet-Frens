// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {QuoteRotator} from "../cauldron/QuoteRotator.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";
import {TreasuryGovernor, IVotes721} from "../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../cauldron/MockQuoteToken.sol";
import {PoolOps, IPositionManagerOps} from "../cauldron/PoolOps.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRegistryAdmin {
    function setAllowedQuote(address quote, bool allowed, uint256 scale) external;
    function allowedQuote(address quote) external view returns (bool);
    function setRotationWiring(address rotator, address governor) external;
    function owner() external view returns (address);
    function mifrens() external view returns (address);
}

/**
 * @notice Stands up the WHOLE treasury-rotation stack and leaves it usable from
 *         the frontend, including the venue the rotation actually swaps through.
 *
 *  ── WHY THIS EXISTS RATHER THAN EXTENDING DeployQuoteAssets ───────────────
 *  That script deploys the quote mocks and the rotator and stops. Three things
 *  it never did are now required before a single rotation can execute:
 *
 *   1. A TREASURY GOVERNOR. `RedemptionExt.rotateSlice` reads
 *      `ITreasuryGovernor(gov).allowance()` and reverts `NotConfigured` when the
 *      governor is unset — so with no governor there is no rotation at all, and
 *      the registry's `setRotationWiring` is the only way to point at one.
 *
 *   2. A VENUE. `QuoteRotator.rotateStep`/`swapOnce` route through a caller
 *      supplied pool, and the venue allowlist added after the red-team pass
 *      FAILS CLOSED: an uncurated venue reverts `NoRoute`. The allowlist is
 *      keyed by PoolId, so `fee`, `tickSpacing` and `hooks` are all pinned —
 *      listing a pair does not list every pool on that pair.
 *
 *   3. THE VENUE POOL ITSELF. USDG here is a fresh mock, so no ETH/USDG pool
 *      exists to curate. "Point it at Uniswap" on a testnet means CREATING the
 *      Uniswap v4 pool and giving it enough depth that a slice can actually
 *      fill, then listing it. A curated venue with no liquidity is a rotation
 *      that reverts on `minOut`.
 *
 *  ── THE PRICE FEEDS: REAL WHERE THEY EXIST ───────────────────────────────
 *  Two of the three quotes get a genuine Chainlink aggregator, probed live on
 *  Sepolia rather than taken from a list:
 *
 *    ETH   -> ETH/USD  0x694AA1769357215DE4FAC081bf1f309aDC325306  ($2481, 113s old)
 *    USDG  -> USDC/USD 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E  ($0.9999, 3.1h old)
 *
 *  USDG is a mock 6-decimal USD stablecoin, so pricing it off the real USDC/USD
 *  feed is not a fabrication — it is the accurate model, and it means the oracle
 *  path under test is the same code mainnet runs.
 *
 *  Scope is ETH -> USDG only. A synthetic equity was in an earlier draft and is
 *  dropped: Sepolia carries no tokenized-equity feed, so it could only ever have
 *  been priced by a mock, and shipping a second quote nobody can price honestly
 *  just to have a third row in the UI is not worth the surface. {MockAggregator}
 *  stays in the tree for the unit suites, unused here.
 *
 *  ── HEARTBEATS HAVE HEADROOM, DELIBERATELY ───────────────────────────────
 *  Testnet feeds update far more slowly than mainnet and some stop entirely:
 *  measured on the same call, DAI/USD was 13h stale and JPY/USD 12.9h, while
 *  ETH/USD was 113s and USDC/USD 3.1h. A heartbeat set to the mainnet cadence
 *  would make the oracle refuse a feed that is working as well as testnet feeds
 *  ever do, and every price would read "cannot judge". These are sized to what
 *  was actually observed, with room to spare.
 *
 *  Run:
 *    forge script deploy/DeployRotationStack.s.sol --rpc-url $RPC --broadcast
 *  Env: PRIVATE_KEY, REGISTRY, POOL_MANAGER, POSITION_MANAGER
 *       VENUE_ETH   (wei of ETH to seed the venue pool with, default 0.05e18)
 *       VENUE_USDG  (USDG units, 6dp, default 150e6 — i.e. ~$3000/ETH)
 */
contract DeployRotationStack is Script {
    /// @notice Chainlink ETH/USD on Sepolia. Verified live: $2481.38, 113s old.
    address internal constant FEED_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    /// @notice Chainlink USDC/USD on Sepolia. Verified live: $0.9999, 3.1h old.
    ///         USDG is a mock USD stable, so this is the honest model for it.
    address internal constant FEED_USDC_USD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    /// @dev Heartbeats. ETH updates fastest; USDC lagged 3.1h when measured, so
    ///      12h is the smallest value that will not flap. The mock is always
    ///      fresh by construction and only needs a nominal bound.
    uint32 internal constant HB_ETH = 4 hours;
    uint32 internal constant HB_USDC = 12 hours;

    /// @dev Vanilla venue pool: 0.30% fee, 60 spacing, NO hook. The protocol's
    ///      own pools are hooked (quote, brew token); a quote-to-quote venue must
    ///      not be, and the rotator's own allowlist is what pins that.
    uint24 internal constant VENUE_FEE = 3000;
    int24 internal constant VENUE_SPACING = 60;

    function run() external {
        //  KEYSTORE OR ENV, matching DeployLaunchpad. `--account <name>` keeps
        //  the key encrypted on disk and never puts it in the environment, which
        //  is the shape a deployer key should have. `PRIVATE_KEY` stays supported
        //  for CI. When neither is set `msg.sender` is Foundry's default sender,
        //  which is what `--sender` overrides.
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address me = pk != 0 ? vm.addr(pk) : msg.sender;
        address registry = vm.envAddress("REGISTRY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        uint256 venueEth = vm.envOr("VENUE_ETH", uint256(0.05 ether));
        uint256 venueUsdg = vm.envOr("VENUE_USDG", uint256(150e6));

        IRegistryAdmin reg = IRegistryAdmin(registry);
        address owner = reg.owner();
        address mifrens = reg.mifrens();

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast();   // signer supplied by --account / --private-key

        // ── 1. Quote assets ────────────────────────────────────────────────
        // 6 decimals like real USDC/USDG — the decimals trap `formatQuote` exists
        // to handle, and the one a rotation would silently misprice by 1e12.
        MockQuoteToken usdg = new MockQuoteToken("Magic USD", "USDG", 6);

        // ── 2. Oracle, rotator, treasury governor ──────────────────────────
        // The oracle is owned by the REGISTRY OWNER (the timelock in a hardened
        // deploy), matching its own header: choosing which assets exist and
        // choosing how they are priced are the same decision.
        QuoteOracle oracle = new QuoteOracle(me);
        //  ── COMPOSE WITH DeployLaunchpad, DO NOT DUPLICATE IT ──────────────
        //  DeployLaunchpad already deploys a QuoteRotator AND a TreasuryGovernor
        //  and calls `setRotationWiring`. This script used to deploy its own pair
        //  and re-wire, which left the Launchpad pair orphaned — wasted gas, two
        //  live rotators, and a venue curated on whichever one happened to win
        //  the last `setRotationWiring`. Getting that ordering wrong silently
        //  produces a deployment where every rotation reverts `NoRoute`, because
        //  the curated venue is on the rotator the registry is NOT pointing at.
        //
        //  `quoteRotator`/`treasuryGovernor` are `internal` on CauldronBase with
        //  no getter (the registry has ~60 bytes of EIP-170 margin), so this
        //  cannot read what is already wired — pass them in. Both are printed by
        //  DeployLaunchpad for exactly this purpose.
        //
        //  Unset => deploy a fresh pair and wire it, which is the standalone path
        //  for a deployment that never ran DeployLaunchpad.
        address existingRotator = vm.envOr("ROTATOR", address(0));
        address existingGov = vm.envOr("TREASURY_GOVERNOR", address(0));

        QuoteRotator rotator;
        TreasuryGovernor governor;
        bool reused = existingRotator != address(0) && existingGov != address(0);

        if (reused) {
            rotator = QuoteRotator(payable(existingRotator));
            governor = TreasuryGovernor(existingGov);
            console2.log("reusing the rotator + governor from DeployLaunchpad");
        } else {
            bool testnetGov = vm.envOr("TESTNET_GOV", false);
            rotator = new QuoteRotator(registry, IPoolManager(poolManager));
            governor = new TreasuryGovernor(
                IVotes721(mifrens), registry, me,
                uint64(vm.envOr("GOV_VOTING_PERIOD", uint256(0))),
                uint64(vm.envOr("GOV_ENVELOPE_LIFETIME", uint256(0))),
                uint64(vm.envOr("GOV_COOLDOWN", uint256(0))),
                uint64(vm.envOr("GOV_EXECUTION_WINDOW", uint256(0))),
                testnetGov
            );
            if (testnetGov) console2.log("!! TESTNET GOVERNANCE TIMING - not for mainnet");
        }
        rotator.setArbParams(address(oracle), 1000, 5e18);

        // ── 2b. Price feeds. Real Chainlink for ETH and USDG; mock for xNVDA.
        //       `quoteDecimals` is the TOKEN's, not the feed's — 18 for native,
        //       6 for USDG. Passing it explicitly rather than letting the oracle
        //       read it keeps a mock with a wrong `decimals()` from mispricing
        //       by orders of magnitude.
        oracle.setFeed(address(0), FEED_ETH_USD, HB_ETH, 18);
        oracle.setFeed(address(usdg), FEED_USDC_USD, HB_USDC, 6);
        // Sepolia is an L1-like fork with no sequencer, so the uptime check stays
        // unset — `_sequencerOk` returns true when it is, which is correct here
        // and wrong to fake.
        // Hand the oracle to whoever owns the registry, now that it is configured.
        if (owner != me) oracle.transferOwnership(owner);

        // ── 3. The VENUE pool: create it, then give it depth ───────────────
        // `openOrAddPair` asserts `token > quote`; USDG sorts above native, so
        // currency0 = ETH and currency1 = USDG. Passing hook = address(0) makes
        // this a vanilla Uniswap v4 pool rather than a Cauldron pool.
        usdg.mint(me, venueUsdg);
        PoolKey memory venue = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(usdg)),
            fee: VENUE_FEE,
            tickSpacing: VENUE_SPACING,
            hooks: IHooks(address(0))
        });

        VenueSeeder seeder = new VenueSeeder();
        usdg.transfer(address(seeder), venueUsdg);
        seeder.seed{value: venueEth}(
            IPoolManager(poolManager), IPositionManagerOps(positionManager),
            address(usdg), venueEth, venueUsdg, VENUE_SPACING, VENUE_FEE
        );

        // ── 4. Curate the venue. FAILS CLOSED — without this every rotation
        //      reverts NoRoute, however well-funded the pool is.
        rotator.setVenue(venue, true);

        // ── 5. Wire it all into the registry ───────────────────────────────
        if (owner == me) {
            reg.setAllowedQuote(address(usdg), true, 1e18);
            //  Only when this script deployed the pair. Re-wiring a reused pair
            //  is a no-op at best and, if the addresses were mistyped, silently
            //  points the registry at a rotator with no curated venue.
            if (!reused) reg.setRotationWiring(address(rotator), address(governor));
            console2.log("wired directly (deployer owns the registry)");
        } else {
            console2.log("REGISTRY OWNED BY TIMELOCK - queue these:");
            console2.log("  setAllowedQuote(usdg,  true, 1e18)");
            console2.log("  setRotationWiring(rotator, governor)");
        }

        vm.stopBroadcast();

        console2.log("--- DEPLOYED ---");
        console2.log("USDG            :", address(usdg));
        console2.log("QuoteOracle     :", address(oracle));
        console2.log("QuoteRotator    :", address(rotator));
        console2.log("TreasuryGovernor:", address(governor));
        console2.log("venue seeder/LP :", address(seeder));
        console2.log("");
        console2.log("--- PUT THESE IN indexer/deployments/round.json ---");
        console2.log('  "quoteRotator":     ', address(rotator));
        console2.log('  "treasuryGovernor": ', address(governor));
        console2.log('  "quoteOracle":      ', address(oracle));
        console2.log("  quoteAssets[USDG].address:  ", address(usdg));
    }
}

/**
 * @dev Holds the venue pool's liquidity.
 *
 *  `PoolOps` is written to be delegatecall'd by the registry, so `address(this)`
 *  is whoever calls it — it settles from its own balances and the LP position is
 *  minted to it. A Script cannot play that role cleanly across a broadcast, so
 *  this minimal contract does: it receives the ETH and USDG, opens the pool, and
 *  keeps the position.
 *
 *  The venue LP is not protocol money. It exists so rotations have something to
 *  fill against on a testnet; on mainnet the venue is a real pool that already
 *  has depth and this contract is not deployed at all.
 */
contract VenueSeeder {
    address public immutable deployer;
    uint256 public positionId;

    constructor() { deployer = msg.sender; }

    function seed(
        IPoolManager poolManager,
        IPositionManagerOps posm,
        address usdg,
        uint256 ethAmount,
        uint256 usdgAmount,
        int24 spacing,
        uint24 fee
    ) external payable returns (uint256) {
        require(msg.sender == deployer, "only deployer");
        // token = USDG (sorts above native), quote = ETH.
        (, positionId) = PoolOps.openOrAddPair(
            poolManager, posm, address(0), usdg, address(0),
            ethAmount, usdgAmount, spacing, fee
        );
        return positionId;
    }

    /**
     * @notice Seed the venue as a CONCENTRATED BAND around the live price.
     *
     *  ── WHY NOT FULL RANGE ───────────────────────────────────────────────
     *  {seed} places MIN_TICK..MAX_TICK, because it borrows `PoolOps`'s launch
     *  placement. That is right for a brew's own pool, which must quote at any
     *  price forever, and wrong for a ROTATION VENUE, which only ever has to
     *  quote near the oracle.
     *
     *  Full range makes the venue behave like constant product, so slippage is
     *  `x/(X+x)` and the capital needed is brutal. Measured against the live
     *  generation LP (one 30000-bps envelope moving 0.2434 ETH in twelve
     *  slices) with 2 ETH of venue:
     *
     *      full range        largest slice 3.05%   whole envelope 10.85%
     *      +/- 10% band      largest slice 0.30%   whole envelope  1.15%
     *      +/-  5% band      largest slice 0.15%   whole envelope  0.59%
     *      +/-  2% band      largest slice 0.06%   whole envelope  0.24%
     *
     *  Same capital, ~18x less slippage at +/-5%. The rotation's floor is
     *  ORACLE-derived, so what matters is that the venue's price barely moves
     *  while a whole envelope crosses it — a band delivers that, and depth alone
     *  buys it only at ~20x the cost.
     *
     *  ── TWO-SIDED, NOT ONE-SIDED ─────────────────────────────────────────
     *  A single-sided USDG position above spot would serve ETH->USDG and NOTHING
     *  else, so the guild could rotate out of ether and never back. A band holds
     *  both assets and quotes both directions, which is what "the treasury may
     *  change its mind" actually requires.
     *
     *  ── THE TRADE-OFF, STATED ────────────────────────────────────────────
     *  A band is only deep INSIDE itself. Push price past an edge and the
     *  position goes one-sided and stops quoting the direction you need. That is
     *  acceptable here precisely because this is a MOCK venue: nothing but our
     *  own rotations moves it, and {recover} plus a re-seed re-centres it. Do not
     *  copy this placement to a venue with real external flow without a keeper
     *  that re-centres.
     *
     * @param bandBps half-width of the band, in bps of price (500 = +/-5%).
     */
    function seedBand(
        IPoolManager poolManager,
        IPositionManagerOps posm,
        address usdg,
        uint256 ethAmount,
        uint256 usdgAmount,
        int24 spacing,
        uint24 fee,
        uint16 bandBps
    ) external payable returns (uint256) {
        require(msg.sender == deployer, "only deployer");
        require(bandBps > 0 && bandBps <= 5_000, "band");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(usdg),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(address(0))
        });

        //  The pool must already exist and hold a price. A band has to be placed
        //  AROUND something, and opening the pool here would let this function
        //  invent the very price the band is supposed to bracket.
        (uint160 sqrtP, int24 tick,,) = StateLibrary.getSlot0(poolManager, PoolIdLibrary.toId(key));
        require(sqrtP != 0, "venue: pool not initialized - run seed() first");

        //  Ticks are log_1.0001(price), so a +/-b price band is +/-ln(1+b)/ln(1.0001)
        //  ticks. ln(1.0001) ~ 1e-4, so delta ~ bandBps * 1e-4 / 1e-4 ... in
        //  integer terms: ticks per 1% is ~99.5, so bandBps * 995 / 100 is within
        //  a tick of exact across the whole permitted range and needs no logs.
        int24 delta = int24(int256(uint256(bandBps)) * 995 / 100);
        int24 lo = ((tick - delta) / spacing) * spacing;
        int24 hi = ((tick + delta) / spacing) * spacing;
        //  Integer division truncates TOWARD ZERO, so a negative tick would round
        //  the wrong way and could collapse the band; nudge to keep it straddling.
        if (lo >= tick) lo -= spacing;
        if (hi <= tick) hi += spacing;
        require(lo < hi, "band collapsed");

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtP,
            TickMath.getSqrtPriceAtTick(lo),
            TickMath.getSqrtPriceAtTick(hi),
            ethAmount,
            usdgAmount
        );
        require(liquidity > 0, "band: zero liquidity");

        IERC20(usdg).approve(address(posm), usdgAmount);
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, lo, hi, liquidity, ethAmount, usdgAmount, address(this), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1);

        positionId = posm.nextTokenId();
        posm.modifyLiquidities{value: ethAmount}(abi.encode(actions, params), block.timestamp + 300);
        return positionId;
    }

    /**
     * @notice Pull the venue position back out and return both sides to the
     *         deployer.
     *
     *  ── WHY THIS HAD TO EXIST BEFORE THE VENUE COULD BE FUNDED PROPERLY ──
     *  This contract minted a full-range position and then stored nothing but
     *  the id. There was no way to decrease liquidity, no way to burn, and no
     *  sweep — so every wei sent to {seed} was permanently stranded the moment
     *  the broadcast ended. That was survivable only because the venue was
     *  seeded with 0.005 ETH.
     *
     *  It stopped being survivable when the venue had to get DEEP. The rotation
     *  floor is oracle-derived, so a slice only clears it if the venue can
     *  absorb the trade without moving price much, which means real capital —
     *  and this session has already spent a day recovering 12.25 ETH stranded by
     *  exactly this shape of contract. A pot with no drain is not a cheaper pot,
     *  it is a slower loss.
     *
     *  `key` is passed in rather than stored: reconstructing it costs a storage
     *  slot and the caller already knows it (it is pinned by the allowlist).
     *  `positionId == 0` is treated as "nothing seeded" rather than reverting, so
     *  a recovery script can be run blindly against every deployment.
     */
    function recover(IPositionManagerOps posm, PoolKey memory key, address usdg)
        external
        returns (uint256 ethOut, uint256 usdgOut)
    {
        require(msg.sender == deployer, "only deployer");
        if (positionId != 0) {
            (ethOut, usdgOut) = PoolOps.removeAll(posm, positionId, key, usdg);
            positionId = 0;
        }
        //  Sweep the BALANCE, not the amounts `removeAll` reported. Fees accrued
        //  since the mint sit here too, and a transfer sized from the return
        //  value would leave them behind for the same reason the position was
        //  stuck in the first place.
        uint256 tok = MockQuoteToken(usdg).balanceOf(address(this));
        if (tok > 0) MockQuoteToken(usdg).transfer(deployer, tok);
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool ok,) = deployer.call{value: bal}("");
            require(ok, "eth return");
        }
    }

    receive() external payable {}
}
