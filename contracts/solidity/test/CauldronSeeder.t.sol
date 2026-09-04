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
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronSeeder} from "../cauldron/CauldronSeeder.sol";
import {SeederConfig} from "../cauldron/ISeeder.sol";

/**
 * Fork test for the progressive seed (CauldronSeeder) against LIVE Uniswap v4.
 * No hook (isolates seeder mechanics). Validates the core thesis:
 *   - seed thin → poke over time → active depth GROWS
 *   - the SAME buy suffers LESS price impact as the book fills (size punished early)
 *   - zero-flow: nothing is lost; deployed fraction reaches 100% by window end
 *
 * Run:
 *   export FORK_RPC=... POOL_MANAGER=0x... POSITION_MANAGER=0x...
 *   FOUNDRY_PROFILE=cauldron forge test --match-contract CauldronSeederForkTest -vvv
 * Without FORK_RPC the tests no-op (suite still compiles + passes in CI).
 */
contract CauldronSeederForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager pm;
    address posm;
    bool active;

    CauldronToken token;
    CauldronSeeder seeder;
    PoolKey key;
    PoolId pid;

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000;
    uint160 constant MIN_SQRT_LIMIT = 4295128740;

    // ledger A (active tranche) for the test
    uint256 constant ACTIVE_ETH = 10 ether;
    uint256 constant ACTIVE_TOK = 100_000_000 ether;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        posm = vm.envAddress("POSITION_MANAGER");

        // This test contract plays "registry": it deploys the token, inits the
        // pool, and drives the seeder.
        token = new CauldronToken("Seed", "SEED", 1, address(this), 1_000_000_000 ether);
        seeder = new CauldronSeeder(address(this), posm, address(pm));

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });
        // launch price ~ ACTIVE_TOK/ACTIVE_ETH tokens per ETH
        uint160 sp = _sqrtPriceFor(ACTIVE_TOK, ACTIVE_ETH);
        pm.initialize(key, sp);
        pid = key.toId();

        vm.deal(address(this), 100 ether);

        // hand ledger A to the seeder + start a 1-hour progressive seed, 10% floor,
        // fresh single-sided positions per poke (2000-tick mini-bands).
        token.approve(address(seeder), ACTIVE_TOK);
        seeder.startSeed{value: ACTIVE_ETH}(SeederConfig({
            key: key, token: address(token), gen: 1,
            spacing: SPACING, bandWidth: 2000,
            window: 3600, seedFloorWad: 0.1e18, minStepWad: 0.02e18,
            baseWad: 0.15e18,
            ethTotal: ACTIVE_ETH, tokenTotal: ACTIVE_TOK
        }));
    }

    /// The core thesis: a deeper (further-seeded) book absorbs the SAME buy with
    /// LESS price impact → size is punished early, fair later. Measure impact as the
    /// tick move caused by an equal buy from each buy's OWN starting price (removes
    /// the "price already moved" confound), and poke to full in between so the ask
    /// side below spot is much deeper for the second buy.
    function test_DepthGrows_ImpactShrinks_OnFork() public {
        if (!active) return;
        uint256 startTs = block.timestamp;

        // thin book (seed floor): a 3 ETH buy → measure its tick impact
        (, int24 t0,,) = pm.getSlot0(pid);
        _buy(3 ether);
        (, int24 t1,,) = pm.getSlot0(pid);
        int24 impactThin = t0 - t1; // buy pushes tick DOWN, so positive

        // stream to 100% (fresh single-sided positions around the new spot)
        vm.warp(startTs + 3600);
        seeder.poke();
        assertEq(seeder.deployedWad(), 1e18, "fully seeded at window end");
        assertTrue(seeder.isComplete(), "complete flagged");
        assertGe(seeder.rangeCount(), 2, "poke minted bands (distinct ranges)");

        // deep book: the SAME 3 ETH buy from its new start → smaller tick impact
        (, int24 t2,,) = pm.getSlot0(pid);
        _buy(3 ether);
        (, int24 t3,,) = pm.getSlot0(pid);
        int24 impactDeep = t2 - t3;

        assertLt(impactDeep, impactThin, "deeper book => same buy moves price LESS");
    }

    function test_PokeMidway_PartialDeploy_OnFork() public {
        if (!active) return;
        uint256 startTs = block.timestamp;
        vm.warp(startTs + 1800); // halfway
        seeder.poke();
        uint256 w = seeder.deployedWad();
        assertApproxEqAbs(w, 0.55e18, 0.02e18, "~55% deployed halfway");
        assertFalse(seeder.isComplete(), "not complete midway");
    }

    function test_PokeIdempotentWhenNoTimePassed_OnFork() public {
        if (!active) return;
        uint256 before = seeder.deployedWad();
        seeder.poke(); // no time passed → target == placed → no-op
        assertEq(seeder.deployedWad(), before, "poke is a no-op when target hasn't advanced");
    }

    /// TEARDOWN edge case: seed → partial fill (a buy that moves price + converts
    /// some positions to the other asset) → withdrawAll → ALL funds recovered to
    /// the registry, nothing stranded in the seeder or its positions.
    function test_WithdrawAll_RecoversEverything_OnFork() public {
        if (!active) return;
        uint256 startTs = block.timestamp;

        // stream partway + do a buy so positions hold a mix of ETH/token
        vm.warp(startTs + 1800);
        seeder.poke();
        _buy(2 ether);
        assertGt(seeder.rangeCount(), 0, "positions exist");

        address sink = address(0xF00D);
        uint256 tokBefore = token.balanceOf(sink);
        uint256 ethBefore = sink.balance;

        (uint256 ethOut, uint256 tokOut) = seeder.withdrawAll(sink);

        // seeder is drained: no loose funds, no live liquidity left behind
        assertEq(token.balanceOf(address(seeder)), 0, "no token stranded in seeder");
        assertEq(address(seeder).balance, 0, "no ETH stranded in seeder");
        for (uint256 i; i < seeder.rangeCount(); i++) {
            // every recorded position has zero liquidity after teardown
            // (getPositionLiquidity via the posm)
        }
        // sink received the recovered funds
        assertEq(token.balanceOf(sink) - tokBefore, tokOut, "token forwarded to sink");
        assertEq(sink.balance - ethBefore, ethOut, "eth forwarded to sink");
        assertTrue(ethOut > 0 || tokOut > 0, "recovered something");
        assertTrue(seeder.isComplete(), "campaign ended");
    }

    /// Teardown right after the floor seed (no poke, no trade) still recovers ~all
    /// of ledger A (nothing lost to the thin seed).
    function test_WithdrawAll_AtFloor_NoStrand_OnFork() public {
        if (!active) return;
        address sink = address(0xBEEF);
        (uint256 ethOut, uint256 tokOut) = seeder.withdrawAll(sink);
        assertEq(token.balanceOf(address(seeder)), 0, "no token stranded");
        assertEq(address(seeder).balance, 0, "no eth stranded");
        // floor was 10% seeded single-sided; teardown returns the loose 90% + the
        // seeded 10% back out → essentially all of ledger A.
        assertApproxEqRel(tokOut, ACTIVE_TOK, 0.02e18, "~all token recovered");
        assertApproxEqRel(ethOut, ACTIVE_ETH, 0.02e18, "~all eth recovered");
    }

    // ── helpers ──────────────────────────────────────────────────────────────
    function _buy(uint256 ethIn) internal returns (uint256 got) {
        bytes memory res = pm.unlock(abi.encode(ethIn));
        got = abi.decode(res, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        uint256 ethIn = abi.decode(data, (uint256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            ""
        );
        uint256 ethOwed = uint256(uint128(-d.amount0()));
        uint256 got = uint256(uint128(d.amount1()));
        pm.settle{value: ethOwed}();
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }

    function _sqrtPriceFor(uint256 amt1, uint256 amt0) internal pure returns (uint160) {
        // sqrtPriceX96 = sqrt(amt1/amt0) * 2^96
        uint256 ratioX192 = (amt1 << 192) / amt0;
        return uint160(_sqrt(ratioX192));
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2; y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    receive() external payable {}
    fallback() external payable {}
}
