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
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);
        address registry = vm.envAddress("REGISTRY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        uint256 venueEth = vm.envOr("VENUE_ETH", uint256(0.05 ether));
        uint256 venueUsdg = vm.envOr("VENUE_USDG", uint256(150e6));

        IRegistryAdmin reg = IRegistryAdmin(registry);
        address owner = reg.owner();
        address mifrens = reg.mifrens();

        vm.startBroadcast(pk);

        // ── 1. Quote assets ────────────────────────────────────────────────
        // 6 decimals like real USDC/USDG — the decimals trap `formatQuote` exists
        // to handle, and the one a rotation would silently misprice by 1e12.
        MockQuoteToken usdg = new MockQuoteToken("Magic USD", "USDG", 6);

        // ── 2. Oracle, rotator, treasury governor ──────────────────────────
        // The oracle is owned by the REGISTRY OWNER (the timelock in a hardened
        // deploy), matching its own header: choosing which assets exist and
        // choosing how they are priced are the same decision.
        QuoteOracle oracle = new QuoteOracle(me);
        QuoteRotator rotator = new QuoteRotator(registry, IPoolManager(poolManager));
        // The guardian can cancel a passed proposal but cannot pass one; the
        // deployer holds it until governance is handed over.
        TreasuryGovernor governor = new TreasuryGovernor(IVotes721(mifrens), registry, me);
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
            reg.setRotationWiring(address(rotator), address(governor));
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

    receive() external payable {}
}
