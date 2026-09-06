// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

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

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * ATTACKS ON THE HOOK-NATIVE PERP ENGINE.
 *
 *  A-02  STALE-`lastTick` TWAP POISONING  (mark manipulation, HIGH)
 *  A-03  `forceCloseAllDead` 96-ITERATION CAP  (engine bricking + cross-generation
 *        position corruption, HIGH)
 *  A-04  FUNDING IS NOT CONSERVED  (PLV principal leak, MEDIUM)
 *
 *  Run:
 *    export FORK_RPC=... POOL_MANAGER=0x... POSITION_MANAGER=0x...
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract A02_PerpAttacksTest -vv
 */
contract A02_PerpAttacksTest is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook hook;
    CauldronRegistry registry;
    PerpEngine perp;
    IPoolManager pm;
    address token;
    bool active;

    address trader = address(0x7EADE7);
    address attacker = address(0xA77ACC);

    uint160 constant MIN_LIMIT = 4295128740;
    uint160 constant MAX_LIMIT = 1461446703485210103287273052203988822378723970342 - 1;

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
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));
        registry.setGovernor(address(new PerpGov()));

        vm.deal(address(this), 400 ether);
        (token,) = registry.summon{value: 20 ether}();

        perp = new PerpEngine(
            IPoolManager(poolManager), address(hook), address(registry),
            address(new NoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 50 ether}(50 ether);

        uint256 seed = 50_000_000 ether;
        deal(token, address(this), seed, true);
        IERC20Minimal(token).approve(address(perp), seed);
        perp.fundPlvToken(seed);

        hook.setDeathThreshold(0, address(0));            // keep the brew "alive" for opens
        vm.warp(block.timestamp + 25 hours);  // past the open warmup
        vm.roll(block.number + 40);           // past the anti-snipe surtax window
        perp.poke();

        vm.deal(trader, 100 ether);
        vm.deal(attacker, 400 ether);
    }

    // =====================================================================
    // A-02 — STALE `lastTick` TWAP POISONING
    //
    //  PerpEngine._writeObs is THROTTLED to one write per OBS_INTERVAL (15s):
    //
    //      uint32 dt = nowTs - lastObsTs;
    //      if (dt < OBS_INTERVAL) return;               // <-- throttle
    //      tickCumulative += int56(lastTick) * int56(uint56(dt));
    //      observations[obsIndex] = Observation(nowTs, tickCumulative);
    //      ...
    //      lastTick = _currentTick();                   // <-- SAMPLED HERE ONLY
    //
    //  `lastTick` is therefore whatever the pool tick was at the LAST WRITE, and
    //  `twapTick()` integrates it across the WHOLE elapsed span:
    //
    //      int56 cumNow = tickCumulative + int56(lastTick) * int56(uint56(nowTs - lastObsTs));
    //
    //  An attacker only has to be the last writer: move the price inside ONE
    //  atomic transaction, let the write happen (it does, unconditionally, via
    //  the hook's afterSwap -> sweepLiquidations -> _pokeFunding -> _writeObs, or
    //  via the fully permissionless `PerpEngine.poke()`), then move the price
    //  straight back. The manipulated tick is now frozen into `lastTick` and is
    //  credited for every second until the next write — so a single, fully
    //  reverted round-trip poisons up to a whole `twapWindow` of the liquidation
    //  mark.
    //
    //  INVARIANT UNDER ATTACK: "liquidations are triggered off a time-weighted
    //  average tick ... so a single-block flash-move can't farm liquidations."
    // =====================================================================

    /// @notice INVARIANT: a healthy position must stay healthy after a price
    ///         round-trip that leaves spot exactly where it started.
    ///         (This test FAILING is the finding.)
    function test_Invariant_A02_HealthyPositionSurvivesAtomicRoundTrip() public {
        if (!active) return;
        console2.log("activeEthDepth:", perp.activeEthDepth());
        console2.log("maxLeverage:", perp.maxLeverage());

        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.1 ether}(2, 0, 0, 0.1 ether);
        assertFalse(perp.isLiquidatable(id), "fresh 2x long is healthy");

        (, int24 tickBefore,,) = pm.getSlot0(_key().toId());

        _poisonMark();

        (, int24 tickAfter,,) = pm.getSlot0(_key().toId());
        console2.log("spot tick before / after round-trip:");
        console2.logInt(tickBefore);
        console2.logInt(tickAfter);
        (int24 mark, bool ok) = perp.twapTick();
        console2.log("poisoned TWAP mark tick (ok):", ok);
        console2.logInt(mark);

        // Spot barely moved (the round trip only paid fees), so the position is
        // economically untouched. The MARK must reflect that.
        assertFalse(perp.isLiquidatable(id), "TWAP mark resisted the atomic round-trip");
    }

    /// @notice Positive PoC (green == the exploit works): the attacker force-
    ///         liquidates a solvent position and walks away with the keeper cut
    ///         + a Liquidatoor badge, while the victim eats the 6.9% penalty.
    /// @notice REGRESSION: the crash-then-restore round-trip can no longer force a
    ///         solvent position into liquidation. `_writeObs` now ALWAYS refreshes
    ///         `lastTick`, so the un-recorded tail is extrapolated at the tick that
    ///         is genuinely in force rather than a frozen, manipulated one.
    ///         (Audit A-02.)
    function test_Fixed_A02_PoisonedMarkCannotLiquidateASolventPosition() public {
        if (!active) return;

        vm.prank(trader);
        uint256 id = perp.openLong{value: 0.1 ether}(2, 0, 0, 0.1 ether);
        assertFalse(perp.isLiquidatable(id), "healthy at open");

        _poisonMark();

        // FIXED: the mark tracks the RESTORED price, so the position is untouched.
        assertFalse(perp.isLiquidatable(id), "FIXED: mark resisted the round-trip");

        // ...and an attacker trying to collect the keeper reward is rejected.
        vm.prank(attacker);
        vm.expectRevert(PerpEngine.Healthy.selector);
        perp.liquidate(id);

        (address t,,,,,,,) = perp.positions(id);
        assertEq(t, trader, "FIXED: the victim's position is still open");
    }

    /// @dev ONE atomic round-trip that leaves spot where it found it, but freezes
    ///      the crashed tick into `lastTick`; then let time pass so the poisoned
    ///      tick is integrated over the whole TWAP window.
    function _poisonMark() internal {
        // >= OBS_INTERVAL since the last observation so the crash swap's write lands.
        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 2);

        // The test contract drives the round-trip (it holds unlockCallback); this is
        // exactly what an attacker's contract does on-chain. tx.origin == attacker so
        // any credit the hook accrues lands on the attacker, not that it matters here.
        // Dump size sets the poison MAGNITUDE (how far the frozen lastTick sits from
        // true spot); on a thin/progressive book a tiny dump suffices, on this deep
        // green-candle book we crash hard to flip a 2x long. The RESTORE buy returns
        // spot to (almost) where it began — the attacker's only real cost is the
        // round-trip fee+slippage, yet the MARK stays poisoned for a full window.
        uint256 dump = 500_000_000 ether;
        deal(token, address(this), dump, true);
        vm.deal(address(this), 100_000_000 ether); // fund the (self-reverting) buy-back leg
        IERC20Minimal(token).approve(address(pm), type(uint256).max);
        _sellFrom(address(this), dump);   // CRASH   -> _writeObs freezes lastTick (post-crash)
        _buyExactOut(dump);               // RESTORE -> buy back EXACTLY what was sold; dt==0, no write

        // Nothing else touches the engine; `lastTick` stays poisoned and accrues.
        vm.warp(block.timestamp + uint256(perp.twapWindow()));
        vm.roll(block.number + 1);
    }

    // =====================================================================
    // A-03 — `forceCloseAllDead` 96-ITERATION CAP
    //
    //      uint256 iters;
    //      while (openCount != 0 && iters < 96) { ... }
    //
    //  and the caller (relaunch) swallows the result:
    //
    //      try hook.forceClosePerps() {} catch {}      (CauldronRegistry._perpHousekeep)
    //      try IPerpForceClose(eng).forceCloseAllDead() {} catch {}   (CauldronHook)
    //
    //  A LEVERAGE-1 long adds ZERO open interest (`borrow = collateral * (leverage-1)`),
    //  so `maxOiBps` / `maxUtilBps` / `PlvInsufficient` never bind — an attacker can
    //  open unbounded dust positions for ~`minCollateral` each. With >96 open, the
    //  relaunch force-close leaves survivors behind. Then:
    //    * `syncGeneration()` reverts `PositionsOpen` FOREVER -> the engine is
    //      stranded on a dead token and the token-side PLV can never be re-armed;
    //    * every survivor's `size`/`principal` is denominated in the OLD token while
    //      `PerpEngine._key()` now resolves to the NEW generation's pool, so any
    //      later `close`/`liquidate` settles an old-token position against the NEW
    //      pool and the new-token inventory.
    // =====================================================================

    /// @notice INVARIANT: the relaunch force-close must leave NOTHING open.
    ///         (This test FAILING is the finding.)
    function test_Invariant_A03_ForceCloseAllDeadClearsEveryPosition() public {
        if (!active) return;

        // FILL THE BOOK COMPLETELY — the worst case the force-close must survive.
        uint256 cap = perp.MAX_OPEN_POSITIONS();
        _spamDustLongs(cap);
        assertEq(perp.openCount(), cap, "book filled to the cap");

        hook.setDeathThreshold(type(uint256).max, address(0)); // brew now reads DEAD
        assertTrue(hook.isDead(registry.generationPoolId(1)), "dead");

        // FIXED: one call drains the whole book, because MAX_OPEN_POSITIONS is
        // strictly below the force-close bound.
        perp.forceCloseAllDead();
        assertEq(perp.openCount(), 0, "force-close cleared every dead position");
    }

    /// @notice REGRESSION: the book can never grow past what one force-close
    ///         clears, so the leftovers that used to strand the engine forever
    ///         cannot exist. (Audit A-03.)
    function test_Fixed_A03_BookCannotExceedForceCloseBound() public {
        if (!active) return;

        uint256 cap = perp.MAX_OPEN_POSITIONS();
        _spamDustLongs(cap);
        assertEq(perp.openCount(), cap, "book filled to the cap");

        // The very next open is refused — this is the structural guarantee.
        address oneMore = address(0xD05799);
        vm.deal(oneMore, 1 ether);
        vm.prank(oneMore, oneMore);
        vm.expectRevert(PerpEngine.OiCapped.selector);
        perp.openLong{value: 0.01 ether}(1, 0, 0, 0.01 ether);
    }

    /// @notice REGRESSION: a maximally-spammed book no longer strands the engine
    ///         across a relaunch. Dust longs used to survive the 96-iteration
    ///         force-close, leaving `openCount != 0` so `syncGeneration()` reverted
    ///         `PositionsOpen` FOREVER — and those leftovers could never be closed
    ///         afterwards either, since `_settle` would swap their old-generation
    ///         sizes against the NEW pool. (Audit A-03.)
    function test_Fixed_A03_DustSpamSurvivesRelaunch() public {
        if (!active) return;

        _spamDustLongs(perp.MAX_OPEN_POSITIONS());

        hook.setDeathThreshold(type(uint256).max, address(0));
        vm.warp(vm.getBlockTimestamp() + registry.minLifetime() + 1);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)

        // The registry's relaunch drives the same best-effort force-close.
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "relaunched");

        // FIXED: the book was fully drained on the way through.
        assertEq(perp.openCount(), 0, "no positions survived the relaunch");

        // ...so the engine re-arms for the new generation, as designed.
        assertEq(perp.syncedGeneration(), 2, "engine re-armed on generation 2");
        assertEq(perp.syncedToken(), registry.currentToken(), "token side follows the live gen");
    }

    // =====================================================================
    // A-04 — FUNDING IS NOT CONSERVED
    //
    //  PerpEngine._settle:
    //      if (fd > 0) {                       // crowded side PAYS
    //          uint256 pay = uint256(fd);
    //          if (pay > residual) pay = residual;   // <-- capped by its OWN residual
    //          plv += pay; residual -= pay;
    //      } else if (fd < 0) {                // underweight side RECEIVES
    //          uint256 credit = uint256(-fd);
    //          if (credit > plv) credit = plv;       // <-- only capped by the WHOLE vault
    //          plv -= credit; residual += credit;
    //      }
    //
    //  A paying position whose residual is short (any position closing at a loss,
    //  and EVERY liquidated long — `repay = proceeds` leaves `residual == 0`)
    //  pays LESS than it owes, while receivers still draw in full. The difference
    //  comes straight out of LP principal.
    // =====================================================================

    /// @notice INVARIANT: with no bad debt, a full open->close round-trip must
    ///         never leave the ETH PLV below where it started (fees only ever add).
    function testFuzz_Invariant_A04_PlvNeverShrinksOnSolventRoundTrip(uint96 rawCollateral, uint8 rawLev)
        public
    {
        if (!active) return;
        // Notional (collateral*leverage) must stay under maxNotionalBps (5%) of the
        // ~20 ETH fork depth, i.e. <= ~1 ETH — keep collateral small.
        uint256 collateral = bound(uint256(rawCollateral), 0.01 ether, 0.3 ether);
        uint8 lev = uint8(bound(uint256(rawLev), 1, perp.maxLeverage()));

        uint256 plv0 = perp.plv();
        uint256 ins0 = perp.insuranceEth();

        vm.prank(trader);
        uint256 id = perp.openLong{value: collateral}(lev, 0, 0, collateral);

        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 10);
        perp.poke();

        vm.prank(trader);
        perp.close(id, 0);

        // The round-trip cost the trader fees + slippage; the vault must be >= flat.
        assertGe(perp.plv() + perp.insuranceEth(), plv0 + ins0, "PLV principal never decreased");
    }

    // =====================================================================
    // helpers
    // =====================================================================

    function _spamDustLongs(uint256 n) internal {
        uint256 stake = 0.004 ether;
        for (uint256 i; i < n; i++) {
            address bot = address(uint160(0xD05700 + i));
            vm.deal(bot, stake);
            vm.prank(bot, bot);
            perp.openLong{value: stake}(1, 0, 0, stake); // leverage 1 => borrow 0 => NO OI
        }
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    function _sellFrom(address who, uint256 tokenIn) internal returns (uint256 ethOut) {
        bytes memory r = pm.unlock(abi.encode(uint8(1), tokenIn, who));
        ethOut = abi.decode(r, (uint256));
    }

    function _buyFrom(address who, uint256 ethIn) internal returns (uint256 got) {
        bytes memory r = pm.unlock(abi.encode(uint8(0), ethIn, who));
        got = abi.decode(r, (uint256));
    }

    function _buyExactOut(uint256 tokenOut) internal returns (uint256 spent) {
        bytes memory r = pm.unlock(abi.encode(uint8(2), tokenOut, address(this)));
        spent = abi.decode(r, (uint256));
    }

    /// @dev Raw (untagged) swaps driven from THIS contract so the hook takes its
    ///      normal fee — the round-trip is a real, fully-paid market operation.
    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (uint8 dir, uint256 amt, address who) = abi.decode(raw, (uint8, uint256, address));
        PoolKey memory key = _key();
        if (dir == 0 || dir == 2) {
            // dir 0 = exact-input ETH->token ; dir 2 = exact-output (buy EXACTLY `amt` token)
            int256 spec = dir == 2 ? int256(amt) : -int256(amt);
            BalanceDelta d = pm.swap(
                key, SwapParams({zeroForOne: true, amountSpecified: spec, sqrtPriceLimitX96: MIN_LIMIT}), ""
            );
            uint256 spent = uint256(uint128(-d.amount0()));
            uint256 got = uint256(uint128(d.amount1()));
            pm.settle{value: spent}();
            pm.take(key.currency1, dir == 2 ? address(this) : who, got);
            return abi.encode(dir == 2 ? spent : got);
        } else {
            BalanceDelta d = pm.swap(
                key, SwapParams({zeroForOne: false, amountSpecified: -int256(amt), sqrtPriceLimitX96: MAX_LIMIT}), ""
            );
            uint256 spent = uint256(uint128(-d.amount1()));
            uint256 got = uint256(uint128(d.amount0()));
            pm.sync(key.currency1);
            vm.prank(who);
            IERC20Minimal(Currency.unwrap(key.currency1)).transfer(address(pm), spent);
            pm.settle();
            pm.take(key.currency0, address(this), got);
            return abi.encode(got);
        }
    }

    receive() external payable {}
}

contract NoFrens {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract PerpGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Shadow Wraith", symbol: "WRAITH", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://wraith/", renderer: address(0), website: "w.xyz",
            socials: "x.com/w", quote: address(0), nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
