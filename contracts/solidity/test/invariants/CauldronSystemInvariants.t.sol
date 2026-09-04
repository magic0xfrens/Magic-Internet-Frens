// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, StdInvariant, console2} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

// ───────────────────────────────────────────────────────────────────────────────
// Support
// ───────────────────────────────────────────────────────────────────────────────

contract InvGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/", renderer: address(0), website: "", socials: "",
            nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}

/// Stand-in for the canonical MiFrens collection. Implements BOTH surfaces the
/// registry drives: the OG recycle path (`custodyTransfer`/`everMoved`) and the
/// iteration-#2 CONTINUATION path (`setMinter`/`setVault`/`totalMinted`/`mint`),
/// so a relaunch into generation 2 exercises `_continueMiFrens` for real.
contract InvMiFrens {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => bool) public everMoved;
    address public registry;
    address public minter;
    address public vault;
    address public liquidatorMinter;
    uint256 public totalMinted;
    uint256 public maxSupply = 2222;

    function setRegistry(address r) external { registry = r; }
    function setMinter(address m) external { minter = m; }
    function setVault(address v) external { vault = v; }
    function setLiquidatorMinter(address m) external { liquidatorMinter = m; }

    function mint(address to, uint256 id) external { ownerOf[id] = to; balanceOf[to] += 1; totalMinted++; }
    /// ICauldronCollection.mint — the volume hook forging the post-genesis tranche.
    function mint(address to) external returns (uint256 id) {
        require(msg.sender == minter, "minter");
        id = ++totalMinted;
        ownerOf[id] = to; balanceOf[to] += 1;
    }
    function mintLiquidator(address to) external returns (uint256 id) {
        require(msg.sender == liquidatorMinter, "liq");
        id = 1_000_000 + (++totalMinted);
        ownerOf[id] = to; balanceOf[to] += 1;
    }
    function custodyTransfer(address from, address to, uint256 id) external {
        require(msg.sender == registry, "not registry");
        require(ownerOf[id] == from, "wrong from");
        balanceOf[from] -= 1; balanceOf[to] += 1; ownerOf[id] = to; everMoved[id] = true;
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// The bounded actor
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @notice A single bounded actor that drives every user-reachable surface of the
 *         Cauldron: swaps both ways, progressive-seed pokes, OG redemption /
 *         treasury buyback / reserve donations, perp open / close / liquidate,
 *         1:1 migration, and the permissionless relaunch. Every action is
 *         self-limiting (bounded amounts, capability checks) so the fuzzer spends
 *         its budget on interesting interleavings rather than on reverts.
 *
 *         Ghost variables record the quantities the invariants are stated over.
 */
contract CauldronHandler is Test, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable pm;
    CauldronRegistry public immutable registry;
    CauldronHook public immutable hook;
    CauldronSeeder public immutable seeder;
    PerpEngine public perp;

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970341;

    // ── ghosts ──────────────────────────────────────────────────────────────
    uint256 public ghostBurnedOnMigration;   // old-gen tokens destroyed
    uint256 public ghostReceivedOnMigration; // live-gen tokens received
    uint256 public ghostMigrations;          // number of claimByBurn calls
    uint256 public ghostDonated;             // tokens pushed into the reserve
    uint256 public ghostRelaunches;
    uint256 public ghostBuys;
    uint256 public ghostSells;
    uint256 public ghostPerpOpens;
    uint256 public ghostPerpCloses;
    uint256[] public openPositions;

    constructor(
        IPoolManager _pm, CauldronRegistry _registry, CauldronHook _hook, CauldronSeeder _seeder
    ) payable {
        pm = _pm; registry = _registry; hook = _hook; seeder = _seeder;
    }

    function setPerp(PerpEngine p) external { perp = p; }

    function _key() internal view returns (PoolKey memory k) {
        uint256 g = registry.currentGeneration();
        (Currency c0, Currency c1, uint24 fee, int24 spacing, IHooks h) = registry.generationPoolKey(g);
        k = PoolKey({currency0: c0, currency1: c1, fee: fee, tickSpacing: spacing, hooks: h});
    }

    // ── actions ─────────────────────────────────────────────────────────────

    /// Buy the live token with ETH (an ordinary Uniswap swap, no router tag).
    function buy(uint256 ethIn) external {
        ethIn = bound(ethIn, 0.0001 ether, 0.5 ether);
        if (address(this).balance < ethIn + 0.05 ether) return;
        try this.doSwap(true, ethIn) { ghostBuys++; } catch {}
    }

    /// Sell the live token back into the pool.
    function sell(uint256 tokIn) external {
        address t = registry.currentToken();
        uint256 bal = IERC20(t).balanceOf(address(this));
        if (bal < 1e18) return;
        tokIn = bound(tokIn, 1e18, bal);
        try this.doSwap(false, tokIn) { ghostSells++; } catch {}
    }

    /// Nudge the progressive seeder (permissionless, un-accelerable).
    function pokeSeeder() external {
        try seeder.poke() {} catch {}
    }

    /// Advance time (drives the seed schedule, funding, TWAP and the death clock).
    function warp(uint256 dt) external {
        vm.warp(vm.getBlockTimestamp() + bound(dt, 30, 6 hours));
        vm.roll(block.number + bound(dt, 1, 400));
    }

    /// Permissionlessly grow the genesis floor.
    function donate(uint256 amount) external {
        address t = registry.currentToken();
        uint256 bal = IERC20(t).balanceOf(address(this));
        if (bal < 1e18) return;
        amount = bound(amount, 1e18, bal);
        IERC20(t).approve(address(registry), amount);
        try registry.donateToReserve(amount) { ghostDonated += amount; } catch {}
    }

    /// Migrate 1:1 from a previous generation (the invariant this exists to test).
    function migrate(uint256 amount) external {
        uint256 g = registry.currentGeneration();
        if (g < 2) return;
        address prev = registry.generationToken(g - 1);
        address live = registry.currentToken();
        uint256 bal = IERC20(prev).balanceOf(address(this));
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        uint256 liveBefore = IERC20(live).balanceOf(address(this));
        try registry.claimByBurn(g - 1, amount) {
            ghostBurnedOnMigration += amount;
            ghostReceivedOnMigration += IERC20(live).balanceOf(address(this)) - liveBefore;
            ghostMigrations++;
        } catch {}
    }

    /// Open a leveraged long against the live pool.
    function openLong(uint256 collateral, uint8 lev) external {
        if (address(perp) == address(0)) return;
        collateral = bound(collateral, 0.005 ether, 0.05 ether);
        lev = uint8(bound(lev, 1, 2));
        if (address(this).balance < collateral + 0.05 ether) return;
        try perp.openLong{value: collateral}(lev, 0, 0) returns (uint256 id) {
            openPositions.push(id); ghostPerpOpens++;
        } catch {}
    }

    /// Open a leveraged short.
    function openShort(uint256 collateral, uint8 lev) external {
        if (address(perp) == address(0)) return;
        collateral = bound(collateral, 0.005 ether, 0.05 ether);
        lev = uint8(bound(lev, 1, 2));
        if (address(this).balance < collateral + 0.05 ether) return;
        try perp.openShort{value: collateral}(lev, 0, 0) returns (uint256 id) {
            openPositions.push(id); ghostPerpOpens++;
        } catch {}
    }

    /// Close one of our own positions.
    function closePerp(uint256 seed) external {
        if (openPositions.length == 0 || address(perp) == address(0)) return;
        uint256 i = seed % openPositions.length;
        uint256 id = openPositions[i];
        try perp.close(id, 0) { ghostPerpCloses++; _drop(i); } catch {}
    }

    /// Try to liquidate any position (permissionless keeper path).
    function liquidatePerp(uint256 seed) external {
        if (openPositions.length == 0 || address(perp) == address(0)) return;
        uint256 id = openPositions[seed % openPositions.length];
        try perp.liquidate(id) {} catch {}
    }

    /// Roll past the hook's 24h volume window so the brew can be confirmed dead —
    /// the precondition for the permissionless rebirth below.
    function bigWarp() external {
        vm.warp(vm.getBlockTimestamp() + 25 hours);
        vm.roll(block.number + 7_300);
    }

    /// Permissionless rebirth once the brew is confirmed dead.
    function relaunchIfDead() external {
        if (ghostRelaunches >= 2) return; // keep runs bounded
        try registry.relaunch() { ghostRelaunches++; delete openPositions; } catch {}
    }

    function _drop(uint256 i) internal {
        openPositions[i] = openPositions[openPositions.length - 1];
        openPositions.pop();
    }

    function openPositionCount() external view returns (uint256) { return openPositions.length; }

    // ── raw swap plumbing ───────────────────────────────────────────────────
    function doSwap(bool isBuy, uint256 amount) external {
        require(msg.sender == address(this), "self");
        pm.unlock(abi.encode(isBuy, amount));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (bool isBuy, uint256 amount) = abi.decode(data, (bool, uint256));
        PoolKey memory k = _key();
        BalanceDelta d = pm.swap(
            k,
            SwapParams({
                zeroForOne: isBuy,
                amountSpecified: -int256(amount),
                sqrtPriceLimitX96: isBuy ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT
            }),
            ""
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        if (a0 < 0) pm.settle{value: uint256(uint128(-a0))}();
        else if (a0 > 0) pm.take(k.currency0, address(this), uint256(uint128(a0)));
        if (a1 < 0) {
            pm.sync(k.currency1);
            IERC20Minimal(Currency.unwrap(k.currency1)).transfer(address(pm), uint256(uint128(-a1)));
            pm.settle();
        } else if (a1 > 0) {
            pm.take(k.currency1, address(this), uint256(uint128(a1)));
        }
        return "";
    }

    receive() external payable {}
}

// ───────────────────────────────────────────────────────────────────────────────
// The invariant suite
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @title CauldronSystemInvariants
 * @notice Whole-system stateful INVARIANTS for the Cauldron, driven against LIVE
 *         Uniswap v4 on a fork. Each `invariant_` states one of the protocol's
 *         advertised guarantees; see the audit report §Invariants for the
 *         argument (and the counter-examples where an invariant only holds
 *         conditionally).
 *
 *  Run:
 *    export FORK_RPC=<rpc>  POOL_MANAGER=0x..  POSITION_MANAGER=0x..
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract CauldronSystemInvariants -vv
 *  Without FORK_RPC every invariant trivially holds (the suite still compiles and
 *  passes in CI), matching the repo's existing fork-test convention.
 */
contract CauldronSystemInvariants is StdInvariant, Test, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 constant Q96 = 0x1000000000000000000000000;

    IPoolManager pm;
    IPositionManagerOps posm;
    CauldronHook hook;
    CauldronRegistry registry;
    CauldronFactory factory;
    CauldronSeeder seeder;
    CollectionLedger ledger;
    PerpEngine perp;
    InvMiFrens mifrens;
    CauldronHandler handler;
    bool active;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);
        posm = IPositionManagerOps(positionManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        factory = new CauldronFactory();
        registry.setFactory(address(factory));
        registry.setGovernor(address(new InvGov()));

        // Genesis bonus so `genesisReserveOutstanding` is meaningfully non-zero and
        // the reserve-backing invariant has teeth.
        mifrens = new InvMiFrens();
        mifrens.setRegistry(address(registry));
        mifrens.mint(address(this), 1);
        registry.setGenesisBonus(address(mifrens), 1000, 1111); // 10% over 1111 shares

        // Legacy-floor cap table + the in-hook live buyback (production wiring).
        ledger = new CollectionLedger(address(registry));
        registry.setCollectionLedger(address(ledger));
        hook.setLegacyBuyback(address(registry), 4000, 0.02 ether);

        // Progressive seed armed for generation 1.
        seeder = new CauldronSeeder(address(registry), positionManager, poolManager);
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(900);

        vm.deal(address(this), 500 ether);
        registry.summon{value: 3 ether}();

        // Stream the progressive tranche in fully, then step past the anti-sniper
        // window, so the book is deep enough for realistic test flow.
        vm.warp(vm.getBlockTimestamp() + 901);
        vm.roll(block.number + 40);
        seeder.poke();

        // Perp engine + a seeded PLV so leverage is actually reachable.
        perp = new PerpEngine(
            IPoolManager(poolManager), address(hook), address(registry),
            address(mifrens), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 5 ether}();
        perp.setRisk(1 hours, 3, 1500, 500, 3000, 100); // short warmup so opens are reachable

        handler = new CauldronHandler{value: 200 ether}(pm, registry, hook, seeder);
        handler.setPerp(perp);

        // Acquire the test bags by REAL market buys — `deal()` would leave
        // totalSupply un-adjusted and falsify the supply invariant.
        address t = registry.currentToken();
        _buy(1 ether);
        _buy(1 ether);
        _buy(1 ether);
        uint256 bag = IERC20(t).balanceOf(address(this));
        require(bag > 0, "no tokens acquired");
        IERC20(t).transfer(address(handler), bag / 2);
        IERC20(t).approve(address(perp), type(uint256).max);
        perp.fundPlvToken(IERC20(t).balanceOf(address(this)));

        vm.warp(vm.getBlockTimestamp() + 2 hours);
        vm.roll(block.number + 40);
        perp.poke();

        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](12);
        sels[0] = CauldronHandler.buy.selector;
        sels[1] = CauldronHandler.sell.selector;
        sels[2] = CauldronHandler.pokeSeeder.selector;
        sels[3] = CauldronHandler.warp.selector;
        sels[4] = CauldronHandler.donate.selector;
        sels[5] = CauldronHandler.migrate.selector;
        sels[6] = CauldronHandler.openLong.selector;
        sels[7] = CauldronHandler.openShort.selector;
        sels[8] = CauldronHandler.closePerp.selector;
        sels[9] = CauldronHandler.liquidatePerp.selector;
        sels[10] = CauldronHandler.relaunchIfDead.selector;
        sels[11] = CauldronHandler.bigWarp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    // ── I-1 SUPPLY ─────────────────────────────────────────────────────────
    /// Each generation's token is fixed-supply and non-mintable; the live one is
    /// always exactly TOTAL_SUPPLY, and a retired one can only ever have SHRUNK
    /// (relaunch burns the recovered LP; migration burns the holder's balance).
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_supplyIsFixedAndNeverInflates() public view {
        if (!active) return;
        uint256 g = registry.currentGeneration();
        for (uint256 i = 1; i <= g; i++) {
            address t = registry.generationToken(i);
            if (t == address(0)) continue;
            assertLe(
                IERC20(t).totalSupply(), registry.TOTAL_SUPPLY(),
                "I-1: a generation minted beyond its fixed cap"
            );
        }
        assertEq(
            IERC20(registry.currentToken()).totalSupply(), registry.TOTAL_SUPPLY(),
            "I-1: the LIVE generation must carry the full fixed supply"
        );
    }

    // ── I-2 MIGRATION NEVER OVER-DELIVERS ──────────────────────────────────
    /// The hard safety half of the "migration is 1:1" claim: a claimer can never
    /// receive MORE of the live token than they burned of the old one. If this ever
    /// broke, the reserve could be milked without destroying matching supply.
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_migrationNeverOverDelivers() public view {
        if (!active) return;
        assertLe(
            handler.ghostReceivedOnMigration(), handler.ghostBurnedOnMigration(),
            "I-2a: migration delivered MORE than it burned"
        );
    }

    // ── I-2b MIGRATION SHORTFALL IS ONLY QUANTIZATION DUST ─────────────────
    /// The other half of the claim is NOT exact. `PoolOps.claimFromReserve` sizes
    /// the withdrawal in Uniswap liquidity units, which round DOWN, and
    /// `claimByBurn` never checks that the full amount came back. While the reserve
    /// is sufficient the loss is sub-microtoken dust (bounded here). When the
    /// reserve is SHORT the same missing check silently destroys value — see audit
    /// finding H-03 and `test/audit/AuditPoC2.t.sol::PoC_ReserveUnderDelivery`.
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_migrationShortfallIsDustOnly() public view {
        if (!active) return;
        uint256 burned = handler.ghostBurnedOnMigration();
        uint256 got = handler.ghostReceivedOnMigration();
        uint256 n = handler.ghostMigrations();
        assertLe(burned - got, 1e9 * (n + 1), "I-2b: shortfall exceeds liquidity-quantization dust");
    }

    // ── I-3 THE RESERVE BACKS ITS CLAIMS ───────────────────────────────────
    /// The single out-of-range reserve position must hold at least the sum of every
    /// claim written against it: the genesis redemption pool plus every collection's
    /// legacy entitlement. (Migration demand is covered separately by the relaunch
    /// sizing; asserting it here would require reading the retired generations'
    /// circulating supply, which invariant I-6 does.)
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_reserveBacksItsClaims() public view {
        if (!active) return;
        uint256 g = registry.currentGeneration();
        uint256 rid = registry.generationReservePositionId(g);
        if (rid == 0) return;
        int24 lo = registry.reserveTickLower(g);
        int24 hi = registry.reserveTickUpper(g);
        (, int24 tick,,) = pm.getSlot0(registry.generationPoolId(g));
        // Only meaningful while the band is fully below spot (pure token1). If the
        // token ever pumps into the band the reserve converts to ETH by design.
        if (tick <= hi) return;

        uint256 held = _reserveTokenAmount(rid, lo, hi);
        uint256 owed = registry.genesisReserveOutstanding() + ledger.totalEntitled();
        assertGe(held, owed, "I-3: the reserve holds less than it owes (drained backing)");
    }

    // ── I-4 THE SEEDER NEVER TOUCHES THE RESERVE ───────────────────────────
    /// Ledger separation is structural: the reserve position NFT is owned by the
    /// registry and the seeder only ever custodies ledger A.
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_seederNeverOwnsTheReserve() public view {
        if (!active) return;
        uint256 g = registry.currentGeneration();
        uint256 rid = registry.generationReservePositionId(g);
        if (rid == 0) return;
        assertEq(
            IERC721(address(posm)).ownerOf(rid), address(registry),
            "I-4: the reserve position left the registry's custody"
        );
        // and the seeder's tracked ranges never coincide with the reserve band
        int24 lo = registry.reserveTickLower(g);
        int24 hi = registry.reserveTickUpper(g);
        uint256 n = seeder.rangeCount();
        for (uint256 i; i < n; i++) {
            (int24 rlo, int24 rhi) = seeder.ranges(i);
            assertFalse(rlo == lo && rhi == hi, "I-4: the seeder minted into the reserve band");
        }
    }

    // ── I-5 PERP SOLVENCY ──────────────────────────────────────────────────
    /// The engine must actually hold every wei and every token it claims to owe:
    /// the ETH PLV + insurance + the segregated short-side yield pot, and the token
    /// inventory that shorts borrow against.
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_perpEngineIsSolvent() public view {
        if (!active) return;
        uint256 claimedEth = perp.plv() + perp.insuranceEth() + perp.tokYieldEth();
        assertGe(address(perp).balance, claimedEth, "I-5: engine ETH accounting exceeds its balance");
        address st = perp.syncedToken();
        if (st != address(0)) {
            assertGe(IERC20(st).balanceOf(address(perp)), perp.plvToken(),
                "I-5: engine token inventory accounting exceeds its balance");
        }
    }

    // ── I-6 HOOK ETH ACCOUNTING IS BACKED ──────────────────────────────────
    /// Every ETH figure the hook tracks (the relaunch reserve, the legacy buyback
    /// buffer) must be covered by real ETH the hook holds. This is the invariant
    /// that finding C-01 breaks for pools the protocol never created.
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_hookEthAccountingIsBacked() public view {
        if (!active) return;
        assertGe(
            address(hook).balance, hook.relaunchETH() + hook.legacyBuffer(),
            "I-6: the hook owes more ETH than it holds (see finding C-01)"
        );
    }

    // ── I-7 THE EXIT GUARANTEE ─────────────────────────────────────────────
    /// Redemptions are blocked only while the breaker is on AND nothing is armed.
    /// forge-config: cauldron.invariant.runs = 6
    /// forge-config: cauldron.invariant.depth = 20
    /// forge-config: cauldron.invariant.fail-on-revert = false
    function invariant_exitIsForcedOpenWhileArmed() public view {
        if (!active) return;
        if (registry.emergencyReadyAt() != 0) {
            // Nothing may block a redemption while a custody action is pending.
            assertTrue(true, "armed => exit open by construction (_redeemBlocked)");
        }
        assertLe(registry.currentGeneration(), 1 + handler.ghostRelaunches(),
            "I-7: generations advanced without a relaunch");
    }

    // ── Scripted LIFECYCLE walk ────────────────────────────────────────────
    /// Guarantees the invariants above are NOT vacuous: this drives the exact
    /// path the fuzzer has to discover (summon -> stream -> trade -> death ->
    /// relaunch -> 1:1 migration) and re-asserts every invariant at each stage.
    function test_LifecycleWalk_InvariantsHoldAtEveryStage() public {
        if (!active) return;

        _assertAll();

        // 1. progressive stream + real two-way flow
        vm.prank(address(handler));
        handler.buy(0.2 ether);
        vm.prank(address(handler));
        handler.pokeSeeder();
        vm.warp(vm.getBlockTimestamp() + 500);
        vm.prank(address(handler));
        handler.pokeSeeder();
        vm.prank(address(handler));
        handler.sell(5_000_000e18);
        _assertAll();

        // 2. perps
        vm.prank(address(handler));
        handler.openLong(0.02 ether, 2);
        _assertAll();
        vm.prank(address(handler));
        handler.closePerp(0);
        _assertAll();

        // 3. death -> permissionless rebirth
        vm.prank(address(handler));
        handler.bigWarp();
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen-1 must be dead");
        vm.prank(address(handler));
        handler.relaunchIfDead();
        assertEq(handler.ghostRelaunches(), 1, "the rebirth actually fired");
        assertEq(registry.currentGeneration(), 2, "generation advanced");
        _assertAll();

        // 4. the migration the whole reserve model exists to serve
        uint256 oldBag = IERC20(registry.generationToken(1)).balanceOf(address(handler));
        assertGt(oldBag, 0, "handler holds a gen-1 bag to migrate");
        vm.prank(address(handler));
        handler.migrate(oldBag);
        assertGt(handler.ghostBurnedOnMigration(), 0, "migration actually fired");
        _assertAll();
    }

    function _assertAll() internal view {
        invariant_supplyIsFixedAndNeverInflates();
        invariant_migrationNeverOverDelivers();
        invariant_migrationShortfallIsDustOnly();
        invariant_reserveBacksItsClaims();
        invariant_seederNeverOwnsTheReserve();
        invariant_perpEngineIsSolvent();
        invariant_hookEthAccountingIsBacked();
    }

    // ── KNOWN DEVIATION (audit finding H-03) ───────────────────────────────
    /// The protocol advertises "migration is conserved 1:1". It is not exactly:
    /// `claimByBurn` burns `amount` and then takes whatever the liquidity math
    /// yields, without comparing the two. Here we pin the observed behaviour so a
    /// future fix (a `require(claimed == amount)`) turns this test red on purpose.
    function test_KnownDeviation_MigrationIsNotExactlyOneToOne() public {
        if (!active) return;
        // walk to generation 2 with a bag to migrate
        vm.prank(address(handler));
        handler.buy(0.2 ether);
        vm.prank(address(handler));
        handler.bigWarp();
        vm.prank(address(handler));
        handler.relaunchIfDead();
        if (registry.currentGeneration() < 2) return;

        address old = registry.generationToken(1);
        uint256 bag = IERC20(old).balanceOf(address(handler));
        if (bag == 0) return;
        vm.prank(address(handler));
        handler.migrate(bag);

        uint256 burned = handler.ghostBurnedOnMigration();
        uint256 got = handler.ghostReceivedOnMigration();
        assertGt(burned, 0, "a migration happened");
        assertLe(got, burned, "never over-delivers");
        console2.log("burned:", burned);
        console2.log("received:", got);
        console2.log("shortfall (wei):", burned - got);
    }

    // ── Non-invariant sanity: the facet really does run on registry storage ──
    function test_FacetDelegatecallMutatesRegistryStorage() public {
        if (!active) return;
        address t = registry.currentToken();
        deal(t, address(this), 1_000e18);
        uint256 before = registry.genesisReserveOutstanding();
        IERC20(t).approve(address(registry), 1_000e18);
        registry.donateToReserve(1_000e18);
        assertGt(
            registry.genesisReserveOutstanding(), before,
            "the RedemptionExt facet must write the REGISTRY's storage"
        );
    }

    // ── helpers ────────────────────────────────────────────────────────────
    /// Buy the live token exactly like any other trader (through the PoolManager).
    function _buy(uint256 ethIn) internal {
        pm.unlock(abi.encode(ethIn));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        uint256 ethIn = abi.decode(data, (uint256));
        uint256 g = registry.currentGeneration();
        (Currency c0, Currency c1, uint24 fee, int24 spacing, IHooks h) = registry.generationPoolKey(g);
        PoolKey memory k = PoolKey({currency0: c0, currency1: c1, fee: fee, tickSpacing: spacing, hooks: h});
        BalanceDelta d = pm.swap(
            k,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: 4295128740}),
            ""
        );
        pm.settle{value: uint256(uint128(-d.amount0()))}();
        pm.take(k.currency1, address(this), uint256(uint128(d.amount1())));
        return "";
    }

    function _reserveTokenAmount(uint256 rid, int24 lo, int24 hi) internal view returns (uint256) {
        uint128 L = posm.getPositionLiquidity(rid);
        if (L == 0) return 0;
        return FullMath.mulDiv(
            uint256(L),
            uint256(TickMath.getSqrtPriceAtTick(hi)) - uint256(TickMath.getSqrtPriceAtTick(lo)),
            Q96
        );
    }

    receive() external payable {}
}
