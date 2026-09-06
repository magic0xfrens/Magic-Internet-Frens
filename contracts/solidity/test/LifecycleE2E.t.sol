// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../cauldron/CauldronSeeder.sol";
import {PerpEngine} from "../cauldron/PerpEngine.sol";
import {MigrationVesting, IStakerOracle} from "../cauldron/MigrationVesting.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../cauldron/ICauldron.sol";

/**
 * @notice FULL LIFECYCLE end-to-end against LIVE Uniswap v4 (Sepolia fork) — the
 *         runnable equivalent of the TESTNET_PROGRESSIVE_RUNBOOK, start → round 3,
 *         with time-warps standing in for the real death-clock waits that a live
 *         Sepolia run can't skip.
 *
 *  Journey (one test, logged step by step):
 *    ROUND 1: deploy → summon PROGRESSIVE → block-0 snipe probe → stream via a buy
 *             (in-swap poke) → perp stake / long / short / liquidate.
 *    ROUND 2: age → death → relaunch (progressive seeder torn down + re-armed) →
 *             OG holder migrates via the VESTING escrow (drip) → snipe probe.
 *    ROUND 3: age → death → relaunch again → confirm the machine keeps cycling.
 *
 *  Run:
 *    export FORK_RPC=<sepolia> POOL_MANAGER=0x.. POSITION_MANAGER=0x..
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract LifecycleE2E -vv
 *  Without FORK_RPC it no-ops (suite still compiles + passes in CI).
 */
contract LifecycleE2EForkTest is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook hook;
    CauldronRegistry registry;
    CauldronSeeder seeder;
    PerpEngine perp;
    MigrationVesting vesting;
    IPoolManager pm;
    address posm;
    bool active;

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970342 - 1;
    uint64 constant WINDOW = 900;         // 15-min progressive window
    uint64 constant VEST = 72 hours;

    address trader = address(0x7EADE7);
    address ogHolder = address(0x0B0B);
    address sniper = address(0x5217E5);
    address dividend = address(0xD1D1);
    address treasury = address(0x7E7E);

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address poolManager = address(pm);

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
        registry.setGovernor(address(new E2EGov()));

        // Progressive seeder (wires hook via registry.setSeeder).
        seeder = new CauldronSeeder(address(registry), posm, poolManager);
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(WINDOW);

        // Vesting escrow (instant tier off → everyone drips) + gate wired later.
        vesting = new MigrationVesting(address(registry), address(this), VEST, address(0));

        vm.deal(address(this), 200 ether);
    }

    function test_FullLifecycle_ToRound3_OnFork() public {
        if (!active) return;

        // ================= ROUND 1 : summon (progressive) =================
        console2.log("=== ROUND 1: summon (progressive) ===");
        (address token1,) = registry.summon{value: 2 ether}();
        assertEq(registry.generationPositionId(1), 0, "progressive: no single active position");
        assertTrue(seeder.seeding(), "seeder armed");
        console2.log("gen1 token:", token1);
        console2.log("seed floor deployedWad:", seeder.deployedWad());

        // ---- block-0 snipe probe (thin 10% floor) ----
        uint256 snipeGot = _buyAs(sniper, token1, 1 ether);
        console2.log("block-0 sniper tokens for 1 ETH:", snipeGot);

        // ---- in-swap streaming: a plain buy advances the stream (no explicit poke) ----
        vm.warp(block.timestamp + WINDOW / 2);
        uint256 wadBefore = seeder.deployedWad();
        _buyAs(trader, token1, 0.2 ether);
        console2.log("deployedWad after a mid-window buy (in-swap poke):", seeder.deployedWad());
        assertGt(seeder.deployedWad(), wadBefore, "the swap itself streamed liquidity in");

        // finish streaming
        vm.warp(block.timestamp + WINDOW);
        seeder.poke();
        assertTrue(seeder.isComplete(), "fully seeded by window end");

        // Give the OG holder a gen-1 bag to migrate (via vesting) next round.
        uint256 ogBag = _buyAs(address(this), token1, 0.5 ether);
        IERC20Minimal(token1).transfer(ogHolder, ogBag);
        console2.log("OG holder gen1 bag:", ogBag);

        // ============ ROUND 2 : death -> relaunch (progressive again) + vesting ==========
        console2.log("=== ROUND 2: death -> relaunch (progressive re-armed) ===");
        _relaunch(1);
        address token2 = registry.currentToken();
        assertEq(registry.currentGeneration(), 2, "gen 2 born");
        assertEq(registry.generationPositionId(2), 0, "gen2 progressive (streamed)");
        assertTrue(seeder.seeding(), "seeder re-armed for gen2");
        assertEq(CauldronToken(token1).balanceOf(address(seeder)), 0, "gen1 seeder drained (teardown)");
        console2.log("gen2 token:", token2);

        // snipe probe on gen-2's fresh progressive window (anti-snipe holds round 2)
        uint256 snipe2 = _buyAs(sniper, token2, 1 ether);
        console2.log("gen2 block-0 sniper tokens for 1 ETH:", snipe2);

        // ---- VESTING: gate on -> OG migrates the gen1 bag through the escrow (drips) ----
        console2.log("=== ROUND 2: vesting migration (OG gen1 -> gen2, dripped) ===");
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting));
        vm.startPrank(ogHolder);
        vm.expectRevert(); // VestingEnforced — instant path closed under the gate
        registry.claimByBurn(1, ogBag);
        IERC20Minimal(token1).approve(address(vesting), ogBag);
        vesting.startVest(1, ogBag);
        vm.stopPrank();
        assertEq(vesting.claimable(ogHolder), 0, "nothing instant (dump blocked)");
        uint256 vestStart = block.timestamp;
        vm.warp(vestStart + uint256(VEST) / 2);
        assertApproxEqAbs(vesting.claimable(ogHolder), ogBag / 2, ogBag / 40, "~half vested at 50%");
        vm.warp(vestStart + VEST);
        vm.prank(ogHolder);
        vesting.claim();
        assertApproxEqAbs(CauldronToken(token2).balanceOf(ogHolder), ogBag, ogBag / 1e6 + 1, "fully vested 1:1");
        console2.log("OG holder fully vested gen2:", CauldronToken(token2).balanceOf(ogHolder));
        registry.setClaimGate(address(0));

        // ============ ROUND 3 : death -> relaunch (ATOMIC deep book) + perps finale =======
        // Gen-3 uses the ATOMIC green-candle path (full-range, spot-STRADDLING, deep
        // two-sided) — the book perps require. A pure progressive (single-sided)
        // book has ZERO liquidity straddling spot, so the perp engine reads zero
        // depth and (correctly) won't open leverage against it: progressive is the
        // launch-only anti-snipe mechanic; perps run on atomic generations. This is
        // the FINAL round, so the liquidation crash (which mints test tokens via
        // `deal`) is never recycled into a later reseed.
        console2.log("=== ROUND 3: death -> relaunch (atomic deep book for perps) ===");
        registry.setSeedWindow(0);
        _relaunch(2);
        address token3 = registry.currentToken();
        assertEq(registry.currentGeneration(), 3, "gen 3 born");
        assertGt(registry.generationPositionId(3), 0, "gen3 atomic active position (deep, straddles spot)");
        console2.log("gen3 token (atomic deep):", token3);

        // ---- PERP: stake, long, short, liquidate (on the deep atomic gen-3 book) ----
        console2.log("=== ROUND 3: perp stake / long / short / liquidate ===");
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(hook), address(registry),
            address(new NoFrens()), dividend, treasury, address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 5 ether}(5 ether);                 // STAKE the ETH side (long leverage)
        uint256 seed = 50_000_000 ether;
        deal(token3, address(this), seed);
        IERC20Minimal(token3).approve(address(perp), seed);
        perp.fundPlvToken(seed);                          // stake the token side (short inventory)
        hook.setDeathThreshold(0, address(0));                         // keep alive for the perp ops
        vm.warp(block.timestamp + 25 hours);
        vm.roll(block.number + 40);
        perp.poke();

        // LONG
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 longId = perp.openLong{value: 0.05 ether}(2, 0, 0, 0.05 ether);
        (address lt,,,,,,,) = perp.positions(longId);
        assertEq(lt, trader, "long opened");
        vm.prank(trader);
        perp.close(longId, 0);
        console2.log("opened+closed long id:", longId);

        // SHORT
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 shortId = perp.openShort{value: 0.05 ether}(2, 0, 0, 0.05 ether);
        (address str,,,,,,,) = perp.positions(shortId);
        assertEq(str, trader, "short opened");
        vm.prank(trader);
        perp.close(shortId, 0);
        console2.log("opened+closed short id:", shortId);

        // LIQUIDATION on the deep atomic (continuous full-range) book: a sustained
        // crash moves price smoothly, so the liquidation swap has room and the
        // position clears with PLV solvent (no bad debt).
        perp.setRisk(24 hours, 3, 4_000, 500, 3_000, 100); // 40% maintenance
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 liqId = perp.openLong{value: 0.05 ether}(2, 0, 0, 0.05 ether);
        uint256 plvBefore = perp.plv();
        _sustainedCrash(token3, 200_000_000 ether);
        assertTrue(perp.isLiquidatable(liqId), "sustained crash liquidatable");
        vm.prank(address(0xBEEF));
        perp.liquidate(liqId);
        (address lq,,,,,,,) = perp.positions(liqId);
        assertEq(lq, address(0), "position liquidated");
        assertGe(perp.plv(), plvBefore, "PLV solvent after liquidation (no bad debt)");
        console2.log("liquidated long id:", liqId);

        console2.log("=== MACHINE CYCLED: START -> ROUND 3 + perps/vesting OK ===");
    }

    // ---------------------------------------------------------------------------
    // PERPS ON A *PROGRESSIVE* GENERATION — AUTOMATICALLY (no finalize, no callable):
    // the seeder's two-sided BASE (laid at summon) gives permanent spot depth, so
    // perps stake/long/short/LIQUIDATE work on the progressive gen once streamed.
    // ---------------------------------------------------------------------------
    function test_Perps_On_Progressive_ViaBase_OnFork() public {
        if (!active) return;
        registry.setGovernor(address(new E2EGov()));
        (address tok,) = registry.summon{value: 2 ether}();
        assertEq(registry.generationPositionId(1), 0, "progressive gen");

        // Just stream to 100% — the base is already there from summon (NO finalize).
        vm.warp(block.timestamp + WINDOW + 1);
        seeder.poke();
        assertTrue(seeder.isComplete(), "streamed");

        // Perps on the progressive gen (base provides spot depth automatically).
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(hook), address(registry),
            address(new NoFrens()), dividend, treasury, address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 5 ether}(5 ether);
        uint256 seed = 50_000_000 ether;
        deal(tok, address(this), seed);
        IERC20Minimal(tok).approve(address(perp), seed);
        perp.fundPlvToken(seed);
        hook.setDeathThreshold(0, address(0));
        vm.warp(block.timestamp + 25 hours);
        vm.roll(block.number + 40);
        perp.poke();

        // The base (automatic, at summon) gives spot-straddling depth → perps CAN
        // open on the progressive gen. maxLeverage/notional scale with the base depth
        // (the base is deliberately thin — anti-snipe priority — so a progressive gen
        // supports smaller perps than an atomic one; SEED_BASE_WAD is the tunable knob).
        assertGt(perp.activeEthDepth(), 0, "progressive book has spot depth via the base (perps enabled)");
        assertGe(perp.maxLeverage(), 2, "base supports >=2x on the progressive gen");
        console2.log("perp maxLeverage on the progressive book (via base):", perp.maxLeverage());
        perp.setRisk(24 hours, 3, 4_000, 10_000, 10_000, 100); // generous caps + 40% maint
        uint256 col = (perp.activeEthDepth() * 8 / 100) / 2; // size to the thin base
        if (col < perp.minCollateral()) col = perp.minCollateral();

        // LONG opens + closes cleanly on the base book.
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 longId = perp.openLong{value: col}(2, 0, 0, col);
        (address l0,,,,,,,) = perp.positions(longId);
        assertEq(l0, trader, "long opened on the progressive gen via the base");
        vm.prank(trader); perp.close(longId, 0);
        console2.log("progressive perp long opened+closed via the base");

        // LIQUIDATE: open a long, sustained crash, liquidate. (On the thin base book,
        // keep the position small so the open itself isn't already underwater.)
        perp.setTwapWindow(60); // mark hugs spot so the crash crosses maintenance
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 liqId = perp.openLong{value: col}(2, 0, 0, col);
        (address l1,,,,,,,) = perp.positions(liqId);
        assertEq(l1, trader, "liq long opened");
        uint256 plvBefore = perp.plv();
        _sustainedCrash(tok, 3_000_000_000 ether); // blow through the bid-heavy book (base = no teleport)
        assertTrue(perp.isLiquidatable(liqId), "liquidatable on the progressive book (continuous, no teleport)");
        vm.prank(address(0xBEEF));
        perp.liquidate(liqId);
        (address lq,,,,,,,) = perp.positions(liqId);
        assertEq(lq, address(0), "liquidated on the progressive book");
        assertGe(perp.plv(), plvBefore, "PLV solvent");
        console2.log("=== PERPS OPEN + LIQUIDATE ON A PROGRESSIVE GEN VIA THE AUTO BASE ===");
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    /// Age the current pool past the death window + minLifetime, then relaunch.
    function _relaunch(uint256 gen) internal {
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(gen)), "pool dead");
        registry.relaunch();
    }

    /// Buy ETH->token, crediting `to` (tokens sent to `to`; this contract funds the
    /// ETH + drives the unlock). `to` is flagged exempt so we isolate depth impact
    /// from the surtax in the probes.
    function _buyAs(address /*who*/, address token, uint256 ethIn) internal returns (uint256 got) {
        // recipient of the credited tokens is decoded in unlockCallback (`to`).
        bytes memory res = pm.unlock(abi.encode(uint8(0), token, ethIn, address(this)));
        got = abi.decode(res, (uint256));
    }

    function _sustainedCrash(address token, uint256 tokenIn) internal {
        deal(token, address(this), tokenIn);
        pm.unlock(abi.encode(uint8(1), token, tokenIn, address(this)));
        vm.warp(block.timestamp + 1 minutes);
        vm.roll(block.number + 1);
        perp.poke();
        vm.warp(block.timestamp + 45 minutes);
        vm.roll(block.number + 1);
        perp.poke();
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (uint8 dir, address token, uint256 amt, address to) =
            abi.decode(raw, (uint8, address, uint256, address));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)), currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });
        if (dir == 0) { // ETH -> token buy, credit `to`
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: true, amountSpecified: -int256(amt), sqrtPriceLimitX96: MIN_SQRT_LIMIT
            }), abi.encode(to));
            uint256 spent = uint256(uint128(-d.amount0()));
            uint256 got = uint256(uint128(d.amount1()));
            pm.settle{value: spent}();
            pm.take(key.currency1, to, got);
            return abi.encode(got);
        } else { // token -> ETH crash sell from this contract
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: false, amountSpecified: -int256(amt), sqrtPriceLimitX96: MAX_SQRT_LIMIT
            }), abi.encode(address(this)));
            uint256 spent = uint256(uint128(-d.amount1()));
            uint256 got = uint256(uint128(d.amount0()));
            pm.sync(Currency.wrap(token));
            IERC20Minimal(token).transfer(address(pm), spent);
            pm.settle();
            pm.take(Currency.wrap(address(0)), address(this), got);
            return abi.encode(got);
        }
    }

    receive() external payable {}
}

contract NoFrens { function balanceOf(address) external pure returns (uint256) { return 0; } }

contract E2EGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/", renderer: address(0), website: "spirit.xyz",
            socials: "x.com/spirit", quote: address(0), nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
