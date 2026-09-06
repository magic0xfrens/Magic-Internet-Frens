// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {SeederConfig} from "../../cauldron/ISeeder.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

// ───────────────────────────────────────────────────────────────────────────────
// Minimal ERC20 for the rogue-pool proofs.
// ───────────────────────────────────────────────────────────────────────────────
contract Evil20 {
    string public name = "EVIL";
    string public symbol = "EVIL";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 s) { totalSupply = s; balanceOf[msg.sender] = s; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (f != msg.sender) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 1 / REGRESSION — CauldronSeeder once left `complete` (and `_basePlaced`) set
//         after teardown, so the SECOND campaign reported complete immediately,
//         `_pendingStep()` returned 0 forever, and ~90% of ledger A sat in the
//         seeder for the whole life of that generation.            (audit H-02)
//         FIXED: `startSeed` now performs a full per-campaign reset.
//         No hook needed; this test contract plays the registry.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_SeederSecondCampaign is Test, IUnlockCallback {
    using PoolIdLibrary for PoolKey;

    IPoolManager pm;
    address posm;
    bool active;

    CauldronToken tokA;
    CauldronToken tokB;
    CauldronSeeder seeder;
    PoolKey keyA;
    PoolKey keyB;

    int24 constant SPACING = 200;
    uint24 constant FEE = 10_000;
    uint256 constant ACTIVE_ETH = 10 ether;
    uint256 constant ACTIVE_TOK = 100_000_000 ether;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        posm = vm.envAddress("POSITION_MANAGER");

        tokA = new CauldronToken("A", "A", 1, address(this), 1_000_000_000 ether);
        tokB = new CauldronToken("B", "B", 2, address(this), 1_000_000_000 ether);
        seeder = new CauldronSeeder(address(this), posm, address(pm));

        keyA = _key(address(tokA));
        keyB = _key(address(tokB));
        pm.initialize(keyA, _sqrtPriceFor(ACTIVE_TOK, ACTIVE_ETH));
        pm.initialize(keyB, _sqrtPriceFor(ACTIVE_TOK, ACTIVE_ETH));
        vm.deal(address(this), 200 ether);
    }

    function test_Fixed_SecondCampaignStreamsToCompletion() public {
        if (!active) return;

        // ── Campaign 1 (generation 1) ───────────────────────────────────────
        tokA.approve(address(seeder), ACTIVE_TOK);
        seeder.startSeed{value: ACTIVE_ETH}(_cfg(keyA, address(tokA), 1));
        assertEq(seeder.deployedWad(), 0.1e18, "gen1 starts at the 10% floor");

        vm.warp(vm.getBlockTimestamp() + 3600);
        seeder.poke();
        assertEq(seeder.deployedWad(), 1e18, "gen1 streams to 100%");
        assertTrue(seeder.isComplete(), "gen1 complete");

        // Relaunch teardown (what CauldronRegistry._removeLiquidity does).
        seeder.withdrawAll(address(this));
        assertFalse(seeder.seeding(), "campaign 1 ended");

        // ── Campaign 2 (generation 2) — the registry re-arms the same seeder ──
        tokB.approve(address(seeder), ACTIVE_TOK);
        seeder.startSeed{value: ACTIVE_ETH}(_cfg(keyB, address(tokB), 2));
        assertTrue(seeder.seeding(), "campaign 2 armed");

        // FIXED A: `complete` is reset, so the campaign starts live.
        assertFalse(seeder.isComplete(), "FIXED: campaign 2 starts fresh, not complete");
        assertEq(seeder.deployedWad(), 0.1e18, "gen2 starts at its own 10% floor");

        // FIXED B: the stream advances over the window, exactly like generation 1.
        vm.warp(vm.getBlockTimestamp() + 1800);
        seeder.poke();
        uint256 mid = seeder.deployedWad();
        assertGt(mid, 0.1e18, "FIXED: gen2 streams past the floor");
        vm.warp(vm.getBlockTimestamp() + 3600);
        seeder.poke();
        assertEq(seeder.deployedWad(), 1e18, "FIXED: gen2 reaches 100% by window end");
        assertTrue(seeder.isComplete(), "FIXED: gen2 completes");

        // FIXED C: `_basePlaced` is reset too, so gen 2 gets its own two-sided
        // full-range base — the spot-straddling depth the perp engine reads.
        // Almost nothing is left stranded in the seeder.
        uint256 strandedTok = tokB.balanceOf(address(seeder));
        uint256 strandedEth = address(seeder).balance;
        console2.log("gen2 token stranded in seeder :", strandedTok);
        console2.log("gen2 ETH   stranded in seeder :", strandedEth);
        assertLt(strandedTok, (ACTIVE_TOK * 20) / 100, "FIXED: ledger-A token reached the pool");
        assertLt(strandedEth, (ACTIVE_ETH * 20) / 100, "FIXED: ledger-A ETH reached the pool");
    }

    // ── helpers ────────────────────────────────────────────────────────────
    function _key(address t) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(t),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });
    }

    function _cfg(PoolKey memory k, address t, uint256 g) internal pure returns (SeederConfig memory) {
        return SeederConfig({
            key: k, token: t, gen: g,
            spacing: SPACING, bandWidth: 2000,
            window: 3600, seedFloorWad: 0.1e18, minStepWad: 0.02e18,
            baseWad: 0.15e18,
            ethTotal: ACTIVE_ETH, tokenTotal: ACTIVE_TOK
        });
    }

    function unlockCallback(bytes calldata) external pure returns (bytes memory) { return ""; }

    function _sqrtPriceFor(uint256 amt1, uint256 amt0) internal pure returns (uint160) {
        uint256 ratioX192 = (amt1 << 192) / amt0;
        return uint160(_sqrt(ratioX192));
    }
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2; y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
    receive() external payable {}
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 2 / REGRESSION — CauldronHook once served ANY V4 pool that named it.
//   2a. A pool whose currency0 is NOT ETH minted phantom `relaunchETH` out of a
//       worthless token → `releaseRelaunchETH()` reverted → `relaunch()` was
//       permanently bricked.                                        (audit C-01a)
//   2b. A pool the attacker controlled drained the hook's `legacyBuffer` ETH into
//       that pool via the in-swap legacy buyback.                   (audit C-01b)
//
// Both are now FIXED. The hook adopts a pool only when the REGISTRY initialized it
// against native ETH (`_afterInitialize` + `_served`), and the legacy buyback only
// ever spends into the registry-recorded `_liveKey`. These tests are the
// regressions: they run the original exploits and assert they no longer work.
//
// NOTE: the attacker here is a DISTINCT address from the wired registry — that is
// the whole point. An earlier revision of this file wired the test contract itself
// as the registry, which made the "attacker" trusted and hid the fix.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_HookRoguePool is Test, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager pm;
    CauldronHook hook;
    bool active;

    address constant REGISTRY = address(0x9E6157);
    Evil20 evilA;
    Evil20 evilB;
    PoolKey rogueKey;     // (EVIL_A, EVIL_B) — no ETH leg at all
    PoolKey ethEvilKey;   // (ETH, EVIL)      — attacker-controlled price

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970341;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");
        // Wire a registry that is NOT this contract: the attacker must be an
        // ordinary, untrusted Uniswap user.
        hook.setRegistry(REGISTRY);

        Evil20 x = new Evil20(1e30);
        Evil20 y = new Evil20(1e30);
        (evilA, evilB) = address(x) < address(y) ? (x, y) : (y, x);

        vm.deal(address(this), 500 ether);
    }

    /// 2a REGRESSION: a pool with NO ether leg can no longer mint relaunchETH.
    function test_Fixed_NoPhantomRelaunchEth() public {
        if (!active) return;

        rogueKey = PoolKey({
            currency0: Currency.wrap(address(evilA)),
            currency1: Currency.wrap(address(evilB)),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        pm.initialize(rogueKey, uint160(1 << 96)); // 1:1

        assertEq(hook.relaunchETH(), 0, "no fees yet");

        // Attacker adds their own worthless liquidity, then sells EVIL_B for
        // EVIL_A (exact input, !zeroForOne) — so currency0 is the UNSPECIFIED leg
        // and the hook treats it as "ETH".
        pm.unlock(abi.encode(uint8(1), uint256(0)));

        uint256 phantom = hook.relaunchETH();
        console2.log("relaunchETH after the rogue-pool swap:", phantom);
        console2.log("hook real ETH balance                :", address(hook).balance);

        // FIXED: the pool was never adopted, so no fee was charged and no ETH-
        // denominated accounting was created out of a worthless token.
        assertEq(phantom, 0, "FIXED: no phantom relaunchETH from a foreign pool");
        assertFalse(hook.trackedPools(rogueKey.toId()), "FIXED: foreign pool not adopted");
        // The accounting therefore never exceeds the real balance (invariant I-6).
        assertLe(hook.relaunchETH() + hook.legacyBuffer(), address(hook).balance,
            "FIXED: hook ETH accounting stays backed");
    }

    /// 2b REGRESSION: the legacy buyback can no longer be steered into an
    ///     attacker-priced pool. It spends ONLY into the registry's `_liveKey`.
    function test_Fixed_LegacyBufferCannotBeStolen() public {
        if (!active) return;

        // Production wiring: the live buyback is ON (DeployLaunchpad does exactly
        // this — 40% of the post-guild fee, 0.02 ETH trigger). Owner may configure.
        hook.setLegacyBuyback(REGISTRY, 4000, 0.02 ether);
        hook.fundLegacyBuffer{value: 5 ether}();
        assertEq(hook.legacyBuffer(), 5 ether, "buffer funded");

        // Attacker pool: ETH paired against a token they minted out of thin air,
        // priced so the hook's ETH buys a mountain of it.
        ethEvilKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(evilA)),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        pm.initialize(ethEvilKey, _sqrtPriceFor(1e26, 1 ether));

        uint256 hookEthBefore = address(hook).balance;
        uint256 attackerEthBefore = address(this).balance;

        // One tiny swap in the attacker's own pool. At the TOP of afterSwap the
        // hook fires `legacyBuyStep(key)` with the ATTACKER'S key and market-buys
        // EVIL with the whole buffer — paying real ETH into the attacker's pool.
        pm.unlock(abi.encode(uint8(2), uint256(0.001 ether)));

        uint256 hookEthAfter = address(hook).balance;
        uint256 attackerEthAfter = address(this).balance;

        console2.log("hook ETH before / after  :", hookEthBefore, hookEthAfter);
        console2.log("attacker ETH before/after:", attackerEthBefore, attackerEthAfter);
        console2.log("hook legacyBuffer after  :", hook.legacyBuffer());
        console2.log("hook EVIL received       :", evilA.balanceOf(address(hook)));

        // FIXED on two independent axes:
        //  (1) the attacker's pool is not adopted, so no fee is taken there, and
        //  (2) even if it were, the buyback only spends into the registry's live
        //      key -- which is unset here, so it cannot fire at all.
        assertGe(hookEthAfter, hookEthBefore, "FIXED: no hook ETH left the hook");
        assertEq(evilA.balanceOf(address(hook)), 0, "FIXED: hook bought no attacker token");
        assertGe(hook.legacyBuffer(), 5 ether, "FIXED: the buffer is intact");
        assertLt(attackerEthAfter, attackerEthBefore, "attacker only lost gas/slippage");
    }

    // ── unlock bodies ──────────────────────────────────────────────────────
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        (uint8 tag, uint256 arg) = abi.decode(data, (uint8, uint256));
        if (tag == 1) return _rogueNoEth();
        return _rogueEthEvil(arg);
    }

    /// Seed the (EVIL_A, EVIL_B) pool then sell B→A so currency0 is unspecified.
    function _rogueNoEth() private returns (bytes memory) {
        int24 lo = -20_000; int24 hi = 20_000;
        uint128 L = LiquidityAmounts.getLiquidityForAmounts(
            uint160(1 << 96), TickMath.getSqrtPriceAtTick(lo), TickMath.getSqrtPriceAtTick(hi),
            1e24, 1e24
        );
        (BalanceDelta d,) = pm.modifyLiquidity(rogueKey, ModifyLiquidityParams(lo, hi, int256(uint256(L)), 0), "");
        _pay(rogueKey.currency0, d.amount0());
        _pay(rogueKey.currency1, d.amount1());

        BalanceDelta s = pm.swap(
            rogueKey,
            SwapParams({zeroForOne: false, amountSpecified: -int256(1e21), sqrtPriceLimitX96: MAX_SQRT_LIMIT}),
            ""
        );
        _pay(rogueKey.currency0, s.amount0());
        _pay(rogueKey.currency1, s.amount1());
        return "";
    }

    /// Seed the attacker's (ETH, EVIL) pool, probe it with a tiny buy (which makes
    /// the hook spend its whole buffer inside this same pool), then pull the LP —
    /// the hook's ETH comes back out to the attacker.
    function _rogueEthEvil(uint256 probe) private returns (bytes memory) {
        (uint160 sp,,,) = pm.getSlot0(ethEvilKey.toId());
        int24 lo = -600_000; int24 hi = 600_000;
        lo = (lo / 200) * 200; hi = (hi / 200) * 200;
        uint128 L = LiquidityAmounts.getLiquidityForAmounts(
            sp, TickMath.getSqrtPriceAtTick(lo), TickMath.getSqrtPriceAtTick(hi), 1 ether, 1e26
        );
        (BalanceDelta d,) = pm.modifyLiquidity(ethEvilKey, ModifyLiquidityParams(lo, hi, int256(uint256(L)), 0), "");
        _pay(ethEvilKey.currency0, d.amount0());
        _pay(ethEvilKey.currency1, d.amount1());

        BalanceDelta s = pm.swap(
            ethEvilKey,
            SwapParams({zeroForOne: true, amountSpecified: -int256(probe), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            ""
        );
        _pay(ethEvilKey.currency0, s.amount0());
        _pay(ethEvilKey.currency1, s.amount1());

        // Pull the whole position back — the hook's ETH is now in it.
        (BalanceDelta r,) = pm.modifyLiquidity(ethEvilKey, ModifyLiquidityParams(lo, hi, -int256(uint256(L)), 0), "");
        _pay(ethEvilKey.currency0, r.amount0());
        _pay(ethEvilKey.currency1, r.amount1());
        return "";
    }

    function _pay(Currency c, int128 amt) private {
        if (amt > 0) { pm.take(c, address(this), uint256(uint128(amt))); return; }
        if (amt == 0) return;
        uint256 owed = uint256(uint128(-amt));
        if (Currency.unwrap(c) == address(0)) { pm.settle{value: owed}(); }
        else {
            pm.sync(c);
            Evil20(Currency.unwrap(c)).transfer(address(pm), owed);
            pm.settle();
        }
    }

    function _sqrtPriceFor(uint256 amt1, uint256 amt0) internal pure returns (uint160) {
        uint256 ratioX192 = (amt1 << 192) / amt0;
        return uint160(_sqrt(ratioX192));
    }
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2; y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
    receive() external payable {}
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 3 / REGRESSION — PerpVault once let the FIRST token-side staker capture the
//         ENTIRE ETH yield pot accrued while there were no token shares, because
//         `_syncTokYield` skipped the fold at zero shares WITHOUT advancing the
//         watermark.                                                (audit H-05)
//         FIXED: the watermark always advances; unattributable yield is emitted
//         as `UnattributedYield` and never back-paid to a first-mover.
// ───────────────────────────────────────────────────────────────────────────────
contract MockPerpEngine {
    uint256 public plv;
    uint256 public longOiEth;
    uint256 public plvToken;
    uint256 public shortOiToken;
    uint256 public tokYieldEth;
    uint256 public tokYieldCumulative;
    Evil20 public tok;

    constructor(address _tok) { tok = Evil20(_tok); }

    function totalEth() external view returns (uint256) { return plv + longOiEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external view returns (uint256) { return plvToken + shortOiToken; }
    function freeToken() external view returns (uint256) { return plvToken; }
    function fundFromVault(uint256 amount) external payable { plv += amount; }
    /// Native book: the vault reads this to decide how to deliver the stake.
    function quote() external pure returns (address) { return address(0); }
    function withdrawPlvTo(uint256 a, address to) external { plv -= a; (bool ok,) = to.call{value: a}(""); require(ok); }
    function fundTokenFromVault(uint256 a) external { tok.transferFrom(msg.sender, address(this), a); plvToken += a; }
    function withdrawPlvTokenTo(uint256 a, address to) external { plvToken -= a; tok.transfer(to, a); }
    function withdrawTokYieldTo(uint256 a, address to) external {
        require(a <= tokYieldEth, "pot");
        tokYieldEth -= a; (bool ok,) = to.call{value: a}(""); require(ok);
    }
    /// Mirrors PerpEngine._creditPerp(false): short-side fees land in the pot.
    function creditShortFee() external payable { tokYieldEth += msg.value; tokYieldCumulative += msg.value; }
    receive() external payable {}
}

contract MockRegistryToken {
    address public currentToken;
    constructor(address t) { currentToken = t; }
}

contract PoC_PerpVaultYieldCapture is Test {
    Evil20 tok;
    MockPerpEngine engine;
    PerpVault vault;

    address whale = address(0xA0A0);
    address sniper = address(0x5111);

    function setUp() public {
        tok = new Evil20(1e30);
        engine = new MockPerpEngine(address(tok));
        vault = new PerpVault(address(engine), address(new MockRegistryToken(address(tok))));
        // A real short-inventory position already exists (owner-seeded, share-less).
        tok.transfer(address(engine), 1_000_000 ether);
        engine.fundTokenFromVault(0); // no-op, keeps the mock honest
        vm.deal(address(this), 100 ether);
    }

    function test_Fixed_FirstTokenStakerCannotTakeThePot() public {
        // 10 ETH of short-side yield accrues while NOBODY has token shares.
        engine.creditShortFee{value: 10 ether}();
        assertEq(engine.tokYieldEth(), 10 ether, "pot funded");
        assertEq(vault.tokShares(), 0, "no token stakers yet");

        // A sniper deposits the minimum that mints >= 1 share and immediately claims.
        tok.transfer(sniper, 1000 ether);
        vm.startPrank(sniper);
        tok.approve(address(vault), type(uint256).max);
        vault.depositToken(1000 ether);
        uint256 gained = vault.pendingTokYield(sniper);
        vm.stopPrank();

        // The *whale* now stakes 1000x more — but the pot is already claimable by
        // the sniper alone.
        tok.transfer(whale, 1_000_000 ether);
        vm.startPrank(whale);
        tok.approve(address(vault), type(uint256).max);
        vault.depositToken(1_000_000 ether);
        vm.stopPrank();

        console2.log("sniper deposit (token)   :", uint256(1000 ether));
        console2.log("sniper pending after join:", gained);
        console2.log("whale  pending ETH       :", vault.pendingTokYield(whale));

        // FIXED: the zero-stake pot is NOT credited to whoever arrives first.
        assertEq(gained, 0, "FIXED: no back-pay of the zero-stake pot");
        vm.prank(sniper);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimTokYield();
        assertEq(vault.pendingTokYield(whale), 0, "whale likewise has no back-pay");

        // ...and yield accrued AFTER staking is still shared correctly, pro-rata.
        engine.creditShortFee{value: 1 ether}();
        uint256 sniperShare = vault.pendingTokYield(sniper);
        uint256 whaleShare  = vault.pendingTokYield(whale);
        console2.log("after 1 ETH of new yield -> sniper:", sniperShare);
        console2.log("after 1 ETH of new yield -> whale :", whaleShare);
        assertGt(whaleShare, sniperShare * 100, "FIXED: new yield follows stake size");
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 4 / REGRESSION — CauldronCollection once took `deployer = msg.sender`, which
//         is the FACTORY, so the registry's legacy recycle/buyback
//         (`custodyTransfer`) could never execute and every governed admin setter
//         was unreachable forever.                                  (audit H-01)
//         FIXED: the registry is passed EXPLICITLY as the controller; the factory
//         keeps only the two setters it needs at deploy time.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_CollectionCustodyLockout is Test {
    CauldronFactory factory;
    CauldronCollection col;
    address registry = address(0x9E61);
    address hookAddr = address(0x1400);

    function setUp() public {
        factory = new CauldronFactory();
        (address c,) = factory.deployBrew(
            CauldronFactory.Config({
                name: "Brew", symbol: "BREW", hook: hookAddr, registry: registry,
                maxSupply: 3333, mode: MetadataMode.BaseURI, baseURI: "ipfs://x/",
                renderer: address(0), royaltyReceiver: address(0xBEEF), royaltyBps: 500
            })
        );
        col = CauldronCollection(c);
    }

    function test_Fixed_ControllerIsTheRegistry() public view {
        assertEq(col.deployer(), registry, "FIXED: the registry controls the collection");
        assertEq(col.configurator(), address(factory), "the factory keeps its deploy-time role");
    }

    function test_Fixed_RegistryCanCustodyTransfer() public {
        vm.prank(hookAddr);
        uint256 id = col.mint(address(0xA11CE));

        // This is EXACTLY what PoolOps.recycleCollection does, as the registry.
        vm.prank(registry);
        col.custodyTransfer(address(0xA11CE), registry, id);
        assertEq(col.ownerOf(id), registry, "FIXED: the NFT reached the treasury");

        // ...and back out to a buyer, which is `buyCollectionNFT`.
        vm.prank(registry);
        col.custodyTransfer(registry, address(0xB0B), id);
        assertEq(col.ownerOf(id), address(0xB0B), "FIXED: resale path works");

        // Still closed to everyone else.
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronCollection.OnlyVault.selector);
        col.custodyTransfer(address(0xB0B), address(0xBAD), id);
    }

    function test_Fixed_CollectionAdminSettersReachable() public {
        // A broken renderer can now actually be repointed — the stated purpose of
        // setMetadata, which was previously unreachable.
        vm.prank(registry);
        col.setMetadata(MetadataMode.BaseURI, address(0), "ipfs://fixed/");
        assertEq(uint256(col.mode()), uint256(MetadataMode.BaseURI));

        // ERC-721C royalty enforcement can now be switched on.
        vm.prank(registry);
        col.setTransferValidator(address(0xDEAD));
        assertEq(col.getTransferValidator(), address(0xDEAD));

        // ...and remain closed to outsiders.
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        col.setTransferValidator(address(0));
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 5 / REGRESSION — `reveal()` used to give the holder TWO independent rarity
//         draws (blockhash inside 256 blocks, a DETERMINISTIC fallback after) and
//         they could simply wait out the window and take the better of the two.
//         With the default tiers that lifts P(>= Rare) from 21% to ~37.6% and
//         roughly doubles the top tier.                            (audit M-03)
//         FIXED: an expired seed RE-ANCHORS to a fresh future block instead of
//         substituting a predictable one, so there is always exactly ONE
//         unknowable draw — and the token stays revealable forever.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_RarityDoubleRoll is Test {
    CauldronFactory factory;
    CauldronCollection col;
    address hookAddr = address(0x1400);

    function setUp() public {
        factory = new CauldronFactory();
        (address c,) = factory.deployBrew(
            CauldronFactory.Config({
                name: "Brew", symbol: "BREW", hook: hookAddr, registry: address(0x9E61),
                maxSupply: 3333, mode: MetadataMode.BaseURI, baseURI: "ipfs://x/",
                renderer: address(0), royaltyReceiver: address(0), royaltyBps: 0
            })
        );
        col = CauldronCollection(c);
    }

    /// A holder who lets the seed expire gets RE-ANCHORED, not a second draw.
    function test_Fixed_ExpiredSeedReAnchorsInsteadOfReRolling() public {
        vm.roll(1_000_000);
        vm.prank(hookAddr);
        uint256 id = col.mint(address(this));
        uint256 mb0 = col.mintBlockOf(id);

        // Let the seed age out of the 256-block blockhash window.
        vm.roll(mb0 + 300);
        assertEq(blockhash(mb0), bytes32(0), "seed really has expired");

        // FIXED: reveal does NOT roll from a predictable fallback. It re-anchors to
        // a fresh future block and leaves the token unrevealed (returning rather
        // than reverting, so the re-anchor actually persists).
        col.reveal(id);

        uint256 mb1 = col.mintBlockOf(id);
        assertGt(mb1, mb0, "FIXED: re-anchored to a fresh, still-unknowable block");
        assertFalse(col.revealed(id), "nothing was revealed from a known seed");

        // Once that new block is mined the reveal succeeds — exactly one draw.
        vm.roll(mb1 + 1);
        col.reveal(id);
        assertTrue(col.revealed(id), "FIXED: still revealable, forever");

        // ...and it is idempotent: no second bite at the rarity.
        uint8 first = col.rarityOf(id);
        col.reveal(id);
        assertEq(col.rarityOf(id), first, "FIXED: rarity is final once revealed");
    }

    /// The normal path is unchanged: reveal inside the window, one draw.
    function test_Fixed_NormalRevealStillWorks() public {
        vm.roll(1_000_000);
        vm.prank(hookAddr);
        uint256 id = col.mint(address(this));
        uint256 mb = col.mintBlockOf(id);
        vm.roll(mb + 1);
        col.reveal(id);
        assertTrue(col.revealed(id), "revealed in the ordinary case");
    }
}
