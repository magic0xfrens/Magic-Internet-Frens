// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";

interface IX4Unlock { function unlockCallback(bytes calldata) external returns (bytes memory); }

contract X4bToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract X4bRegistry {
    address public q;
    address public tok;
    constructor(address _q, address _t) { q = _q; tok = _t; }
    function currentToken() external view returns (address) { return tok; }
    function currentGeneration() external pure returns (uint256) { return 1; }
    function generationQuote(uint256) external view returns (address) { return q; }
}

contract X4bHook {
    function commitCrystals(address, uint256, uint256) external pure returns (uint256) { return 0; }
    function resolveTickets(uint256) external pure returns (uint256, uint256) { return (0, 0); }
    function crystalsReady(address) external pure returns (uint256) { return 0; }
    function costOfNextCrystals(uint256) external pure returns (uint256) { return 0; }
    function buyWeightBps() external pure returns (uint256) { return 15_000; }
}

/// @dev A pool that FILLS ONLY `fillBps` of an exact-input buy — the state
///      `LegacyBuyLib.sol:65-70` explicitly says the code must handle ("If the
///      price limit ever binds, the pool consumes LESS than `amt`").
contract X4bPoolManager {
    X4bToken public brew;
    uint256 public fillBps = 10_000;
    bool public isNativeQuote;
    X4bToken public quoteToken;

    constructor(X4bToken _brew) { brew = _brew; }
    function setFill(uint256 b) external { fillBps = b; }
    function setQuote(bool native_, X4bToken q) external { isNativeQuote = native_; quoteToken = q; }

    function unlock(bytes calldata data) external returns (bytes memory) {
        return IX4Unlock(msg.sender).unlockCallback(data);
    }

    function swap(PoolKey calldata, SwapParams calldata p, bytes calldata)
        external view returns (BalanceDelta)
    {
        uint256 want = uint256(-p.amountSpecified);
        if (p.zeroForOne) {
            uint256 filled = (want * fillBps) / 10_000;      // quote consumed
            return toBalanceDelta(-int128(int256(filled)), int128(int256(filled * 2)));
        }
        return toBalanceDelta(int128(int256(want / 2)), -int128(int256(want)));
    }
    function sync(Currency) external {}
    function settle() external payable returns (uint256) { return msg.value; }
    function take(Currency c, address to, uint256 amount) external {
        if (Currency.unwrap(c) == address(0)) { (bool ok,) = to.call{value: amount}(""); require(ok); }
        else if (Currency.unwrap(c) == address(brew)) brew.mint(to, amount);
        else quoteToken.mint(to, amount);
    }
    receive() external payable {}
}


/**
 * X4b REGRESSION — this file was the PoC; the assertions are inverted now that
 *       the fix has landed. Name and path kept so the finding stays greppable.
 *
 *       `CauldronGachaRouter._churn` used to set `ethBal = 0` after every buy
 *       leg instead of debiting what the pool actually consumed, so any
 *       unconsumed quote was dropped from the returned leftover and never
 *       refunded — while `_play` on the identical state refunded
 *       `spend - ethConsumed`. On an ERC20 generation the confiscated quote had
 *       no exit at all: `rescueETH` is native-only and there was no
 *       `rescueToken`.
 *
 *       These tests now assert the refund ARRIVES, on both quote denominations
 *       and at both fill levels, and that the ERC20 rescue exists and is gated.
 *       Restore `ethBal = 0;` at CauldronGachaRouter._churn and they fail.
 */
contract X4b_ChurnConfiscatesRefund is Test {
    X4bToken internal brew;
    X4bToken internal usdg;
    X4bPoolManager internal pm;
    X4bRegistry internal regNative;
    X4bRegistry internal regErc;
    X4bHook internal hookStub;

    address internal constant PLAYER = address(0x9111);

    function setUp() public {
        brew = new X4bToken();
        usdg = new X4bToken();
        pm = new X4bPoolManager(brew);
        hookStub = new X4bHook();
        regNative = new X4bRegistry(address(0), address(brew));
        regErc = new X4bRegistry(address(usdg), address(brew));
        vm.deal(address(pm), 100 ether);
    }

    function _router(X4bRegistry r) internal returns (CauldronGachaRouter) {
        return new CauldronGachaRouter(IPoolManager(address(pm)), address(hookStub), address(r), address(this));
    }

    /// CONTROL: `play()` on a 60%-filled pool refunds the remainder.
    function _playRefund(uint256 send_) internal returns (uint256 refunded, uint256 strandedInRouter) {
        CauldronGachaRouter router = _router(regNative);
        pm.setQuote(true, X4bToken(address(0)));
        pm.setFill(6_000);
        vm.deal(PLAYER, send_);
        uint256 before = PLAYER.balance;
        vm.prank(PLAYER);
        router.play{value: send_}(0, 0, 0, 0, 0);
        refunded = PLAYER.balance - (before - send_);
        strandedInRouter = address(router).balance;
    }

    /// `playChurn()` on the identical pool must refund the same remainder.
    function _churnRefund(uint256 send_) internal returns (uint256 refunded, uint256 strandedInRouter) {
        CauldronGachaRouter router = _router(regNative);
        pm.setQuote(true, X4bToken(address(0)));
        pm.setFill(6_000);
        vm.deal(PLAYER, send_);
        uint256 before = PLAYER.balance;
        vm.prank(PLAYER);
        router.playChurn{value: send_}(0, 1, 0);
        refunded = PLAYER.balance - (before - send_);
        strandedInRouter = address(router).balance;
    }

    /// ERC20 QUOTE: the remainder comes back in the quote the player supplied,
    /// and value stranded before the fix now has an owner-gated exit.
    function _churnErc20(uint256 amount)
        internal
        returns (uint256 refunded, uint256 strandedErc20, bool rescueWorks, bool rescueIsGated)
    {
        CauldronGachaRouter router = _router(regErc);
        pm.setQuote(false, usdg);
        pm.setFill(6_000);
        usdg.mint(PLAYER, amount);
        vm.startPrank(PLAYER);
        usdg.approve(address(router), amount);
        router.playChurn(amount, 1, 0);
        vm.stopPrank();
        refunded = usdg.balanceOf(PLAYER);
        strandedErc20 = usdg.balanceOf(address(router));

        // `rescueToken` exists, moves the balance, and is owner-only. This test
        // contract is the router's owner; PLAYER is not.
        usdg.mint(address(router), 7);
        bytes memory cd =
            abi.encodeWithSignature("rescueToken(address,address,uint256)", address(usdg), address(this), uint256(7));
        vm.prank(PLAYER);
        (bool strangerOk,) = address(router).call(cd);
        rescueIsGated = !strangerOk;
        uint256 ownerBefore = usdg.balanceOf(address(this));
        (bool ownerOk,) = address(router).call(cd);
        rescueWorks = ownerOk && usdg.balanceOf(address(this)) == ownerBefore + 7;
    }

    function test_playChurn_refunds_the_unconsumed_quote() public {
        uint256 send_ = 1 ether;

        (uint256 playRefunded, uint256 playStranded) = _playRefund(send_);
        (uint256 churnRefunded, uint256 churnStranded) = _churnRefund(send_);
        (uint256 ercRefunded, uint256 ercStranded, bool rescueWorks, bool rescueIsGated) = _churnErc20(1_000e6);

        // CONTROL — play() still returns the 40% the pool did not take.
        assertEq(playRefunded, 0.4 ether, "play refunds the unconsumed quote");
        assertEq(playStranded, 0, "play leaves nothing behind");

        // REGRESSION — playChurn() now matches play(): the remainder comes back.
        assertEq(churnRefunded, 0.4 ether, "playChurn refunds the unconsumed quote");
        assertEq(churnStranded, 0, "nothing is stranded in the router");

        // REGRESSION — same on an ERC20 quote, paid in that quote.
        assertEq(ercRefunded, 400e6, "ERC20 remainder refunded to the player");
        assertEq(ercStranded, 0, "no ERC20 stranded in the router");
        assertTrue(rescueWorks, "rescueToken recovers stranded ERC20");
        assertTrue(rescueIsGated, "rescueToken is owner-only, like rescueETH");

        emit log_named_uint("play()      refunded", playRefunded);
        emit log_named_uint("playChurn() refunded", churnRefunded);
        emit log_named_uint("playChurn() stranded (wei)", churnStranded);
        emit log_named_uint("playChurn() ERC20 refunded (raw USDG)", ercRefunded);
    }

    /// FULL FILL is unaffected: every wei is consumed, nothing is refunded, and
    /// the churn still compounds volume across loops.
    function test_fullFill_churn_consumes_everything_and_still_loops() public {
        CauldronGachaRouter router = _router(regNative);
        pm.setQuote(true, X4bToken(address(0)));
        pm.setFill(10_000);
        vm.deal(PLAYER, 1 ether);
        uint256 before = PLAYER.balance;
        vm.prank(PLAYER);
        router.playChurn{value: 1 ether}(0, 2, 0);
        assertEq(PLAYER.balance, before - 1 ether, "full fill refunds nothing");
        assertEq(address(router).balance, 0, "router holds no quote after a full fill");
        assertEq(brew.balanceOf(PLAYER), 2 ether, "the final buy's tokens reach the player");
        emit log_named_uint("full-fill churn tokens to player", brew.balanceOf(PLAYER));
    }

    /// PARTIAL FILL over MULTIPLE loops: the remainder is not dropped, it churns
    /// again on the next loop and whatever survives the last buy is refunded.
    function test_partialFill_multiLoop_carries_the_remainder_forward() public {
        CauldronGachaRouter router = _router(regNative);
        pm.setQuote(true, X4bToken(address(0)));
        pm.setFill(6_000);
        vm.deal(PLAYER, 1 ether);
        uint256 before = PLAYER.balance;
        vm.prank(PLAYER);
        router.playChurn{value: 1 ether}(0, 2, 0);
        uint256 refunded = PLAYER.balance - (before - 1 ether);
        // loop0 buy takes 0.6 (0.4 survives), sell returns 0.6 -> 1.0 into loop1,
        // loop1 buy takes 0.6 and 0.4 survives to the refund.
        assertEq(refunded, 0.4 ether, "the surviving remainder is refunded");
        assertEq(address(router).balance, 0, "router holds no quote afterwards");
        assertEq(brew.balanceOf(PLAYER), 1.2 ether, "the final buy's tokens reach the player");
        emit log_named_uint("multi-loop partial-fill refunded", refunded);
    }

    receive() external payable {}
}
