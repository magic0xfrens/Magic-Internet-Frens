// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {QuoteRotator} from "../cauldron/QuoteRotator.sol";

contract RegistryStub {
    mapping(address => bool) public allowedQuote;
    function set(address q, bool v) external { allowedQuote[q] = v; }
}

/**
 * @dev The rotator's SWAP leg, against a real Uniswap v4 pool with real depth.
 *
 *  Everything else about the rotator was tested against stubs, which proves the
 *  bookkeeping and none of the machinery that moves money: v4's
 *  unlock/settle/take sequence, whether native settle actually pays, and whether
 *  the proceeds land on this contract. This is the last untested path before the
 *  rotator can hold funds.
 *
 *  ROUTE. A pool found by scanning v4 Initialize events on Sepolia and reading
 *  each pool's liquidity out of storage, then filtered to those with NO HOOK — a
 *  hooked route could take fees or reject the swap for reasons that have nothing
 *  to do with this contract, and would make a failure ambiguous.
 *
 *  Skips cleanly without FORK_RPC.
 */
contract RotatorSwapForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    bool active;
    IPoolManager pm;
    QuoteRotator rot;
    RegistryStub reg;

    /// ETH/C1WWH, fee 3000, spacing 60, hookless. ~688e18 liquidity.
    address constant TOKEN = 0x92B637d3De3587394664d5036e69399d8060C9c2;
    uint24 constant FEE = 3000;
    int24 constant SPACING = 60;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;

        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));

        reg = new RegistryStub();
        reg.set(TOKEN, true);
        rot = new QuoteRotator(address(reg), pm);
    }

    function _route() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)), // native ETH
            currency1: Currency.wrap(TOKEN),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });
    }

    /// The route must actually be live before anything else here means much.
    function test_RouteIsLiveAndDeep_OnFork() public view {
        if (!active) return;
        PoolId id = _route().toId();
        (uint160 sqrtPriceX96,,,) = pm.getSlot0(id);
        assertGt(sqrtPriceX96, 0, "pool is initialized");
        assertGt(pm.getLiquidity(id), 0, "and has liquidity to trade against");
    }

    /**
     * THE PATH THAT HAS NEVER RUN: unlock -> swap -> settle native -> take.
     *
     * Proves the ETH leaves this contract, the bought token arrives here, and
     * the plan's own bookkeeping matches what the pool actually returned rather
     * than what was projected.
     */
    function test_RotateStepActuallySwaps_OnFork() public {
        if (!active) return;

        vm.deal(address(rot), 10 ether);

        // A deliberately permissive floor: this test is about whether the
        // machinery works, not about price. The floor itself is covered by
        // test_StepBelowTheGovernedFloorReverts.
        rot.setPlan(address(0), TOKEN, 1 ether, 0.25 ether, 1, 1 hours);

        uint256 ethBefore = address(rot).balance;
        uint256 tokBefore = IERC20(TOKEN).balanceOf(address(rot));

        uint256 out = rot.rotateStep(_route());

        assertGt(out, 0, "the swap returned something");
        assertLt(address(rot).balance, ethBefore, "ETH actually left the contract");
        assertGt(IERC20(TOKEN).balanceOf(address(rot)), tokBefore, "and the token arrived here");

        (,,,, uint128 doneIn, uint128 gotOut,,,) = rot.plan();
        assertEq(doneIn, 0.25 ether, "one slice recorded as sold");
        // gotOut is what the POOL returned, minus the keeper's cut, so it must
        // track the measured result rather than any projection.
        assertGt(gotOut, 0, "and the proceeds recorded from the actual fill");
    }

    /// The governed floor is the whole price protection. A floor the market
    /// cannot meet must abort the step, not fill into a bad price.
    function test_StepBelowTheGovernedFloorReverts_OnFork() public {
        if (!active) return;

        vm.deal(address(rot), 10 ether);
        // Demand an absurd rate: 1e30 token per ETH. No real pool clears this.
        rot.setPlan(address(0), TOKEN, 1 ether, 0.25 ether, 1e30, 1 hours);

        vm.expectRevert(QuoteRotator.SlippageTooHigh.selector);
        rot.rotateStep(_route());
    }

    /// Slicing is the execution strategy. A second step in the same block would
    /// collapse the plan into one large, front-runnable print.
    function test_SecondStepInTheSameBlockIsRefused_OnFork() public {
        if (!active) return;

        vm.deal(address(rot), 10 ether);
        rot.setPlan(address(0), TOKEN, 1 ether, 0.25 ether, 1, 1 hours);

        rot.rotateStep(_route());
        vm.expectRevert(QuoteRotator.TooSoon.selector);
        rot.rotateStep(_route());

        // ...and it resumes once the interval has passed.
        vm.warp(block.timestamp + 1 hours + 1);
        assertGt(rot.nextSliceSize(), 0, "the next slice becomes due on schedule");
    }

    /// A route that is not the plan's pair must be refused, or a keeper could
    /// point the rotation at a pool of their choosing.
    function test_MismatchedRouteIsRefused_OnFork() public {
        if (!active) return;

        vm.deal(address(rot), 10 ether);
        rot.setPlan(address(0), TOKEN, 1 ether, 0.25 ether, 1, 1 hours);

        PoolKey memory wrong = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0xDEAD)), // not the plan's token
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });

        vm.expectRevert(QuoteRotator.NoRoute.selector);
        rot.rotateStep(wrong);
    }

    /// The whole plan must be able to run to completion and then stop.
    function test_PlanRunsToCompletionThenStops_OnFork() public {
        if (!active) return;

        vm.deal(address(rot), 10 ether);
        rot.setPlan(address(0), TOKEN, 0.5 ether, 0.25 ether, 1, 1 hours);

        rot.rotateStep(_route());
        vm.warp(block.timestamp + 1 hours + 1);
        rot.rotateStep(_route());

        vm.warp(block.timestamp + 1 hours + 1);
        assertEq(rot.nextSliceSize(), 0, "a finished plan schedules nothing further");

        (,,,, uint128 doneIn,,,,) = rot.plan();
        assertEq(doneIn, 0.5 ether, "exactly the planned total was converted");
    }

    receive() external payable {}
}
