// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { Currency } from "v4-core/src/types/Currency.sol";
import { BalanceDelta, toBalanceDelta } from "v4-core/src/types/BalanceDelta.sol";
import { SwapParams } from "v4-core/src/types/PoolOperation.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { HookMiner } from "../../vendor/HookMiner.sol";
import { CauldronHook } from "../../CauldronHook.sol";
import { CauldronRegistry } from "../../CauldronRegistry.sol";
import { RedemptionExt } from "../../cauldron/RedemptionExt.sol";

/// @dev ERC20 with CONFIGURABLE decimals. The whole finding is that the hook's
///      trigger threshold is written in wei and compared against raw units of
///      whatever the live generation is quoted in, so the decimal count is the
///      independent variable and has to be settable.
contract F2Erc20 {
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(
        uint8 d
    ) {
        decimals = d;
    }

    function mint(
        address to,
        uint256 a
    ) external {
        balanceOf[to] += a;
        totalSupply += a;
    }

    function transfer(
        address to,
        uint256 a
    ) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function approve(
        address s,
        uint256 a
    ) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transferFrom(
        address f,
        address t,
        uint256 a
    ) external returns (bool) {
        allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}

/**
 * @dev Stub PoolManager. Answers the selectors {LegacyBuyLib.buyStep} uses
 *      (swap / sync / settle / take / extsload) and is the `onlyPoolManager`
 *      caller for the hook's callbacks.
 *
 *      Reports tick 0 (price 1.0) and fills the buy 1:1, which clears
 *      {LegacyBuyLib}'s `Slipped` backstop: the worst allowed price buys
 *      `spent * 0.9486^2 = 0.8998 * spent` and the guard demands 90% of that.
 *      `take` MINTS, so the hook really receives the token it bought — a stub
 *      that swallowed the take would make the buyback look free.
 */
contract F2PoolManagerStub {
    F2Erc20 public tokenOut;
    uint256 public lastNativeSettled;
    uint256 public lastErc20Settled;
    uint256 public lastTakenOut;

    function setTokenOut(
        F2Erc20 t
    ) external {
        tokenOut = t;
    }

    function swap(
        PoolKey calldata,
        SwapParams calldata p,
        bytes calldata
    ) external pure returns (BalanceDelta) {
        uint256 offered = uint256(-p.amountSpecified);
        // currency0 debit (we pay the quote), currency1 credit (we receive token), 1:1.
        return toBalanceDelta(-int128(int256(offered)), int128(int256(offered)));
    }

    function sync(
        Currency
    ) external { }

    /// @dev {StateLibrary.getSlot0}: 160 bits of sqrtPriceX96 then 24 bits of tick.
    function extsload(
        bytes32
    ) external pure returns (bytes32) {
        return bytes32(uint256(TickMath.getSqrtPriceAtTick(int24(0))));
    }

    function settle() external payable returns (uint256) {
        if (msg.value > 0) lastNativeSettled += msg.value;
        return msg.value;
    }

    function take(
        Currency c,
        address to,
        uint256 amount
    ) external {
        address a = Currency.unwrap(c);
        if (a != address(0) && address(tokenOut) == a) {
            lastTakenOut += amount;
            tokenOut.mint(to, amount);
        }
    }

    // --- drivers (the hook's callbacks are onlyPoolManager) ---
    function driveAfterInitialize(
        address hook_,
        address sender,
        PoolKey memory key
    ) external {
        CauldronHook(payable(hook_)).afterInitialize(sender, key, uint160(1 << 96), int24(0));
    }

    /// @dev A SELL leg: exact-input token -> quote, so the quote is the unspecified
    ///      currency and the hook charges its fee in `afterSwap` (CauldronHook:1072).
    ///      `quoteOut` is credited on currency0, which is where an allowlisted quote
    ///      that sorts below the mined iteration token sits.
    function driveSell(
        address hook_,
        PoolKey memory key,
        uint256 tokenIn,
        uint256 quoteOut
    ) external {
        SwapParams memory p = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(tokenIn),
            sqrtPriceLimitX96: uint160(TickMath.MAX_SQRT_PRICE - 1)
        });
        CauldronHook(payable(hook_))
            .afterSwap(
                address(this),
                key,
                p,
                toBalanceDelta(int128(int256(quoteOut)), -int128(int256(tokenIn))),
                ""
            );
    }

    receive() external payable { }
}

/**
 * @title F2A — the legacy floor buyback's trigger is written in WEI and compared
 *        against RAW UNITS of the live quote.
 *
 *  `CauldronHook.legacyThreshold` is declared `0.02 ether` (CauldronHook.sol:336)
 *  and is compared, unscaled, against `legacyBuffer` in two places:
 *
 *      CauldronHook.sol:1124   if (legacyBuffer < legacyThreshold) return;
 *      CauldronHook.sol:1173   if (amt < legacyThreshold) return;
 *
 *  `legacyBuffer` is raw units of `_liveKey.currency0` — the hook itself says so
 *  at CauldronHook.sol:1507-1517, where a fee is buffered only when
 *  `_feeAsset == Currency.unwrap(_liveKey.currency0)`. On a 6-decimal quote
 *  `0.02 ether` is 2e16 raw units = 20,000,000,000 USDG, so the comparison can
 *  never pass and the floor buyback silently never runs.
 *
 *  THE SKIP AT :1135 IS NOT WHAT STOPS IT. The comment above `if
 *  (!quoteIsCurrency0[id]) return;` claims the path is deliberately ETH-only
 *  because "the native settle would revert against an ERC20 quote anyway". That
 *  comment is STALE: {LegacyBuyLib.buyStep} settles `sync -> transfer -> settle`
 *  for a non-native quote (LegacyBuyLib.sol:263-275), and `quoteIsCurrency0` is
 *  recorded from the registry allowlist at CauldronHook.sol:660-663, so it is
 *  TRUE for an allowlisted ERC20 quote that sorts to currency0. The control
 *  below proves the ERC20 path runs end to end at 18 decimals; only the decimal
 *  count separates it from the 6-decimal case.
 *
 *  Rig: production `CauldronHook` + production `CauldronRegistry` bytecode.
 *  `legacyBuyStep` is reached exactly as the hook reaches it — a self-call
 *  (CauldronHook.sol:1165-1167), simulated with `vm.prank(address(hook))`.
 */
contract F2A_LegacyThresholdDecimals is Test {
    using PoolIdLibrary for PoolKey;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    F2PoolManagerStub internal pm;

    F2Erc20 internal usdg; // 6-decimal quote  -> currency0
    F2Erc20 internal dai; // 18-decimal quote -> currency0 (control)
    F2Erc20 internal brew; // iteration token  -> currency1

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    /// @dev The declared default (CauldronHook.sol:336). Re-asserted in setUp so a
    ///      change to it cannot quietly make this test measure something else.
    uint256 internal constant DECLARED_THRESHOLD = 0.02 ether;

    function setUp() public {
        pm = new F2PoolManagerStub();
        bytes memory ctorArgs = abi.encode(
            IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this)
        );
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{ salt: salt }(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        registry = new CauldronRegistry(address(pm), address(pm), address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));

        usdg = new F2Erc20(6);
        dai = new F2Erc20(18);
        brew = new F2Erc20(18);
        pm.setTokenOut(brew);

        registry.setAllowedQuote(address(usdg), true, 1e12);
        registry.setAllowedQuote(address(dai), true, 1);

        // Arm the buyback: 100% of the post-guild remainder, default threshold.
        hook.setLegacyBuyback(address(registry), 10_000, 0);
    }

    // ------------------------------------------------------------------ helpers

    function _key(
        address c0
    ) internal view returns (PoolKey memory k) {
        k = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(address(brew)),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
    }

    function _makeLive(
        PoolKey memory k
    ) internal {
        pm.driveAfterInitialize(address(hook), address(registry), k);
        vm.prank(address(registry));
        hook.setLiveKey(k);
    }

    /// @dev Fill the buffer through the REAL fee route: a sell leg whose quote
    ///      proceeds are `quoteOut`, repeated `n` times.
    function _fill(
        PoolKey memory k,
        uint256 quoteOut,
        uint256 n
    ) internal {
        for (uint256 i = 0; i < n; i++) {
            pm.driveSell(address(hook), k, 1e18, quoteOut);
        }
    }

    /// @dev Drive the buyback the way production does — a self-call — twice, in two
    ///      DIFFERENT blocks, because the first call on a pool only seeds
    ///      {LegacyBuyLib}'s price reference and deliberately spends nothing
    ///      (LegacyBuyLib.sol:212-213). Returns the buffer and the token bought
    ///      after the call that is actually allowed to spend.
    function _runBuyback(
        PoolKey memory k
    ) internal returns (uint256 bufferAfter, uint256 bought) {
        vm.prank(address(hook));
        hook.legacyBuyStep(k);

        uint256 t0 = vm.getBlockTimestamp();
        uint256 b0 = vm.getBlockNumber();
        vm.roll(b0 + 1);
        vm.warp(t0 + 12);
        // The warp/roll MUST have landed: under via_ir a stale stack slot has
        // silently defeated this before.
        assertEq(vm.getBlockNumber(), b0 + 1, "roll landed");
        assertEq(vm.getBlockTimestamp(), t0 + 12, "warp landed");

        uint256 before = brew.balanceOf(address(hook));
        vm.prank(address(hook));
        hook.legacyBuyStep(k);

        bufferAfter = hook.legacyBuffer();
        bought = brew.balanceOf(address(hook)) - before;
    }

    // -------------------------------------------------------------------- tests

    /// @notice CONTROL — an 18-decimal ERC20 quote at currency0 runs the buyback
    ///         end to end. This is what makes the 6-decimal case a DECIMALS bug
    ///         and not "the ERC20 path is switched off".
    function test_F2A_control_eighteenDecimalQuoteBuysBack() public {
        PoolKey memory k = _key(address(dai));
        _makeLive(k);

        // $100,000 of proceeds, 18 decimals -> 1e23 raw units.
        _fill(k, 100_000e18, 1);

        uint256 buffered = hook.legacyBuffer();
        // The hook must really hold what it buffered (the stub's `take` does not
        // mint the quote), or {LegacyBuyLib}'s free-balance clamp zeroes the buy.
        dai.mint(address(hook), buffered * 10);

        (uint256 bufferAfter, uint256 bought) = _runBuyback(k);

        console2.log("18-dec: buffered raw   ", buffered);
        console2.log("18-dec: threshold raw  ", DECLARED_THRESHOLD);
        console2.log("18-dec: buffer after   ", bufferAfter);
        console2.log("18-dec: token bought   ", bought);

        assertEq(hook.legacyBufferAsset(), address(dai), "buffered in the live quote");
        assertGt(buffered, DECLARED_THRESHOLD, "18-dec buffer clears the wei-written threshold");
        assertGt(bought, 0, "CONTROL: the ERC20 buyback really executes");
        assertLt(bufferAfter, buffered, "CONTROL: the buffer was spent");
    }

    /// @notice THE FINDING — the SAME dollar value, quoted in a 6-decimal stable,
    ///         can never reach a threshold written in wei.
    ///
    ///  `0.02 ether` = 2e16 raw units of a 6-decimal quote = 20,000,000,000 USDG.
    ///  A generation would have to buffer twenty billion dollars of fees before
    ///  the floor buyback fired once.
    function test_F2A_sixDecimalQuoteNeverReachesTheWeiWrittenThreshold() public {
        PoolKey memory k = _key(address(usdg));
        _makeLive(k);

        // $100,000 of proceeds, 6 decimals -> 1e11 raw units. Repeat it: even a
        // hundred such swaps stays ~5 orders of magnitude under 2e16.
        _fill(k, 100_000e6, 100);

        uint256 buffered = hook.legacyBuffer();
        usdg.mint(address(hook), buffered * 10);

        (uint256 bufferAfter, uint256 bought) = _runBuyback(k);

        uint256 dollarsBuffered = buffered / 1e6;
        uint256 dollarsNeeded = DECLARED_THRESHOLD / 1e6;

        console2.log("6-dec: buffered raw    ", buffered);
        console2.log("6-dec: buffered USD    ", dollarsBuffered);
        console2.log("6-dec: threshold raw   ", DECLARED_THRESHOLD);
        console2.log("6-dec: threshold USD   ", dollarsNeeded);
        console2.log("6-dec: buffer after    ", bufferAfter);
        console2.log("6-dec: token bought    ", bought);

        assertEq(hook.legacyBufferAsset(), address(usdg), "buffered in the live quote");
        assertGt(dollarsBuffered, 1000, "a real, large fee balance is sitting in the buffer");
        assertEq(
            dollarsNeeded,
            20_000_000_000,
            "the wei-written threshold is twenty billion dollars at 6 decimals"
        );

        // ---- the assertions that flip with the fix -------------------------
        //  MEASURED on the unfixed hook (this exact rig, `forge test -vv`):
        //      6-dec: buffer after    9900000000000   (unchanged)
        //      6-dec: token bought    0
        //  i.e. $9,900,000 of buffered fees and the floor buyback never fires.
        //
        //  MEASURED with `legacyThresholdRaw` in place:
        //      6-dec: buffer after    0
        //      6-dec: token bought    9900000000000
        assertGt(bought, 0, "REGRESSION: the floor buyback must fire on a 6-decimal quote");
        assertEq(bufferAfter, 0, "REGRESSION: the buffer must actually be spent");
    }
}
