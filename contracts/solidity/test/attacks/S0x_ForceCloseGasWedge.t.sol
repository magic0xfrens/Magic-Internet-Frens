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
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/// S0x — the force-close gas wedge.
///
/// PROPERTY UNDER TEST (liveness): once the generation is dead, the whole perp
/// book must be clearable in ONE `forceCloseAllDead()` call that fits inside a
/// block, because `CauldronRegistry._perpHousekeep(false)` forwards
/// `gasleft() - RELAUNCH_TAIL_RESERVE` (8_000_000) to
/// `CauldronHook.forceClosePerps()`, which is NOT try-wrapped on the registry
/// side and reverts `PerpsOpen()` if a single position survives. If the book
/// costs more than the relaunch can forward, relaunch reverts forever.
contract S0xForceCloseGasWedge is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook hook;
    CauldronRegistry registry;
    PerpEngine perp;
    IPoolManager pm;
    address token;

    address dividend = address(0xD1D1);
    address treasury = address(0x7E7E);

    // Measured results, filled by internal helpers, asserted at the top level.
    uint256 opened;
    uint256 gasFullBook;      // gas for forceCloseAllDead over the whole book
    uint256 leftOpen;         // openCount after the drain
    uint256 gasPerPosition;

    function setUp() public {
        string memory rpc = vm.envString("FORK_RPC");
        vm.createSelectFork(rpc);
        vm.etch(dividend, address(new Sink()).code);

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
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 500 ether);
        (token, ) = registry.summon{value: 20 ether}();

        perp = new PerpEngine(
            IPoolManager(poolManager), address(hook), address(registry),
            address(new NoFrens()), dividend, treasury, address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 50 ether}(50 ether);


        hook.setDeathThreshold(0, address(0), 0, 0, 0); // alive: vol < 0 is never true
        vm.warp(block.timestamp + 25 hours);
        vm.roll(block.number + 40);
        perp.poke();
    }

    // ── the property: a dead book drains in ONE call, inside a block ───────
    /// Fabricated inventory (forge `deal`): mints balance WITHOUT touching
    /// totalSupply, so it is NOT part of the token's circulating supply.
    function _seedTokenSideFabricated(uint256 seed) internal {
        deal(token, address(this), seed);
        IERC20Minimal(token).approve(address(perp), seed);
        perp.fundPlvToken(seed);
    }

    /// PRODUCTION-SHAPED inventory: bought out of the live pool with ETH, so the
    /// tokens genuinely left the LP and are genuinely circulating.
    function _seedTokenSideFromMarket(uint256 ethIn) internal returns (uint256 got) {
        got = _buyToken(ethIn);
        IERC20Minimal(token).approve(address(perp), got);
        perp.fundPlvToken(got);
    }

    function _buyToken(uint256 ethIn) internal returns (uint256 out) {
        out = abi.decode(pm.unlock(abi.encode(uint8(0), ethIn)), (uint256));
    }

    function test_DeadBookDrainsInOneCallInsideABlock() public {
        opened = _fillBook();
        (gasFullBook, leftOpen) = _drainDead();
        gasPerPosition = opened == 0 ? 0 : gasFullBook / opened;

        emit log_named_uint("positions opened", opened);
        emit log_named_uint("forceCloseAllDead gas", gasFullBook);
        emit log_named_uint("gas per position", gasPerPosition);
        emit log_named_uint("openCount left", leftOpen);

        assertGt(opened, 0, "book must have been filled");
        assertEq(leftOpen, 0, "the whole book drained in one call");
        // The registry keeps an 8M tail reserve, so a 30M block can forward at
        // most ~22M to forceClosePerps. Anything above that is a permanent
        // relaunch brick, because nothing else clears the book wholesale.
        assertLt(gasFullBook, 22_000_000, "one force-close must fit the relaunch's forwardable gas");
    }

    // ── how far can the book actually be filled, and what does it cost? ────
    function _fillBook() internal returns (uint256 n) {
        for (uint256 i; i < 64; ++i) {
            address t = address(uint160(0x100000 + i));
            vm.deal(t, 1 ether);
            vm.prank(t);
            // dust longs: minCollateral is 0.003 ether, 2x is the thin-pool tier
            try perp.openLong{value: 0.0035 ether}(2, 0, 0, 0.0035 ether) returns (uint256) {
                n++;
            } catch {
                break;
            }
        }
    }

    /// Fill with the BIGGEST positions the caps admit, halving on rejection, so the
    /// settlement swaps are as large (and as many-tick-crossing) as the protocol
    /// permits. `wantShort` picks the side.
    function _fillBookFat(bool wantShort) internal returns (uint256 n) {
        emit log_named_uint("plvToken before", perp.plvToken());
        emit log_named_uint("plv before", perp.plv());
        uint256 amt = 1 ether;
        for (uint256 i; i < 64; ++i) {
            address t = address(uint160(0x200000 + i));
            vm.deal(t, 5 ether);
            bool ok;
            for (uint256 k; k < 12; ++k) {
                vm.prank(t);
                if (wantShort) {
                    try perp.openShort{value: amt}(2, 0, 0, amt) returns (uint256) { ok = true; } catch { amt /= 2; }
                } else {
                    try perp.openLong{value: amt}(2, 0, 0, amt) returns (uint256) { ok = true; } catch { amt /= 2; }
                }
                if (ok) break;
                if (amt < 0.0035 ether) break;
            }
            if (!ok) break;
            n++;
            if (i == 0 || i == 63) emit log_named_uint("open amt", amt);
        }
    }

    function _drainDead() internal returns (uint256 gasUsed, uint256 stillOpen) {
        emit log_named_uint("openCount pre-drain", perp.openCount());
        emit log_named_uint("shortOi pre-drain", perp.shortOiToken());
        emit log_named_uint("longOi pre-drain", perp.longOiEth());
        emit log_named_uint("plvToken pre-drain", perp.plvToken());
        // Kill the generation the way the hook decides death: 24h volume below
        // the threshold. Raising the threshold above realised volume is exactly
        // the on-chain condition, reached here without waiting a day.
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        assertTrue(perp.openCount() > 0, "book is non-empty before the drain");
        uint256 g0 = gasleft();
        perp.forceCloseAllDead();
        gasUsed = g0 - gasleft();
        stillOpen = perp.openCount();
    }

    function test_FatShortBookDrainsInOneCallInsideABlock() public {
        _seedTokenSideFabricated(200_000_000 ether);
        opened = _fillBookFat(true);
        (gasFullBook, leftOpen) = _drainDead();
        gasPerPosition = opened == 0 ? 0 : gasFullBook / opened;
        emit log_named_uint("fat short opens that succeeded", opened);
        emit log_named_uint("openCount seen", perp.openCount());
        emit log_named_uint("plvToken after ", perp.plvToken());
        emit log_named_uint("shortOiToken after", perp.shortOiToken());
        emit log_named_uint("plv after", perp.plv());
        emit log_named_uint("insurance after", perp.insuranceEth());
        emit log_named_uint("engine tok bal", IERC20Minimal(token).balanceOf(address(perp)));
        emit log_named_uint("forceCloseAllDead gas", gasFullBook);
        emit log_named_uint("gas per position", gasPerPosition);
        emit log_named_uint("openCount left", leftOpen);
        assertGt(opened, 0, "book must have been filled");
        assertEq(leftOpen, 0, "the whole fat short book drained in one call");
        // NOTE: many of these opens were auto-liquidated by the NEXT open's
        // post-open sweep, so the live book at drain time is smaller than `opened`
        // (logged above as "openCount pre-drain"). The 64-dust-long case is the
        // honest full-book measurement.
        assertLt(gasFullBook, 22_000_000, "one force-close must fit the relaunch's forwardable gas");
    }

    function test_FatLongBookDrainsInOneCallInsideABlock() public {
        opened = _fillBookFat(false);
        (gasFullBook, leftOpen) = _drainDead();
        gasPerPosition = opened == 0 ? 0 : gasFullBook / opened;
        emit log_named_uint("fat long opens that succeeded", opened);
        emit log_named_uint("forceCloseAllDead gas", gasFullBook);
        emit log_named_uint("gas per position", gasPerPosition);
        emit log_named_uint("openCount left", leftOpen);
        assertGt(opened, 0, "book must have been filled");
        assertEq(leftOpen, 0, "the whole fat long book drained in one call");
        assertLt(gasFullBook, 22_000_000, "one force-close must fit the relaunch's forwardable gas");
    }

    uint256 tokBefore; uint256 tokAfter; uint256 oiBefore; uint256 shortSize;

    /// ONE dust short. At death the engine must BUY THE TOKEN BACK, so the
    /// token-side inventory (`plvToken`) must be whole again afterwards.
    function test_DeadShortIsBoughtBackNotWrittenOff() public {
        _seedTokenSideFabricated(200_000_000 ether);
        address t = address(0x51D1);
        vm.deal(t, 1 ether);
        tokBefore = perp.plvToken();
        vm.prank(t);
        uint256 id = perp.openShort{value: 0.02 ether}(2, 0, 0, 0.02 ether);
        (,,, shortSize,,,,) = perp.positions(id);
        oiBefore = perp.shortOiToken();

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        uint256 g0 = gasleft();
        perp.forceCloseAllDead();
        gasFullBook = g0 - gasleft();
        tokAfter = perp.plvToken();
        leftOpen = perp.openCount();

        emit log_named_uint("short size (token)", shortSize);
        emit log_named_uint("shortOiToken at open", oiBefore);
        emit log_named_uint("plvToken before", tokBefore);
        emit log_named_uint("plvToken after ", tokAfter);
        emit log_named_uint("force-close gas", gasFullBook);
        emit log_named_uint("engine token bal", IERC20Minimal(token).balanceOf(address(perp)));

        assertGt(shortSize, 0, "the short borrowed token");
        assertEq(leftOpen, 0, "closed");
        assertEq(tokAfter, tokBefore, "token inventory made whole by the death buy-back");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  ORCHESTRATOR LEAD: the token-side inventory wipe at relaunch.
    //  PROPERTY: a relaunch must carry the engine's token inventory across 1:1,
    //  so PerpVault.assetsTok() (= totalTokenAssets()) survives the rebirth.
    // ══════════════════════════════════════════════════════════════════════
    uint256 resId; uint128 resLiq; uint256 tokAssetsBefore; uint256 tokAssetsAfter;
    uint256 newBal; uint256 oldBal; uint256 strandedAmt;

    function test_RelaunchCarriesTheTokenInventory() public {
        _seedTokenSideFabricated(200_000_000 ether);
        registry.setGovernor(address(new MiniGov()));
        registry.setMinLifetime(0);
        // The engine must be armed on gen 1 so the sync sees fromGen < gen.
        try perp.syncGeneration() {} catch {}

        tokAssetsBefore = perp.totalTokenAssets();
        address oldTok = token;

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        (address newTok, ) = registry.relaunch();

        resId = registry.generationReservePositionId(2);
        tokAssetsAfter = perp.totalTokenAssets();
        newBal = IERC20Minimal(newTok).balanceOf(address(perp));
        oldBal = IERC20Minimal(oldTok).balanceOf(address(perp));
        strandedAmt = perp.strandedToken(oldTok);

        emit log_named_uint("totalTokenAssets BEFORE", tokAssetsBefore);
        emit log_named_uint("totalTokenAssets AFTER ", tokAssetsAfter);
        emit log_named_uint("gen2 reserve positionId", resId);
        emit log_named_uint("engine NEW token bal", newBal);
        emit log_named_uint("engine OLD token bal", oldBal);
        emit log_named_uint("strandedToken[old]", strandedAmt);
        emit log_named_uint("syncedGeneration", perp.syncedGeneration());

        // THE DIAGNOSIS, asserted. The reserve position EXISTS (so this is not
        // PerpSwapLib.sol:325's "RedemptionExt not wired" cause) and the shortfall
        // IS recorded — the reserve simply has no capacity for inventory that was
        // never part of circulating supply, because
        // CauldronRegistry.sol:1112 sizes it as TOTAL_SUPPLY - newActive.
        assertGt(tokAssetsBefore, 0, "engine had token inventory before the rebirth");
        assertGt(resId, 0, "a gen-2 reserve position WAS created (not the NotConfigured cause)");
        assertLt(tokAssetsAfter, tokAssetsBefore / 1000, "fabricated inventory does NOT migrate");
        assertApproxEqAbs(strandedAmt, tokAssetsBefore, 1e18, "and the shortfall is recorded, not silent");
    }

    /// THE CONTROL. Same relaunch, but the engine's inventory was BOUGHT from the
    /// pool, so it is real circulating supply and the reserve is sized for it.
    function test_RelaunchCarriesMarketBoughtInventory() public {
        uint256 bought = _seedTokenSideFromMarket(5 ether);
        registry.setGovernor(address(new MiniGov()));
        registry.setMinLifetime(0);
        try perp.syncGeneration() {} catch {}

        tokAssetsBefore = perp.totalTokenAssets();
        address oldTok = token;
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        (address newTok, ) = registry.relaunch();

        tokAssetsAfter = perp.totalTokenAssets();
        newBal = IERC20Minimal(newTok).balanceOf(address(perp));
        oldBal = IERC20Minimal(oldTok).balanceOf(address(perp));
        strandedAmt = perp.strandedToken(oldTok);

        emit log_named_uint("bought from pool", bought);
        emit log_named_uint("totalTokenAssets BEFORE", tokAssetsBefore);
        emit log_named_uint("totalTokenAssets AFTER ", tokAssetsAfter);
        emit log_named_uint("engine NEW token bal", newBal);
        emit log_named_uint("engine OLD token bal", oldBal);
        emit log_named_uint("strandedToken[old]", strandedAmt);
        emit log_named_uint("gen2 reserve positionId", registry.generationReservePositionId(2));

        assertGt(tokAssetsBefore, 0, "engine had token inventory before the rebirth");
        assertEq(oldBal, 0, "the whole old-token inventory was burned into the migration");
        assertApproxEqRel(
            tokAssetsAfter, tokAssetsBefore, 1e12,
            "market-bought inventory migrates 1:1 across the rebirth"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    //  BORN-UNDERWATER: opens fill at SPOT but are judged against the 5-min
    //  TWAP mark (and, per _liqTest, live SPOT with a ZERO buffer). PROPERTY: a
    //  freshly opened, fully funded position must not be liquidatable by its own
    //  price impact.
    // ══════════════════════════════════════════════════════════════════════
    bool victimAliveAfterOwnOpen; bool victimAliveAfterStrangerDust;
    uint256 vicColl; uint256 attackerGain; uint256 vicPayout;

    function test_FreshPositionSurvivesItsOwnOpen() public {
        address vic = address(0x91C);
        vm.deal(vic, 50 ether);
        uint256 amt = _largestOpenableLong(vic);
        emit log_named_uint("largest openable long (wei)", amt);
        assertGt(amt, 0, "some long size is openable");

        vm.prank(vic);
        uint256 id = perp.openLong{value: amt}(2, 0, 0, amt);
        (address t,, uint128 c,,,,,) = perp.positions(id);
        victimAliveAfterOwnOpen = t != address(0);
        vicColl = c;
        emit log_named_uint("openCount right after the open", perp.openCount());
        emit log_named_string("survived its own open", victimAliveAfterOwnOpen ? "yes" : "no");
        assertTrue(victimAliveAfterOwnOpen, "a fresh max-size open must not be liquidated by its own sweep");
    }

    function test_StrangerDustOpenCannotFarmAFreshPosition() public {
        address vic = address(0x91C);
        address atk = address(0xA77AC4);
        vm.deal(vic, 50 ether);
        vm.deal(atk, 50 ether);
        uint256 amt = _largestOpenableLong(vic);
        vm.prank(vic);
        uint256 id = perp.openLong{value: amt}(2, 0, 0, amt);
        (,, uint128 c,,,,,) = perp.positions(id);
        vicColl = c;
        if (c == 0) { victimAliveAfterStrangerDust = false; }

        uint256 b0 = atk.balance;
        uint256 v0 = vic.balance;
        vm.prank(atk);
        perp.openLong{value: 0.0035 ether}(2, 0, 0, 0.0035 ether);
        (address t2,,,,,,,) = perp.positions(id);
        victimAliveAfterStrangerDust = t2 != address(0);
        attackerGain = atk.balance + 0.0035 ether > b0 ? atk.balance + 0.0035 ether - b0 : 0;
        vicPayout = vic.balance - v0;

        emit log_named_uint("victim collateral", vicColl);
        emit log_named_string("victim still open after stranger dust open", victimAliveAfterStrangerDust ? "yes" : "no");
        emit log_named_uint("attacker net (excl. the dust it locked)", attackerGain);
        emit log_named_uint("victim liquidation payout", vicPayout);
        assertTrue(victimAliveAfterStrangerDust, "a stranger's 0.0035 ETH open must not liquidate a fresh position");
    }

    /// The largest long the caps admit, found by halving. Does NOT open it.
    function _largestOpenableLong(address who) internal returns (uint256) {
        uint256 amt = 4 ether;
        for (uint256 k; k < 14; ++k) {
            uint256 snap = vm.snapshotState();
            vm.prank(who);
            bool ok;
            try perp.openLong{value: amt}(2, 0, 0, amt) returns (uint256) { ok = true; } catch {}
            vm.revertToState(snap);
            if (ok) return amt;
            amt /= 2;
        }
        return 0;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  PUMP-SANDWICH: an attacker front-runs a pending openLong with a buy. The
    //  open fills at the PUMPED SPOT but is judged against the lagging TWAP mark,
    //  so the victim is born liquidatable and the attacker liquidates it in the
    //  same block and sells back out.
    //  PROPERTY: a position opened with full collateral must not be liquidatable
    //  in the block it was opened in.
    // ══════════════════════════════════════════════════════════════════════
    bool bornLiquidatable; bool liqSucceeded; uint256 vicRefund; uint256 vicIn;

    function test_PositionIsNotLiquidatableInItsOwnBlock() public {
        address vic = address(0x91C);
        vm.deal(vic, 50 ether);

        // 1. ATTACKER front-runs with a buy that pumps spot. Spot moves now; the
        //    5-minute TWAP mark does not.
        uint256 pBefore = _sqrtP();
        _buyToken(6 ether);
        emit log_named_uint("sqrtP before pump", pBefore);
        emit log_named_uint("sqrtP after pump ", _sqrtP());

        // 2. VICTIM's pending openLong lands, minTokenOut = 0 (the UI default).
        vicIn = 0.05 ether;
        uint256 v0 = vic.balance;
        vm.prank(vic);
        uint256 id = perp.openLong{value: vicIn}(2, 0, 0, vicIn);

        bornLiquidatable = perp.isLiquidatable(id);
        emit log_named_string("born liquidatable", bornLiquidatable ? "yes" : "no");

        // 3. ANYONE liquidates it immediately, same block.
        address atk = address(0xA77AC4);
        vm.prank(atk);
        try perp.liquidate(id) { liqSucceeded = true; } catch {}
        vicRefund = vic.balance - (v0 - vicIn);
        emit log_named_string("liquidated same block", liqSucceeded ? "yes" : "no");
        emit log_named_uint("victim paid in ", vicIn);
        emit log_named_uint("victim got back", vicRefund);
        emit log_named_uint("keeper bounty (wei)", atk.balance);

        assertFalse(bornLiquidatable, "a fresh, fully collateralised open must not be liquidatable");
        assertFalse(liqSucceeded, "nobody may liquidate a position in the block it opened");
    }

    // ── v4 lock plumbing for the fixture's own swaps ───────────────────────
    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (uint8 dir, uint256 amt) = abi.decode(raw, (uint8, uint256));
        PoolKey memory key = _key();
        if (dir == 0) {
            BalanceDelta d = pm.swap(key, SwapParams({
                zeroForOne: true, amountSpecified: -int256(amt), sqrtPriceLimitX96: 4295128740
            }), abi.encode(address(this)));
            uint256 spent = uint256(uint128(-d.amount0()));
            uint256 got = uint256(uint128(d.amount1()));
            pm.settle{value: spent}();
            pm.take(Currency.wrap(token), address(this), got);
            return abi.encode(got);
        }
        BalanceDelta d2 = pm.swap(key, SwapParams({
            zeroForOne: false, amountSpecified: -int256(amt),
            sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970342 - 1
        }), abi.encode(address(this)));
        uint256 spent2 = uint256(uint128(-d2.amount1()));
        uint256 got2 = uint256(uint128(d2.amount0()));
        pm.sync(Currency.wrap(token));
        IERC20Minimal(token).transfer(address(pm), spent2);
        pm.settle();
        pm.take(Currency.wrap(address(0)), address(this), got2);
        return abi.encode(got2);
    }

    function _sqrtP() internal view returns (uint256) {
        (uint160 sp,,,) = pm.getSlot0(_key().toId());
        return sp;
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)), currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    receive() external payable {}
}

contract Sink { receive() external payable {} }

contract MiniGov {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://s/", renderer: address(0), website: "", socials: "",
            quote: address(0), nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
contract NoFrens { function balanceOf(address) external pure returns (uint256) { return 0; } }
