// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronGovernor} from "../cauldron/CauldronGovernor.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {MiFrensGenesis} from "../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../cauldron/MiFrensDividend.sol";
import {CauldronGachaRouter} from "../cauldron/CauldronGachaRouter.sol";
import {MetadataMode} from "../cauldron/ICauldron.sol";

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
        uint256 price = vm.envOr("PRESALE_PRICE", uint256(0.01 ether));
        uint256 maxWallet = vm.envOr("PRESALE_MAXWALLET", uint256(100));
        uint256 bonusBps = vm.envOr("GENESIS_BONUS_BPS", uint256(1000)); // 10%
        uint256 deathThreshold = vm.envOr("DEATH_THRESHOLD", uint256(1 ether));

        vm.startBroadcast(pk);

        // 1. Genesis fundraise — the founding guild (ERC721Votes electorate).
        MiFrensGenesis presale = new MiFrensGenesis(
            "MiFrens", "MIFREN", supply, artCap, price, maxWallet, "https://magicfrens.xyz/api/mifren/"
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
        // Break-glass admin + timelock. Testnet: deployer EOA + delay 0 (instant
        // recovery). Mainnet: pass EMERGENCY_ADMIN=<Safe multisig> and
        // EMERGENCY_DELAY=604800 (7 days) so withdrawals must be armed + waited out.
        address emergencyAdmin = vm.envOr("EMERGENCY_ADMIN", address(0)); // 0 → deployer
        uint256 emergencyDelay = vm.envOr("EMERGENCY_DELAY", uint256(0));
        CauldronRegistry registry =
            new CauldronRegistry(poolManager, positionManager, address(hook), emergencyAdmin, emergencyDelay);
        console2.log("CauldronRegistry:", address(registry));

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

        // 5. Wire everything (owner calls first).
        hook.setRegistry(address(registry));
        hook.setGuild(address(dividend)); // stream 1% of fees to genesis holders
        hook.setOpener(address(gacha), true); // only the gacha router opens crystals
        // EIP-2981 royalties on EVERY collection → the genesis dividend (5%).
        registry.setRoyalty(address(dividend), 500);
        presale.setRoyalty(address(dividend), 500);
        // Wire the dividend into the collection so a genesis transfer breaks its
        // "cast the spell" enchantment (settles the leaver + frees the share).
        presale.setDividend(address(dividend));
        registry.setFactory(address(factory));
        registry.setGovernor(address(governor));
        registry.setGenesisMetadata(MetadataMode.Renderer, "", gnomeRenderer);
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
        governor.setRegistry(address(registry));
        presale.setRegistry(address(registry));

        // 6. Hand the registry to the presale so ONLY finalize() can summon.
        IOwnable(address(registry)).transferOwnership(address(presale));

        vm.stopBroadcast();

        console2.log("--- WIRED ---");
        console2.log("genesis renderer:", gnomeRenderer);
        console2.log("genesis bonus bps:", bonusBps);
        console2.log("presale price wei:", price);
        console2.log("presale supply  :", supply);
    }
}
