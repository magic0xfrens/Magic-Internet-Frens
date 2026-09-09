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

contract Stable6 is IERC20 {
    string public constant name = "Stable";
    string public constant symbol = "USDG";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) { balanceOf[msg.sender] -= a; balanceOf[to] += a; return true; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract Swapper {
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
                sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970342 - 1
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
        if (Currency.unwrap(c) == address(0)) { pm.settle{value: amt}(); }
        else { pm.sync(c); IERC20(Currency.unwrap(c)).transfer(address(pm), amt); pm.settle(); }
    }
    receive() external payable {}
}

/**
 * @dev REGRESSION test for R-1 — a non-ETH generation must not mint PHANTOM
 *      `relaunchETH`, and the fees it collects must have an exit.
 *
 *  `_takeEthFee` was generalised to collect on whichever side is the quote
 *  (CauldronHook.sol), so a USDG-quoted pool pays its fee in USDG, and
 *  `FeeRouteLib` moves the right asset. The RESIDUAL was not generalised: it was
 *  booked straight into `relaunchETH`, a wei counter paid out as NATIVE ether by
 *  `registry.call{value:}`. Nothing converted, and nothing checked the asset.
 *
 *  Two consequences, both permanent:
 *    1. Once the phantom exceeded the hook's real ETH balance,
 *       `releaseRelaunchETH` reverted. The counter is only zeroed INSIDE the
 *       call that reverts, so nothing self-corrected and the generation could
 *       never fund its successor — which is the whole protocol.
 *    2. The USDG actually collected had no exit at all: no release path, and
 *       `sweepLegacyReserve` is gated to a different counter.
 *
 *  The hook's own adoption-gate comment named this failure, and the
 *  `currency0 != address(0)` line that prevented it was removed when quotes were
 *  generalised. The fix splits the reserve by denomination (`relaunchETH` vs
 *  `relaunchAsset`) so that line can stay removed safely.
 *
 *  Run:
 *    export FORK_RPC=<sepolia> POOL_MANAGER=0x.. POSITION_MANAGER=0x..
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract AuditPoC6 -vv
 */
contract AuditPoC6_QuoteReserve is Test {
    using PoolIdLibrary for PoolKey;

    bool active;
    IPoolManager pm;
    CauldronHook hook;
    Stable6 usdg;
    Swapper swapper;

    /// @dev The hook reads this off its registry at adoption. This contract IS
    ///      the registry for the purposes of the test.
    function allowedQuote(address q) external view returns (bool) {
        return q == address(usdg) || q == address(0);
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
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

        usdg = new Stable6();
        swapper = new Swapper(pm);
        vm.deal(address(this), 200 ether);
    }

    function test_R1_NonEthFeeCreditsItsOwnAssetNotEth_OnFork() public {
        
        vm.skip(!active);
        address positionManager = vm.envAddress("POSITION_MANAGER");

        (address token, ) =
            PoolOps.deployTokenAbove("Gnome", "GNOME", 2, 777_000_000e18, address(usdg));
        usdg.mint(address(this), 5_000_000e6);

        PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 1_000_000e6, 1_000_000e18, 200, 0
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });

        // Precondition: a pure USDG generation. No ether, no reserve.
        assertEq(address(hook).balance, 0, "hook starts with no ETH");
        assertEq(hook.relaunchETH(), 0, "and no native reserve");

        // A single ordinary, taxable swap. The swapper is NOT tax-exempt, so it
        // pays the default 3% — in USDG, because USDG is the quote.
        usdg.mint(address(swapper), 100_000e6);
        swapper.swap(key, true, -10_000e6);

        uint256 held = usdg.balanceOf(address(hook));
        emit log_named_uint("relaunchETH (native)      ", hook.relaunchETH());
        emit log_named_uint("relaunchAsset[USDG]       ", hook.relaunchAsset(address(usdg)));
        emit log_named_uint("hook USDG actually held   ", held);

        // THE FIX: the reserve is booked in the asset it is denominated in, and
        // the native counter is untouched by a non-native fee.
        assertEq(hook.relaunchETH(), 0, "a USDG fee must not credit the ETH reserve");
        assertGt(held, 0, "the fee was collected");
        assertEq(
            hook.relaunchAsset(address(usdg)), held,
            "and booked 1:1 against the USDG the hook actually holds"
        );

        // The native release is no longer bricked — there is simply nothing
        // native to release, which is the honest answer for this generation.
        vm.expectRevert(CauldronHook.NoETHToRelease.selector);
        hook.releaseRelaunchETH();

        // And the value has an exit. `registry` is this contract (see setUp).
        uint256 before = usdg.balanceOf(address(this));
        uint256 got = hook.releaseRelaunchAsset(address(usdg));
        assertEq(got, held, "released the full reserve");
        assertEq(usdg.balanceOf(address(this)) - before, held, "the registry received it");
        assertEq(hook.relaunchAsset(address(usdg)), 0, "counter cleared");

        // Draining twice is refused, exactly like the native path.
        vm.expectRevert(CauldronHook.NoETHToRelease.selector);
        hook.releaseRelaunchAsset(address(usdg));
    }
}
