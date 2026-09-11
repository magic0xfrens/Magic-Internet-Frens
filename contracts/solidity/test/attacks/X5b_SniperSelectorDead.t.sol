// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchSniper} from "../../cauldron/LaunchSniper.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract X5Token {
    string public name = "GNOME";
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

contract X5Presale {
    address public tok;
    bool public ignited;
    constructor(address t) { tok = t; }
    function soldOut() external pure returns (bool) { return true; }
    function igniteCauldron() external returns (address) { ignited = true; return tok; }
}

contract X5Registry {
    address public currentToken;
    constructor(address t) { currentToken = t; }
}

/// @dev FAITHFUL stand-in for CauldronGachaRouter's entry point: five uint256
///      arguments (CauldronGachaRouter.sol:233) and an open `receive()` with NO
///      fallback.
contract X5Router5 {
    X5Token public immutable t;
    uint256 public delivered;
    constructor(X5Token _t) { t = _t; }
    function play(uint256, uint256, uint256, uint256, uint256)
        external payable returns (uint256)
    {
        delivered += msg.value;
        t.mint(msg.sender, msg.value * 1000);
        return 1;
    }
    receive() external payable {}
}

/// @dev The shape LaunchSniper USED to declare: four args. Nothing implements
///      it; kept as the negative control.
contract X5Router4 {
    X5Token public immutable t;
    uint256 public delivered;
    constructor(X5Token _t) { t = _t; }
    function play(uint256, uint256, uint256, uint256)
        external payable returns (uint256)
    {
        delivered += msg.value;
        t.mint(msg.sender, msg.value * 1000);
        return 1;
    }
    receive() external payable {}
}

/// @notice X5b — REGRESSION (was: LaunchSniper.launch() called a `play` that did
///         not exist).
///
///  `IGachaPlay.play` declared FOUR uint256 args = selector 0x1ca5b161;
///  `CauldronGachaRouter.play` (CauldronGachaRouter.sol:233) is FIVE args =
///  0x7fe7c4b6, and the router has no fallback — so `launch()` reverted
///  unconditionally and the atomic launch+buy could never run. Fixed by adapting
///  the CALLER; the router (fixer E's file) was not touched. Test name kept from
///  the PoC, the assertions are inverted.
contract X5bSniperSelectorDead is Test {
    LaunchSniper sniper;
    X5Token tok;
    X5Presale presale;
    X5Registry reg;
    X5Router5 r5;
    X5Router4 r4;
    address airdrop = address(0xA1D0);

    function setUp() public {
        tok = new X5Token();
        presale = new X5Presale(address(tok));
        reg = new X5Registry(address(tok));
        r5 = new X5Router5(tok);
        r4 = new X5Router4(tok);
        sniper = new LaunchSniper(address(this));
        vm.deal(address(this), 100 ether);
    }

    function _tryLaunch(address router) internal returns (bool ok, uint256 bought) {
        try sniper.launch{value: 1 ether}(
            address(presale), address(reg), router, airdrop, 0, 1
        ) returns (address, uint256 g) {
            return (true, g);
        } catch {
            return (false, 0);
        }
    }

    function _rawCall4(address target) internal returns (bool ok, uint256 retLen) {
        (bool s, bytes memory ret) = target.call{value: 1 ether}(
            abi.encodeWithSelector(
                bytes4(keccak256("play(uint256,uint256,uint256,uint256)")),
                uint256(0), uint256(0), uint256(0), uint256(1)
            )
        );
        return (s, ret.length);
    }

    function test_Attack_SniperPlaySelectorDoesNotExistOnTheRouter() public {
        bytes4 deadFour = bytes4(keccak256("play(uint256,uint256,uint256,uint256)"));
        bytes4 declared = bytes4(keccak256("play(uint256,uint256,uint256,uint256,uint256)"));
        bytes4 real = CauldronGachaRouter.play.selector;
        bytes4 fiveStub = X5Router5.play.selector;

        // The REAL router, deployed for real, still has no fallback: the OLD
        // 4-arg calldata falls through with empty returndata. That is why the
        // CALLER had to change.
        CauldronGachaRouter live =
            new CauldronGachaRouter(IPoolManager(address(0xdead)), address(0xdead), address(reg), address(this));
        (bool liveOk, uint256 liveRetLen) = _rawCall4(address(live));

        // End-to-end through the real LaunchSniper.
        (bool okFive, uint256 boughtFive) = _tryLaunch(address(r5)); // faithful router
        (bool okFour, uint256 boughtFour) = _tryLaunch(address(r4)); // the shape that never existed

        emit log_named_bytes32("sniper declares  ", bytes32(declared));
        emit log_named_bytes32("router implements", bytes32(real));

        assertEq(fiveStub, real, "stub mirrors the real router's play() selector");
        assertEq(declared, real, "FIXED: LaunchSniper declares the router's real selector");
        assertTrue(deadFour != real, "the old 4-arg selector was never on the router");

        assertFalse(liveOk, "raw 4-arg play() on the REAL router still fails");
        assertEq(liveRetLen, 0, "no fallback: the dispatcher falls through with empty returndata");

        assertTrue(okFive, "FIXED: launch() works against the router's real 5-arg play()");
        assertGt(boughtFive, 0, "the launch buy actually delivered tokens");
        assertEq(r5.delivered(), 1 ether, "the whole funding buy reached the router");
        assertEq(tok.balanceOf(airdrop), boughtFive, "and was forwarded to the airdrop wallet");

        assertFalse(okFour, "the 4-arg shape is no longer what the sniper calls");
        assertEq(boughtFour, 0, "nothing bought against a router that lacks the real play()");
    }

    receive() external payable {}
}
