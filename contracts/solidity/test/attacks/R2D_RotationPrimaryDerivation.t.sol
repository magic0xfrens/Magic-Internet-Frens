// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";

/// @dev Voting weight only. The governor calls nothing else on MiFrens.
contract R2DVotes {
    mapping(address => uint256) public v;
    uint256 public total;
    function set(address a, uint256 n) external { total = total - v[a] + n; v[a] = n; }
    function getVotes(address a) external view returns (uint256) { return v[a]; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return v[a]; }
    function getPastTotalSupply(uint256) external view returns (uint256) { return total; }
}

abstract contract R2DErc20 {
    string public name = "R2DUSD";
    string public symbol = "R2DUSD";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[to] += a; return true;
    }
}

contract R2DQuote is R2DErc20 {}

/// @dev Venue stand-in: 1:1 both ways. The real rotator's venue allowlist and
///      oracle floor are exercised by the QuoteRotator tests; this test is
///      about the `fromPrimary` derivation in RedemptionExt.
contract R2DRotator {
    R2DQuote public usd;
    function setUsd(R2DQuote u) external { usd = u; }
    function swapOnce(PoolKey calldata, address, address toQuote, uint256 amountIn, uint256)
        external returns (uint256)
    {
        if (toQuote != address(0)) usd.mint(address(this), amountIn);
        return amountIn;
    }
    function withdraw(address asset, address to, uint256 amount) external {
        if (asset == address(0)) { (bool ok,) = to.call{value: amount}(""); require(ok, "eth out"); }
        else { usd.transfer(to, amount); }
    }
    receive() external payable {}
}

/**
 * @notice R2D — AFTER A ROUND TRIP THE ROTATION PICKS THE WRONG "PRIMARY".
 *
 *  `RedemptionExt.rotateSliceFrom` (cauldron/RedemptionExt.sol:412-415):
 *
 *      address curQuote = generationQuote[gen];
 *      bool fromPrimary =
 *          fromQuote == curQuote &&
 *          (fromLeg == 0) == (Currency.unwrap(generationPoolKey[gen].currency0) == curQuote);
 *
 *  The comment above it says "that is exactly one position at any time". It is
 *  not. `_recordLeg` (:799) upserts legs by QUOTE into `generationLegs`, which
 *  never contains the launch position — so rotating the denomination HOME
 *  (ETH -> USD -> ETH) leaves TWO positions holding the current quote:
 *
 *    * the launch pair, holding only the residual the migration left behind, and
 *    * the come-home leg, holding everything the migration moved.
 *
 *  With `generationPoolKey.currency0 == curQuote` true again, the tiebreak picks
 *  `fromLeg == 0` — the residual. The position holding the treasury books as a
 *  SECONDARY leg.
 *
 *  Consequence, which is the Critical at :593-601 reopened through a different
 *  door: a whole migration mandate can be spent against the residual, which
 *  advances `movedPrimaryBps` to the cap, fires `migrationMandateSpent()` and
 *  flips `generationQuote` (and re-points the perp engine) while the position
 *  holding the treasury has not moved.
 */
contract R2D_RotationPrimaryDerivation is YBase {
    TreasuryGovernor internal gov;
    R2DRotator internal rot;
    R2DQuote internal usd;
    R2DVotes internal votes;

    address internal guild = address(0x6111D);

    uint64 internal constant VOTING = 1 days;
    uint64 internal constant LIFETIME = 30 days;
    uint64 internal constant CD = 1 days;

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

    function _dumpLegs(uint256 gen, string memory when) internal {
        uint256 n = registry.legCount(gen);
        console2.log("=== leg book", when);
        console2.log("  legCount", n);
        for (uint256 i; i < n; ++i) {
            (address lq, uint256 lid, PoolKey memory k) = registry.legAt(gen, i);
            console2.log("  i", i);
            console2.log("    .quote", lq);
            console2.log("    .positionId", lid);
            console2.log("    .key.currency0", Currency.unwrap(k.currency0));
        }
        console2.log("  generationQuote", registry.generationQuote(gen));
    }

    function _installEnvelope(address quote, uint16 cap) internal {
        vm.prank(guild);
        uint256 id = gov.propose(quote, cap);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(guild);
        gov.vote(id, true);
        vm.warp(vm.getBlockTimestamp() + VOTING + 1);
        gov.execute(id);
    }

    /// @dev One slice. Returns success + the amount of destination asset the
    ///      slice produced (proportional to the source position's size).
    function _slice(address to, uint8 fromLeg, uint16 bps)
        internal
        returns (bool ok, uint256 moved)
    {
        bytes memory ret;
        (ok, ret) = address(registry).call(
            abi.encodeWithSignature(
                "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
                fromLeg, bps, uint256(0), _key(to)
            )
        );
        if (ok && ret.length >= 64) (moved,) = abi.decode(ret, (uint256, uint256));
        if (!ok) { console2.log("slice revert, fromLeg", fromLeg); console2.logBytes(ret); }
    }

    function test_R2D_roundTripMisclassifiesThePositionHoldingTheTreasury() public {
        assertTrue(active, "fork harness must be live");

        votes = new R2DVotes();
        votes.set(guild, 1000);
        rot = new R2DRotator();
        usd = new R2DQuote();
        rot.setUsd(usd);
        vm.deal(address(rot), 1_000 ether);
        require(uint160(address(usd)) < uint160(0xf000000000000000000000000000000000000000), "watermark");

        gov = new TreasuryGovernor(
            IVotes721(address(votes)), address(registry), address(0xFEED),
            VOTING, LIFETIME, CD, 1 days, false
        );

        registry.setAllowedQuote(address(usd), true, 1e18);
        registry.setRotationWiring(address(rot), address(gov));

        uint256 gen = registry.currentGeneration();
        assertEq(registry.generationQuote(gen), address(0), "gen launched against native ETH");

        // ── 1. MIGRATE AWAY. 10,000-bps mandate, two 5,000-bps slices.
        _installEnvelope(address(usd), 10_000);
        (bool a1,) = _slice(address(usd), 0, 2500);
        (bool a2,) = _slice(address(usd), 0, 2500);
        (bool a3,) = _slice(address(usd), 0, 2500);
        (bool a4,) = _slice(address(usd), 0, 2500);
        bool flippedToUsd = registry.generationQuote(gen) == address(usd);
        _dumpLegs(gen, "AFTER away migration ETH->USD");

        // ── 2. COME HOME. The USD leg (fromLeg 1) holds the denomination.
        vm.warp(vm.getBlockTimestamp() + CD + 1);
        _installEnvelope(address(0), 10_000);
        (bool h1,) = _slice(address(0), 1, 2500);
        (bool h2,) = _slice(address(0), 1, 2500);
        (bool h3,) = _slice(address(0), 1, 2500);
        (bool h4,) = _slice(address(0), 1, 2500);
        bool flippedHome = registry.generationQuote(gen) == address(0);
        _dumpLegs(gen, "AFTER come-home USD->ETH");
        uint256 legs = registry.legCount(gen);
        // Find the leg that holds the CURRENT denomination (ETH) after the trip.
        uint8 ethLeg = 0;
        for (uint256 i; i < legs; ++i) {
            (address lq, uint256 lid,) = registry.legAt(gen, i);
            console2.log("leg", i);
            console2.log("  quote", lq);
            console2.log("  posId", lid);
            if (lq == address(0)) ethLeg = uint8(i + 1);
        }
        console2.log("ethLeg index (1-based, 0 = none)", ethLeg);

        // ── 3. THE STATE THE DERIVATION CANNOT EXPRESS: two positions hold ETH.
        //      Measure both with the SAME slice size, from the same state.
        vm.warp(vm.getBlockTimestamp() + CD + 1);
        _installEnvelope(address(usd), 10_000);

        uint256 snap = vm.snapshotState();
        (bool okLaunch, uint256 movedLaunch) = _slice(address(usd), 0, 2500);
        uint16 primaryAfterLaunch = _primaryBps();
        vm.revertToState(snap);

        (bool okLeg, uint256 movedLeg) = _slice(address(usd), ethLeg, 2500);
        uint16 primaryAfterLeg = _primaryBps();

        console2.log("legs recorded", legs);
        console2.log("25% of the LAUNCH pair (fromLeg 0), wei", movedLaunch);
        console2.log("25% of the COME-HOME leg (fromLeg 2), wei", movedLeg);
        console2.log("movedPrimaryBps after a launch-pair slice", primaryAfterLaunch);
        console2.log("movedPrimaryBps after a come-home-leg slice", primaryAfterLeg);

        assertTrue(a1 && a2 && a3 && a4, "away slices must succeed");
        assertTrue(flippedToUsd, "denomination migrated to USD");
        assertTrue(h1 && h2 && h3 && h4, "home slices must succeed");
        assertTrue(flippedHome, "denomination came home to ETH");
        //  ── INVERTED: THE INVERSION THIS TEST HUNTED DOES NOT EXIST ────────
        //  Written to prove that after ETH -> USD -> ETH the derivation at
        //  RedemptionExt.sol:412-415 books the DRAINED launch residual as
        //  primary and the position actually holding the treasury as secondary.
        //  Two sessions reached that reading independently from the code --
        //  `_upsertLeg` does contain a branch that pushes a new leg, and
        //  `generationPoolKey` is never rewritten -- and both were wrong,
        //  because neither checked whether the come-home path REACHES that
        //  branch with the launch quote. It does not.
        //
        //  The original assertions, kept verbatim so the refutation is legible:
        //      assertGt(ethLeg, 0,             "a leg holding the current denomination (ETH) exists beside the launch pair");
        //      assertTrue(okLeg,               "slice out of the come-home leg succeeds");
        //      assertGt(movedLeg, movedLaunch, "the come-home leg holds the treasury");
        //      assertEq(primaryAfterLaunch, 2500, "launch residual booked as the PRIMARY slice");
        //      assertEq(primaryAfterLeg, 0,    "the position holding the treasury booked as SECONDARY");
        //
        //  What actually happens: the come-home consolidates into the launch
        //  pair, `legCount` stays 1 (the USD leg), and NO second ETH-quoted leg
        //  is ever created. With exactly one position holding the current
        //  denomination, `fromPrimary` being true for `fromLeg == 0` is CORRECT.
        //
        //  Agreement between two readings is not evidence; execution is. Do not
        //  re-raise this without a leg book that shows two ETH-quoted positions.
        assertEq(ethLeg, 0, "REFUTED: the come-home creates no second ETH leg to misclassify");
        assertTrue(okLaunch, "the launch pair -- the only ETH holder -- is sliceable");
        assertGt(movedLaunch, 0, "and a slice out of it moves real value");
        assertEq(primaryAfterLaunch, 2500, "booked as PRIMARY, which is the honest answer");
    }

    function _primaryBps() internal view returns (uint16) {
        (, uint16 left) = gov.allowance();
        // allowance() reports maxTotalBps - movedPrimaryBps while the envelope
        // is live (TreasuryGovernor.sol:826-828).
        return left == 0 ? 10_000 : 10_000 - left;
    }
}
