// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
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
 *    PRIVATE_KEY        deployer (required)
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
 *    GENESIS_BONUS_BPS  bonus share of gen-1 supply, bps (default 1000 = 10%)
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
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address gnomeRenderer = vm.envOr("GNOME_RENDERER", DEFAULT_GNOME_RENDERER);

        uint256 supply = vm.envOr("PRESALE_SUPPLY", uint256(1111));   // OG rare tranche
        uint256 artCap = vm.envOr("MIFRENS_ART_CAP", uint256(2222));  // total incl. volume
        uint256 price = vm.envOr("PRESALE_PRICE", uint256(0.0062 ether)); // 1111 → ~6.9 Ξ thin LP
        uint256 maxWallet = vm.envOr("PRESALE_MAXWALLET", uint256(100));
        // 20% OG airdrop = the ENTIRE genesis reserve (active band is 80%). So the
        // OG gift equals the reserve and there is no leftover migration reserve on
        // gen 1 — matches GEN1_ACTIVE_TOKENS = 80%. (OG marks ~-75% at launch.)
        uint256 bonusBps = vm.envOr("GENESIS_BONUS_BPS", uint256(2000)); // 20%
        uint256 deathThreshold = vm.envOr("DEATH_THRESHOLD", uint256(1 ether));
        // Governance timelock: minDelay seconds (testnet 180 = 3min; mainnet e.g.
        // 172800 = 48h). Proposer/executor/canceller = deployer EOA now; on mainnet
        // grant these to a Gnosis Safe + revoke the EOA (no redeploy).
        uint256 tlDelay = vm.envOr("TIMELOCK_DELAY", uint256(180));

        vm.startBroadcast(pk);

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
                console2.log("CauldronSeeder  :", address(seeder));
                console2.log("seed window (s) :", seedWindow);
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
            // The hook hands this to every collection it wires, so each future
            // iteration's fresh collection renders badges on-chain too — without
            // it, only the genesis tranche would, and every later brew would fall
            // back to a URI base pointing at a metadata server.
            hook.setLiquidatorRenderer(address(badgeRenderer));
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
}
