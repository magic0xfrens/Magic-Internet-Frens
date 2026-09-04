// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {HookMiner} from "../vendor/HookMiner.sol";
import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {PerpEngine} from "../cauldron/PerpEngine.sol";
import {CauldronCollection} from "../cauldron/CauldronCollection.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../cauldron/ICauldron.sol";

/**
 * Fork integration for PerpEngine Phase 2 (LONGS + SHORTS) against LIVE Uniswap V4.
 * Proves: leverage tiers by depth, real price impact (long → up, short → down),
 * two-sided PLV solvency (ETH for longs, token inventory for shorts), the short
 * buy-back making the inventory whole (reflexive squeeze), OI/notional caps, the
 * 6.9% fee split, and the liquidation guard.
 *
 *   export FORK_RPC=<sepolia>  POOL_MANAGER=0x..  POSITION_MANAGER=0x..
 *   FOUNDRY_PROFILE=cauldron forge test --match-contract PerpEngineForkTest -vv
 */
contract PerpEngineForkTest is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook hook;
    CauldronRegistry registry;
    PerpEngine perp;
    IPoolManager pm;
    address token;
    bool active;

    address trader = address(0x7EADE7);
    address dividend = address(0xD1D1);
    address treasury = address(0x7E7E);

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
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

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        hook.setRegistry(address(registry));
        // Genesis summon now does a green-candle reseed BUY, so the registry must be
        // the opener + tax-exempt BEFORE summon (as relaunch already required).
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 50 ether);
        (token, ) = registry.summon{value: 2 ether}();

        // MiFrens NFT isn't needed here — pass a dummy that returns 0 balance.
        perp = new PerpEngine(
            IPoolManager(poolManager), address(hook), address(registry),
            address(new NoFrens()), dividend, treasury, address(this)
        );
        perp.fundPlv{value: 5 ether}();       // seed the ETH side (long leverage)

        // Seed the TOKEN side (short inventory) with an allocation of supply —
        // exactly the "% of supply to shorts" model (a grant, not a market buy).
        uint256 seed = 50_000_000 ether;
        deal(token, address(this), seed);
        IERC20Minimal(token).approve(address(perp), seed);
        perp.fundPlvToken(seed);

        // A freshly-summoned pool has 0 rolling volume → the hook's volume-based
        // isDead() reads "dead" until real trading. That's correct on mainnet
        // (the 24h warmup + launch flow generate volume) but here it would block
        // opens, so zero the threshold to keep the token "alive" for the tests.
        hook.setDeathThreshold(0);

        vm.warp(block.timestamp + 25 hours);  // past the time warmup
        vm.roll(block.number + 40);           // past the 30-block anti-snipe surtax
        perp.poke();                           // seed a TWAP observation post-warp
    }

    function test_MaxLeverage_ByDepth() public view {
        if (!active) return;
        assertEq(perp.maxLeverage(), 2, "thin pool caps at 2x");
    }

    // ── H-01 setVault drain guard: can't repoint the vault while the PLV holds
    //    depositor funds (blocks the owner→setVault(attacker)→drain path). ──
    function test_SetVault_Guard_BlocksRepointWhileFunded() public {
        if (!active) return;
        // setUp seeded plv (5 ETH) via fundPlv but wired NO vault (vault()==0), so
        // the FIRST set is allowed even when funded (owner bootstrapping the vault).
        assertGt(perp.plv(), 0, "plv funded in setUp");
        assertEq(perp.vault(), address(0), "no vault wired in setUp");
        perp.setVault(address(0xCAFE));
        assertEq(perp.vault(), address(0xCAFE), "first vault set allowed even when funded");

        // Now a REPOINT must revert (vault already set AND plv>0) — this is the
        // H-01 drain guard: owner can't swap the vault out from under staked funds.
        vm.expectRevert(); // BadParam
        perp.setVault(address(0xD00D));
        assertEq(perp.vault(), address(0xCAFE), "repoint blocked while funded");
    }

    /// The liquidation-mark TWAP window is owner-tunable down to a 1s floor (so the
    /// mark can hug spot closer on a fast L2) — but never below MIN_TWAP (1s).
    function test_SetTwapWindow_Bounds() public {
        if (!active) return;
        perp.setTwapWindow(60);
        assertEq(perp.twapWindow(), 60, "window set to 60s");
        perp.setTwapWindow(1); // MIN_TWAP floor
        assertEq(perp.twapWindow(), 1, "window set to the 1s floor");
        vm.expectRevert(); // below MIN_TWAP
        perp.setTwapWindow(0);
    }

    // ── Governance: after transferring ownership to a TimelockController, a direct
    //    owner-only call from a random EOA must revert; a scheduled+executed call
    //    through the timelock (after the delay) must succeed. ──
    function test_Timelock_OwnsEngine_ScheduleExecute() public {
        if (!active) return;
        address[] memory roles = new address[](1);
        roles[0] = address(this);
        TimelockController tl = new TimelockController(180, roles, roles, address(this));
        perp.transferOwnership(address(tl));
        assertEq(perp.owner(), address(tl), "engine owned by timelock");

        // direct call from a random EOA reverts (not owner)
        vm.prank(address(0xABCD));
        vm.expectRevert();
        perp.setMinCollateral(0.01 ether);

        // schedule setMinCollateral(0.01) via the timelock, wait 180s, execute
        bytes memory data = abi.encodeWithSignature("setMinCollateral(uint256)", uint256(0.01 ether));
        bytes32 salt = bytes32(uint256(1));
        tl.schedule(address(perp), 0, data, bytes32(0), salt, 180);
        vm.warp(block.timestamp + 181);
        tl.execute(address(perp), 0, data, bytes32(0), salt);
        assertEq(perp.minCollateral(), 0.01 ether, "timelock executed the param change");
    }

    // ── IFeeRouter: a router that sends 100% to relaunch → relaunchETH grows by
    //    the whole fee; a reverting or bad-sum router → the swap still succeeds
    //    (fallback to the built-in split, never bricks). ──
    function test_FeeRouter_RoutesAndFallsBack() public {
        if (!active) return;
        // 1. Route 100% → relaunch. A buy's ETH fee should land entirely there.
        hook.setFeeRouter(address(new AllToRelaunchRouter()));
        uint256 r0 = hook.relaunchETH();
        _buyToken(0.05 ether);
        uint256 r1 = hook.relaunchETH();
        assertGt(r1, r0, "100%-to-relaunch router credited the reserve");

        // 2. A REVERTING router must not brick the swap — buy still succeeds and
        //    the fee still routes (built-in fallback).
        hook.setFeeRouter(address(new RevertingRouter()));
        uint256 out = _buyToken(0.05 ether);
        assertGt(out, 0, "buy succeeds despite a reverting fee router");

        // 3. A BAD-SUM router (parts != fee) is rejected → built-in split used.
        hook.setFeeRouter(address(new BadSumRouter()));
        uint256 out2 = _buyToken(0.05 ether);
        assertGt(out2, 0, "buy succeeds; bad-sum router rejected, built-in used");

        // 4. Clear back to built-in (address 0) — still works.
        hook.setFeeRouter(address(0));
        uint256 out3 = _buyToken(0.05 ether);
        assertGt(out3, 0, "built-in split works after clearing the router");
    }

    function test_OpenLong_MovesPriceUp_AndCloses() public {
        if (!active) return;

        uint256 pBefore = _sqrtP();
        uint256 plvBefore = perp.plv();

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.02 ether}(2, 0, 0);

        (address t, bool isLong, uint128 col, uint256 size, uint256 principal,, uint8 lev,) = perp.positions(id);
        assertEq(t, trader, "trader");
        assertTrue(isLong, "long");
        assertEq(lev, 2, "2x");
        assertGt(size, 0, "bought token");
        assertGt(principal, 0, "borrowed from PLV");
        assertGt(col, 0, "collateral net of fee");
        assertEq(perp.plv(), plvBefore - principal, "PLV lent the borrow");

        // opening a LONG pushed the real price UP (ETH→token lowers sqrtP in this
        // orientation: tokens-per-ETH falls). Assert the true directional move.
        assertLt(_sqrtP(), pBefore, "open long moved sqrtP down = token up");

        assertGt(dividend.balance, 0, "OG dividend funded");
        assertGt(treasury.balance, 0, "treasury funded");

        uint256 tBal = trader.balance;
        vm.prank(trader);
        perp.close(id, 0);
        assertGe(perp.plv(), plvBefore, "PLV made whole (>= pre-open)");
        assertGt(trader.balance, tBal, "trader received close proceeds");
        (address t2,,,,,,,) = perp.positions(id);
        assertEq(t2, address(0), "position cleared");
    }

    function test_OpenShort_MovesPriceDown_AndCloses() public {
        if (!active) return;

        uint256 pBefore = _sqrtP();
        uint256 tokBefore = perp.plvToken();

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openShort{value: 0.02 ether}(2, 0, 0);

        (address t, bool isLong, uint128 col, uint256 size, uint256 principal,,,) = perp.positions(id);
        assertEq(t, trader, "trader");
        assertTrue(!isLong, "short");
        assertGt(size, 0, "borrowed+sold token");
        assertGt(principal, 0, "holds ETH proceeds");
        assertGt(col, 0, "collateral net of fee");
        assertEq(perp.plvToken(), tokBefore - size, "inventory lent to the short");

        // opening a SHORT sold token → sqrtP UP (tokens-per-ETH rises = token down)
        assertGt(_sqrtP(), pBefore, "open short moved price down");

        assertGt(dividend.balance, 0, "OG dividend funded");
        assertGt(treasury.balance, 0, "treasury funded");

        uint256 tBal = trader.balance;
        vm.prank(trader);
        perp.close(id, 0);
        // the buy-back returns EXACTLY the borrowed token → inventory whole again
        assertEq(perp.plvToken(), tokBefore, "short inventory made whole");
        assertGt(trader.balance, tBal, "trader received residual backing");
        (address t2,,,,,,,) = perp.positions(id);
        assertEq(t2, address(0), "position cleared");
    }

    function test_Liquidate_RevertsOnHealthy() public {
        if (!active) return;
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.02 ether}(2, 0, 0);
        vm.expectRevert(PerpEngine.Healthy.selector);
        perp.liquidate(id);
    }

    function test_OpenLong_RejectsOverCap() public {
        if (!active) return;
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        vm.expectRevert(PerpEngine.BadLeverage.selector);
        perp.openLong{value: 0.02 ether}(3, 0, 0); // depth tier is 2× here
    }

    /* ── Phase 3: TWAP mark ─────────────────────────────────────────────── */

    /// A single-block flash-crash must NOT liquidate: the TWAP mark barely moves
    /// over one block, so the position still reads healthy. This is the core
    /// anti-manipulation guarantee (can't farm liquidations by wicking the pool).
    function test_Liquidate_IgnoresFlashCrash() public {
        if (!active) return;
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        // brutal same-block crash on spot…
        _crashSell(200_000_000 ether);
        perp.poke(); // record the crashed tick

        // …but the TWAP mark hasn't moved → not liquidatable.
        assertFalse(perp.isLiquidatable(id), "flash crash must not liquidate");
        vm.expectRevert(PerpEngine.Healthy.selector);
        perp.liquidate(id);
    }

    /// A SUSTAINED crash (held across the TWAP window) DOES liquidate, and the PLV
    /// is made whole + the keeper is paid from the penalty. This is the real
    /// crash→liquidate→solvency path.
    function test_Liquidate_OnSustainedCrash_PlvSolvent() public {
        if (!active) return;
        uint256 plvBefore = perp.plv();

        // Liquidate EARLY (wide maintenance margin) — the slippage-aware invariant:
        // trigger with buffer left so the debt + penalty are always covered even
        // after the liquidation swap's own impact. Proves no bad debt + keeper pay.
        perp.setRisk(24 hours, 3, 4_000, 500, 3_000, 100); // maintenanceBps = 40%

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        // A mild sustained crash crosses the (wide) maintenance threshold while
        // the position still holds equity → penalty buffer intact.
        _sustainedCrash(200_000_000 ether);
        assertTrue(perp.isLiquidatable(id), "sustained crash is liquidatable");

        address keeper = address(0xBEEF);
        uint256 kBefore = keeper.balance;
        vm.prank(keeper);
        perp.liquidate(id);

        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, address(0), "position cleared by liquidation");
        assertGt(keeper.balance, kBefore, "keeper rewarded from penalty");
        // PLV recovered its ETH loan (no bad debt): the long's borrow is repaid
        // from proceeds first, so the vault never ends below where it started.
        assertGe(perp.plv(), plvBefore, "PLV solvent after liquidation");
        assertGt(dividend.balance, 0, "penalty routed to OG dividend");
    }

    /* ── Phase 3: death force-close + open gate ──────────────────────────── */

    function test_DeathBlocksOpen_AndForceClose() public {
        if (!active) return;
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.03 ether}(2, 0, 0); // opened while alive

        // kill the token (volume-based death): raise the threshold sky-high.
        hook.setDeathThreshold(type(uint256).max);

        // opens are now blocked…
        vm.deal(trader, 1 ether);
        vm.prank(trader);
        vm.expectRevert(PerpEngine.TokenDead.selector);
        perp.openLong{value: 0.02 ether}(2, 0, 0);

        // …but the live position can be permissionlessly force-closed (solvent,
        // no penalty) — a keeper earns a small reward, the trader keeps the rest.
        uint256 tBal = trader.balance;
        address keeper = address(0xCAFE);
        uint256 kBal = keeper.balance;
        vm.prank(keeper);
        perp.forceCloseDead(id);
        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, address(0), "force-closed");
        assertGt(trader.balance, tBal, "residual returned to trader");
        assertGt(keeper.balance, kBal, "keeper rewarded for clearing");

        hook.setDeathThreshold(0); // revive for any later assertions
    }

    /* ── per-iteration sync (one engine, all generations) ────────────────── */

    function test_Sync_GuardsAndOpenCount() public {
        if (!active) return;
        // armed for gen-1 at deploy; syncing the same gen is a no-op → reverts.
        vm.expectRevert(PerpEngine.AlreadySynced.selector);
        perp.syncGeneration();

        // openCount tracks live positions (must be 0 before a real sync).
        assertEq(perp.openCount(), 0, "starts empty");
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.02 ether}(2, 0, 0);
        assertEq(perp.openCount(), 1, "one open");
        vm.prank(trader);
        perp.close(id, 0);
        assertEq(perp.openCount(), 0, "back to zero");

        // engine is armed for the live generation with its token.
        assertEq(perp.syncedGeneration(), 1, "armed for gen-1");
    }

    /* ── Phase 3: per-block liquidation cap ──────────────────────────────── */

    function test_PerBlockLiqCap_Throttles() public {
        if (!active) return;
        // Tighten the cap so a single liquidation's notional exceeds it.
        perp.setGuards(30 minutes, 1, 5000); // maxLiqBps = 1 (0.01% of depth)

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        _sustainedCrash(1_200_000_000 ether);
        assertTrue(perp.isLiquidatable(id), "underwater");
        vm.expectRevert(PerpEngine.LiqCapped.selector);
        perp.liquidate(id); // notional > tiny per-block cap → throttled
    }

    /* ── Phase 3 (fixed leftover): funding is a real transfer, not a sink ──── */

    /// With net-long OI the funding index rises, so a LONG is charged funding
    /// (pays) and a SHORT is credited (receives). Proves funding flips sign by
    /// side — a real long↔short transfer — and stays bounded/solvent.
    function test_Funding_TransfersCrowdedToUnderweight() public {
        if (!active) return;
        // Amplify the rate so the effect is measurable over the test horizon.
        perp.setRisk(24 hours, 3, 1500, 500, 3000, 5000); // fundingBpsPerDay = 5000

        // net LONG imbalance
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 longId = perp.openLong{value: 0.05 ether}(2, 0, 0);

        // a smaller short on the underweight side
        address t2 = address(0x5057);
        vm.deal(t2, 5 ether);
        vm.prank(t2);
        uint256 shortId = perp.openShort{value: 0.02 ether}(2, 0, 0);

        // let funding accrue with the book net-long
        vm.warp(block.timestamp + 12 hours);
        vm.roll(block.number + 1);
        perp.poke();

        int256 longFd = perp.fundingDelta(longId);
        int256 shortFd = perp.fundingDelta(shortId);
        assertGt(longFd, int256(0), "crowded long PAYS funding");
        assertLt(shortFd, int256(0), "underweight short RECEIVES funding");
        // bounded by the safety cap (|fd| ≤ 50% collateral)
        assertLe(longFd, int256(0.05 ether / 2), "funding capped for long");
    }

    /// The TWAP oracle must resist ring-flooding: even if an attacker spams poke()
    /// across many blocks to push observations forward, then flash-crashes spot in
    /// one block, the mark stays a multi-minute average → NOT liquidatable.
    function test_Twap_ResistsRingFlood() public {
        if (!active) return;
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        // spam observations forward (respecting the 30s throttle) for ~20 min.
        for (uint256 i = 0; i < 45; i++) {
            vm.warp(block.timestamp + 31);
            vm.roll(block.number + 1);
            perp.poke();
        }
        // now a one-block flash crash on spot…
        _crashSell(200_000_000 ether);
        perp.poke();
        // …the mark is still a multi-minute TWAP → position stays healthy.
        assertFalse(perp.isLiquidatable(id), "flood + flash crash must not liquidate");
    }

    /* ── Liquidatoor badges + hook-native auto-liquidation ───────────────── */

    /// The in-swap liquidation entrypoint is hook-only: a direct call reverts.
    /// (The hinted `liquidateInSwap`/`liquidateManyInSwap` pair was removed — the
    /// hook has only ever called the hint-free `sweepLiquidations`, so they were
    /// dead code carrying their own `_inLocked` reentrancy surface. Audit I-08.)
    function test_SweepLiquidations_OnlyHook() public {
        if (!active) return;
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        perp.openLong{value: 0.02 ether}(2, 0, 0);
        vm.expectRevert(PerpEngine.OnlyHook.selector);
        perp.sweepLiquidations(address(0xBEEF));
    }

    /// The full path: wire the engine into the hook + the collection, open a
    /// long, sustain a crash, then a USER swap carrying (player, liqHint) auto-
    /// liquidates the position from inside afterSwap AND mints the swapper a
    /// Liquidatoor badge into the live collection — without ever reverting the
    /// swap. Also proves the badge id is in the dedicated range (art untouched).
    function test_AutoLiquidateOnSwap_MintsBadge() public {
        if (!active) return;
        address col = _wireBadges();
        perp.setRisk(24 hours, 3, 4_000, 500, 3_000, 100); // wide maintenance

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        _sustainedCrash(200_000_000 ether);
        assertTrue(perp.isLiquidatable(id), "underwater at the mark");

        address swapper = address(0x5AAA);
        uint256 badgesBefore = CauldronCollection(col).liquidatorMinted();
        uint256 artBefore = CauldronCollection(col).totalMinted();

        // A normal user sell carrying the liquidation hint → afterSwap fires the
        // engine, which liquidates `id` and badges `swapper`.
        _hintSell(1_000_000 ether, swapper, id);

        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, address(0), "auto-liquidated inside the swap");
        // HYBRID badge (gas audit G-03): with ample swap gas it AUTO-MINTS in-swap
        // (creature-like UX); only under a tight gas budget does it fall back to a
        // claimable credit. This swap carries plenty of gas → struck immediately.
        assertEq(
            CauldronCollection(col).liquidatorMinted(), badgesBefore + 1,
            "one badge struck in-swap"
        );
        assertEq(perp.badgesOwed(swapper), 0, "auto-minted, nothing owed");
        uint256 badgeId = CauldronCollection(col).LIQUIDATOR_ID_BASE() + badgesBefore + 1;
        assertEq(CauldronCollection(col).ownerOf(badgeId), swapper, "swapper holds the badge");
        assertTrue(CauldronCollection(col).isLiquidatoor(badgeId), "flagged Liquidatoor");
        assertEq(CauldronCollection(col).totalMinted(), artBefore, "art supply untouched");
    }

    /// FLASH-LOAN RESISTANCE (the core claim): an attacker can't use their OWN
    /// swap to farm a liquidation. They flash-crash spot in ONE block and tag the
    /// crashing swap with a hint at a healthy position — but the engine checks the
    /// TWAP MARK (unmoved by a single-block wick), so it's a silent no-op: the
    /// position survives and no badge is minted. This is the in-swap analogue of
    /// test_Liquidate_IgnoresFlashCrash, proving the new path is NOT exploitable.
    function test_AutoLiquidate_FlashCrash_CannotFarm() public {
        if (!active) return;
        address col = _wireBadges();

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        address attacker = address(0xBAD);
        uint256 badgesBefore = CauldronCollection(col).liquidatorMinted();

        // Attacker's single swap BOTH crashes spot AND carries the hint — the most
        // an atomic flash-loan can do. The mark is a multi-minute TWAP → unmoved.
        _hintSell(200_000_000 ether, attacker, id);

        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, trader, "flash crash did NOT liquidate (mark unmoved)");
        assertEq(
            CauldronCollection(col).liquidatorMinted(), badgesBefore,
            "no badge farmed from a flash crash"
        );
    }

    /// MULTI-liquidation: one swap carrying an array of hints rekts EVERY
    /// underwater position at once (both longs here), badging the swapper for
    /// each. Proves a single trade can clear several walls.
    function test_AutoLiquidate_Many_RektsAll() public {
        if (!active) return;
        address col = _wireBadges();
        perp.setRisk(300, 3, 4_000, 500, 3_000, 100); // wide maintenance

        vm.deal(trader, 5 ether);
        vm.startPrank(trader);
        uint256 a = perp.openLong{value: 0.05 ether}(2, 0, 0);
        uint256 b = perp.openLong{value: 0.04 ether}(2, 0, 0);
        vm.stopPrank();

        _sustainedCrash(200_000_000 ether);
        assertTrue(perp.isLiquidatable(a) && perp.isLiquidatable(b), "both underwater");

        address hunter = address(0x5AAA);
        uint256 badgesBefore = CauldronCollection(col).liquidatorMinted();
        uint256[] memory hints = new uint256[](2);
        hints[0] = a; hints[1] = b;
        _hintSellMany(1_000_000 ether, hunter, hints);

        (address ta,,,,,,,) = perp.positions(a);
        (address tb,,,,,,,) = perp.positions(b);
        assertEq(ta, address(0), "position a liquidated");
        assertEq(tb, address(0), "position b liquidated");
        // HYBRID: ample gas → both badges auto-mint in-swap (one per kill).
        assertEq(CauldronCollection(col).liquidatorMinted(), badgesBefore + 2, "TWO badges struck in-swap");
    }

    /// Dust filter: an open below `minCollateral` reverts, so bots can't spam
    /// millions of dust positions.
    function test_DustFilter_RejectsTinyOpen() public {
        if (!active) return;
        perp.setMinCollateral(0.01 ether);
        vm.deal(trader, 1 ether);
        vm.prank(trader);
        vm.expectRevert(PerpEngine.DustPosition.selector);
        perp.openLong{value: 0.005 ether}(2, 0, 0); // 0.005 − fee < 0.01 → dust
    }

    /// A HEALTHY hint is a silent no-op: the swap still succeeds, nothing is
    /// liquidated, and no badge is minted.
    function test_AutoLiquidate_HealthyHint_NoOp() public {
        if (!active) return;
        address col = _wireBadges();

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.02 ether}(2, 0, 0);

        uint256 badgesBefore = CauldronCollection(col).liquidatorMinted();
        _hintSell(1_000 ether, address(0x5AAA), id); // healthy → skip

        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, trader, "position still open (healthy)");
        assertEq(
            CauldronCollection(col).liquidatorMinted(), badgesBefore,
            "no badge for a healthy hint"
        );
    }

    /// The engine's OWN swaps (open/close) must never re-enter the auto-liq path
    /// — the hook skips when sender == perpEngine. Opening a position while the
    /// engine is wired must succeed (no reentrancy revert).
    function test_EngineSwap_DoesNotReenter() public {
        if (!active) return;
        _wireBadges();
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.02 ether}(2, 0, 0); // engine swaps internally
        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, trader, "opened fine - engine swap did not re-enter");
        vm.prank(trader);
        perp.close(id, 0); // close also swaps internally — must not re-enter
        (address t2,,,,,,,) = perp.positions(id);
        assertEq(t2, address(0), "closed fine");
    }

    /// M-01 fix: a malicious keeper cannot re-enter the engine during the in-swap
    /// liquidation payout. We make the liquidator a contract whose receive() tries
    /// to re-enter openLong; the `notNested` guard reverts that re-entry (the
    /// keeper swallows it), so the liquidation still completes cleanly AND the
    /// re-entry was provably blocked.
    function test_AutoLiquidate_ReentrantKeeper_Blocked() public {
        if (!active) return;
        address col = _wireBadges();
        perp.setRisk(24 hours, 3, 4_000, 500, 3_000, 100);

        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.05 ether}(2, 0, 0);

        ReentrantKeeper keeper = new ReentrantKeeper(perp);
        _sustainedCrash(200_000_000 ether);
        assertTrue(perp.isLiquidatable(id), "underwater");

        uint256 badgesBefore = CauldronCollection(col).liquidatorMinted();
        _hintSell(1_000_000 ether, address(keeper), id);

        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, address(0), "liquidation completed despite reentrant keeper");
        assertTrue(keeper.reentryBlocked(), "keeper's re-entry into openLong was blocked");
        // HYBRID: ample gas → badge auto-mints to the keeper in-swap.
        assertEq(CauldronCollection(col).liquidatorMinted(), badgesBefore + 1, "badge minted to keeper in-swap");
    }

    /// The headline UX: OPENING a leveraged position can rekt someone. A trader
    /// opens a long carrying a `liqHint` at an underwater position → the open
    /// liquidates it and mints the OPENER a Liquidatoor badge (+ keeper reward),
    /// while their own new long is booked normally.
    function test_OpenLong_WithLiqHint_RektsAndBadges() public {
        if (!active) return;
        address col = _wireBadges();
        perp.setRisk(24 hours, 3, 4_000, 500, 3_000, 100); // wide maintenance

        // Victim opens a long, then a sustained crash puts them underwater.
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        uint256 victim = perp.openLong{value: 0.05 ether}(2, 0, 0);
        _sustainedCrash(200_000_000 ether);
        assertTrue(perp.isLiquidatable(victim), "victim underwater at mark");

        // Attacker opens their OWN long AND tags the victim as the liqHint.
        address hunter = address(0x40D);
        vm.deal(hunter, 5 ether);
        uint256 badgesBefore = CauldronCollection(col).liquidatorMinted();
        vm.prank(hunter);
        uint256 mine = perp.openLong{value: 0.02 ether}(2, 0, victim);

        // The victim is gone, the hunter holds a fresh long AND a badge.
        (address vt,,,,,,,) = perp.positions(victim);
        assertEq(vt, address(0), "victim liquidated by the open");
        (address mt,,,,,,,) = perp.positions(mine);
        assertEq(mt, hunter, "hunter's own long is open");
        // HYBRID: ample gas → badge auto-mints to the hunter's open in-swap.
        assertEq(CauldronCollection(col).liquidatorMinted(), badgesBefore + 1, "badge minted in-swap");
        uint256 badgeId = CauldronCollection(col).LIQUIDATOR_ID_BASE() + badgesBefore + 1;
        assertEq(CauldronCollection(col).ownerOf(badgeId), hunter, "hunter holds the Liquidatoor badge");
    }

    /// PERP-FEE ROUTING: a perp swap's hook fee rewards the OGs + ETH stakers
    /// (30% dividend / 70% PLV) instead of the collection floor. Open a long/short →
    /// the ETH PLV grows by the redirected 70% + the engine's own open fees.
    function test_PerpSwapFee_RoutesToStakers_OnFork() public {
        if (!active) return;
        hook.setPerpEngine(address(perp));
        // Wire a guild so the 30% OG cut has somewhere to land + observe it.
        hook.setGuild(dividend);

        uint256 totalEthBefore = perp.totalEth();   // plv + longOiEth (borrow-neutral)
        uint256 guildBefore = dividend.balance;
        uint256 relaunchBefore = hook.relaunchETH();

        // A perp open swaps the pool (sender == engine) → fee routed to OGs + PLV.
        perp.openLong{value: 0.05 ether}(2, 0, 0);

        // 30% of the perp fee → genesis dividend (external send, unambiguous).
        assertGt(dividend.balance, guildBefore, "genesis dividend grew (30pct perp fee to OGs)");
        // 70% → the engine's ETH assets (PLV). totalEth is borrow-neutral, so it grew
        // by the redirected fee + the engine's own open fee.
        assertGt(perp.totalEth(), totalEthBefore, "engine ETH assets grew (70pct perp fee to stakers)");
        // The fee did NOT route to the relaunch reserve (proves the perp branch, not
        // the normal _routeEthFee which — with no vault — would grow relaunchETH).
        assertEq(hook.relaunchETH(), relaunchBefore, "perp fee bypassed the relaunch reserve");
        // And the engine is NOT permanently exempt — it paid the fee to get here.
        assertFalse(hook.taxExempt(address(perp)), "engine not exempt; perp swaps pay the fee");

        // SIDE-ATTRIBUTION: a SHORT open SELLS the token → its fee credits the TOKEN
        // stakers' pot (tokYieldEth), not the ETH side. Buys→ETH, sells→token.
        uint256 tokYieldBefore = perp.tokYieldEth();
        perp.openShort{value: 0.02 ether}(2, 0, 0);
        assertGt(perp.tokYieldEth(), tokYieldBefore, "short SELL fee credited the token stakers (tokYieldEth)");
    }

    /// THE MAKE-OR-BREAK TEST: a staker's PLV auto-migrates across a relaunch with
    /// OPEN positions, with NO manual step. relaunch() force-closes every position
    /// (oldest-first) while the old pool is alive, then re-arms the engine on the new
    /// token — and must NEVER brick. Proves the "stake & chill" set-and-forget path.
    function test_Relaunch_AutoMigratesPerps_WithOpenPositions_OnFork() public {
        if (!active) return;

        // Wire the engine into the hook (so the registry finds it via hook.perpEngine).
        // NOTE: the engine is NOT tax-exempt — perp swaps pay the hook fee normally
        // (revenue); the hook exempts it ONLY for the relaunch force-close window.
        hook.setPerpEngine(address(perp));
        registry.setGovernor(address(new PerpMockGov()));

        // The engine is NOT permanently tax-exempt — perp swaps pay the hook fee
        // normally (revenue). The hook exempts it only for the force-close window.
        assertFalse(hook.taxExempt(address(perp)), "engine NOT permanently exempt (revenue preserved)");
        // Open a LONG and a SHORT on gen-1 (both must force-close at relaunch).
        perp.openLong{value: 0.05 ether}(2, 0, 0);
        perp.openShort{value: 0.02 ether}(2, 0, 0);
        assertEq(perp.openCount(), 2, "two positions open");
        uint256 plvEthBefore = perp.plv();
        assertEq(perp.syncedGeneration(), 1, "armed for gen-1");

        // Kill gen-1: raise the death threshold above its (zero) rolling volume.
        hook.setDeathThreshold(1 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen-1 dead");

        // REBIRTH → gen-2. Must SUCCEED despite open positions (the make-or-break).
        (address token2, ) = registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "gen-2 born (relaunch did not brick)");

        // Auto-migrated: all positions force-closed + engine re-armed on the new token.
        assertEq(perp.openCount(), 0, "all positions force-closed at relaunch");
        assertEq(perp.syncedGeneration(), 2, "engine auto-synced to gen-2");
        assertEq(perp.syncedToken(), token2, "token side re-denominated to gen-2 token");
        assertGt(perp.plvToken(), 0, "token PLV migrated 1:1 into the new token (non-zero)");
        assertGt(perp.plv(), 0, "ETH PLV carried over");
        // The staker never lifted a finger — their share is intact, now in gen-2.
        plvEthBefore; // (ETH side carries untouched by design)
    }

    /// Best-effort guarantee: relaunch still completes if the engine is UNSET
    /// (hook.perpEngine == 0) — the try/catch never blocks the rebirth.
    function test_Relaunch_NoEngine_StillCompletes_OnFork() public {
        if (!active) return;
        // Engine NOT wired into the hook → hook.perpEngine() == 0.
        registry.setGovernor(address(new PerpMockGov()));
        hook.setDeathThreshold(1 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "relaunch completed with no engine wired");
    }

    /// Wire the PerpEngine into the hook and authorise it to mint badges on the
    /// live collection. Returns the collection address.
    function _wireBadges() internal returns (address col) {
        hook.setPerpEngine(address(perp));
        col = hook.collection();
        require(col != address(0), "no collection wired");
        vm.prank(CauldronCollection(col).deployer());
        CauldronCollection(col).setLiquidatorMinter(address(perp));
    }

    // ── helpers: exact-input swaps the test drives directly through the pool,
    //    to seed inventory and to CRASH the price (sell token) for liq tests. ──
    function _buyToken(uint256 ethIn) internal returns (uint256 out) {
        out = abi.decode(pm.unlock(abi.encode(uint8(0), ethIn)), (uint256));
    }
    /// A NATIVE buy — EMPTY hookData, tx.origin = `buyer` (a raw Uniswap swap).
    function _nativeBuy(uint256 ethIn, address buyer) internal returns (uint256 out) {
        vm.prank(address(this), buyer); // tx.origin = buyer
        out = abi.decode(pm.unlock(abi.encode(uint8(4), ethIn)), (uint256));
    }

    // ── NATIVE (Uniswap-native) gacha: raw swaps forge crystals with NO router ──
    function test_NativeGacha_DirectBuyForgesCrystals() public {
        if (!active) return;
        address buyer = address(0xB0B);
        // A direct buy (empty hookData) must credit tx.origin (the buyer) — the
        // Uniswap-native path — even though it never touched our router.
        _nativeBuy(0.5 ether, buyer);
        uint256 credited = hook.nftCredit(hook.creditEpoch(), buyer);
        uint256 pend = hook.pendingOf(buyer);
        assertGt(credited + pend, 0, "native buy credited the buyer");

        // If that buy committed crystals in-swap, a follow-up buy in a LATER block
        // resolves them (commit-reveal needs a future blockhash) — proving the
        // whole forge happens through the pool with no router.
        if (pend > 0) {
            vm.roll(block.number + 2);
            vm.warp(block.timestamp + 60);
            uint256 openedBefore = hook.opened(buyer);
            _nativeBuy(0.3 ether, buyer);
            assertTrue(hook.opened(buyer) >= openedBefore, "resolution ran in-swap (no revert)");
            assertLe(hook.pendingOf(buyer), pend + 10, "pending didn't run away (resolution progressed)");
        }
    }

    function test_NativeGacha_PostMintout_TradingStillWorks() public {
        if (!active) return;
        address col = hook.collection();
        require(col != address(0), "no collection");
        uint256 max = CauldronCollection(col).maxSupply();
        // Mint the collection OUT via its minter (the hook).
        vm.startPrank(address(hook));
        while (CauldronCollection(col).totalMinted() < max) {
            CauldronCollection(col).mint(address(0xDEAD));
        }
        vm.stopPrank();
        assertEq(CauldronCollection(col).totalMinted(), max, "collection minted out");

        // A NATIVE buy AFTER mint-out must STILL succeed — the gacha no-ops
        // (commit returns 0, resolve misses), trading lives on.
        uint256 out = _nativeBuy(0.3 ether, address(0xCAFE));
        assertGt(out, 0, "buy still works after mintout");
        // And a plain buy too (fee path unaffected).
        uint256 out2 = _buyToken(0.2 ether);
        assertGt(out2, 0, "router-style buy also works after mintout");
    }
    /// Sell `tokenIn` token → ETH (drives the real price DOWN). Uses `deal`-minted
    /// token so a crash doesn't require buying first (which would prop the price).
    function _crashSell(uint256 tokenIn) internal returns (uint256 ethOut) {
        deal(token, address(this), tokenIn);
        ethOut = abi.decode(pm.unlock(abi.encode(uint8(1), tokenIn)), (uint256));
    }

    /// Crash the spot price and HOLD it past the TWAP window so the mark follows:
    /// crash → advance a block and poke (records the crashed tick) → warp past the
    /// window and poke again (the crashed tick now dominates the average).
    function _sustainedCrash(uint256 tokenIn) internal {
        _crashSell(tokenIn);
        vm.warp(block.timestamp + 1 minutes); // past OBS_INTERVAL so the write lands
        vm.roll(block.number + 1);
        perp.poke(); // lastTick ← crashed tick
        vm.warp(block.timestamp + 45 minutes); // > twapWindow (30m)
        vm.roll(block.number + 1);
        perp.poke(); // accumulate the crashed tick across the window
    }

    /// Sell `tokenIn` token → ETH carrying a (player, uint256[] hints) hookData so
    /// the hook's afterSwap auto-liquidates every underwater hint + credits
    /// `player`. Single-hint convenience wrapper.
    function _hintSell(uint256 tokenIn, address player, uint256 hint) internal {
        uint256[] memory hints = new uint256[](1);
        hints[0] = hint;
        _hintSellMany(tokenIn, player, hints);
    }
    function _hintSellMany(uint256 tokenIn, address player, uint256[] memory hints) internal {
        deal(token, address(this), tokenIn);
        // The hint-free sweep credits tx.origin. Keep msg.sender = this test (so
        // the PoolManager calls back our unlockCallback) but set tx.origin =
        // `player` (the swapper we expect to receive the keeper reward + badge).
        vm.prank(address(this), player);
        pm.unlock(abi.encode(uint8(3), tokenIn, player, hints));
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        uint8 dir = abi.decode(raw[:32], (uint8));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)), currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });
        if (dir == 3) {
            // Hinted sell: hookData = abi.encode(player, uint256[] hints).
            (, uint256 amt, address player, uint256[] memory hints) =
                abi.decode(raw, (uint8, uint256, address, uint256[]));
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: false, amountSpecified: -int256(amt),
                sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970342 - 1
            }), abi.encode(player, hints));
            uint256 spent = uint256(uint128(-d.amount1()));
            uint256 got = uint256(uint128(d.amount0()));
            pm.sync(Currency.wrap(token));
            IERC20Minimal(token).transfer(address(pm), spent);
            pm.settle();
            pm.take(Currency.wrap(address(0)), address(this), got);
            return abi.encode(got);
        }
        if (dir == 4) {
            // NATIVE buy — EMPTY hookData (a direct Uniswap/aggregator swap that
            // never went through our router). The hook must credit tx.origin +
            // forge crystals natively.
            (, uint256 amt4) = abi.decode(raw, (uint8, uint256));
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: true, amountSpecified: -int256(amt4), sqrtPriceLimitX96: 4295128740
            }), "");
            uint256 spent = uint256(uint128(-d.amount0()));
            uint256 got = uint256(uint128(d.amount1()));
            pm.settle{value: spent}();
            pm.take(Currency.wrap(token), address(this), got);
            return abi.encode(got);
        }
        (, uint256 amt2) = abi.decode(raw, (uint8, uint256));
        uint256 amt = amt2;
        if (dir == 0) {
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: true, amountSpecified: -int256(amt), sqrtPriceLimitX96: 4295128740
            }), abi.encode(address(this)));
            uint256 spent = uint256(uint128(-d.amount0()));
            uint256 got = uint256(uint128(d.amount1()));
            pm.settle{value: spent}();
            pm.take(Currency.wrap(token), address(this), got);
            return abi.encode(got);
        } else {
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: false, amountSpecified: -int256(amt),
                sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970342 - 1
            }), abi.encode(address(this)));
            uint256 spent = uint256(uint128(-d.amount1())); // token in
            uint256 got = uint256(uint128(d.amount0()));    // ETH out
            pm.sync(Currency.wrap(token));
            IERC20Minimal(token).transfer(address(pm), spent);
            pm.settle();
            pm.take(Currency.wrap(address(0)), address(this), got);
            return abi.encode(got);
        }
    }

    function _sqrtP() internal view returns (uint256) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)), currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });
        (uint160 sp,,,) = pm.getSlot0(key.toId());
        return sp;
    }

    receive() external payable {}
}

/// ERC721 stub whose balanceOf is always 0 (no OG discount in these tests).
contract NoFrens {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

/// IFeeRouter that routes 100% of the fee to the relaunch reserve (0 guild/floor).
contract AllToRelaunchRouter {
    function route(uint256 feeAmount, address, address, uint256, uint256)
        external pure returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch)
    { return (0, 0, feeAmount); }
}

/// A malicious/broken IFeeRouter — always reverts. The hook must fall back to its
/// built-in split so a swap never bricks on the fee routing.
contract RevertingRouter {
    function route(uint256, address, address, uint256, uint256)
        external pure returns (uint256, uint256, uint256)
    { revert("nope"); }
}

/// An IFeeRouter that returns amounts summing to MORE than the fee — the hook must
/// reject it (sum != fee) and fall back to the built-in split (no over-send).
contract BadSumRouter {
    function route(uint256 feeAmount, address, address, uint256, uint256)
        external pure returns (uint256, uint256, uint256)
    { return (feeAmount, feeAmount, feeAmount); } // 3× — must be rejected
}

/// A malicious liquidator: on receiving its keeper reward it tries to re-enter
/// the engine (openLong). The `notNested` guard must revert that; we catch it and
/// flag `reentryBlocked` so the outer liquidation still completes.
contract ReentrantKeeper {
    PerpEngine public immutable perp;
    bool public reentryBlocked;
    constructor(PerpEngine _perp) { perp = _perp; }
    receive() external payable {
        // Attempt a re-entry mid-liquidation. openLong runs `notNested` (before its
        // body), which reverts because the engine is settling an in-swap liq.
        try perp.openLong{value: 0}(2, 0, 0) returns (uint256) {
            // reached the body → guard FAILED to block (leave reentryBlocked false)
        } catch {
            reentryBlocked = true; // guard reverted the re-entry — expected
        }
    }
}

/// Minimal governor for the relaunch auto-migrate test — always has a winning brew.
contract PerpMockGov is ICauldronGovernor {
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
