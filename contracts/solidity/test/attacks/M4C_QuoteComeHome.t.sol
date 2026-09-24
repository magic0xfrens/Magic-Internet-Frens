// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/// @dev Stand-in for TreasuryGovernor: only the three methods
///      `RedemptionExt.rotateSliceFrom` actually calls. It RECORDS the
///      `fromPrimary` flag, which is the value the fix is about — that flag is
///      what `TreasuryGovernor.consume` (:900) turns into `movedPrimaryBps`,
///      and `movedPrimaryBps >= cap` (:913) is what deactivates the envelope
///      and stops it blocking `propose` (TreasuryGovernor.sol:437).
contract M4Gov {
    address public q;
    uint16 public remaining;
    bool public spent;

    uint16 public lastBps;
    bool public lastFromPrimary;
    uint16 public primaryBps; // the counter the real governor calls movedPrimaryBps
    uint256 public consumeCount;

    function setEnvelope(address _q, uint16 _r) external { q = _q; remaining = _r; }
    function setSpent(bool s) external { spent = s; }
    function allowance() external view returns (address, uint16) { return (q, remaining); }

    function consume(uint16 bps, bool fromPrimary) external {
        lastBps = bps;
        lastFromPrimary = fromPrimary;
        if (fromPrimary) primaryBps += bps;
        consumeCount += 1;
    }

    function migrationMandateSpent() external view returns (bool) { return spent; }
}

/// @dev Rotator stand-in that actually DELIVERS the destination asset, so the
///      slice completes and the generation's denomination really flips. The
///      real rotator's venue/oracle-floor guards are exercised by the
///      QuoteRotator tests; this harness is about the leg accounting.
contract M4Rotator {
    M4Quote public usd;
    uint256 public rate = 1; // 1 wei in -> 1 unit out, both directions

    function setUsd(M4Quote u) external { usd = u; }

    function swapOnce(PoolKey calldata, address, address toQuote, uint256 amountIn, uint256)
        external returns (uint256)
    {
        uint256 out = amountIn * rate;
        if (toQuote != address(0)) usd.mint(address(this), out);
        return out;
    }

    function withdraw(address asset, address to, uint256 amount) external {
        if (asset == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "eth out");
        } else {
            usd.transfer(to, amount);
        }
    }

    receive() external payable {}
}

abstract contract M4Erc20Base {
    string public name = "M4USD";
    string public symbol = "M4USD";
    uint8 public decimals = 6; // deliberately NOT 18
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
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[to] += a; return true;
    }
}

contract M4Quote is M4Erc20Base {}

/**
 * @notice REGRESSION — A GENERATION'S DENOMINATION CAN COME HOME.
 *
 *  ORIGINALLY (T4C): `rotateSliceFrom` decided "is this slice the primary?"
 *  with `fromLeg == 0`, and derived the primary's asset from
 *  `generationPoolKey[gen].currency0` — the pair the generation LAUNCHED
 *  against, written once and never re-pointed. After an ETH -> USD migration
 *  the denomination lives in leg 1, but only `fromLeg == 0` booked
 *  `fromPrimary`, and `fromLeg == 0` toward ETH dies at
 *  `if (fromQuote == toQuote) revert BadConfig()`. So:
 *    - the denomination flip (RedemptionExt.sol:~600) was unreachable, and
 *    - `movedPrimaryBps` stayed 0 forever, so `TreasuryGovernor.consume`
 *      (:913) never cleared `envelope.active` and the mandate blocked
 *      `propose` (TreasuryGovernor.sol:437) until it expired.
 *
 *  THE FIX: "primary" is the position holding the CURRENT denomination, not
 *  the launch pair. This test drives the full round trip
 *  ETH -> USD -> ETH and asserts the primary counter advances on BOTH halves.
 */
contract M4C_QuoteComeHome is YBase {
    M4Gov internal gov;
    M4Rotator internal rot;
    M4Quote internal usd;

    function setUp() public {
        _boot(25 ether, 0);
    }

    function _key(address quote) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _slice(address to, uint8 fromLeg, bool spent)
        internal
        returns (bool ok, bytes4 sel)
    {
        gov.setEnvelope(to, 10_000);
        gov.setSpent(spent);
        bytes memory ret;
        (ok, ret) = address(registry).call(
            abi.encodeWithSignature(
                "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
                fromLeg, uint16(2500), uint256(0), _key(to)
            )
        );
        if (!ok && ret.length >= 4) sel = bytes4(ret);
    }

    function test_launch_quote_can_never_be_restored() public {
        if (!active && bytes(vm.envOr("FORK_RPC", string(""))).length == 0) vm.skip(true); // no fork, no local boot: SKIPPED, never PASS
        assertTrue(active, "fork harness must be live");

        gov = new M4Gov();
        rot = new M4Rotator();
        usd = new M4Quote();
        rot.setUsd(usd);
        vm.deal(address(rot), 100 ether);
        require(
            uint160(address(usd)) < uint160(0xf000000000000000000000000000000000000000),
            "watermark"
        );

        registry.setAllowedQuote(address(usd), true, 1e18);
        registry.setRotationWiring(address(rot), address(gov));

        uint256 gen = registry.currentGeneration();
        assertEq(registry.generationQuote(gen), address(0), "gen 1 launched against native ETH");

        // ── LEG A: migrate AWAY, ETH -> USD. Primary slice, mandate spent, so
        //    the denomination flips on this call.
        (bool okAway, bytes4 selAway) = _slice(address(usd), 0, true);
        console2.log("away ok:", okAway);
        console2.logBytes4(selAway);
        assertTrue(okAway, "away slice must succeed");
        assertTrue(gov.lastFromPrimary(), "away slice is a primary slice");
        assertEq(gov.primaryBps(), uint16(2500), "movedPrimaryBps must advance on the way out");
        assertEq(registry.generationQuote(gen), address(usd), "denomination moved to USD");

        // ── THE GUARD WE DID NOT WEAKEN: the launch pair is still ETH, so a
        //    fromLeg == 0 slice toward ETH is a rotation into itself and is
        //    still refused. That is correct, and it is why the come-home path
        //    has to be the leg holding the denomination.
        (bool okSelf, bytes4 selSelf) = _slice(address(0), 0, true);
        assertTrue(!okSelf, "launch-pair slice into its own asset must still revert");
        assertEq(selSelf, bytes4(keccak256("BadConfig()")), "and it must die at fromQuote == toQuote");

        // ── LEG B: come HOME, USD -> ETH, out of the leg that now holds the
        //    denomination. THIS is what used to be booked as a secondary slice.
        uint16 before = gov.primaryBps();
        (bool okHome, bytes4 selHome) = _slice(address(0), 1, true);
        console2.log("home ok:", okHome);
        console2.logBytes4(selHome);
        assertTrue(okHome, "home slice must succeed");
        assertTrue(gov.lastFromPrimary(), "home slice must be booked as the PRIMARY slice");
        assertEq(gov.primaryBps(), before + 2500, "movedPrimaryBps must advance on the way home");
        assertEq(registry.generationQuote(gen), address(0), "denomination came home to the launch asset");
    }
}
