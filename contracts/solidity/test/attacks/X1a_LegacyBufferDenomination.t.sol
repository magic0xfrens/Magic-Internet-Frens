// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";

/// @notice 6-decimal ERC20 standing in for an allowlisted quote (USDG-shaped).
contract X1Erc20 {
    string public name = "X1 Quote";
    string public symbol = "X1Q";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "X1Q: insufficient");
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "X1Q: insufficient");
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/**
 * @notice Stub PoolManager. It only has to answer the four selectors
 *         {LegacyBuyLib.buyStep} uses (swap / sync / settle / take) and to be the
 *         `onlyPoolManager` caller for the hook's callbacks. `capacity` models an
 *         exact-input swap with NO price limit: the pool absorbs up to the amount
 *         offered, and the hook must then really pay what it absorbed.
 */
contract X1PoolManagerStub {
    uint256 public capacity = type(uint128).max;
    uint256 public lastNativeSettled;
    uint256 public lastSwapAmountOffered;
    uint256 public lastSpentReported;
    Currency public lastSynced;

    function setCapacity(uint256 c) external { capacity = c; }

    function swap(PoolKey calldata, SwapParams calldata p, bytes calldata)
        external returns (BalanceDelta)
    {
        uint256 offered = uint256(-p.amountSpecified);
        lastSwapAmountOffered = offered;
        uint256 spent = offered > capacity ? capacity : offered;
        lastSpentReported = spent;
        // currency0 debit (negative to the swapper), currency1 credit (positive).
        return toBalanceDelta(-int128(int256(spent)), int128(int256(spent / 1_000)));
    }

    function sync(Currency c) external { lastSynced = c; }

    /// @dev {StateLibrary.getSlot0} reads the packed pool-state slot through this.
    ///      The buyback's slippage bound needs a live sqrt price: 1<<96 is price
    ///      1.0 at tick 0.
    function extsload(bytes32) external pure returns (bytes32) { return bytes32(uint256(1) << 96); }
    function settle() external payable returns (uint256) { lastNativeSettled = msg.value; return msg.value; }
    function take(Currency, address, uint256) external {}

    // --- drivers (the hook's callbacks are onlyPoolManager) ---
    function driveAfterInitialize(address hook_, address sender, PoolKey memory key) external {
        CauldronHook(payable(hook_)).afterInitialize(sender, key, uint160(1 << 96), int24(0));
    }

    function driveAfterSwap(address hook_, PoolKey memory key, SwapParams memory p) external {
        CauldronHook(payable(hook_)).afterSwap(address(this), key, p, toBalanceDelta(0, 0), "");
    }

    receive() external payable {}
}

/**
 * @title X1a — `legacyBuffer` is a denomination-less balance
 *
 *  `CauldronHook.fundLegacyBuffer()` (CauldronHook.sol:1096) is permissionless,
 *  `payable`, and credits `msg.value` — always NATIVE wei — into `legacyBuffer`.
 *  `legacyBuyStep` (CauldronHook.sol:1063) then spends that same integer through
 *  {LegacyBuyLib.buyStep}, which settles it in `key.currency0` of the LIVE pool,
 *  whatever that currency is.
 *
 *  Control: a native live pool settles wei for wei.
 *  Attack : an ERC20-quoted live pool settles the SAME integer as raw units of
 *           that ERC20, paid out of the hook's own balance.
 */
contract X1aLegacyBufferDenomination is Test {
    using PoolIdLibrary for PoolKey;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    X1PoolManagerStub internal pm;
    X1Erc20 internal quoteToken;   // 6-decimal quote
    X1Erc20 internal brewToken;    // iteration token (currency1)

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    uint256 internal constant DONATION = 0.05 ether; // > legacyThreshold (0.02 ether)

    function setUp() public {
        pm = new X1PoolManagerStub();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        registry = new CauldronRegistry(address(pm), address(pm), address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));

        // Arm the legacy buyback: any non-zero registry address turns it on.
        hook.setLegacyBuyback(address(registry), 500, 0.02 ether);

        quoteToken = new X1Erc20();
        brewToken = new X1Erc20();
        registry.setAllowedQuote(address(quoteToken), true, 1e12);
    }

    // ---------------------------------------------------------------- helpers
    function _key(address c0, address c1) internal view returns (PoolKey memory k) {
        k = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
    }

    /// @dev Adopt `k` through the real `_afterInitialize` gate and make it live.
    function _makeLive(PoolKey memory k) internal {
        pm.driveAfterInitialize(address(hook), address(registry), k);
        vm.prank(address(registry));
        hook.setLiveKey(k);
    }

    /// @dev Fire a swap callback on `k`; the buyback runs at the top of afterSwap.
    function _swap(PoolKey memory k) internal {
        SwapParams memory p =
            SwapParams({zeroForOne: true, amountSpecified: -int256(1e15), sqrtPriceLimitX96: uint160(4295128740)});
        pm.driveAfterSwap(address(hook), k, p);
    }

    // ------------------------------------------------------------------ tests

    /// @notice CONTROL: on a native live pool the buffer is spent as ether.
    function test_X1a_control_nativeLivePool_settlesWei() public {
        PoolKey memory k = _key(address(0), address(brewToken));
        _makeLive(k);

        hook.fundLegacyBuffer{value: DONATION}();
        uint256 hookEthBefore = address(hook).balance;

        _swap(k);

        uint256 settled = pm.lastNativeSettled();
        console2.log("control: native settled (wei)", settled);
        console2.log("control: buffer after", hook.legacyBuffer());
        assertEq(settled, DONATION, "native buyback must settle exactly the donated wei");
        assertEq(hook.legacyBuffer(), 0, "buffer consumed");
        assertEq(address(hook).balance, hookEthBefore - DONATION, "wei really left the hook");
    }

    /// @notice REGRESSION (was the attack): the same native donation on an
    ///         ERC20-quoted live pool is now REFUSED at the door. `legacyBuffer`
    ///         is spent as raw units of `currency0`, so wei may not enter it
    ///         while `currency0` is a token — and refusing (rather than keeping
    ///         value with no exit) is the point: nothing in this contract could
    ///         ever have paid that ether back out.
    function test_X1a_attack_erc20LivePool_spendsErc20ReserveForNativeDonation() public {
        PoolKey memory k = _key(address(quoteToken), address(brewToken));
        _makeLive(k);

        // The hook's per-asset relaunch reserve for this quote (fees it collected).
        // 5,000 USDG at 6 decimals.
        uint256 reserve = 5_000e6;
        quoteToken.mint(address(hook), reserve);

        address attacker = address(0xA11CE);
        vm.deal(attacker, 1 ether);

        vm.prank(attacker);
        vm.expectRevert(CauldronHook.BadParam.selector);
        hook.fundLegacyBuffer{value: DONATION}();

        console2.log("regression: buffer after refused donation", hook.legacyBuffer());
        assertEq(hook.legacyBuffer(), 0, "no wei entered a buffer spent as ERC20 units");
        assertEq(attacker.balance, 1 ether, "the donor keeps the ether instead of stranding it");

        // Nothing is armed, so a swap cannot point a wei-sized number at the quote.
        pm.setCapacity(reserve);
        uint256 erc20Before = quoteToken.balanceOf(address(hook));
        _swap(k);
        console2.log("regression: quote drained", erc20Before - quoteToken.balanceOf(address(hook)));
        assertEq(quoteToken.balanceOf(address(hook)), erc20Before, "not one raw unit of the reserve moved");
        assertEq(pm.lastSwapAmountOffered(), 0, "no buyback swap was attempted at all");
    }

    /// @notice REGRESSION: the other half of the mechanism — a buffer funded
    ///         while the generation was NATIVE-quoted, then a quote rotation
    ///         underneath it. The stale wei must not be spent as the new quote,
    ///         and it must not sit there unreachable either: it is rolled into
    ///         `relaunchETH`, a counter that HAS a payout path.
    function test_X1a_rotationReclaimsTheStaleBufferInsteadOfSpendingTheQuote() public {
        PoolKey memory nk = _key(address(0), address(brewToken));
        _makeLive(nk);

        hook.fundLegacyBuffer{value: DONATION}();
        assertEq(hook.legacyBuffer(), DONATION, "funded while native-quoted");
        assertEq(hook.legacyBufferAsset(), address(0), "and tagged as native");

        // The treasury rotates the live generation onto a 6-decimal ERC20.
        PoolKey memory ek = _key(address(quoteToken), address(brewToken));
        vm.prank(address(registry));
        hook.setLiveKey(ek);

        uint256 reserve = 5_000e6;
        quoteToken.mint(address(hook), reserve);
        pm.setCapacity(reserve);

        _swap(nk);

        console2.log("regression: buffer after rotation", hook.legacyBuffer());
        console2.log("regression: relaunchETH          ", hook.relaunchETH());
        assertEq(hook.legacyBuffer(), 0, "stale buffer drained");
        assertEq(hook.relaunchETH(), DONATION, "into the counter that can actually pay it out");
        assertEq(quoteToken.balanceOf(address(hook)), reserve, "not one raw unit of quote was spent");
        assertEq(pm.lastSwapAmountOffered(), 0, "no buyback swap was attempted");
    }
}
