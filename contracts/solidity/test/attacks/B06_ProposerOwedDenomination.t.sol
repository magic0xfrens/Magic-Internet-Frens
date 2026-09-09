// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

/// @dev An 18-decimal quote worth LESS than ether — the shape of `xNVDA` in the
///      live manifest (indexer/deployments/round.json: 18 decimals, "Nvidia
///      (synthetic)"). The decimals are what matter; the price only sets the
///      multiplier on the overpayment.
contract Quote18 is IERC20 {
    string public constant name = "Synthetic Equity";
    string public constant symbol = "XNVDA";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract B06Swapper {
    IPoolManager public immutable pm;

    constructor(IPoolManager _pm) { pm = _pm; }

    function swap(PoolKey memory key, bool zeroForOne, int256 amount) external payable {
        pm.unlock(abi.encode(key, zeroForOne, amount));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (PoolKey memory key, bool zeroForOne, int256 amount) =
            abi.decode(data, (PoolKey, bool, int256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne
                    ? 4295128740
                    : 1461446703485210103287273052203988822378723970342 - 1
            }),
            ""
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        if (a0 < 0) _pay(key.currency0, uint256(uint128(-a0)));
        if (a1 < 0) _pay(key.currency1, uint256(uint128(-a1)));
        if (a0 > 0) pm.take(key.currency0, address(this), uint256(uint128(a0)));
        if (a1 > 0) pm.take(key.currency1, address(this), uint256(uint128(a1)));
        return "";
    }

    function _pay(Currency c, uint256 amt) private {
        if (Currency.unwrap(c) == address(0)) pm.settle{value: amt}();
        else { pm.sync(c); IERC20(Currency.unwrap(c)).transfer(address(pm), amt); pm.settle(); }
    }

    receive() external payable {}
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-06 — `proposerOwed` MIXED DENOMINATIONS, PAID OUT IN ETHER [HIGH — FIXED]
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  FIX (asserted below): the proposer carve is now NATIVE-ONLY —
 *  `address prop = _feeAsset == address(0) ? activeProposer : address(0);`
 *  (CauldronHook.sol, `_routeEthFee`). The skipped slice is not lost: it stays in
 *  `feeAmount` and lands in `relaunchAsset[]` through `_creditReserve`, which has
 *  an exit via `releaseRelaunchAsset`. Skipping rather than adding a second
 *  per-asset mapping is deliberate — the hook had 22 bytes of EIP-170 headroom.
 *
 *  The registry ALSO now wraps `hook.releaseRelaunchETH()` in try/catch, so even
 *  a future desynchronisation of that counter degrades to "seed with less"
 *  instead of freezing the rebirth.
 *
 *
 *  CauldronHook.sol:1162-1170 (accrual) and :1882-1889 (payout).
 *
 *  `_routeEthFee` carves the proposer slice off the TOP of every fee, BEFORE any
 *  `_feeAsset` check:
 *
 *      address prop = activeProposer;
 *      if (prop != address(0) && proposerBps > 0) {
 *          uint256 wantProp = (feeAmount * proposerBps) / BPS;
 *          proposerOwed[prop] += wantProp;          // <-- units of _feeAsset
 *
 *  `feeAmount` is denominated in whatever asset the fee was collected in — the
 *  hook took it with `poolManager.take(feeCur, ...)` at :1348-1350, where
 *  `feeCur` is the pool's quote. But the claim is unconditionally NATIVE:
 *
 *      function claimProposerFees() external nonReentrant returns (uint256) {
 *          amount = proposerOwed[msg.sender];
 *          proposerOwed[msg.sender] = 0;
 *          (bool ok, ) = msg.sender.call{value: amount}("");   // <-- WEI
 *
 *  So `N` base units of an ERC20 quote are paid out as `N` wei of ether. Every
 *  OTHER sink in the same function was generalised for this exact reason — the
 *  guild slice goes through `FeeRouteLib.routeSplit` (:1244), the floor share is
 *  explicitly folded into the per-asset reserve (:1232-1241, citing audit Q-01),
 *  and the residual goes through `_creditReserve` (:1146-1151, citing audit R-1),
 *  which branches on `_feeAsset`. The proposer carve sits ABOVE all of them and
 *  was never converted.
 *
 *  ── TWO INDEPENDENT HARMS ────────────────────────────────────────────────
 *
 *  1. OVERPAYMENT / THEFT. For an 18-decimal quote worth less than ether the
 *     proposer is paid `ETH_price / quote_price` times what they earned, in real
 *     ether, out of the hook's balance. The live manifest ships xNVDA at 18
 *     decimals. (A 6-decimal quote like USDG errs the other way — the proposer is
 *     underpaid ~1e12x — so the bug is not "small in one direction", it is
 *     unbounded in both.)
 *
 *  2. THE RESERVE LOSES ITS BACKING, AND RELAUNCH BRICKS. `relaunchETH` is
 *     tracked by counter, not by balance (CauldronHook.sol:249-255: "a figure
 *     booked here must be ether the hook actually holds"). A non-native fee
 *     credits `proposerOwed` without adding one wei to the hook, so claiming it
 *     drains ether that was backing `relaunchETH`. Once the balance falls below
 *     the counter, `releaseRelaunchETH()` fails its send and reverts `SendFailed`
 *     — and `relaunch()` calls it UNGUARDED at CauldronRegistry.sol:782-784:
 *
 *         if (hook.relaunchETH() > 0) { ethFromHook = hook.releaseRelaunchETH(); }
 *
 *     That revert rolls back `governor.markConsumed(winId)` (:825), so the same
 *     proposal wins forever and the machine is permanently bricked — the same
 *     terminal state as B-05, reached by a different road.
 *
 *  ── REACHABILITY ─────────────────────────────────────────────────────────
 *  A non-native pool that the hook SERVES is reachable today without touching
 *  the (bricked) non-ETH relaunch path: `RedemptionExt.rotateSlice` is
 *  PERMISSIONLESS within the treasury governor's approved envelope and calls
 *  `PoolOps.openOrAddPair` + `hook.linkVolume` directly, so a guild-approved
 *  rotation into USDG/xNVDA creates a tracked sibling pool whose fees are
 *  collected in that asset. `activeProposer` is attacker-reachable by
 *  construction — anyone may propose, and the winner is pushed to the hook at
 *  CauldronRegistry.sol:844.
 *
 *  ── WHY NO TEST CAUGHT IT ────────────────────────────────────────────────
 *  test/audit/AuditPoC6_QuoteReserve.t.sol is the one test that drives a
 *  non-native fee through the hook, and it never sets `activeProposer` or
 *  `guild` — so `wantProp` is always 0 there and the carve is never exercised.
 *  Its closing assertion, `relaunchAsset[USDG] == held`, only holds BECAUSE the
 *  proposer slice is absent; with a proposer set, the hook books more than it
 *  holds.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B06_ProposerOwedDenomination is Test {
    using PoolIdLibrary for PoolKey;

    bool internal active;
    IPoolManager internal pm;
    CauldronHook internal hook;
    Quote18 internal xq;
    B06Swapper internal swapper;
    address internal positionManager;

    address internal constant PROPOSER = address(0xBEEF);

    /// @dev The hook reads this off its registry at adoption. This contract IS the
    ///      registry for the purposes of the test (same pattern as AuditPoC6).
    function allowedQuote(address q) external view returns (bool) {
        return q == address(xq) || q == address(0);
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(
            IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this)
        );
        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );

        hook.setRegistry(address(this));
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true); // the LP-adder, not the swapper

        xq = new Quote18();
        swapper = new B06Swapper(pm);
        vm.deal(address(this), 500 ether);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  THE INVARIANT — the reason the fix exists
    // ───────────────────────────────────────────────────────────────────────

    /// @notice INVARIANT: the hook must never owe more NATIVE ether than it holds.
    ///         Every native-denominated counter (`relaunchETH`, `legacyBuffer`,
    ///         `proposerOwed`) is paid out with `call{value:}`, so their sum is a
    ///         claim on real balance. A fee collected in an ERC20 quote adds no
    ///         ether, so it must not increase any of them.
    ///
    ///  Pre-fix this failed 315000000000000000 > 300000000000000000 after a single
    ///  xNVDA swap.
    function test_FIXED_B06_NativeClaimsNeverExceedNativeBalance() public {
        vm.skip(!active);

        _seedNativeReserve();
        uint256 nativeBefore = address(hook).balance;

        _swapOnQuotePool();

        uint256 owed = hook.relaunchETH() + hook.legacyBuffer() + hook.proposerOwed(PROPOSER);
        assertEq(address(hook).balance, nativeBefore, "an xNVDA fee adds no ether");
        assertLe(owed, address(hook).balance, "hook must never owe more ether than it holds");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  THE FIX — the carve is native-only
    // ───────────────────────────────────────────────────────────────────────

    /// @notice The proposer must NOT be credited off a non-native fee. Pre-fix,
    ///         1.65e16 xNVDA base units were credited and `claimProposerFees` paid
    ///         the same integer out as real wei.
    function test_FIXED_B06_QuoteFeeDoesNotCreditTheProposer() public {
        vm.skip(!active);

        _seedNativeReserve();
        uint256 owedBefore = hook.proposerOwed(PROPOSER); // from the NATIVE seed swap
        uint256 hookEthBefore = address(hook).balance;

        _swapOnQuotePool();

        assertEq(
            hook.proposerOwed(PROPOSER),
            owedBefore,
            "an xNVDA fee must not move a wei-denominated counter"
        );
        assertEq(address(hook).balance, hookEthBefore, "and brings no ether either");
    }

    /// @notice The skipped slice is NOT lost. It stays in `feeAmount` and lands in
    ///         the per-asset reserve via `_creditReserve`, still backing the
    ///         generation and still exiting through `releaseRelaunchAsset`.
    function test_FIXED_B06_SkippedSliceLandsInTheAssetReserve() public {
        vm.skip(!active);

        _seedNativeReserve();
        _swapOnQuotePool();

        uint256 booked = hook.relaunchAsset(address(xq));
        uint256 held = xq.balanceOf(address(hook));
        assertGt(booked, 0, "the xNVDA fee was booked");
        assertEq(booked, held, "and booked 1:1 against the xNVDA actually held");
    }

    /// @notice The feature is preserved where it is sound: a NATIVE fee still
    ///         credits the proposer, and the claim still pays. The fix must not
    ///         have silently disabled the proposer flywheel outright.
    function test_FIXED_B06_NativeFeeStillPaysTheProposer() public {
        vm.skip(!active);

        _seedNativeReserve(); // native pool + one taxed native swap

        uint256 owed = hook.proposerOwed(PROPOSER);
        assertGt(owed, 0, "a native fee still carves the proposer slice");

        uint256 before = PROPOSER.balance;
        vm.prank(PROPOSER);
        uint256 claimed = hook.claimProposerFees();
        assertEq(claimed, owed, "claim pays the accrued amount");
        assertEq(PROPOSER.balance - before, owed, "in ether, correctly denominated");
    }

    /// @notice REGRESSION (the consequence that made B-06 High rather than Medium):
    ///         the native reserve must stay backed, so `releaseRelaunchETH()` — which
    ///         `relaunch()` calls at CauldronRegistry.sol:782-784 — still succeeds
    ///         after arbitrary non-native volume. Pre-fix, claiming the xNVDA-derived
    ///         credit drained the reserve's backing and this reverted `SendFailed`,
    ///         rolling back `markConsumed` and bricking the machine like B-05.
    function test_FIXED_B06_ReserveStaysBackedSoTheReleaseSucceeds() public {
        vm.skip(!active);

        _seedNativeReserve();
        for (uint256 i; i < 6; ++i) _swapOnQuotePool();

        // Claim everything the proposer is owed (all of it native-derived now).
        if (hook.proposerOwed(PROPOSER) > 0) {
            vm.prank(PROPOSER);
            hook.claimProposerFees();
        }

        uint256 reserve = hook.relaunchETH();
        assertGe(address(hook).balance, reserve, "reserve must remain fully backed");

        // The registry's pull succeeds. (This contract IS the registry — see setUp.)
        uint256 got = hook.releaseRelaunchETH();
        assertEq(got, reserve, "the full reserve is released");
        assertEq(hook.relaunchETH(), 0, "and the counter clears");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  Helpers
    // ───────────────────────────────────────────────────────────────────────

    /// @dev Build a NATIVE-quoted pool and trade it, so the hook accrues a genuine
    ///      `relaunchETH` reserve backed by real ether — the state every live
    ///      generation is in.
    function _seedNativeReserve() private {
        (address tokenA,) = PoolOps.deployTokenAbove("Gnome", "GNOME", 1, 777_000_000e18, address(0));

        // PoolOps is a LINKED library reached by delegatecall, so it spends this
        // contract's own ether for the native leg — no `{value:}` (and none is
        // permitted on a library call).
        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            tokenA, address(0), 60 ether, 60_000_000e18, 200, 0
        );

        PoolKey memory ethKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(tokenA),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });

        // The proposer slice is only carved once a proposer is set — the live
        // registry pushes this at every relaunch (CauldronRegistry.sol:844).
        hook.setActiveProposer(PROPOSER);

        // Past the anti-snipe window (30 blocks) so this is an ordinary 3% fee,
        // not the ~99% launch surtax — the steady state a live generation trades in.
        vm.roll(block.number + 31);

        vm.deal(address(swapper), 50 ether);
        swapper.swap(ethKey, true, -10 ether);

        require(hook.relaunchETH() > 0, "native reserve seeded");
        require(address(hook).balance > 0, "hook holds real ether");
    }

    address private _qToken;
    PoolKey private _qKey;

    /// @dev Build (once) an xNVDA-quoted pool the hook serves, and trade it. This is
    ///      the state a guild-approved `rotateSlice` puts the protocol in.
    function _swapOnQuotePool() private {
        if (_qToken == address(0)) {
            (_qToken,) = PoolOps.deployTokenAbove("Wraith", "WRAITH", 2, 777_000_000e18, address(xq));
            xq.mint(address(this), 5_000_000e18);
            PoolOps.openOrAddPair(
                pm, IPositionManagerOps(positionManager), address(hook),
                _qToken, address(xq), 1_000_000e18, 1_000_000e18, 200, 0
            );
            _qKey = PoolKey({
                currency0: Currency.wrap(address(xq)),
                currency1: Currency.wrap(_qToken),
                fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
            });
            xq.mint(address(swapper), 2_000_000e18);
            // Past this pool's own anti-snipe window too, so the fee is the
            // ordinary 3% and the credit is a realistic steady-state figure.
            vm.roll(block.number + 31);
        }
        swapper.swap(_qKey, true, -100e18);
    }

    receive() external payable {}
}
