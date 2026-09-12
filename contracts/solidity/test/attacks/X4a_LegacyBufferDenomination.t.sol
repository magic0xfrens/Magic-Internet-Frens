// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";

/// @dev 6-decimal stablecoin quote, the shape the whole FeeRouteLib/LegacyBuyLib
///      refactor exists to support.
contract X4Token {
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    constructor(uint8 d) { decimals = d; }
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// @dev Minimal PoolManager standing in for the live book. `swap` fills the whole
///      exact-input amount, so `spent == amt` exactly as a deep pool would.
contract X4PoolManagerMock {
    X4Token public outToken;
    uint256 public outAmount;
    uint256 public nativeSettled;

    function configure(X4Token t, uint256 a) external { outToken = t; outAmount = a; }

    function swap(PoolKey calldata, SwapParams calldata p, bytes calldata) external view returns (BalanceDelta) {
        uint256 amtIn = uint256(-p.amountSpecified);
        return toBalanceDelta(-int128(int256(amtIn)), int128(int256(outAmount)));
    }
    function sync(Currency) external {}
    /// @dev {StateLibrary.getSlot0} reads the packed pool-state slot through this.
    ///      The buyback's slippage bound needs a live sqrt price: 1<<96 = price 1.0.
    function extsload(bytes32) external pure returns (bytes32) { return bytes32(uint256(1) << 96); }
    function settle() external payable returns (uint256) { nativeSettled += msg.value; return msg.value; }
    function take(Currency, address to, uint256 amount) external { outToken.mint(to, amount); }
    receive() external payable {}
}

/**
 * X4a — `legacyBuffer` is a SINGLE counter written in native wei by a
 *       permissionless payable entrypoint (CauldronHook.fundLegacyBuffer, the
 *       RoyaltyRouter's only exit) but SPENT in whatever the live pool is quoted
 *       in (LegacyBuyLib.buyStep branches on key.currency0).
 *
 *  The rig is the production bytecode of CauldronHook with a stub PoolManager.
 *  `legacyBuyStep` is reached exactly the way the hook reaches it: a self-call
 *  (`address(this).call(...)`, CauldronHook.sol:1035-1037), simulated with
 *  vm.prank(address(hook)).
 */
contract X4a_LegacyBufferDenomination is Test {
    CauldronHook internal hook;
    X4PoolManagerMock internal pm;
    X4Token internal usdg;   // 6-decimal quote  (currency0 on a rotated generation)
    X4Token internal brew;   // iteration token  (currency1)

    address internal constant ROYALTY_PAYER = address(0xA0A1);

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    function setUp() public {
        pm = new X4PoolManagerMock();
        usdg = new X4Token(6);
        brew = new X4Token(18);

        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        // Be the registry so `setLiveKey` is callable (registry-only, hook:1823).
        hook.setRegistry(address(this));
        hook.setLegacyBuyback(address(0xBEEF), 2_000, 0.02 ether);
    }

    function _liveKeyFor(address quote) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(address(brew)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    // ── control: on a NATIVE generation the buffer IS native and spends native ──
    function _nativeRoundTrip(uint256 donation) internal returns (uint256 ethSpent, uint256 bufferAfter) {
        hook.setLiveKey(_liveKeyFor(address(0)));
        pm.configure(brew, 500e18);

        vm.deal(ROYALTY_PAYER, donation);
        vm.prank(ROYALTY_PAYER);
        hook.fundLegacyBuffer{value: donation}();

        //  THE FIRST BUYBACK ON A POOL ONLY SEEDS THE PRICE REFERENCE and spends
        //  nothing (red-team T-1). Drive it, roll a block, then measure the buyback
        //  that actually runs — every assertion on the control is unchanged.
        vm.prank(address(hook));
        hook.legacyBuyStep(_liveKeyFor(address(0)));
        vm.roll(vm.getBlockNumber() + 1);

        uint256 balBefore = address(hook).balance;
        vm.prank(address(hook));
        hook.legacyBuyStep(_liveKeyFor(address(0)));
        ethSpent = balBefore - address(hook).balance;
        bufferAfter = hook.legacyBuffer();
    }

    // ── regression: the same donation on an ERC20-quoted generation is REFUSED ──
    struct Result {
        uint256 bufferAfterDonation;
        uint256 usdgRawPaidToPool;
        uint256 hookEthAfter;
        uint256 payerEthAfter;
        uint256 hookUsdgAfter;
        uint256 relaunchEthAfter;
    }

    function _erc20RoundTrip(uint256 donation, uint256 hookUsdgReserve) internal returns (Result memory r) {
        PoolKey memory live = _liveKeyFor(address(usdg));
        hook.setLiveKey(live);
        pm.configure(brew, 500e18);

        // The hook already holds USDG: accrued swap fees booked to
        // `relaunchAsset[USDG]` by `_creditReserve`.
        usdg.mint(address(hook), hookUsdgReserve);

        // A marketplace pays an NFT secondary royalty; RoyaltyRouter.receive
        // forwards the whole msg.value into this entrypoint. It is ACCEPTED but
        // ROUTED: the buffer is spent as raw units of the live currency0, so the
        // wei goes to `relaunchETH`, which `releaseRelaunchETH` can pay out.
        vm.deal(ROYALTY_PAYER, donation);
        vm.prank(ROYALTY_PAYER);
        hook.fundLegacyBuffer{value: donation}();
        r.bufferAfterDonation = hook.legacyBuffer();
        r.relaunchEthAfter = hook.relaunchETH();

        uint256 poolUsdgBefore = usdg.balanceOf(address(pm));
        vm.prank(address(hook));
        (bool ok, ) = address(hook).call(abi.encodeWithSelector(hook.legacyBuyStep.selector, live));
        assertTrue(ok, "an empty buffer is a clean no-op, not a revert");

        r.usdgRawPaidToPool = usdg.balanceOf(address(pm)) - poolUsdgBefore;
        r.hookEthAfter = address(hook).balance;
        r.payerEthAfter = ROYALTY_PAYER.balance;
        r.hookUsdgAfter = usdg.balanceOf(address(hook));
    }

    /// @dev The other half of the mechanism: a buffer legitimately funded in WEI
    ///      while the generation was native-quoted, and then a quote rotation
    ///      underneath it. The spender must REFUSE rather than pay the wei figure
    ///      out in raw units of the new 6-decimal quote.
    function _rotationStrand(uint256 donation, uint256 realisticReserve)
        internal
        returns (bool reverted, uint256 usdgMoved, uint256 bufferAfter)
    {
        hook.setLiveKey(_liveKeyFor(address(0)));
        pm.configure(brew, 500e18);

        vm.deal(ROYALTY_PAYER, donation);
        vm.prank(ROYALTY_PAYER);
        hook.fundLegacyBuffer{value: donation}();

        PoolKey memory live = _liveKeyFor(address(usdg));
        hook.setLiveKey(live);
        usdg.mint(address(hook), realisticReserve);

        uint256 poolUsdgBefore = usdg.balanceOf(address(pm));
        vm.prank(address(hook));
        (bool ok, ) = address(hook).call(abi.encodeWithSelector(hook.legacyBuyStep.selector, live));
        reverted = !ok;
        usdgMoved = usdg.balanceOf(address(pm)) - poolUsdgBefore;
        bufferAfter = hook.legacyBuffer();
    }

    function test_royalty_eth_is_spent_as_quote_token_and_stranded() public {
        uint256 donation = 1 ether;

        (uint256 ethSpent, uint256 nativeBufferAfter) = _nativeRoundTrip(donation);

        // fresh hook state for the ERC20 leg
        setUp();
        Result memory r = _erc20RoundTrip(donation, 2_000e6);

        // CONTROL — native generation: unchanged, the wei donated is the wei spent.
        assertEq(ethSpent, donation, "native: buffer spends the donated ETH");
        assertEq(nativeBufferAfter, 0, "native: buffer consumed");

        // REGRESSION — ERC20 generation.
        assertEq(r.bufferAfterDonation, 0, "no wei entered a buffer spent as USDG");
        assertEq(r.usdgRawPaidToPool, 0, "the hook paid no raw USDG units for a wei donation");
        assertEq(r.hookUsdgAfter, 2_000e6, "the quote reserve is untouched");
        assertEq(r.hookEthAfter, donation, "the hook holds the ether...");
        assertEq(r.relaunchEthAfter, donation, "...and relaunchETH claims it, so releaseRelaunchETH can pay it out");
        assertEq(r.payerEthAfter, 0, "the royalty was ACCEPTED, not bounced: a sale must never revert");

        emit log_named_uint("control: wei spent on a native generation", ethSpent);
        emit log_named_uint("regression: buffer after a refused 1 ETH royalty", r.bufferAfterDonation);
        emit log_named_uint("regression: RAW USDG units paid to the pool", r.usdgRawPaidToPool);
        emit log_named_uint("regression: ether claimed by relaunchETH", r.relaunchEthAfter);
    }

    function test_dust_royalty_permanently_bricks_the_floor_buyback() public {
        // 0.02 ether of wei buffered while native-quoted, then a rotation onto a
        // 6-decimal quote with 10,000 USDG of accrued fees sitting in the hook.
        (bool reverted, uint256 usdgMoved, uint256 bufferAfter) = _rotationStrand(0.02 ether, 10_000e6);

        assertTrue(reverted, "the spender refuses a buffer denominated in something else");
        assertEq(usdgMoved, 0, "not one raw unit of the 6-decimal quote moved");
        assertEq(bufferAfter, 0.02 ether, "and the wei is preserved, not zeroed into nothing");

        emit log_named_uint("regression: raw quote units moved", usdgMoved);
        emit log_named_uint("regression: buffer preserved (wei)", bufferAfter);
    }

    receive() external payable {}
}
