// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {SeederConfig} from "../../cauldron/ISeeder.sol";

/**
 * @notice T9b — REGRESSION for audit Z-17 (was a Critical PoC).
 *
 *  THE BUG. The PERMISSIONLESS `CauldronSeeder.poke()` performed two attacker-timed
 *  actions against LIVE pool state:
 *
 *   1. `_primeStep` swapped treasury ETH for the brew token with
 *      `sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1` — the absolute end of the
 *      tick range, so it could never bind — and no minimum output at all.
 *   2. `_placeStep` read `poolManager.getSlot0` and placed the whole pending
 *      ledger-A step as single-sided bands adjacent to THAT tick.
 *
 *  Both ran in the attacker's own transaction, so the attacker chose the price.
 *  Measured here before the fix: the treasury received 68,793.99 tokens instead of
 *  46,122,162.16 (-99.85%) and the attacker netted +12.157 ETH.
 *
 *  THE FIX. `CauldronSeeder._syncRef()` keeps a reference tick that only moves
 *  `MAX_TICK_DEV` (1000) ticks per BLOCK and is never re-written twice in one block,
 *  and `_primeStep` now trades with a `sqrtPriceLimitX96` derived from it plus a
 *  minimum output. An atomic sandwich is therefore skipped outright, and dragging
 *  the reference costs one block of held manipulation per 1000 ticks.
 *
 *  These tests assert BOTH halves of that: the attack is dead, AND the honest
 *  stream still completes (a gate that also bricks the feature is not a fix).
 *  No fork needed: a real v4-core PoolManager is deployed locally.
 */
contract T9bSeederPokeSandwich is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager pm;
    CauldronToken token;
    CauldronSeeder seeder;
    PoolKey key;
    PoolId pid;

    address constant TREASURY = address(uint160(0xDEAD01));

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000;
    uint160 constant MIN_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 constant MAX_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    uint256 constant ACTIVE_ETH = 10 ether;
    uint256 constant ACTIVE_TOK = 100_000_000 ether;
    uint256 constant PRIME = 5 ether;
    uint64 constant WINDOW = 3600;

    function setUp() public {
        pm = IPoolManager(address(new PoolManager(address(this))));
        token = new CauldronToken("Seed", "SEED", 1, address(this), 500_000_000 ether);
        seeder = new CauldronSeeder(address(this), address(0xBEEF), address(pm));

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        pm.initialize(key, _sqrtPriceFor(ACTIVE_TOK, ACTIVE_ETH));

        vm.deal(address(this), 1_000 ether);
        token.approve(address(seeder), ACTIVE_TOK);
        seeder.startSeed{value: ACTIVE_ETH}(SeederConfig({
            key: key, token: address(token), gen: 1,
            spacing: SPACING, bandWidth: 2000,
            window: WINDOW, seedFloorWad: 0.1e18, minStepWad: 0.02e18,
            baseWad: 0.15e18,
            ethTotal: ACTIVE_ETH, tokenTotal: ACTIVE_TOK
        }));
        // Ledger C: the treasury's prime-buy budget. `deployer == address(this)`.
        seeder.fundPrime{value: PRIME}(TREASURY);
    }

    // ── the pool primitive (this test contract holds its own unlock) ─────────

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (bool z, int256 amt) = abi.decode(data, (bool, int256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: z, amountSpecified: amt, sqrtPriceLimitX96: z ? MIN_LIMIT : MAX_LIMIT}),
            ""
        );
        int128 d0 = d.amount0();
        int128 d1 = d.amount1();
        if (d0 < 0) pm.settle{value: uint256(uint128(-d0))}();
        if (d1 < 0) {
            pm.sync(key.currency1);
            IERC20(address(token)).transfer(address(pm), uint256(uint128(-d1)));
            pm.settle();
        }
        if (d0 > 0) pm.take(key.currency0, address(this), uint256(uint128(d0)));
        if (d1 > 0) pm.take(key.currency1, address(this), uint256(uint128(d1)));
        return abi.encode(d);
    }

    function _swap(bool zeroForOne, int256 amt) internal returns (BalanceDelta) {
        return abi.decode(pm.unlock(abi.encode(zeroForOne, amt)), (BalanceDelta));
    }

    receive() external payable {}

    function _sqrtPriceFor(uint256 amount1, uint256 amount0) internal pure returns (uint160) {
        uint256 ratio = (amount1 * 1e18) / amount0;
        uint256 s = _sqrt(ratio) * 2 ** 96 / 1e9;
        return uint160(s);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    // ── scenarios ───────────────────────────────────────────────────────────

    /// @dev Honest baseline: nobody manipulates, someone pokes at window end.
    function _honest() internal returns (uint256 treasuryTokens) {
        vm.warp(block.timestamp + WINDOW + 1);
        seeder.poke();
        treasuryTokens = token.balanceOf(TREASURY);
    }

    /// @dev Attack: push the price with a buy, poke (the treasury prime buy lands
    ///      against the price the attacker just set, with no minOut, and the whole
    ///      remaining ledger-A step is placed adjacent to that tick), then unwind.
    function _attack(uint256 pushEth)
        internal
        returns (uint256 treasuryTokens, int256 attackerPnl)
    {
        vm.warp(block.timestamp + WINDOW + 1);
        uint256 ethBefore = address(this).balance;
        uint256 tokBefore = token.balanceOf(address(this));

        _swap(true, -int256(pushEth));      // ETH -> token: tick DOWN, token dearer
        seeder.poke();                      // victim: prime buy + band placement
        uint256 bought = token.balanceOf(address(this)) - tokBefore;
        _swap(false, -int256(bought));      // sell the exact position back

        treasuryTokens = token.balanceOf(TREASURY);
        attackerPnl = int256(address(this).balance) - int256(ethBefore)
            + int256(token.balanceOf(address(this))) - int256(tokBefore);
    }

    /// @dev REGRESSION (Z-17a). The prime tranche used to execute at whatever price
    ///      the sandwicher had just set. It must now be REFUSED outright — and the
    ///      round trip must lose money, which is what removes the incentive.
    function test_PokePrimeBuyHasNoSlippageGuard() public {
        uint256 snap = vm.snapshotState();

        uint256 honestTokens = _honest();
        assertGt(honestTokens, 0, "honest poke delivers the prime buy");

        vm.revertToState(snap);

        (uint256 attackedTokens, int256 pnl) = _attack(40 ether);

        emit log_named_uint("treasury tokens, honest ", honestTokens);
        emit log_named_uint("treasury tokens, attacked", attackedTokens);
        emit log_named_int("attacker net (wei)        ", pnl);

        // BEFORE: 68,793.99 tokens were handed over at the pushed price (-99.85%).
        // NOW: the poke is skipped entirely, so the budget is not spent at all.
        assertEq(attackedTokens, 0, "the sandwiched prime tranche is REFUSED, not mispriced");
        assertEq(seeder.primeSpent(), 0, "nothing was drawn from the prime budget");
        assertEq(seeder.primeBudget(), PRIME, "the budget is intact for a later honest poke");

        // BEFORE: +12.157 ETH. The sandwich must now cost the attacker money.
        assertLt(pnl, 0, "the sandwich is a LOSS, so there is no incentive to run it");
    }

    /// @dev REGRESSION (Z-17b). BOTH bands used to anchor to whatever tick the caller's
    ///      own swap had just set, donating the protocol's freshly streamed liquidity
    ///      right next to the attacker's position so they could sell back through it.
    ///
    ///      The band the attacker must trade back THROUGH must now be pinned to the
    ///      reference instead: they pushed spot DOWN, so they unwind UPWARD, so the BID
    ///      (ETH) band has to sit above the HONEST tick — out of the whole unwind
    ///      corridor (pushedTick, honestTick). The stream must still deploy, because
    ///      refusing would break keeperless in-swap streaming on any thin book.
    function test_PlacementFollowsManipulatedTick() public {
        vm.warp(block.timestamp + WINDOW + 1);
        (, int24 honestTick,,) = pm.getSlot0(pid);

        _swap(true, -int256(40 ether));
        (, int24 pushedTick,,) = pm.getSlot0(pid);
        uint256 rangesBefore = seeder.rangeCount();
        uint256 placedBefore = seeder.placedWad();
        seeder.poke();
        uint256 rangesAfter = seeder.rangeCount();

        emit log_named_int("honest tick", honestTick);
        emit log_named_int("pushed tick", pushedTick);
        emit log_named_uint("ranges before", rangesBefore);
        emit log_named_uint("ranges after ", rangesAfter);

        assertTrue(pushedTick < honestTick - 2000, "attacker moved spot far");
        // LIVENESS: the step still deploys. A gate that stops streaming would break
        // the keeperless model it is meant to protect.
        assertGt(rangesAfter, rangesBefore, "the step still deploys");
        assertGt(seeder.placedWad(), placedBefore, "and is booked as deployed");

        // SAFETY: nothing new landed inside the attacker's unwind corridor. Every band
        // minted by this poke must either sit BELOW the pushed tick (token asks, which
        // an upward unwind never touches and which only get cheaper to ignore) or ABOVE
        // the honest tick (ETH bids pinned to the reference).
        for (uint256 i = rangesBefore; i < rangesAfter; i++) {
            (int24 lo, int24 hi) = seeder.ranges(i);
            emit log_named_int("new band lo", lo);
            emit log_named_int("new band hi", hi);
            assertTrue(
                hi <= pushedTick || lo >= honestTick,
                "no band was donated inside the sandwich corridor"
            );
        }
    }

    /// @dev LIVENESS, unattacked: the gate must not brick the feature it protects.
    ///      Run the progressive seed end to end — poke once per block across the
    ///      window — and assert BOTH ledgers close out: the stream reaches 100% and
    ///      the whole prime budget is spent.
    function test_HonestStreamAndPrimeBudgetStillCompleteEndToEnd() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 b0 = vm.getBlockNumber();
        for (uint256 i; i < 400; i++) {
            vm.roll(b0 + i + 1);
            vm.warp(t0 + ((WINDOW + 600) * (i + 1)) / 400);
            seeder.poke();
        }
        emit log_named_uint("placedWad  ", seeder.placedWad());
        emit log_named_uint("primeSpent ", seeder.primeSpent());
        emit log_named_uint("prime budget", seeder.primeBudget());
        emit log_named_uint("treasury tok", token.balanceOf(TREASURY));

        assertEq(seeder.placedWad(), 1e18, "the whole ledger-A stream deployed");
        assertTrue(seeder.isComplete(), "campaign reports complete");
        assertGt(token.balanceOf(TREASURY), 0, "and the treasury holds the tokens it bought");
        // The prime buy is now IMPACT-CAPPED per block (`sqrtPriceLimitX96` derived from
        // the rate-limited reference), so a 5 ETH budget against a 10 ETH book is spent
        // over many blocks instead of in one unbounded market order. What must hold is
        // that it keeps making progress and is never bricked. MEASURED: it still closes
        // out in full, it just takes the blocks.
        assertEq(seeder.primeSpent(), PRIME, "the whole prime budget still closes out");
    }
}
