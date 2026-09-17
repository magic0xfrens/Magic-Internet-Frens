// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/// @dev Minimal stand-in for TreasuryGovernor: only the three methods
///      `RedemptionExt.rotateSliceFrom` actually calls.
contract M4Gov {
    address public q;
    uint16 public remaining;
    bool public spent;

    function setEnvelope(address _q, uint16 _r) external { q = _q; remaining = _r; }
    function allowance() external view returns (address, uint16) { return (q, remaining); }
    function consume(uint16, bool) external {}
    function migrationMandateSpent() external view returns (bool) { return spent; }
}

/// @dev Rotator stand-in. Reverts with a UNIQUE error so we can tell
///      "the call reached the rotator" apart from "it never got there".
contract M4Rotator {
    error ReachedRotator();
    function swapOnce(PoolKey calldata, address, address, uint256, uint256)
        external pure returns (uint256) { revert ReachedRotator(); }
    function withdraw(address, address, uint256) external {}
    receive() external payable {}
}

abstract contract M4Erc20Base {
    string public name = "M4USD";
    string public symbol = "M4USD";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a; return true;
    }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[to] += a; return true;
    }
}

contract M4Quote is M4Erc20Base {}

/**
 * @notice THE LAUNCH QUOTE CAN NEVER BE RESTORED AS A GENERATION'S DENOMINATION.
 *
 *  `RedemptionExt.rotateSliceFrom` derives the primary's source asset from the
 *  pair itself (`:371 fromQuote = Currency.unwrap(srcKey.currency0)`), and
 *  `generationPoolKey[gen]` is written once at seeding and never re-pointed. So
 *  a slice out of the PRIMARY (`fromLeg == 0`) toward the launch quote always
 *  hits `:381 if (fromQuote == toQuote) revert BadConfig();`.
 *
 *  `:581-582` is the ONLY non-relaunch writer of `generationQuote[gen]`, and it
 *  fires only on a `fromLeg == 0` slice whose mandate is spent — and
 *  `TreasuryGovernor.consume` (`:900`) advances `movedPrimaryBps` only for
 *  `fromPrimary`. A "come home to ETH" mandate can therefore never advance and
 *  never complete.
 */
contract M4C_QuoteComeHome is YBase {
    struct Res {
        bool booted;
        bool homeReverted;
        bytes4 homeSel;
        bool awayReverted;
        bytes4 awaySel;
        address primaryC0;
    }

    Res internal R;
    M4Gov internal gov;
    M4Rotator internal rot;
    M4Quote internal usd;

    function setUp() public {
        _boot(25 ether, 0);
        R.booted = active;
    }

    function _key0() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _slice(address to) internal returns (bool reverted, bytes4 sel) {
        gov.setEnvelope(to, 10_000);
        (bool ok, bytes memory ret) = address(registry).call(
            abi.encodeWithSignature(
                "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
                uint8(0), uint16(2500), uint256(0), _key0()
            )
        );
        reverted = !ok;
        if (ret.length >= 4) sel = bytes4(ret);
    }

    function _run() internal {
        if (!R.booted) return;

        gov = new M4Gov();
        rot = new M4Rotator();
        usd = new M4Quote();
        require(uint160(address(usd)) < uint160(0xf000000000000000000000000000000000000000), "watermark");

        registry.setAllowedQuote(address(usd), true, 1e18);
        registry.setRotationWiring(address(rot), address(gov));

        R.primaryC0 = address(0); // gen 1 launched against native ETH

        // CASE A — the guild votes to bring the denomination HOME to the launch
        //          quote (native ETH). Every primary slice is refused.
        (R.homeReverted, R.homeSel) = _slice(address(0));
        console2.log("home-slice reverted:", R.homeReverted);
        console2.logBytes4(R.homeSel);

        // CASE B — CONTROL: the identical call with a DIFFERENT destination gets
        //          past :381 and reaches the rotator.
        (R.awayReverted, R.awaySel) = _slice(address(usd));
        console2.log("away-slice reverted:", R.awayReverted);
        console2.logBytes4(R.awaySel);
    }

    function test_launch_quote_can_never_be_restored() public {
        _run();
        assertTrue(R.booted, "fork harness must be live");

        // CONTROL: a slice to a NEW quote is accepted by :381 and reaches the rotator.
        assertEq(R.awaySel, M4Rotator.ReachedRotator.selector, "control: primary slice must reach the rotator");

        // ATTACK: the same primary slice toward the LAUNCH quote is refused at :381.
        assertTrue(R.homeReverted, "home slice must revert");
        assertEq(R.homeSel, bytes4(keccak256("BadConfig()")), "home slice must die at fromQuote == toQuote");
        assertTrue(R.homeSel != M4Rotator.ReachedRotator.selector, "home slice never reaches the rotator");
    }
}
