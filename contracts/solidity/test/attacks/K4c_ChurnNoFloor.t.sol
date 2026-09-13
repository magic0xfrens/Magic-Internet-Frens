// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";

interface IK4Unlock { function unlockCallback(bytes calldata) external returns (bytes memory); }

contract K4cToken {
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

contract K4cRegistry {
    address public tok;
    constructor(address _t) { tok = _t; }
    function currentToken() external view returns (address) { return tok; }
    function currentGeneration() external pure returns (uint256) { return 1; }
    function generationQuote(uint256) external pure returns (address) { return address(0); }
}

contract K4cHook {
    function commitCrystals(address, uint256, uint256) external pure returns (uint256) { return 0; }
    function resolveTickets(uint256) external pure returns (uint256, uint256) { return (0, 0); }
    function crystalsReady(address) external pure returns (uint256) { return 0; }
    function costOfNextCrystals(uint256) external pure returns (uint256) { return 0; }
    function buyWeightBps() external pure returns (uint256) { return 15_000; }
}

/**
 * @dev A pool whose exchange rate can be moved between the honest rate and the
 *      rate a sandwich leaves behind. Every `_churn` leg swaps at the extreme
 *      tick (`CauldronGachaRouter._limit`), so the pool decides the rate and the
 *      router accepts whatever it is told — which is exactly the hole.
 *
 *      `buyRateBps`: creature tokens out per 1e4 of quote in (10_000 = 1:1).
 *      `sellRateBps`: quote out per 1e4 of creature token in.
 */
contract K4cPoolManager {
    K4cToken public brew;
    uint256 public buyRateBps = 10_000;
    uint256 public sellRateBps = 10_000;

    constructor(K4cToken _brew) { brew = _brew; }
    /// @dev Move the pool to the price a sandwicher would leave it at.
    function sandwich(uint256 buyBps, uint256 sellBps) external { buyRateBps = buyBps; sellRateBps = sellBps; }

    function unlock(bytes calldata data) external returns (bytes memory) {
        return IK4Unlock(msg.sender).unlockCallback(data);
    }

    function swap(PoolKey calldata, SwapParams calldata p, bytes calldata)
        external view returns (BalanceDelta)
    {
        uint256 want = uint256(-p.amountSpecified);
        if (p.zeroForOne) {
            // exact-input buy: all of `want` quote in, `want * buyRateBps / 1e4` token out
            return toBalanceDelta(-int128(int256(want)), int128(int256((want * buyRateBps) / 10_000)));
        }
        // exact-input sell: all of `want` token in, quote out at the sell rate
        return toBalanceDelta(int128(int256((want * sellRateBps) / 10_000)), -int128(int256(want)));
    }
    function sync(Currency) external {}
    function settle() external payable returns (uint256) { return msg.value; }
    function take(Currency c, address to, uint256 amount) external {
        if (Currency.unwrap(c) == address(0)) { (bool ok,) = to.call{value: amount}(""); require(ok); }
        else brew.mint(to, amount);
    }
    receive() external payable {}
}

/**
 * K4c — `playChurn` took no slippage bound of any kind while its sibling `play`
 * has taken two since day one, and every one of its up-to-19 legs swaps at the
 * extreme tick. A sandwicher could therefore take essentially the whole
 * `quoteIn` and the caller had no parameter to stop them.
 *
 * REGRESSION: `playChurn` now takes `minTokenOut`, enforced on the tokens the
 * final buy leg leaves the player holding. These tests assert that
 *   (1) an honest pool still fills a churn that carries a real floor, and
 *   (2) the SAME churn, with the SAME floor, REVERTS once the pool is sandwiched.
 * Delete the `if (tokBal < c.minTokenOut) revert Slippage();` line in
 * `CauldronGachaRouter._churn` and test (2) fails.
 */
contract K4c_ChurnNoFloor is Test {
    K4cToken internal brew;
    K4cPoolManager internal pm;
    K4cRegistry internal reg;
    K4cHook internal hookStub;
    CauldronGachaRouter internal router;

    address internal constant PLAYER = address(0x9111);
    uint256 internal constant STAKE = 1 ether;

    function setUp() public {
        brew = new K4cToken();
        pm = new K4cPoolManager(brew);
        hookStub = new K4cHook();
        reg = new K4cRegistry(address(brew));
        router = new CauldronGachaRouter(IPoolManager(address(pm)), address(hookStub), address(reg), address(this));
        vm.deal(address(pm), 1000 ether);
    }

    /// @dev One buy→sell→buy round trip. Returns the tokens the player ends with.
    function _churn(uint256 minTokenOut) internal returns (uint256 tokensOut) {
        vm.deal(PLAYER, STAKE);
        vm.prank(PLAYER);
        router.playChurn{value: STAKE}(0, 2, minTokenOut, 0);
        tokensOut = brew.balanceOf(PLAYER);
    }

    /// HONEST POOL: 1:1 both ways, so the round trip returns the stake in tokens.
    /// This establishes the floor a caller would legitimately sign.
    function test_K4c_honest_churn_meets_its_floor() public {
        uint256 got = _churn(0);
        emit log_named_uint("honest churn tokens out (wei)", got);
        assertGt(got, 0, "the honest churn delivered tokens");
        // A caller signing 95% of the honest fill is still filled.
        uint256 floor_ = (got * 95) / 100;
        setUp();
        uint256 again = _churn(floor_);
        assertGe(again, floor_, "an honest churn clears a realistic floor");
        emit log_named_uint("floor signed (wei)", floor_);
    }

    /// THE ATTACK, NOW CLOSED: the pool is sandwiched into a punitive rate before
    /// the churn lands. Without a floor the router accepted it silently; now the
    /// whole transaction reverts and the player keeps their stake.
    function test_K4c_sandwiched_churn_reverts_on_the_floor() public {
        uint256 honest = _churn(0);
        uint256 floor_ = (honest * 95) / 100;

        setUp();
        // A sandwicher moves the pool: buys fill at 5% of the honest rate, and the
        // sell leg back out is just as bad. This is the value extraction the
        // caller previously had no way to refuse.
        pm.sandwich(500, 500);

        vm.deal(PLAYER, STAKE);
        vm.prank(PLAYER);
        vm.expectRevert(CauldronGachaRouter.Slippage.selector);
        router.playChurn{value: STAKE}(0, 2, floor_, 0);

        assertEq(brew.balanceOf(PLAYER), 0, "the sandwiched churn delivered nothing");
        assertEq(PLAYER.balance, STAKE, "and the player still holds their whole stake");
        emit log_named_uint("floor that saved the stake (wei)", floor_);

        // CONTROL: the same sandwiched churn with a zero floor still goes through,
        // so the revert above is the FLOOR biting and not the fixture breaking.
        vm.prank(PLAYER);
        router.playChurn{value: STAKE}(0, 2, 0, 0);
        uint256 sandwiched = brew.balanceOf(PLAYER);
        emit log_named_uint("sandwiched churn tokens out with no floor (wei)", sandwiched);
        assertGt(honest, sandwiched * 10, "the sandwich really did take most of the stake");
    }
}
