// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {LocalLifecycleBoot} from "../audit_full_scope/LocalLifecycleAdapters.t.sol";
import {VenueSeeder} from "../../deploy/DeployRotationStack.s.sol";
import {FixFactoryWiring} from "../../deploy/FixFactoryWiring.s.sol";
import {DeployMigrationVesting} from "../../deploy/DeployMigrationVesting.s.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {YBase, YGov} from "./YBase.sol";

/// Regressions for the owner-requested Low fixes (2026-09-23). Real local V4
/// managers and production contracts unless a fixture is named explicitly.

interface R23PosInfo {
    function positionInfo(uint256 id) external view returns (PositionInfo);
}

// ── FS-venueband-L01 ─────────────────────────────────────────────────────────
contract R23LowVenueBand is Test {
    using PositionInfoLibrary for PositionInfo;

    function test_seedBandWidthMatchesTheDocumentedBand() public {
        address manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        address positions = deployCode("out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0)));
        MockQuoteToken usd = new MockQuoteToken("USD", "USD", 6);
        vm.deal(address(this), 10 ether);
        VenueSeeder opening = new VenueSeeder();
        usd.mint(address(opening), 3000e6);
        opening.seed{value: 1 ether}(IPoolManager(manager), IPositionManagerOps(positions), address(usd), 1 ether, 3000e6, 60, 3000);
        VenueSeeder band = new VenueSeeder();
        usd.mint(address(band), 3000e6);
        uint256 id = band.seedBand{value: 1 ether}(
            IPoolManager(manager), IPositionManagerOps(positions), address(usd), 1 ether, 3000e6, 60, 3000, 500
        );
        PositionInfo info = R23PosInfo(positions).positionInfo(id);
        int256 width = int256(info.tickUpper()) - int256(info.tickLower());
        // +/-5% of price is +/-ln(1.05)/ln(1.0001) ~ +/-488 ticks; allow one
        // spacing (60) of alignment on each edge. The old formula gave ~9,950.
        assertLe(width, 2 * (488 + 60), "band no wider than documented");
        assertGe(width, 2 * (488 - 60), "band no narrower than documented");
    }

    receive() external payable {}
}

// ── FS-hook-L01 ──────────────────────────────────────────────────────────────
contract R23ShortPolicy {
    fallback() external {
        assembly { mstore(0, 0x07) return(31, 1) }
    }
}
contract R23ZeroPolicy {
    function priceAt(uint256, uint256, uint256) external pure returns (uint256) { return 0; }
}
contract R23GoodPolicy {
    function priceAt(uint256, uint256, uint256) external pure returns (uint256) { return 0.123 ether; }
}

contract R23LowHookCurve is LocalLifecycleBoot {
    function test_malformedCurvePolicyFallsBackAndCommitsStillWork() public {
        _boot(20 ether, 0);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        hook.setNftCurve(0.001 ether, 0);
        uint256 builtIn = hook.nftPriceAt(3);
        assertGt(builtIn, 0);

        hook.setPolicies(address(0), address(0), address(new R23ShortPolicy()));
        assertEq(hook.nftPriceAt(3), builtIn, "short reply -> built-in curve");
        hook.setPolicies(address(0), address(0), address(0xDEAD));
        assertEq(hook.nftPriceAt(3), builtIn, "codeless policy -> built-in curve");
        hook.setPolicies(address(0), address(0), address(new R23ZeroPolicy()));
        assertEq(hook.nftPriceAt(3), builtIn, "zero price guarded");
        hook.setPolicies(address(0), address(0), address(new R23GoodPolicy()));
        assertEq(hook.nftPriceAt(3), 0.123 ether, "valid policy honoured");

        // A funded untagged buy under the malformed policy still forges crystals.
        hook.setPolicies(address(0), address(0), address(new R23ShortPolicy()));
        _warp(25 hours);
        vm.roll(vm.getBlockNumber() + 40);
        _buy(0.05 ether, tx.origin);
        assertGt(hook.pendingOf(tx.origin), 0, "commit path survives a malformed policy");
    }
}

// ── FS-router-L01 ────────────────────────────────────────────────────────────
contract R23OracleShort {
    fallback() external {
        assembly { mstore(0, 0x01) return(31, 1) }
    }
}
contract R23OracleHuge {
    function usdPerRawUnit(address) external pure returns (uint256) { return type(uint256).max; }
}
contract R23OracleGood {
    function usdPerRawUnit(address) external pure returns (uint256) { return 2e18; }
}

contract R23LowRouterOracle is LocalLifecycleBoot {
    function test_malformedOracleFallsBackAndPlayStillWorks() public {
        _boot(20 ether, 0);
        CauldronGachaRouter r = new CauldronGachaRouter(pm, address(hook), address(registry), address(this));
        assertEq(r.playInCurveUnits(1 ether), 1 ether, "no oracle passthrough");
        r.setOracle(address(new R23OracleShort()));
        assertEq(r.playInCurveUnits(1 ether), 1 ether, "short reply -> passthrough");
        r.setOracle(address(new R23OracleHuge()));
        assertEq(r.playInCurveUnits(3 ether), 3 ether, "unrepresentable product -> passthrough");
        r.setOracle(address(new R23OracleGood()));
        assertEq(r.playInCurveUnits(1 ether), 2 ether, "valid oracle honoured");

        // The router's real play path under the malformed oracle.
        r.setOracle(address(new R23OracleShort()));
        hook.setOpener(address(r), true);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        _warp(25 hours);
        vm.roll(vm.getBlockNumber() + 40);
        address player = address(0xB1A7E4);
        vm.deal(player, 1 ether);
        uint256 before = IERC20Minimal(token).balanceOf(player);
        vm.prank(player, player);
        r.play{value: 0.05 ether}(0, 0, 1, 0, 4);
        assertGt(IERC20Minimal(token).balanceOf(player), before, "play delivers tokens");
    }
}

// ── FS-registry-L01 ──────────────────────────────────────────────────────────
contract R23UsdGov is ICauldronGovernor {
    address internal immutable q;
    constructor(address quote) { q = quote; }
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external view returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Stable Brew", symbol: "STBL", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://stable/", renderer: address(0), website: "", socials: "",
            quote: q, nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}

contract R23LowEmergencyERC20 is LocalLifecycleBoot {
    function test_emergencyWithdrawPaysAnErc20GenerationInItsOwnAsset() public {
        _boot(20 ether, 0);
        MockQuoteToken usd = new MockQuoteToken("Local USD", "LUSD", 18);
        assertLt(uint160(address(usd)), uint160(token), "quote sorts below the iteration token");
        registry.setAllowedQuote(address(usd), true, 1e18);
        uint256 g1 = registry.currentGeneration();

        // Gen 1 dies and its LP is withdrawn, so the relaunch recovers no native.
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        registry.armEmergency();
        registry.emergencyWithdrawLP(g1);

        // FIXTURE (named, mechanism isolation only): the hook's USD relaunch
        // reserve. The balance is really minted; only the fee-credited counter
        // `relaunchAsset[usd]` is written, standing in for USD fee income.
        usd.mint(address(hook), 1_000 ether);
        vm.record();
        hook.relaunchAsset(address(usd));
        (bytes32[] memory reads,) = vm.accesses(address(hook));
        vm.store(address(hook), reads[reads.length - 1], bytes32(uint256(1_000 ether)));
        assertEq(hook.relaunchAsset(address(usd)), 1_000 ether);

        registry.setGovernor(address(new R23UsdGov(address(usd))));
        registry.relaunch();
        uint256 g2 = registry.currentGeneration();
        assertEq(g2, g1 + 1);
        assertEq(registry.generationQuote(g2), address(usd), "generation 2 is USD-quoted");
        (Currency c0,,,,) = registry.generationPoolKey(g2);
        assertEq(Currency.unwrap(c0), address(usd), "primary currency0 is USD");

        _warp(registry.minLifetime() + 1 days + 1);
        uint256 usdBefore = usd.balanceOf(address(this));
        uint256 nativeBefore = address(this).balance;
        registry.armEmergency();
        registry.emergencyWithdrawLP(g2);
        assertGt(usd.balanceOf(address(this)), usdBefore, "recovered quote paid in USD");
        assertEq(address(this).balance, nativeBefore, "no unrelated native paid out");
    }
}

// ── FS-registry-L02 ──────────────────────────────────────────────────────────
/// Genesis continuation built exactly as R23_GenesisMintFailure (passing suite).
contract R23LowOgFold is YBase {
    uint256 internal constant GENESIS_PENDING_SLOT = 17; // CauldronBase layout (REGISTRY_FACET_STORAGE_CHECK.json)

    function test_relaunchFoldsTheFlushedOgShareIntoThisGeneration() public {
        address poolManager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        posm = deployCode("out/PositionManager.sol/PositionManager.json",
            abi.encode(poolManager, permit, uint256(100_000), address(0), address(0)));
        pm = IPoolManager(poolManager);
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(poolManager), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");
        registry = new CauldronRegistry(poolManager, posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));
        registry.setGovernor(address(new YGov()));
        vm.deal(address(this), 1000 ether);
        vm.deal(victim, 1000 ether);
        MiFrensGenesis genesis = new MiFrensGenesis("Frens", "FREN", 1, 100, 20 ether, 1, "ipfs://test/");
        genesis.setRegistry(address(registry));
        registry.setGenesisBonus(address(genesis), 2000, 1);
        registry.setIgniter(address(genesis));
        genesis.mint{value: 20 ether}(uint256(1));
        genesis.igniteCauldron();
        _warp(25 hours);
        registry.relaunch();
        token = registry.currentToken();
        assertEq(registry.currentGeneration(), 2);
        assertEq(hook.collection(), address(genesis), "Genesis continues as generation 2");

        CollectionLedger ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        hook.setLegacyBuyback(address(registry), 1000, 0.001 ether);
        hook.fundLegacyBuffer{value: 0.1 ether}();
        vm.roll(vm.getBlockNumber() + 40);
        _buy(0.1 ether, victim);
        vm.roll(vm.getBlockNumber() + 1);
        _buy(0.001 ether, victim);
        assertGt(hook.legacyOwedToReserve(), 0, "real buyback holds pending tokens");

        uint256 outBefore = registry.genesisReserveOutstanding();
        uint256 pendBefore = uint256(vm.load(address(registry), bytes32(GENESIS_PENDING_SLOT)));
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        registry.relaunch();
        assertEq(registry.currentGeneration(), 3);
        assertEq(uint256(vm.load(address(registry), bytes32(GENESIS_PENDING_SLOT))), 0,
            "the OG share flushed at this relaunch is folded now, not a generation later");
        assertGt(registry.genesisReserveOutstanding(), outBefore + pendBefore,
            "reserve sizing covers the flushed OG share");
    }
}

// ── FS-deployfactory-01 / FS-deployvesting-01 ────────────────────────────────
contract R23FactoryRegistry {
    address public owner;
    address public factory;
    constructor(address o) { owner = o; }
    function setFactory(address f) external {
        require(msg.sender == owner, "owner");
        factory = f;
    }
}

/// Mirrors CauldronRegistry's gate semantics exactly: setClaimGate(nonzero) is
/// emergency-only and consumes a matured arm (Registry._consumeTimelock).
contract R23GateRegistry {
    address public emergencyAdmin;
    uint256 public emergencyDelay = 300;
    uint256 public emergencyReadyAt;
    address public claimGate;
    constructor(address a) { emergencyAdmin = a; }
    function armEmergency() external {
        require(msg.sender == emergencyAdmin, "admin");
        emergencyReadyAt = block.timestamp + emergencyDelay;
    }
    function setClaimGate(address g) external {
        require(msg.sender == emergencyAdmin, "admin");
        if (g != address(0)) {
            require(emergencyReadyAt != 0 && block.timestamp >= emergencyReadyAt, "Timelocked");
            emergencyReadyAt = 0;
        }
        claimGate = g;
    }
}
contract R23VaultStub {}

contract R23LowScripts is Test {
    function test_fixFactoryWiringExecutesTheScheduledFactory() public {
        uint256 pk = 0xA11CE;
        address dep = vm.addr(pk);
        address[] memory roles = new address[](1);
        roles[0] = dep;
        TimelockController tl = new TimelockController(60, roles, roles, address(0));
        R23FactoryRegistry reg = new R23FactoryRegistry(address(tl));
        vm.setEnv("PRIVATE_KEY", vm.toString(pk));
        vm.setEnv("REGISTRY", vm.toString(address(reg)));
        vm.setEnv("TIMELOCK", vm.toString(address(tl)));
        vm.setEnv("BADGE_RENDERER", vm.toString(address(0xBADE)));
        vm.setEnv("EXECUTE", "false");
        FixFactoryWiring s = new FixFactoryWiring();
        uint64 nonce = vm.getNonce(dep);
        s.run();
        address scheduled = vm.computeCreateAddress(dep, nonce);
        assertGt(scheduled.code.length, 0, "schedule run deployed the factory");
        vm.warp(vm.getBlockTimestamp() + 61);
        vm.setEnv("EXECUTE", "true");
        vm.setEnv("FACTORY", vm.toString(scheduled));
        s.run();
        assertEq(reg.factory(), scheduled, "execute installs exactly the scheduled factory");
        vm.setEnv("EXECUTE", "false");
    }

    function test_vestingScriptEnforcesOnlyWithAMaturedArm() public {
        uint256 pk = 0xB0B;
        address dep = vm.addr(pk);
        R23GateRegistry reg = new R23GateRegistry(dep);
        vm.setEnv("PRIVATE_KEY", vm.toString(pk));
        vm.setEnv("REGISTRY", vm.toString(address(reg)));
        vm.setEnv("PERP_VAULT", vm.toString(address(new R23VaultStub())));
        vm.setEnv("TIMELOCK", vm.toString(address(0)));
        vm.setEnv("ENFORCE", "true");
        DeployMigrationVesting s = new DeployMigrationVesting();
        s.run();
        assertEq(reg.claimGate(), address(0), "without a matured arm the script reports, not reverts");
        vm.prank(dep);
        reg.armEmergency();
        vm.warp(vm.getBlockTimestamp() + 301);
        s.run();
        assertTrue(reg.claimGate() != address(0), "enforced once the arm matured");
    }
}
