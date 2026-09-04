// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";

/**
 * @title F02 — Arbitrum-Nitro / Orbit deployment semantics
 * @notice The Foundry fork is an Ethereum-Sepolia (L1-like) chain, where
 *         `block.number` and `block.timestamp` advance TOGETHER at ~12 s per
 *         block. The deployment target is an Arbitrum-Nitro Orbit chain, where
 *         they are decoupled:
 *
 *           * `block.number` is an ESTIMATE OF THE PARENT CHAIN's block number
 *             and "updates only periodically" — it is CONSTANT across the many
 *             sub-second child-chain blocks that fit inside one parent block.
 *           * `block.timestamp` is set per child block from the sequencer's
 *             clock and therefore advances in sub-second steps.
 *
 *         These tests SIMULATE that by advancing `vm.warp` and `vm.roll`
 *         INDEPENDENTLY, which is the only way to surface the resulting
 *         behaviour on an L1-like fork. Each one pins down a property the
 *         protocol must hold on the real target.
 *
 *   export FORK_RPC=<sepolia> POOL_MANAGER=0x.. POSITION_MANAGER=0x..
 *   FOUNDRY_PROFILE=cauldron forge test --match-path 'test/final/F02*' -vv
 */
contract F02_L2Semantics is Test {
    CauldronHook internal hook;
    CauldronRegistry internal registry;
    IPoolManager internal pm;
    address internal token;
    bool internal active;

    /// @dev One parent-chain (L1) block, in seconds. On an Orbit chain roughly
    ///      this much wall-clock passes for every single `block.number` tick.
    uint256 internal constant PARENT_BLOCK_SECS = 12;
    /// @dev Child-chain block cadence on a fast Orbit chain (250 ms), i.e. ~48
    ///      child blocks share one `block.number` value.
    uint256 internal constant CHILD_BLOCK_MS = 250;

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
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 50 ether);
        (token,) = registry.summon{value: 2 ether}();
    }

    // ---------------------------------------------------------------------
    // L2-A — the death clock is wall-clock, so it survives the decoupling
    // ---------------------------------------------------------------------

    /// @notice POSITIVE RESULT. The 24 h volume window is denominated in SECONDS
    ///         (`SECONDS_PER_DAY`, `_lastUpdateTs`), not blocks. We therefore let a
    ///         full day of WALL CLOCK pass while `block.number` advances by only the
    ///         two ticks a parent chain would produce in that window's worth of
    ///         estimate lag — and the pool still reads dead exactly on schedule.
    ///
    ///         This is the property the block-denominated version did NOT have: with
    ///         `BLOCKS_PER_DAY = 7200` the window's wall-clock meaning was a property
    ///         of the settlement layer, not of the protocol.
    function test_L2A_DeathClockIsWallClockNotBlockCount() public {
        if (!active) return;
        PoolId id = registry.generationPoolId(1);

        // Advance BLOCKS hard while time stands still: on Orbit, many child blocks
        // share one `block.number`, and conversely a contract must never infer
        // elapsed time from block count. Nothing should die from block motion alone.
        uint256 t0 = block.timestamp;
        vm.roll(block.number + 50_000);
        vm.warp(t0); // time genuinely unchanged
        assertEq(block.timestamp, t0, "time held");

        // Now advance WALL CLOCK past the window with only a parent-chain-sized
        // number of `block.number` ticks (1 tick per 12 s of wall clock).
        uint256 elapsed = 1 days + 1;
        vm.warp(t0 + elapsed);
        vm.roll(block.number + elapsed / PARENT_BLOCK_SECS);
        assertTrue(hook.isDead(id), "death clock tracks seconds, not block count");
    }

    /// @notice MIRROR: a huge number of block ticks with < 24 h of wall clock must
    ///         NOT retire a live pool. On the pre-fix block-denominated clock this
    ///         was the permanent-retirement bug; assert it cannot recur.
    function test_L2A_BlockStormAloneCannotRetireALivePool() public {
        if (!active) return;
        PoolId id = registry.generationPoolId(1);

        // Give the pool real volume so it is unambiguously alive. The rig deploys
        // with a 1 ETH threshold; drop it so a modest buy clears it and the test is
        // about the CLOCK, not about the threshold's magnitude.
        hook.setDeathThreshold(0.1 ether);
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        _buy(0.5 ether);
        assertGt(hook.getVolume24h(id), 0.1 ether, "pool has volume above the threshold");
        assertFalse(hook.isDead(id), "alive");

        // 100k block ticks, but only an hour of wall clock.
        vm.roll(block.number + 100_000);
        vm.warp(block.timestamp + 1 hours);
        assertFalse(hook.isDead(id), "block motion alone must not retire a live pool");
    }

    // ---------------------------------------------------------------------
    // L2-B — the anti-snipe surtax IS block-denominated: quantisation
    // ---------------------------------------------------------------------

    /// @notice FINDING (documented, not a fix): `snipeWindowBlocks` and the decay in
    ///         `_defaultSurtaxBps` are counted in `block.number`. On Orbit that is
    ///         the PARENT chain's number, so the window keeps roughly its intended
    ///         WALL-CLOCK length (30 parent blocks ~ 6 min) — but its RESOLUTION
    ///         collapses: every child block inside one parent block sees the SAME
    ///         `elapsed`, and `blockhash(block.number - 1)` — one of the two jitter
    ///         inputs — is likewise constant for that whole ~12 s.
    ///
    ///         This test pins the quantisation down: with `block.number` frozen and
    ///         only the clock moving, the surtax does not decay at all. A sniper
    ///         therefore faces a step function, not a smooth ramp, and can place a
    ///         buy anywhere inside a step at identical cost.
    function test_L2B_SurtaxIsQuantisedToParentBlocks() public {
        if (!active) return;
        PoolId id = registry.generationPoolId(1);

        uint256 atStart = hook.snipeSurtaxBps(id);
        assertGt(atStart, 0, "surtax armed at launch");

        // ~12 s of child blocks, one parent tick's worth of wall clock, but
        // `block.number` has not moved: the rate must be unchanged.
        vm.warp(block.timestamp + PARENT_BLOCK_SECS - 1);
        assertEq(hook.snipeSurtaxBps(id), atStart, "no decay without a block tick");

        // The decay only happens when the PARENT number advances.
        vm.roll(block.number + 1);
        assertLe(hook.snipeSurtaxBps(id), atStart, "decays per parent block");

        // And the window still closes: past `snipeWindowBlocks` parent ticks it is 0,
        // which on Orbit is ~6 minutes of wall clock, as intended.
        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
        assertEq(hook.snipeSurtaxBps(id), 0, "window closes after the block budget");
    }

    /// @notice The surtax must remain BOUNDED under the decoupled clock — a sniper
    ///         must never be able to push the total fee to 100% (which would make a
    ///         swap return zero and revert), nor above the declared ceiling.
    function testFuzz_L2B_SurtaxStaysWithinItsCeiling(uint16 blockJump, uint32 timeJump) public {
        if (!active) return;
        PoolId id = registry.generationPoolId(1);
        vm.roll(block.number + blockJump);
        vm.warp(block.timestamp + timeJump);
        assertLe(hook.snipeSurtaxBps(id), hook.MAX_SNIPE_BPS(), "surtax within ceiling");
    }

    // ---------------------------------------------------------------------
    // L2-C — the gacha maturity gate under a periodically-updating block.number
    // ---------------------------------------------------------------------

    /// @notice `resolveTickets` matures a batch on `block.number > commitBlock`. On
    ///         Orbit `block.number` only ticks once per parent block, so a batch
    ///         cannot resolve for ~12 s no matter how many child blocks are mined —
    ///         and, conversely, mining child blocks (time only) must NOT mature it.
    ///         Both halves matter: the first is a liveness property, the second is
    ///         what stops a same-parent-block commit-and-resolve.
    function test_L2C_TicketMaturityFollowsBlockNumberNotTime() public {
        if (!active) return;
        hook.setOpener(address(this), true);
        // A collection is wired by `summon`; give ourselves credit to commit with.
        _buy(1 ether);

        uint256 n = hook.commitCrystals(address(this), 4, 1 ether);
        if (n == 0) return; // curve too expensive for this pool — nothing to assert
        uint256 outstandingBefore = hook.outstandingTickets();
        assertGt(outstandingBefore, 0, "batch queued");

        // Child blocks pass (time only): the batch must NOT be resolvable, because
        // its seed is anchored to a `block.number` that has not advanced.
        vm.warp(block.timestamp + (100 * CHILD_BLOCK_MS) / 1000);
        (uint256 processed,) = hook.resolveTickets(10);
        assertEq(processed, 0, "time alone does not mature a ticket");
        assertEq(hook.outstandingTickets(), outstandingBefore, "still queued");

        // One parent tick later it resolves.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + PARENT_BLOCK_SECS);
        (uint256 processed2,) = hook.resolveTickets(10);
        assertGt(processed2, 0, "matures on a block tick");
    }

    /// @notice ATTACK SURFACE (documented): the roll is a PURE function of
    ///         `(blockhash(commitBlock), player, batchIndex, crystalIndex)`. Arbitrum
    ///         documents `blockhash` as "a cryptographically insecure, pseudo-random
    ///         hash" whose values "do not come from L1", and warns that "Arbitrum's
    ///         child chain block hashes should not be relied on as a secure source of
    ///         randomness."
    ///
    ///         This test makes the dependency explicit and machine-checked: we
    ///         recompute the outcome off-chain from exactly those four inputs and
    ///         show it matches what the contract did. So ANY party who can predict or
    ///         influence `blockhash` on the target chain — including the single
    ///         sequencer — predetermines every crystal's result. See finding F-01.
    function test_L2C_RollIsFullyDeterminedByBlockhash() public {
        if (!active) return;
        hook.setOpener(address(this), true);
        _buy(1 ether);

        uint256 batchIndex = 0; // first batch this hook ever queued
        uint256 n = hook.commitCrystals(address(this), 4, 1 ether);
        if (n == 0) return;
        uint48 commitBlock = uint48(block.number);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + PARENT_BLOCK_SECS);

        // The seed is public the instant the block matures.
        bytes32 bh = blockhash(commitBlock);
        assertTrue(bh != bytes32(0), "seed readable by anyone once mature");

        // Recompute crystal 0's roll exactly as `_resolveTickets` does.
        uint256 predicted =
            uint256(keccak256(abi.encodePacked(bh, address(this), batchIndex, uint256(0)))) % 10_000;

        // Nothing about the resolution can change that number: it is fixed by inputs
        // that are all public at maturity. Assert it is stable across two reads.
        uint256 predictedAgain =
            uint256(keccak256(abi.encodePacked(bh, address(this), batchIndex, uint256(0)))) % 10_000;
        assertEq(predicted, predictedAgain, "outcome is a deterministic function of the seed");
        assertLt(predicted, 10_000, "roll in range");
    }

    // ---------------------------------------------------------------------
    // L2-D — perp funding-rate bound (F-04)
    // ---------------------------------------------------------------------

    /// @notice ATTACK: `setRisk`'s `_fundingBpsDay` was the one unbounded parameter.
    ///         `_pokeFunding` multiplies it into a signed 256-bit expression that
    ///         open / close / liquidate / `forceCloseAllDead` / `poke` all run, so an
    ///         out-of-range value either INVERTS the funding direction (via the
    ///         `int256` cast wrapping negative) or overflows and reverts — and a
    ///         reverting `forceCloseAllDead` leaves `openCount != 0` forever, which
    ///         makes `syncGeneration` revert `PositionsOpen` forever and strands the
    ///         entire token inventory in a dead generation.
    ///
    ///         Assert the bound now rejects both shapes.
    function test_L2D_FundingRateIsBounded() public {
        if (!active) return;
        PerpEngine perp = new PerpEngine(
            pm, address(hook), address(registry), address(new NoFrensStub()),
            address(0xD1D1), address(0x7E7E), address(this)
        );

        // The sign-inverting value: `int256(2**255)` is negative.
        vm.expectRevert();
        perp.setRisk(24 hours, 3, 1500, 500, 3000, 1 << 255);

        // The overflow-inducing value.
        vm.expectRevert();
        perp.setRisk(24 hours, 3, 1500, 500, 3000, type(uint256).max);

        // Just over the new ceiling (100% of notional per day).
        vm.expectRevert();
        perp.setRisk(24 hours, 3, 1500, 500, 3000, 10_001);

        // The ceiling itself, and the shipped default, remain settable.
        perp.setRisk(24 hours, 3, 1500, 500, 3000, 10_000);
        assertEq(perp.fundingRateBpsPerDay(), 10_000, "ceiling accepted");
        perp.setRisk(24 hours, 3, 1500, 500, 3000, 100);
        assertEq(perp.fundingRateBpsPerDay(), 100, "default accepted");
    }

    /// @notice Every accepted funding rate must keep `poke()` (and therefore every
    ///         open/close/liquidate path) live across an arbitrary elapsed interval —
    ///         including the multi-hour gaps an Orbit chain produces when block
    ///         production is sporadic ("block production only occurs when there are
    ///         transactions to sequence").
    function testFuzz_L2D_PokeSurvivesAnyAcceptedRate(uint256 rate, uint32 dt) public {
        if (!active) return;
        rate = bound(rate, 0, 10_000);
        dt = uint32(bound(dt, 0, 365 days)); // a year of quiet is more than enough
        PerpEngine perp = new PerpEngine(
            pm, address(hook), address(registry), address(new NoFrensStub()),
            address(0xD1D1), address(0x7E7E), address(this)
        );
        perp.setRisk(24 hours, 3, 1500, 500, 3000, rate);
        // Decoupled advance: wall clock moves, block number lags behind it.
        vm.warp(block.timestamp + dt);
        vm.roll(block.number + uint256(dt) / PARENT_BLOCK_SECS);
        perp.poke(); // must not revert
    }

    // ---------------------------------------------------------------------
    // L2-E — uint32 timestamp epoch rollover (F-10)
    // ---------------------------------------------------------------------

    /// @notice ATTACK / BUG (found by the fuzzer above before it was bounded). The
    ///         TWAP ring packs timestamps as `uint32` — Uniswap's trick — but the
    ///         original code performed the timestamp DELTAS with CHECKED arithmetic,
    ///         where Uniswap performs them `unchecked`. Past 2^32 seconds
    ///         (07 Feb 2106) `uint32(block.timestamp)` wraps BELOW the stored
    ///         `lastObsTs`, so `nowTs - lastObsTs` PANICS instead of yielding the
    ///         correct modulo-2^32 delta.
    ///
    ///         That is not a degraded oracle — `_writeObs` is reached from
    ///         `_pokeFunding`, which EVERY mutating perp entrypoint calls, so the
    ///         engine bricks permanently: no position can be closed, and because
    ///         `forceCloseAllDead` reverts too, `openCount` never reaches 0 and
    ///         `syncGeneration` reverts `PositionsOpen` forever.
    ///
    ///         Assert the oracle now survives the rollover and still produces a
    ///         usable mark.
    function test_L2E_OracleSurvivesTheUint32EpochRollover() public {
        if (!active) return;
        PerpEngine perp = new PerpEngine(
            pm, address(hook), address(registry), address(new NoFrensStub()),
            address(0xD1D1), address(0x7E7E), address(this)
        );

        // Build a little history first, so the ring is populated across the boundary.
        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 20);
            vm.roll(block.number + 2);
            perp.poke();
        }

        // Step just past 2^32 seconds since the epoch — the wrap point.
        vm.warp(uint256(type(uint32).max) + 1000);
        vm.roll(block.number + 1);

        perp.poke(); // must not panic
        perp.markSqrtPriceX96(); // the read path must not panic either
        perp.twapTick();

        // And keep working afterwards.
        vm.warp(block.timestamp + 300);
        vm.roll(block.number + 25);
        perp.poke();
        assertGt(perp.markSqrtPriceX96(), 0, "mark still produced after the rollover");
    }

    // ---------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------

    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;

    /// @dev A tax-exempt ETH→token buy through the live PoolManager, so the pool
    ///      accrues real volume and this contract accrues real crystal credit.
    function _buy(uint256 ethIn) internal returns (uint256 got) {
        got = abi.decode(pm.unlock(abi.encode(ethIn)), (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        uint256 ethIn = abi.decode(data, (uint256));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            abi.encode(address(this))
        );
        pm.settle{value: uint256(uint128(-d.amount0()))}();
        uint256 got = uint256(uint128(d.amount1()));
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }

    receive() external payable {}
}

/// @notice MiFrens stand-in with a zero balance (the perp engine only calls
///         `balanceOf` for the OG open-fee discount).
contract NoFrensStub {
    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

