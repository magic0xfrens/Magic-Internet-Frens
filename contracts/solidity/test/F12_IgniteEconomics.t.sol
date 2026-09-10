// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../cauldron/CauldronSeeder.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-12 — IGNITION ECONOMICS: THE CANDLE, THE ALLOCATION, THE TRANCHES
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  WHAT WENT WRONG ON ROUND 35. The progressive path placed the redemption
 *  reserve silently and handed the whole active tranche to the seeder, so the
 *  launch produced NO trade. The seeder only streams on `poke`/`pokeInSwap`, and
 *  `pokeInSwap` fires from the hook's afterSwap — so "no buyer" meant "no poke"
 *  meant "no stream". Measured live: the 900s window closed with `placedWad`
 *  still equal to `seedFloorWad` (no poke had EVER run) and 76.5% of ledger A
 *  still sitting in the seeder.
 *
 *  WHAT THIS SUITE PINS DOWN.
 *    1. Ignition emits a REAL swap, so the chart has a trade in block 0 and the
 *       stream is not waiting on a stranger to arrive.
 *    2. The genesis allocation is worth a bounded fraction of what an OG paid for
 *       the NFT — the launch price is not a free variable.
 *    3. Prime-buy tranches ride the SAME schedule as the liquidity, so each one
 *       meets a deeper book than the last, and the budget closes out exactly.
 *
 *  THE ALLOCATION IDENTITY (why the 15-20% target is a supply choice, not a
 *  price choice). Every wei of presale ETH becomes LP, so
 *
 *      allocationValue   genesisBonusBps       TOTAL_SUPPLY
 *      ─────────────── = ─────────────── ×  ────────────────────
 *         nftSpend            10_000        GEN1_ACTIVE_TOKENS
 *
 *  With an 80% active tranche the right-hand factor is 1.25, so `bonusBps = 2000`
 *  (round 35) pays 25% — ABOVE the intended ceiling. The dial is the bonus, and
 *  it is a setter, not a constant: `bonusBps = target × 8000`.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F12_IgniteEconomicsForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    CauldronHook hook;
    CauldronRegistry registry;
    CauldronSeeder seeder;
    IPoolManager pm;
    address posm;
    bool active;

    uint64 constant WINDOW = 600;
    /// @dev The shipped target: 1400 bps -> 17.5% of NFT spend (mid of 15-20%).
    uint256 constant BONUS_BPS = 1400;
    /// @dev Round-35 presale shape: 1111 MiFrens at 0.0008 ETH = 0.8888 ETH.
    uint256 constant FRENS = 1111;
    uint256 constant NFT_PRICE = 0.0008 ether;
    uint256 constant RAISE = FRENS * NFT_PRICE;
    address constant TREASURY = address(0x7EEA);

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

        seeder = new CauldronSeeder(address(registry), posm, poolManager);
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(WINDOW);
        // The seeder buys on the treasury's behalf; the hook waives the launch
        // surtax only when BOTH flags are set (CauldronHook._isExemptPlayer).
        hook.setOpener(address(seeder), true);
        hook.setTaxExempt(address(seeder), true);

        // Genesis bonus sized to the 17.5% target.
        registry.setGenesisBonus(address(this), BONUS_BPS, FRENS);

        vm.deal(address(this), 100 ether);
    }

    /// @dev Spot as ETH-per-token, WAD.
    ///
    ///  `sqrtPriceX96` encodes token1-per-token0, and the brew token is deliberately
    ///  deployed to sort ABOVE the quote (so quote == currency0). The raw square is
    ///  therefore GNOME-per-ETH — the RECIPROCAL of the number every economic
    ///  statement here is about — so it is inverted once, at the boundary, rather
    ///  than in each assertion.
    ///
    ///  Squaring is done in TWO 512-bit steps: `sqrtP` reaches 2^160, so a single
    ///  `sqrtP * sqrtP` overflows uint256 before any division can bring it back.
    function _price() internal view returns (uint256 ethPerTokenWad) {
        (uint160 sp,,,) = pm.getSlot0(registry.generationPoolId(1));
        uint256 p = uint256(sp);
        uint256 half = FullMath.mulDiv(p, p, 1 << 96); // sqrtP^2 / 2^96
        uint256 tokPerEth = FullMath.mulDiv(half, 1e18, 1 << 96);
        return FullMath.mulDiv(1e18, 1e18, tokPerEth);
    }

    // ── 1. IGNITION TRADES ──────────────────────────────────────────────────

    /// @notice The launch must produce a real swap in its own transaction. This is
    ///         the property whose absence stalled round 35: with no trade there is
    ///         no `pokeInSwap`, and with no poke the stream never starts.
    function test_F12_IgnitionEmitsARealSwap_OnFork() public {
        vm.skip(!active);

        vm.recordLogs();
        registry.summon{value: RAISE}();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // v4 PoolManager Swap topic.
        bytes32 SWAP = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");
        uint256 swaps;
        for (uint256 i; i < logs.length; i++) if (logs[i].topics[0] == SWAP) swaps++;

        assertGt(swaps, 0, "ignition must print at least one real swap (the green candle)");
        assertGt(registry.generationPositionId(1), 0, "base position placed by the registry");
        assertGt(registry.generationReservePositionId(1), 0, "reserve re-parked out of range");
        assertTrue(seeder.seeding(), "stream armed for the remainder");
    }

    /// @notice The candle must not disturb where the pool ENDS UP. Whatever the
    ///         base fraction, the post-buy price is the launch price — the discount
    ///         is an opening, not a repricing.
    function test_F12_PostCandlePriceIsTheLaunchPrice_OnFork() public {
        vm.skip(!active);
        registry.summon{value: RAISE}();

        uint256 supply = registry.TOTAL_SUPPLY();
        uint256 activeTok = registry.GEN1_ACTIVE_TOKENS();
        // Intended launch price = ledger-A ETH per active token.
        uint256 want = FullMath.mulDiv(RAISE, 1e18, activeTok);
        uint256 got = _price();

        // 1% tolerance: the settle buffer and tick rounding both nudge the last wei.
        assertApproxEqRel(got, want, 0.01e18, "post-candle spot == intended launch price");
        assertGt(supply, activeTok, "reserve exists outside the active tranche");
    }

    // ── 2. THE ALLOCATION IS WORTH WHAT WE SAID ─────────────────────────────

    /// @notice THE REQUIREMENT, asserted directly: an OG's genesis allocation is
    ///         worth 15-20% of what they paid for the MiFren.
    function test_F12_GenesisAllocationIsWithinTarget_OnFork() public {
        vm.skip(!active);
        registry.summon{value: RAISE}();

        uint256 perFren = registry.floorPerFren();
        assertGt(perFren, 0, "genesis bonus sized");

        uint256 valuePerFren = FullMath.mulDiv(perFren, _price(), 1e18);
        uint256 bps = FullMath.mulDiv(valuePerFren, 10_000, NFT_PRICE);

        emit log_named_uint("allocation per fren (tokens)", perFren / 1e18);
        emit log_named_uint("allocation value (wei)      ", valuePerFren);
        emit log_named_uint("as bps of the NFT price     ", bps);

        assertGe(bps, 1_500, "allocation must be worth at least 15% of the NFT price");
        assertLe(bps, 2_000, "allocation must be worth at most 20% of the NFT price");
    }

    /// @notice And the identity behind it, so a future supply change cannot quietly
    ///         move the ratio without this failing.
    function test_F12_AllocationIdentityHolds_OnFork() public {
        vm.skip(!active);
        uint256 supply = registry.TOTAL_SUPPLY();
        uint256 activeTok = registry.GEN1_ACTIVE_TOKENS();
        // ratio_bps = bonusBps * TOTAL / ACTIVE
        uint256 predicted = FullMath.mulDiv(BONUS_BPS, supply, activeTok);
        assertGe(predicted, 1_500, "identity: >=15%");
        assertLe(predicted, 2_000, "identity: <=20%");
    }

    // ── 3. PRIME TRANCHES ───────────────────────────────────────────────────

    /// @notice The prime budget is spent ACROSS the window, never in one lump, and
    ///         it closes out exactly. A lump sum at t0 would meet the thinnest book
    ///         of the entire launch — the single worst moment to spend it.
    function test_F12_PrimeBuyIsTranchedAndCompletes_OnFork() public {
        vm.skip(!active);

        uint256 budget = 0.2 ether;
        seeder.fundPrime{value: budget}(TREASURY);
        assertEq(seeder.primeBudget(), budget, "budget committed");

        registry.summon{value: RAISE}();
        address token = registry.currentToken();

        // At t0 only the seed floor is placed, so at most a floor-sized slice is due.
        uint256 dueAtStart = seeder.primePending();
        assertLt(dueAtStart, budget, "t0 must not authorise the whole budget");

        // Stream to completion in steps, poking as a keeper would.
        for (uint256 i; i < 6; i++) {
            vm.warp(block.timestamp + WINDOW / 5);
            seeder.poke();
        }

        assertEq(seeder.primePending(), 0, "nothing left pending");
        assertEq(seeder.primeSpent(), budget, "budget spent in full by completion");
        assertGt(IERC20(token).balanceOf(TREASURY), 0, "treasury received the bought token");
        assertTrue(seeder.complete(), "stream complete");
    }

    /// @notice Each tranche meets a deeper book than the one before, so the marginal
    ///         price impact of the prime buy FALLS as the launch proceeds. This is
    ///         the whole reason for tranching.
    function test_F12_LaterTranchesMoveThePriceLess_OnFork() public {
        vm.skip(!active);

        seeder.fundPrime{value: 0.2 ether}(TREASURY);
        registry.summon{value: RAISE}();

        vm.warp(block.timestamp + WINDOW / 5);
        uint256 a0 = _price();
        seeder.poke();
        uint256 a1 = _price();
        uint256 firstMove = FullMath.mulDiv(a1 - a0, 1e18, a0);

        // Run most of the way out, then measure a late tranche.
        vm.warp(block.timestamp + WINDOW / 2);
        seeder.poke();
        vm.warp(block.timestamp + WINDOW / 5);
        uint256 b0 = _price();
        seeder.poke();
        uint256 b1 = _price();
        uint256 lateMove = b1 > b0 ? FullMath.mulDiv(b1 - b0, 1e18, b0) : 0;

        emit log_named_uint("first tranche move (wad)", firstMove);
        emit log_named_uint("late  tranche move (wad)", lateMove);
        assertLt(lateMove, firstMove, "a later tranche must move price less than an early one");
    }

    /// @notice Unspent budget is never stranded: teardown returns it and clears the
    ///         accounting, so the next campaign cannot authorise a swap it can't pay.
    function test_F12_UnspentPrimeIsRecovered_OnFork() public {
        vm.skip(!active);

        seeder.fundPrime{value: 0.2 ether}(TREASURY);
        registry.summon{value: RAISE}();

        // Stop early — most of the budget is still uncommitted.
        vm.warp(block.timestamp + WINDOW / 5);
        seeder.poke();
        assertLt(seeder.primeSpent(), 0.2 ether, "budget only partly spent");

        uint256 regBefore = address(registry).balance;
        vm.prank(address(registry));
        seeder.withdrawAll(address(registry));

        assertGe(address(registry).balance, regBefore, "leftover returned to the registry");
        assertEq(seeder.primeBudget(), 0, "ledger C cleared");
        assertEq(seeder.primeSpent(), 0, "ledger C cleared");
    }

    /// @notice Only the registry's owner may aim the prime buy — `primeTo` decides
    ///         where bought tokens land.
    function test_F12_PrimeFundingIsGated_OnFork() public {
        vm.skip(!active);
        vm.deal(address(0xBAD), 1 ether);
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronSeeder.OnlyRegistry.selector);
        seeder.fundPrime{value: 0.1 ether}(address(0xBAD));
    }
}
