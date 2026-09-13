// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../cauldron/CauldronSeeder.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../cauldron/ICauldron.sol";

/**
 * @notice Fork integration test for the PROGRESSIVE launch seed wired into the
 *         registry summon → stream → teardown → relaunch lifecycle, against LIVE
 *         Uniswap v4. Complements the isolated CauldronSeeder mechanics test — this
 *         drives the seeder through the REAL registry glue (createAndSeedProgressive
 *         + the _removeLiquidity teardown), which is where the summon-side funding
 *         path + the death-time recovery are exercised end to end.
 *
 *  Run:
 *    export FORK_RPC=... POOL_MANAGER=0x... POSITION_MANAGER=0x...
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract ProgressiveSeedForkTest -vvv
 *  Without FORK_RPC the tests no-op (suite still compiles + passes in CI).
 */
contract ProgressiveSeedForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    CauldronHook hook;
    CauldronRegistry registry;
    CauldronSeeder seeder;
    IPoolManager pm;
    address posm;
    bool active;

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint64 constant WINDOW = 600; // 10-min launch window

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
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

        registry = new CauldronRegistry(poolManager, posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        // Wire the progressive seeder + a launch window → summon goes progressive.
        seeder = new CauldronSeeder(address(registry), posm, poolManager);
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(WINDOW);

        vm.deal(address(this), 100 ether);
    }

    // ---------------------------------------------------------------------------
    // Full lifecycle: summon(FULL-RANGE base) → trade → teardown → relaunch
    //
    //  Commit 40b9608 ("fix(pool): full range always") raised PoolOps.SEED_BASE_WAD
    //  from 0.15e18 to 1e18 (cauldron/PoolOps.sol:168), so the WHOLE of ledger A is
    //  laid as a two-sided full-range base in the ignition tx and the streamed
    //  campaign is deliberately never started (PoolOps.sol:404-408: "NOTHING LEFT TO
    //  STREAM once the base is the whole of ledger A ... the campaign is simply not
    //  started"). This test used to drive that campaign; it now proves the launch
    //  state that replaced it, and the teardown/relaunch half is untouched.
    // ---------------------------------------------------------------------------
    function test_Summon_FullRange_Teardown_Relaunch_OnFork() public {

        vm.skip(!active);

        SeedGov gov = new SeedGov();
        registry.setGovernor(address(gov));

        // --- SUMMON (seeder + window armed, but the base is 100% of ledger A) ---
        (address token1,) = registry.summon{value: 1 ether}();
        uint256 supply = registry.TOTAL_SUPPLY();

        // FULL-RANGE markers. The registry owns the whole base position (laid and
        // then bought through in the ignition tx by the green candle); the seeder
        // owns nothing at all, because there is no remainder to hand it.
        assertGt(registry.generationPositionId(1), 0, "registry owns the full-range base position");
        assertGt(registry.generationReservePositionId(1), 0, "reserve (ledger B) placed at summon");
        assertFalse(seeder.seeding(), "no campaign: nothing left to stream (40b9608)");
        assertEq(seeder.gen(), 0, "campaign never armed");
        assertEq(seeder.rangeCount(), 0, "no streamed bands exist");
        assertEq(seeder.deployedWad(), 0, "seeder received no tranche");
        // Ledger separation is unchanged: the 69x reserve backs redemption from
        // block 0, and it is out of range, so it is not the spot depth below.
        assertGt(pm.getLiquidity(registry.generationPoolId(1)), 0, "spot depth from block 0");

        // --- THE STREAM IS INERT, AND THE BOOK DOES NOT NEED IT ---
        vm.warp(vm.getBlockTimestamp() + WINDOW / 2);
        seeder.poke();
        assertEq(seeder.deployedWad(), 0, "poke() is inert with no campaign");

        // Real buys fill against the full-range base, and the book stays CONTINUOUS:
        // a second identical buy is not starved by an exhausted band (the r42 failure
        // 40b9608 removes). Constant product puts got2/got1 near 0.83 here; under the
        // old single-sided 15% band a buy past the last band returned ~nothing.
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        uint256 bought = _buy(0.1 ether);
        assertGt(bought, 0, "buy fills against the full-range base");
        uint256 bought2 = _buy(0.1 ether);
        assertGt(bought2, bought / 2, "book is continuous: no teleport past a last band");

        // Time still passes to the end of the launch window; nothing changes.
        vm.warp(vm.getBlockTimestamp() + WINDOW);
        seeder.poke();
        assertEq(seeder.deployedWad(), 0, "still nothing to stream at window end");
        assertGt(pm.getLiquidity(registry.generationPoolId(1)), 0, "spot depth persists through the window");

        // --- TEARDOWN + RELAUNCH ---
        // Switch the NEXT generation to the atomic path so we can assert the gen-1
        // seeder ends fully idle (a clean teardown), then rebirth.
        registry.setSeedWindow(0);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen1 dead");

        (address token2,) = registry.relaunch();

        // The seeder was torn down at relaunch: campaign ended + NOTHING stranded.
        assertFalse(seeder.seeding(), "seeder torn down at relaunch");
        assertEq(CauldronToken(token1).balanceOf(address(seeder)), 0, "no gen1 tokens stranded in seeder");
        assertEq(address(seeder).balance, 0, "no ETH stranded in seeder");

        // gen-2 born on the atomic path (single active position + bought reserve).
        assertEq(registry.currentGeneration(), 2, "gen 2 born");
        assertEq(CauldronToken(token2).totalSupply(), supply, "supply conserved across the rebirth");
        assertGt(registry.generationPositionId(2), 0, "gen2 atomic active position");
        assertGt(registry.generationReservePositionId(2), 0, "gen2 reserve placed");

        // Migration still 1:1 from the recovered/reseeded liquidity.
        uint256 bal1 = CauldronToken(token1).balanceOf(address(this));
        if (bal1 > 0) {
            CauldronToken(token1).approve(address(registry), bal1);
            uint256 got = registry.claimByBurn(1, bal1);
            assertApproxEqAbs(got, bal1, bal1 / 1e6 + 1, "migrated 1:1 post-rebirth");
        }
    }

    // ---------------------------------------------------------------------------
    // MID-LIFE DEATH → FULL RECOVERY (the design's explicit teardown case). This
    // used to kill a campaign MID-STREAM; since 40b9608 (PoolOps.sol:168,
    // SEED_BASE_WAD 0.15e18 -> 1e18) there is no campaign to kill — the whole of
    // ledger A is a registry-owned full-range base. The recovery property is the
    // same and is asserted unchanged: everything is unwound at relaunch, nothing
    // stranded, supply conserved.
    // ---------------------------------------------------------------------------
    function test_NoCampaign_Death_FullRecovery_OnFork() public {

        vm.skip(!active);

        SeedGov gov = new SeedGov();
        registry.setGovernor(address(gov));

        (address token1,) = registry.summon{value: 1 ether}();

        // There is no partial fill to reach: the seeder never took a tranche.
        vm.warp(vm.getBlockTimestamp() + WINDOW / 4);
        seeder.poke();
        assertEq(seeder.deployedWad(), 0, "nothing streamed (base is 100% of ledger A)");
        assertFalse(seeder.seeding(), "no campaign is live");
        assertEq(seeder.rangeCount(), 0, "no mini-positions exist");
        // ...and the depth the bands used to provide is in the pool already.
        assertGt(pm.getLiquidity(registry.generationPoolId(1)), 0, "full-range base is the book");

        // Some organic trading against the full-range book → real circulating supply
        // to migrate (so the newborn's reserve reseed is non-degenerate) and mixed
        // ETH/token in the position the teardown must recover.
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        uint256 circulating = _buy(0.15 ether);
        assertGt(circulating, 0, "acquired real circulating supply");

        // Kill it mid-life and rebirth on the atomic path.
        registry.setSeedWindow(0);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)

        uint256 supply = registry.TOTAL_SUPPLY();
        (address token2,) = registry.relaunch();

        // FULL RECOVERY: nothing stranded, supply conserved — the newborn seeded
        // from the recovered ledger-A + reserve.
        assertFalse(seeder.seeding(), "no campaign left armed after relaunch");
        assertEq(CauldronToken(token1).balanceOf(address(seeder)), 0, "no tokens stranded");
        assertEq(address(seeder).balance, 0, "no ETH stranded");
        assertEq(registry.currentGeneration(), 2, "gen2 born from a mid-life death");
        assertEq(CauldronToken(token2).totalSupply(), supply, "supply conserved");
        assertGt(registry.generationPositionId(2), 0, "gen2 seeded");
    }

    // ---------------------------------------------------------------------------
    // Opt-out: with the seeder set but window 0, summon uses the ATOMIC green-candle
    // path unchanged (feature is strictly opt-in).
    // ---------------------------------------------------------------------------
    function test_WindowZero_IsAtomicGreenCandle_OnFork() public {
        
        vm.skip(!active);

        registry.setSeedWindow(0); // seeder set, but window 0 → atomic
        registry.summon{value: 1 ether}();

        assertGt(registry.generationPositionId(1), 0, "atomic: single active position");
        assertGt(registry.generationReservePositionId(1), 0, "atomic reserve bought");
        assertFalse(seeder.seeding(), "seeder never armed on the atomic path");
        assertGt(hook.getVolume24h(registry.generationPoolId(1)), 0, "green candle fired");
    }

    // ---------------------------------------------------------------------------
    // IN-SWAP STREAMING IS WIRED BUT HAS NOTHING TO DO. The hook still points at
    // the seeder and afterSwap still calls pokeInSwap, but since 40b9608
    // (PoolOps.sol:168, SEED_BASE_WAD -> 1e18) no campaign is armed, so the nudge
    // is a no-op — and the depth it used to add is in the pool from block 0. The
    // property that replaced "the swap streamed the book deeper" is "the swap
    // did not need to: the book was already there and stays continuous".
    // ---------------------------------------------------------------------------
    function test_InSwap_NoStreamNeeded_FullRangeFromSummon_OnFork() public {

        vm.skip(!active);
        registry.setGovernor(address(new SeedGov()));
        registry.summon{value: 1 ether}();
        PoolId pid = registry.generationPoolId(1);
        assertEq(seeder.deployedWad(), 0, "nothing streamed at t0");
        assertFalse(seeder.seeding(), "no campaign armed (40b9608)");
        assertEq(hook.seeder(), address(seeder), "registry propagated the seeder to the hook");
        uint256 liq0 = pm.getLiquidity(pid);
        assertGt(liq0, 0, "full-range base is live at t0");

        // Advance the schedule, then just TRADE — no poke() call anywhere.
        vm.warp(vm.getBlockTimestamp() + WINDOW / 2);
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        uint256 got = _buy(0.05 ether);

        assertGt(got, 0, "the swap filled against the base, not against a streamed band");
        assertEq(seeder.deployedWad(), 0, "the in-swap nudge is inert: there is nothing to stream");
        // The liquidity the swap traded against is the SAME position it started
        // with — full range, so it is still in range after the price moved up.
        assertEq(pm.getLiquidity(pid), liq0, "one full-range position, unchanged and still in range");
    }

    // ---------------------------------------------------------------------------
    // TWO-SIDED BASE (automatic, at summon, no callable, no removal): the seeder
    // lays a small full-range two-sided BASE straddling spot at t0 alongside the
    // single-sided streaming bands → the pool ALWAYS has liquidity at spot (perps
    // get depth) + is continuous (no teleport). Nothing is ever removed mid-life.
    // ---------------------------------------------------------------------------
    function test_Base_GivesSpotDepth_FromSummon_OnFork() public {
        
        vm.skip(!active);
        registry.setGovernor(address(new SeedGov()));
        registry.summon{value: 1 ether}();
        PoolId pid = registry.generationPoolId(1);
        address token1 = registry.generationToken(1);

        // Spot depth exists IMMEDIATELY at summon (the base straddles spot) — no
        // finalize, no callable, no removal.
        assertGt(pm.getLiquidity(pid), 0, "base gives spot-straddling depth from block 0");

        // Streaming still advances the single-sided anti-snipe bands over the window;
        // spot depth stays non-zero throughout.
        vm.warp(block.timestamp + WINDOW + 1);
        seeder.poke();
        assertTrue(seeder.isComplete(), "fully streamed");
        assertGt(pm.getLiquidity(pid), 0, "spot depth persists after full stream");

        // A real buy fills against the continuous book (leaves circulating supply).
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        _buy(0.3 ether);

        // Teardown at relaunch recovers the base + bands (nothing stranded) — the
        // ONLY time liquidity is removed is the normal death/rebirth.
        registry.setSeedWindow(0);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "relaunched");
        assertEq(CauldronToken(token1).balanceOf(address(seeder)), 0, "base+bands torn down, nothing stranded");
    }

    // Toggle: clearing the hook's seeder pointer disables the in-swap nudge, but the
    // permissionless poke() fallback still streams (the "can be turned off" path).
    function test_InSwap_ToggleOff_PermissionlessStillWorks_OnFork() public {
        
        vm.skip(!active);
        registry.setGovernor(address(new SeedGov()));
        registry.summon{value: 1 ether}();

        hook.setSeeder(address(0)); // disable in-swap streaming only
        assertEq(hook.seeder(), address(0), "in-swap nudge off");

        vm.warp(block.timestamp + WINDOW / 2);
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        _buy(0.05 ether);
        assertEq(seeder.deployedWad(), 0.1e18, "no in-swap streaming when the hook pointer is cleared");

        // permissionless fallback still advances it
        seeder.poke();
        assertGt(seeder.deployedWad(), 0.1e18, "permissionless poke() fallback still streams");
    }

    // --- helpers -------------------------------------------------------------
    function _buy(uint256 ethIn) internal returns (uint256 got) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        bytes memory res = pm.unlock(abi.encode(key, ethIn));
        got = abi.decode(res, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        (PoolKey memory key, uint256 ethIn) = abi.decode(data, (PoolKey, uint256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            abi.encode(address(this))
        );
        uint256 ethOwed = uint256(uint128(-d.amount0()));
        uint256 got = uint256(uint128(d.amount1()));
        pm.settle{value: ethOwed}();
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }

    receive() external payable {}
}

/// Minimal governor: always has a winning proposal so relaunch can proceed.
contract SeedGov is ICauldronGovernor {
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
