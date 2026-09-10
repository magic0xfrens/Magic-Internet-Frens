// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPositionManagerOps} from "../cauldron/PoolOps.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../cauldron/CauldronSeeder.sol";
import {CauldronGovernor} from "../cauldron/CauldronGovernor.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {MiFrensGenesis} from "../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../cauldron/MiFrensDividend.sol";
import {CauldronGachaRouter} from "../cauldron/CauldronGachaRouter.sol";
import {CollectionLedger} from "../cauldron/CollectionLedger.sol";
import {LiquidatoorRenderer} from "../render/LiquidatoorRenderer.sol";
import {BadgeArtLib} from "./BadgeArtLib.sol";
import {QuoteRotator} from "../cauldron/QuoteRotator.sol";
import {TreasuryGovernor, IVotes721} from "../cauldron/TreasuryGovernor.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";
import {MockQuoteToken} from "../cauldron/MockQuoteToken.sol";
import {MintCurvePolicy} from "../cauldron/MintCurvePolicy.sol";
import {VenueSeeder} from "./DeployRotationStack.s.sol";
import {MetadataMode} from "../cauldron/ICauldron.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

/**
 * @title DeployLaunchpad
 * @notice One-shot deploy + wiring of the entire autonomous Cauldron launchpad.
 *
 *  Deploys and connects, in dependency order:
 *    1. MiFrensGenesis     — genesis fundraise (ERC721Votes founding guild)
 *    2. CauldronHook        — V4 volume hook (CREATE2-mined address)
 *    3. CauldronRegistry    — token/pool orchestrator
 *    4. CauldronGovernor    — proposals + checkpointed voting
 *
 *  Wiring (all owner calls happen BEFORE ownership is handed to the presale):
 *    - hook.setRegistry(registry)
 *    - registry.setGovernor(governor)
 *    - registry.setGenesisMetadata(Renderer, "", GNOME_RENDERER)   // iteration #1 art
 *    - registry.setGenesisBonus(presale, BONUS_BPS, presale.MAX_SUPPLY())
 *    - governor.setRegistry(registry)
 *    - presale.setRegistry(registry)
 *    - registry.transferOwnership(presale)   // so finalize() (and only it) can summon
 *
 *  After this, the loop is fully autonomous & permissionless:
 *    presale mints out -> anyone finalize() -> summon gen-1 + pool + collection
 *    -> swaps mint NFTs by volume -> volume dies -> anyone relaunch() -> winner.
 *
 *  Env:
 *    PRIVATE_KEY        deployer key (OPTIONAL — prefer `--account <name>`,
 *                       which reads an encrypted keystore and keeps the raw key
 *                       out of the environment and shell history)
 *    POOL_MANAGER       V4 PoolManager (required)
 *    POSITION_MANAGER   V4 PositionManager (required)
 *    GNOME_RENDERER     iteration #1 on-chain renderer (default: Sepolia Gnome)
 *    BADGE_ART          upload Liquidatoor badge art + wire the on-chain badge
 *                       renderer (default true). ~167KB across 8 SSTORE2 writes,
 *                       so roughly 33M gas — set false to skip on a chain where
 *                       that is expensive, and run DeployBadgeRenderer later.
 *    PRESALE_SUPPLY     MiFrens count (default 1111)
 *    PRESALE_PRICE      wei per MiFren (default 0.01 ether)
 *    PRESALE_MAXWALLET  per-wallet cap (default 100)
 *    GENESIS_BONUS_BPS  bonus share of gen-1 supply, bps (default 1400 -> OG
 *                       allocation = 17.5% of the mint price; see the note inline)
 *    DEATH_THRESHOLD    24h volume floor, wei (default 1 ether)
 *
 *  Run (from contracts/solidity):
 *    FOUNDRY_PROFILE=cauldron forge script deploy/DeployLaunchpad.s.sol \
 *      --rpc-url $SEPOLIA_RPC --broadcast -vvv
 */
contract DeployLaunchpad is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    // GnomeLand's on-chain renderer on Sepolia (iteration #1 art).
    address constant DEFAULT_GNOME_RENDERER = 0x15EbCb6c3cf473b4DF5F7DF05cD5609513dEe4A7;

    function run() external {
        //  SIGNER. Prefer an ENCRYPTED KEYSTORE (`--account <name>`), which
        //  never puts the raw key in the environment, the shell history or a
        //  process listing. `PRIVATE_KEY` stays supported for CI and for
        //  unattended runs, but it is no longer required.
        //
        //  With `--account`, forge already knows the signer, so the script must
        //  NOT pass one to startBroadcast — doing so would override the keystore
        //  and fail on the missing env var before it ever prompted.
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = pk != 0 ? vm.addr(pk) : msg.sender;
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address gnomeRenderer = vm.envOr("GNOME_RENDERER", DEFAULT_GNOME_RENDERER);

        uint256 supply = vm.envOr("PRESALE_SUPPLY", uint256(1111));   // OG rare tranche
        uint256 artCap = vm.envOr("MIFRENS_ART_CAP", uint256(2222));  // total incl. volume
        uint256 price = vm.envOr("PRESALE_PRICE", uint256(0.0062 ether)); // 1111 → ~6.9 Ξ thin LP
        uint256 maxWallet = vm.envOr("PRESALE_MAXWALLET", uint256(100));
        // GENESIS BONUS = THE OG ALLOCATION DIAL. Every wei of presale ETH becomes
        // LP, so an OG's allocation is worth a FIXED fraction of what they paid:
        //
        //     allocationValue/nftSpend = (bonusBps/10000) * TOTAL_SUPPLY/GEN1_ACTIVE
        //
        // which is bonusBps x 1.25 at an 80% active tranche. The old default of 2000
        // therefore paid 25% of the mint price - above the intended 15-20% ceiling.
        // Inverting: bonusBps = targetRatio * 8000. 1400 -> 17.5% (mid of the band);
        // 1200 -> 15%, 1600 -> 20%. Asserted on a live fork by F12.
        uint256 bonusBps = vm.envOr("GENESIS_BONUS_BPS", uint256(1400)); // 17.5% of mint
        uint256 deathThreshold = vm.envOr("DEATH_THRESHOLD", uint256(1 ether));
        // Governance timelock: minDelay seconds (testnet 180 = 3min; mainnet e.g.
        // 172800 = 48h). Proposer/executor/canceller = deployer EOA now; on mainnet
        // grant these to a Gnosis Safe + revoke the EOA (no redeploy).
        uint256 tlDelay = vm.envOr("TIMELOCK_DELAY", uint256(180));

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast();   // signer supplied by --account / --private-key

        // 0. GOVERNANCE TIMELOCK — the eventual owner of hook/registry-emergency/
        //    perp engine. Deployed FIRST because the registry's `emergencyAdmin` is
        //    IMMUTABLE and must be the timelock from birth. OZ TimelockController
        //    (audited, standard — no upgradeable-proxy red flag on the money code).
        address[] memory tlRoles = new address[](1);
        tlRoles[0] = deployer;
        TimelockController timelock = new TimelockController(tlDelay, tlRoles, tlRoles, deployer);
        console2.log("Timelock       :", address(timelock));

        // 1. Genesis fundraise — the founding guild (ERC721Votes electorate).
        MiFrensGenesis presale = new MiFrensGenesis(
            "MiFrens", "MIFREN", supply, artCap, price, maxWallet, "https://mifrens.xyz/api/mifren/"
        );
        console2.log("MiFrensGenesis :", address(presale));

        // 2. Mine + CREATE2-deploy the volume hook (owner = deployer).
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), deathThreshold, address(0), deployer, deployer);
        (address hookAddr, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(CauldronHook).creationCode, ctorArgs);
        CauldronHook hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), deathThreshold, address(0), deployer, deployer
        );
        require(address(hook) == hookAddr, "hook addr mismatch");
        console2.log("CauldronHook   :", address(hook));

        // 3. Registry (token/pool orchestrator).
        // Break-glass admin = the TIMELOCK by default (immutable). So an LP
        // recovery is: timelock.schedule(registry.armEmergency) → wait
        // emergencyDelay → execute → emergencyWithdrawLP. EMERGENCY_ADMIN /
        // EMERGENCY_DELAY still overridable via env (e.g. a Safe for mainnet).
        address emergencyAdmin = vm.envOr("EMERGENCY_ADMIN", address(timelock));
        // AUDIT: the default used to be 0, which made every "timelocked"
        // break-glass action (emergencyWithdrawLP / emergencySweep /
        // migrateToSuccessor) execute INSTANTLY, with no arm-and-wait window for
        // holders to exit and no window for the guardian to veto. The delay is
        // IMMUTABLE once constructed, so a zero here can never be corrected.
        // Default to 48h. A throwaway testnet can pass a SMALL value (e.g. 300) —
        // but no longer ZERO. See below.
        uint256 emergencyDelay = vm.envOr("EMERGENCY_DELAY", uint256(48 hours));
        // ZERO IS REFUSED AT DEPLOY (audit F-19). `emergencyDelay` is `immutable`,
        // so a zero passed here can never be corrected on that deployment — and it
        // used to do far more than remove the waiting period. The registry's
        // arm-and-wait was skipped entirely at zero, so `emergencyReadyAt` was never
        // set; and because {CauldronBase._redeemBlocked} keys THE EXIT GUARANTEE off
        // exactly that variable, the "arming forces the redemption exit open"
        // protection silently did not exist. Round-31 shipped with `0` for this
        // reason and cannot be fixed without a redeploy.
        // The registry now makes arming mandatory at any delay, so a zero is no
        // longer unsafe — but it still collapses the holder's exit window to a
        // single transaction boundary, which is not a window. Refuse it here so the
        // choice is deliberate: a testnet that wants fast recovery passes 60-300s
        // and still exercises the real arm -> wait -> execute path.
        require(emergencyDelay > 0, "EMERGENCY_DELAY must be > 0 (audit F-19)");
        CauldronRegistry registry =
            new CauldronRegistry(poolManager, positionManager, address(hook), emergencyAdmin, emergencyDelay);
        console2.log("CauldronRegistry:", address(registry));

        // OG-redemption delegatecall facet (one-time wiring; frozen after set).
        // MUST run while the deployer still owns the registry (before any
        // ownership handoff), since setRedemptionExt is onlyOwner + one-shot.
        RedemptionExt redemptionExt = new RedemptionExt();
        registry.setRedemptionExt(address(redemptionExt));
        console2.log("RedemptionExt   :", address(redemptionExt));

        // 4. Governor (electorate = the MiFrens presale NFT).
        CauldronGovernor governor = new CauldronGovernor(address(presale));
        console2.log("CauldronGovernor:", address(governor));

        // 4b. Factory that deploys each brew's collection + vault.
        CauldronFactory factory = new CauldronFactory();
        console2.log("CauldronFactory :", address(factory));

        // 4c. Genesis MiFrens fee dividend — OG holders earn a sliver of every
        //     brew's fees, forever (persistent, not per-brew). Fees with no
        //     spell-casters sweep to the treasury (default: deployer on testnet).
        MiFrensDividend dividend = new MiFrensDividend(address(presale), vm.envOr("TREASURY", deployer));
        console2.log("MiFrensDividend :", address(dividend));

        // 4d. Crystal gacha router (one-click play → open crystals → tickets).
        //     Reads the current iteration's pool from the registry each call.
        CauldronGachaRouter gacha =
            new CauldronGachaRouter(IPoolManager(poolManager), address(hook), address(registry), deployer);
        console2.log("CauldronGacha   :", address(gacha));

        // 4e. Collection legacy-floor cap table — every volume collection preserves
        //     the value its own volume/royalties accrued, forever, as a token
        //     entitlement that moons with the machine (see CollectionLedger).
        CollectionLedger ledger = new CollectionLedger(address(registry));
        console2.log("CollectionLedger:", address(ledger));

        // 4b. Liquidatoor badge renderer — draws the trophy for a perp
        //     liquidation entirely on-chain from the stats recorded at mint, so
        //     badges need no metadata server. ONE instance serves every
        //     collection (it reads stats back off its caller), so this is also
        //     what every future iteration's collection points at.
        LiquidatoorRenderer badgeRenderer;
        if (vm.envOr("BADGE_ART", true)) {
            badgeRenderer = new LiquidatoorRenderer();
            BadgeArtLib.upload(
                badgeRenderer,
                "render/badge-art/liq-long.svgbody",
                "render/badge-art/liq-short.svgbody"
            );
            console2.log("LiquidatoorRndr :", address(badgeRenderer));
        }

        // 5. Wire everything (owner calls first).
        hook.setRegistry(address(registry));
        hook.setGuild(address(dividend)); // stream 1% of fees to genesis holders
        hook.setOpener(address(gacha), true); // only the gacha router opens crystals
        //  THE ROUTER NEEDS THE SAME ORACLE THE HOOK PRICES VOLUME WITH (audit
        //  Q-02). The hook's odds curve is restated from ether into USD the moment
        //  an oracle is wired (audit U-1, `setDeathThreshold`), and this router
        //  measures its play size as an ETH notional — so without the oracle it
        //  would hand a wei numerator to a USD denominator and collapse its own
        //  players' odds by roughly the ETH price. Unset is safe (curve is in
        //  ether terms, sizes pass through); WIRE IT IN THE SAME OPERATION THAT
        //  CALLS `setDeathThreshold` with an oracle, or the two drift apart.
        address quoteOracle = vm.envOr("QUOTE_ORACLE", address(0));
        if (quoteOracle != address(0)) gacha.setOracle(quoteOracle);

        //  ── MAKE VOLUME CURRENCY-AGNOSTIC ────────────────────────────────
        //  The hook measures a generation's life in VOLUME, and volume decides
        //  three things: whether the brew is dying, how much crystal credit a
        //  trade earns, and the odds of a spin. Without an oracle `_toUsd`
        //  returns the raw quote amount, so all three are denominated in
        //  whatever the pool happens to be paired against.
        //
        //  That is survivable while every generation is ETH-quoted and wrong the
        //  moment one is not. USDG is 6-decimal: the same dollar of volume
        //  arrives as 1e6 instead of 1e18, a trillion-fold difference against a
        //  threshold that did not move. A rotated generation would read as dead
        //  on arrival and mint nothing, with nothing reverting to say so.
        //
        //  Wiring the oracle restates volume in USD at 1e18. The curve constants
        //  are compared directly against that number, so they MUST be restated
        //  in the same breath — the setter refuses an oracle without them
        //  (see CauldronHook.setDeathThreshold, which documents the ~3000x
        //  over-issuance this prevents). Defaults below are the previous ETH
        //  values converted at ~$2.4k/ETH, so the economics are unchanged:
        //      0.02 Ξ/NFT -> $50    0.00002 Ξ step -> $0.05
        //      0.5 Ξ odds -> $1200  1 Ξ death      -> $2500
        if (quoteOracle != address(0)) {
            hook.setDeathThreshold(
                vm.envOr("DEATH_THRESHOLD_USD", uint256(2500e18)),
                quoteOracle,
                vm.envOr("VOLUME_PER_NFT_USD", uint256(50e18)),
                vm.envOr("NFT_PRICE_STEP_USD", uint256(0.05e18)),
                vm.envOr("ODDS_FULL_VOLUME_USD", uint256(1200e18))
            );
            console2.log("volume denominated in USD via oracle:", quoteOracle);

            //  ── THE MINT LADDER ──────────────────────────────────────────
            //  Only wired ALONGSIDE the oracle, and that pairing is not
            //  cosmetic. The ladder is compared directly against accumulated
            //  crystal credit, so the two must share a denomination: a USD
            //  ladder against wei-denominated credit is a ~1000x mismatch and
            //  nothing would ever mint. Same hazard `setDeathThreshold` guards
            //  for base/step; the policy sits outside that check, so it is
            //  enforced here by construction instead.
            //
            //  cost(k) = base + spread*k^2/(k+knee): quadratic below the knee,
            //  linear above it, so the price always rises while the rate it
            //  rises at decays. Calibrated EXACTLY rather than by search -
            //  summing the ladder gives
            //      total = N*base + spread * SUM(k^2/(k+knee))
            //  so `spread` is one division once the sum is known.
            {
                uint256 mintOut = vm.envOr("MINT_OUT_TARGET_USD", uint256(20_000e18));
                uint256 knee = vm.envOr("MINT_CURVE_KNEE", uint256(300));
                uint256 n = artCap;

                //  `base` IS DERIVED FROM THE TARGET, not configured beside it.
                //  Fixing base independently is how a sane-looking pair becomes
                //  unreachable: a $20k target with a $50 base over 3333 frens
                //  needs $166,650 just to pay the base, so the ladder clamps
                //  flat — the one shape that dilutes the floor. Taking base as a
                //  FRACTION of the mean makes every target reachable and keeps
                //  the shape constant: 8% of the mean gives a ~25x span from
                //  first fren to last, whatever the total.
                uint256 baseBps = vm.envOr("MINT_CURVE_BASE_BPS", uint256(800)); // 8%
                uint256 curveBase = (mintOut / n) * baseBps / 10_000;
                uint256 sum;
                for (uint256 k; k < n; ++k) sum += (k * k * 1e18) / (k + knee);
                uint256 spread = ((mintOut - n * curveBase) * 1e18) / sum;
                MintCurvePolicy curve = new MintCurvePolicy(curveBase, spread, knee, n);
                hook.setPolicies(address(0), address(0), address(curve));
                console2.log("MintCurvePolicy :", address(curve));
                console2.log("  mint-out target (usd):", mintOut / 1e18);
                console2.log("  actual ladder total  :", curve.totalToMintOut() / 1e18);
                console2.log("  first / last fren    :",
                    curve.priceAt(0, 0, 0) / 1e18, curve.priceAt(n - 1, 0, 0) / 1e18);
            }
        }
        // The registry funds each new iteration's migration reserve with a REAL
        // first-block market buy (green candle). That buy MUST skip the base tax +
        // anti-sniper surtax, else its ETH is taxed away mid-buy and relaunch
        // reverts (OutOfFunds). Exemption is gated on BOTH isOpener[sender] (audit
        // F-13) AND taxExempt — and the registry is both the swap sender and the
        // tagged player — so it needs both flags.
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        // EIP-2981 royalties on EVERY collection → the genesis dividend (5%).
        registry.setRoyalty(address(dividend), 500);
        presale.setRoyalty(address(dividend), 500);
        // Wire the dividend into the collection so a genesis transfer breaks its
        // "cast the spell" enchantment (settles the leaver + frees the share).
        presale.setDividend(address(dividend));
        // Wire the registry into the dividend so a MOVED fren's re-enchant fee is
        // priced + routed into the reserve (grows the genesis floor). Original
        // never-moved OGs stay free. treasury (= deployer here) gates this.
        dividend.setRegistry(address(registry));
        // The hook is the ONLY address permitted to fund the fee basket (audit
        // D-1). Without this the ERC20 side of the dividend stays closed, which
        // is the safe default — an un-fundable basket loses nothing, an openly
        // fundable one can be poisoned permanently.
        dividend.setFunder(address(hook));
        registry.setFactory(address(factory));
        registry.setGovernor(address(governor));
        // PROGRESSIVE SEED (opt-in): deploy the persistent streamer + set the launch
        // window. registry.setSeeder propagates to the hook so afterSwap streams the
        // active tranche in-swap (keeperless); the seeder's permissionless poke() is
        // the fallback. SEED_WINDOW=0 → the atomic green-candle path (unchanged).
        // Default 900s (15min) so the genesis summon is progressive on testnet.
        {
            uint64 seedWindow = uint64(vm.envOr("SEED_WINDOW", uint256(900)));
            if (seedWindow > 0) {
                CauldronSeeder seeder =
                    new CauldronSeeder(address(registry), positionManager, poolManager);
                registry.setSeeder(address(seeder));       // also wires hook.setSeeder
                registry.setSeedWindow(seedWindow);

                // The seeder BUYS on the treasury's behalf (the tranched prime buy).
                // The hook waives the base fee + launch surtax only when BOTH flags
                // are set — see CauldronHook._isExemptPlayer, which deliberately
                // requires isOpener AND taxExempt so a direct swapper cannot forge
                // an exemption through hookData (audit F-13).
                hook.setOpener(address(seeder), true);
                hook.setTaxExempt(address(seeder), true);

                // ALIGN THE ANTI-SNIPE WINDOW WITH THE LIQUIDITY SCHEDULE.
                // These are independently configured and were pulling opposite ways:
                // snipeWindowBlocks defaulted to 30 (~6 min) while the seed window is
                // 900s (~75 blocks), so the surtax decayed to ZERO with only ~54% of
                // ledger A placed. The remaining 46% then streamed into a book with no
                // sniper protection at all — precisely the window a sniper wants. Tie
                // the surtax to the same clock so protection fades as depth arrives.
                uint256 snipeBlocks = vm.envOr(
                    "SNIPE_WINDOW_BLOCKS", uint256(seedWindow) / vm.envOr("BLOCK_TIME", uint256(12))
                );
                hook.setSnipeParams(snipeBlocks, vm.envOr("SNIPE_MAX_BPS", uint256(9600)));

                // LEDGER C: the treasury's own ETH, spent by poke() in tranches that
                // ride the same schedule (see CauldronSeeder.primePending). Optional —
                // PRIME_BUY_ETH=0 simply skips it.
                uint256 primeEth = vm.envOr("PRIME_BUY_ETH", uint256(0));
                if (primeEth > 0) {
                    seeder.fundPrime{value: primeEth}(vm.envOr("PRIME_TO", deployer));
                    console2.log("prime budget (wei):", primeEth);
                }

                console2.log("CauldronSeeder  :", address(seeder));
                console2.log("seed window (s) :", seedWindow);
                console2.log("snipe window (b):", snipeBlocks);
            }
        }
        // Wire the legacy-floor cap table + enable the in-hook LIVE buyback:
        // legacyBps of each swap's post-guild fee market-buys the token to back the
        // live collection's floor (no keeper). Default 4000 = 40% of the post-guild
        // fee → buyback; the rest keeps funding the collection's ETH vault floor.
        registry.setCollectionLedger(address(ledger));
        hook.setLegacyBuyback(
            address(registry),
            vm.envOr("LEGACY_BPS", uint256(4000)),
            vm.envOr("LEGACY_THRESHOLD", uint256(0.02 ether))
        );
        registry.setGenesisMetadata(MetadataMode.Renderer, "", gnomeRenderer);
        // Badge metadata: on-chain renderer instead of the URI base. Must happen
        // here — `deployer` is the only address allowed to set it, and ownership
        // moves to the timelock at the end of this script.
        if (address(badgeRenderer) != address(0)) {
            presale.setLiquidatorRenderer(address(badgeRenderer));
            // The FACTORY applies this to every collection it deploys, so each
            // future iteration's fresh collection renders badges on-chain too.
            // Without it only the genesis tranche would, and every later brew
            // would fall back to a URI base pointing at a metadata server.
            //
            // It lives on the factory rather than the hook because the hook is
            // against the EIP-170 ceiling and the factory has room to spare.
            factory.setLiquidatorRenderer(address(badgeRenderer));
        }

        // 4c. QuoteRotator — the guild's treasury arm. It converts a measured
        //     slice of the LP from one approved quote into another, so the LP is
        //     not permanently long whatever it launched against.
        //
        //     Deployed HERE rather than as a follow-up script: `rotateSlice`
        //     reverts NotConfigured without it, and a launch that silently omits
        //     it looks complete right up until governance tries to use it.
        QuoteRotator rotator = new QuoteRotator(address(registry), IPoolManager(poolManager));
        console2.log("QuoteRotator    :", address(rotator));

        //  4d. THE TREASURY GOVERNOR, AND THE WIRING THAT MAKES ROTATION EXIST.
        //
        //  `RedemptionExt.rotateSlice` reads BOTH `quoteRotator` and
        //  `treasuryGovernor` off the registry and reverts `NotConfigured` if
        //  either is zero. This script deployed the rotator and stopped, and no
        //  script anywhere deployed a governor or called `setRotationWiring` —
        //  so `quoteRotator`/`treasuryGovernor` were written by nothing and every
        //  rotation reverted on every deployment that has ever existed. (The
        //  setter itself was also a forwarder into a facet that never implemented
        //  it; that is fixed in RedemptionExt.)
        //
        //  The guardian may CANCEL a passed proposal but cannot pass one. It goes
        //  to the timelock where one exists, else the deployer.
        //  GOVERNANCE TIMING IS A DEPLOY-TIME CHOICE, fixed immutably at
        //  construction — no setter, so nothing can shorten it afterwards.
        //
        //  Mainnet wants a 3-day vote and a 7-day cooldown. A testnet that
        //  inherits those cannot be exercised at all: a full rotation would need
        //  more than a week of real waiting before anyone could see whether it
        //  works. So the durations come from env, defaulting to the MAINNET
        //  values when unset — a deploy that specifies nothing is a safe deploy.
        //
        //  `TESTNET_GOV=true` waives the contract's own floors (1 day minimum on
        //  the vote, cooldown and execution window). Setting it on a mainnet
        //  deploy would be the mistake; leaving it unset is the default.
        bool testnetGov = vm.envOr("TESTNET_GOV", false);
        TreasuryGovernor treasuryGov = new TreasuryGovernor(
            IVotes721(address(presale)),
            address(registry),
            address(timelock) != address(0) ? address(timelock) : deployer,
            uint64(vm.envOr("GOV_VOTING_PERIOD", uint256(0))),
            uint64(vm.envOr("GOV_ENVELOPE_LIFETIME", uint256(0))),
            uint64(vm.envOr("GOV_COOLDOWN", uint256(0))),
            uint64(vm.envOr("GOV_EXECUTION_WINDOW", uint256(0))),
            testnetGov
        );
        if (testnetGov) console2.log("!! TESTNET GOVERNANCE TIMING - do not use these values on mainnet");
        registry.setRotationWiring(address(rotator), address(treasuryGov));
        console2.log("TreasuryGovernor:", address(treasuryGov));

        //  4e. THE ROTATION STACK — quote asset, price feeds, and the VENUE.
        //
        //  Folded in here rather than left to a follow-up script. Two scripts
        //  each deploying a QuoteRotator meant the venue could end up curated on
        //  the rotator the registry was NOT pointing at, and the failure mode is
        //  silent: every rotation reverts `NoRoute` while both contracts look
        //  perfectly deployed. One script cannot get that ordering wrong.
        //
        //  Skipped entirely when DEPLOY_QUOTES=false, for a deployment that only
        //  wants the ETH-quoted core.
        if (vm.envOr("DEPLOY_QUOTES", true)) {
            _deployRotationStack(registry, rotator, poolManager, positionManager, deployer);
        }

        registry.setGenesisBonus(address(presale), bonusBps, supply);
        // OG-holder airdrop: DEFAULT is the "snipe" model (no reserve → no
        // presaler dilution). The deployer is flagged fee-EXEMPT so it can buy
        // $GNOME at launch tax-free to fund the airdrop from the market. Set
        // AIRDROP_RESERVE>0 only if you want the old carve-from-supply model.
        {
            uint256 airdropWhole = vm.envOr("AIRDROP_RESERVE", uint256(0));
            address airdropTo = vm.envOr("AIRDROP_WALLET", deployer);
            if (airdropWhole > 0) registry.setAirdropReserve(airdropTo, airdropWhole * 1e18);
        }
        // Snipe wallet is fee-exempt (default: deployer). One-time launch funding.
        hook.setTaxExempt(vm.envOr("SNIPE_WALLET", deployer), true);
        // PRIME BUY: authorize a funder to pre-load personal ETH (fundPrimeBuy)
        // during the presale window. At the genesis summon the registry spends it on
        // a REAL first-block market buy → GNOME to the treasury (airdropWallet, else
        // the funder) for a later OG airdrop. Net demand + zero dilution. The role
        // survives the presale ownership handoff below (owner→presale) so the funder
        // can still top up before mint-out. Send 2-3Ξ via registry.fundPrimeBuy().
        registry.setPrimeFunder(vm.envOr("PRIME_FUNDER", deployer));
        // GUARDIAN VETO: a pure-safety role that can CANCEL an armed emergency /
        // migration during its timelock window (can only block, never steal). Set
        // once here (owner, pre-handoff); thereafter only the timelock can change
        // it. Default deployer on testnet; pass a Safe multisig for mainnet.
        registry.setGuardian(vm.envOr("GUARDIAN", deployer));
        governor.setRegistry(address(registry));
        presale.setRegistry(address(registry));
        // WHO GETS TO LIGHT IT. `finalizer == 0` means the sold-out presale can be
        // ignited by anyone, so a watching bot can take the moment (and pick the
        // block the green candle lands in). Naming a finalizer makes ignition
        // deliberate. Defaults to the deployer; FINALIZER=0x0 restores the
        // permissionless behaviour if that is what a round actually wants.
        presale.setFinalizer(vm.envOr("FINALIZER", deployer));

        // 6. IGNITION vs OWNERSHIP (audit Z-06). This used to `transferOwnership` the
        //    registry to the PRESALE, purely so `finalize()` could reach `summon()`.
        //    But `MiFrensGenesis` calls exactly one registry function, exposes no
        //    forwarder and has no fallback — so that handoff permanently BURNED every
        //    `onlyOwner` setter (`setGovernor`, `setFactory`, `setSeeder`,
        //    `setSeedWindow`, `setReserveCeiling`, `setCollectionLedger`, ...), several
        //    of which document themselves as "Owner = timelock, chosen per iteration".
        //    A spammed governor or a broken factory — both called from inside
        //    `relaunch()` — could then never be replaced.
        //
        //    Ignition is now its own narrow role, so the presale keeps exactly the
        //    right it needs and OWNERSHIP goes to the governance timelock.
        registry.setIgniter(address(presale));
        IOwnable(address(registry)).transferOwnership(address(timelock));

        // NOTE: hook ownership STAYS with the deployer through the launchpad deploy
        // so DeployPerp can still call hook.setPerpEngine while wiring. DeployPerp
        // performs the final hook→timelock AND engine→timelock handoff as its last
        // step. (Pass TIMELOCK=<this address> to DeployPerp.)

        vm.stopBroadcast();

        console2.log("--- WIRED ---");
        console2.log("timelock (reg emergencyAdmin; owns hook+engine after DeployPerp):", address(timelock));
        console2.log("genesis renderer:", gnomeRenderer);
        console2.log("genesis bonus bps:", bonusBps);
        console2.log("presale price wei:", price);
        console2.log("presale supply  :", supply);
    }

    /// @notice Chainlink ETH/USD on Sepolia. Verified live: $2481.38, 113s old.
    address internal constant FEED_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    /// @notice Chainlink USDC/USD on Sepolia. Verified live: $0.9999, 3.1h old.
    ///         USDG is a mock USD stable, so this is the honest model for it.
    address internal constant FEED_USDC_USD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    /// @dev Heartbeats sized to what testnet feeds ACTUALLY do: USDC lagged 3.1h
    ///      when measured and DAI/USD was 13h stale, so a mainnet-cadence
    ///      heartbeat would reject feeds that are working as well as testnet
    ///      feeds ever work, and every price would read "cannot judge".
    uint32 internal constant HB_ETH = 4 hours;
    uint32 internal constant HB_USDC = 12 hours;
    uint24 internal constant VENUE_FEE = 3000;
    int24 internal constant VENUE_SPACING = 60;

    /**
     * @dev Quote asset, oracle feeds, and the curated venue the rotation swaps
     *      through. Separate function purely to keep `run()` under the stack
     *      limit; it is part of the same broadcast.
     *
     *  THE VENUE IS THE PART THAT IS EASY TO FORGET. `QuoteRotator`'s allowlist
     *  FAILS CLOSED, so a rotation through an uncurated pool reverts `NoRoute`
     *  however deep that pool is. And USDG here is a fresh mock, so no ETH/USDG
     *  pool exists to curate — it has to be CREATED and given depth first. A
     *  curated venue with no liquidity is a rotation that reverts on `minOut`.
     */
    function _deployRotationStack(
        CauldronRegistry registry,
        QuoteRotator rotator,
        address poolManager,
        address positionManager,
        address deployer
    ) internal {
        MockQuoteToken usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        QuoteOracle oracle = new QuoteOracle(deployer);

        //  Real Chainlink where it exists. USDG is a mock USD stablecoin, so
        //  pricing it off the real USDC/USD feed is the accurate model rather
        //  than a fabrication — and it means the oracle path under test is the
        //  same code mainnet runs. `quoteDecimals` is the TOKEN's (18 native,
        //  6 USDG), passed explicitly so a mock with a wrong `decimals()` cannot
        //  misprice by orders of magnitude.
        oracle.setFeed(address(0), FEED_ETH_USD, HB_ETH, 18);
        oracle.setFeed(address(usdg), FEED_USDC_USD, HB_USDC, 6);
        rotator.setArbParams(address(oracle), 1000, 5e18);
        registry.setAllowedQuote(address(usdg), true, 1e18);

        //  Create and seed the venue pool, then curate it. `openOrAddPair`
        //  asserts `token > quote`; USDG sorts above native, so currency0 is ETH
        //  and currency1 is USDG, with hook = 0 (a vanilla v4 pool, not a
        //  Cauldron pool).
        uint256 venueEth = vm.envOr("VENUE_ETH", uint256(0.02 ether));
        uint256 venueUsdg = vm.envOr("VENUE_USDG", uint256(60e6));
        //  Mint STRAIGHT to the seeder. Foundry refuses `address(this)` inside a
        //  script — script contracts are ephemeral, so an address derived from
        //  one is meaningless once the broadcast ends — and the mint-then-
        //  transfer round trip was only ever there to stage the tokens.
        VenueSeeder vs = new VenueSeeder();
        usdg.mint(address(vs), venueUsdg);
        vs.seed{value: venueEth}(
            IPoolManager(poolManager), IPositionManagerOps(positionManager),
            address(usdg), venueEth, venueUsdg, VENUE_SPACING, VENUE_FEE
        );
        rotator.setVenue(
            PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(usdg)),
                fee: VENUE_FEE,
                tickSpacing: VENUE_SPACING,
                hooks: IHooks(address(0))
            }),
            true
        );

        console2.log("USDG           :", address(usdg));
        console2.log("QuoteOracle    :", address(oracle));
        console2.log("venue LP holder:", address(vs));
    }
}
