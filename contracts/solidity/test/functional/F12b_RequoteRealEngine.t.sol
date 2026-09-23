// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {PerpSwapLib} from "../../cauldron/PerpSwapLib.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockAggregator} from "../../cauldron/MockAggregator.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  F-12b — THE BOOK REQUOTE, ACROSS THE REAL ENGINE ↔ REAL VAULT SEAM
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  {PerpEngine.requoteBook} converts every quote figure the engine and its vault
 *  keep, in one call, at the rotation's flip. The previous design was tested
 *  half-and-half — the vault against a mock engine, the engine against a mock
 *  vault — and never ran end to end (the credit reverted `BadParam` in both
 *  directions). So nothing here mocks either side of that seam: real
 *  {PerpEngine}, real {PerpVault}, real {QuoteOracle}. Stand-ins are only the
 *  PoolManager (slot0 reads), the registry (the rotated `generationQuote`) and
 *  the venue (a fixed-rate swap at 1 ETH = 2,850 USDG — deliberately BELOW the
 *  oracle's 3,000, so the realized rate and the oracle rate are distinguishable).
 *
 *  Open positions need real swaps and are covered on a fork in F14 / F14c.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract F12b_RequoteRealEngine is Test {
    REPM internal pm;
    RERegistry internal reg;
    PerpEngine internal engine;
    PerpVault internal vault;
    MockQuoteToken internal usdg;
    MockQuoteToken internal tok;
    RERotator internal rot;
    QuoteOracle internal oracle;

    address internal alice = address(0xA11CE);   // quote-side staker
    address internal carol = address(0xCA201);   // token-side staker
    address internal constant TREASURY = address(0x7E7E);

    uint256 internal constant ORACLE_USD = 3000;  // oracle: 1 ETH = $3000
    uint256 internal constant VENUE_USDG = 2850e6; // venue: 1 ETH fills 2850 USDG (5% impact)

    function setUp() public {
        pm = new REPM();
        tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new RERegistry(address(tok));
        engine = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), TREASURY, address(this)
        );
        vault = new PerpVault(address(engine), address(reg));
        engine.setVault(address(vault));
        usdg = new MockQuoteToken("USDG", "USDG", 6);
        oracle = new QuoteOracle(address(this));
        oracle.setFeed(address(0), address(new MockAggregator("ETH/USD", int256(ORACLE_USD) * 1e8)), 4 hours, 18);
        oracle.setFeed(address(usdg), address(new MockAggregator("USDG/USD", 1e8)), 4 hours, 6);
        rot = new RERotator(usdg, oracle, VENUE_USDG);
        vm.deal(address(rot), 1_000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(address(this), 100 ether);
    }

    /// The engine asks its hook this inside `_isDead`; this contract is the hook.
    function isDead(PoolId) external pure returns (bool) { return false; }

    /// What `RedemptionExt.rotateSliceFrom` does at the flip: re-denominate the
    /// generation, then — as the registry — have the engine carry its book.
    function _flipTo(address q) internal {
        reg.setQuote(q);
        vm.prank(address(reg));
        engine.requoteBook(address(rot));
    }

    function _quoteUnit() internal view returns (uint256) {
        return uint256(vm.load(address(engine), bytes32(uint256(86)))); // `forge inspect` slot
    }

    /// alice 4 ETH of quote-side stake; carol 1,000 tokens earning 1 ETH of
    /// token-side yield; 0.5 ETH of insurance.
    function _fund() internal {
        vm.prank(alice);
        vault.depositEth{value: 4 ether}();
        tok.mint(carol, 1_000 ether);
        vm.startPrank(carol);
        tok.approve(address(vault), type(uint256).max);
        vault.depositToken(1_000 ether);
        vm.stopPrank();
        engine.creditPerpFeeToken{value: 1 ether}();     // hook-only → tokYieldEth
        engine.fundInsurance{value: 0.5 ether}(0.5 ether);
    }

    // ── ETH → USDG: every pot converts, adoption lands in the same call ─────

    function test_F12b_EthToUsdg_EveryPotConverts_AtTheRealizedRate() public {
        _fund();
        assertApproxEqAbs(vault.pendingTokYield(carol), 1 ether, 2, "precondition: carol earned 1 ETH");

        _flipTo(address(usdg));

        //  5.5 ETH of physical money (4 plv + 0.5 insurance + 1 yield) swapped at
        //  the venue's 2,850 — the REALIZED rate, not the oracle's 3,000.
        assertEq(engine.quote(), address(usdg), "adopted in the same call");
        assertEq(engine.plv(), 11_400e6, "plv: 4 ETH x 2850");
        assertEq(engine.insuranceEth(), 1_425e6, "insurance: 0.5 ETH x 2850 - converted, not swept");
        assertEq(engine.tokYieldEth(), 2_850e6, "token-side yield pot: 1 ETH x 2850 - converted, not written off");
        assertEq(usdg.balanceOf(address(engine)), 15_675e6, "the engine holds exactly what the three figures claim");
        assertEq(address(engine).balance, 0, "no old-asset residue");
        assertEq(_quoteUnit(), 3000e6, "quoteUnit restated from the ROTATOR's oracle: 1 ETH = 3000 USDG");

        assertApproxEqRel(_value(alice), 11_400e6, 1e12, "alice's stake: all of it, in USDG");
        assertApproxEqAbs(vault.pendingTokYield(carol), 2_850e6, 2, "carol's yield: rescaled, NOT forfeited");
        assertEq(vault.yieldEpoch(), 0, "no forfeit epoch was triggered");

        //  And both are REAL: they exit in the new asset.
        uint256 shares = vault.ethShareOf(alice);
        vm.prank(alice);
        vault.withdrawEth(shares);
        assertApproxEqRel(usdg.balanceOf(alice), 11_400e6, 1e12, "alice paid 11,400 USDG");
        vm.prank(carol);
        vault.claimTokYield();
        assertApproxEqAbs(usdg.balanceOf(carol), 2_850e6, 2, "carol paid 2,850 USDG");
        console2.log("F12b alice USDG", usdg.balanceOf(alice));
        console2.log("F12b carol USDG", usdg.balanceOf(carol));
    }

    // ── the round trip ──────────────────────────────────────────────────────

    function test_F12b_RoundTrip_EthUsdgEth() public {
        _fund();
        _flipTo(address(usdg));
        _flipTo(address(0));

        //  2,850 each way: 5.5 ETH → 15,675 USDG → 5.5 ETH exactly.
        assertEq(engine.quote(), address(0), "native again");
        assertEq(_quoteUnit(), 1e18, "quoteUnit back to wei");
        assertEq(engine.plv(), 4 ether, "plv back to 4 ETH");
        assertEq(engine.insuranceEth(), 0.5 ether, "insurance back to 0.5 ETH");
        assertEq(engine.tokYieldEth(), 1 ether, "yield pot back to 1 ETH");
        assertEq(usdg.balanceOf(address(engine)), 0, "no USDG residue");
        assertApproxEqAbs(vault.pendingTokYield(carol), 1 ether, 4, "carol's yield survived both flips");
        assertEq(engine.unabsorbedEth(), 0, "no bad debt anywhere on the trip");

        uint256 before = alice.balance;
        uint256 shares = vault.ethShareOf(alice);
        vm.prank(alice);
        vault.withdrawEth(shares);
        assertApproxEqAbs(alice.balance - before, 4 ether, 2, "alice exits with her 4 ETH");
    }

    // ── the TWAP is carried, not reset ──────────────────────────────────────

    /**
     *  Every new-pool tick sits log_1.0001(fOld / fNew) above its old-pool twin.
     *  For ETH → USDG that is log_1.0001(1e18 / 3e9) ≈ 196,250. The ring must be
     *  shifted by exactly that, so a carried book is marked continuously instead
     *  of off a freshly reset ring that falls back to the new pool's spot.
     */
    function test_F12b_TwapIsShiftedByTheOracleOffset() public {
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        engine.poke();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        engine.poke();
        (int24 before, bool okBefore) = engine.twapTick();
        assertTrue(okBefore, "a warm ring before the flip");

        _flipTo(address(usdg));
        (int24 afterTick, bool okAfter) = engine.twapTick();
        console2.log("F12b twap before", int256(before));
        console2.log("F12b twap after ", int256(afterTick));
        assertTrue(okAfter, "still warm: the ring was carried, not reset");
        int256 d = int256(afterTick) - int256(before);
        assertGt(d, 196_000, "shifted up by ~log(3.33e8)");
        assertLt(d, 196_500, "...and by nothing else");
    }

    // ── all or nothing ──────────────────────────────────────────────────────

    function test_F12b_OnlyTheRegistryMayCarryTheBook() public {
        _fund();
        reg.setQuote(address(usdg));
        vm.expectRevert(PerpSwapLib.RequoteNotRegistry.selector);
        engine.requoteBook(address(rot));
        assertEq(engine.quote(), address(0), "nothing moved");
    }

    function test_F12b_OwedPayouts_RefuseAndMoveNothing() public {
        _fund();
        vm.store(address(engine), bytes32(uint256(77)), bytes32(uint256(1))); // payoutOwedTotal
        reg.setQuote(address(usdg));
        vm.prank(address(reg));
        vm.expectRevert(PerpSwapLib.RequotePayoutsOwed.selector);
        engine.requoteBook(address(rot));
        assertEq(engine.plv(), 4 ether, "plv untouched");
        assertEq(address(engine).balance, 5.5 ether, "every wei still here, still ETH");
    }

    function test_F12b_UnpriceableQuote_Refuses() public {
        _fund();
        MockQuoteToken odd = new MockQuoteToken("ODD", "ODD", 18);   // no feed
        reg.setQuote(address(odd));
        vm.prank(address(reg));
        vm.expectRevert(PerpSwapLib.RequoteUnpriced.selector);
        engine.requoteBook(address(rot));
        assertEq(engine.quote(), address(0), "nothing adopted");
    }

    function test_F12b_VaultHooksAreEngineOnly() public {
        vm.expectRevert(PerpVault.NotEngine.selector);
        vault.beforeBookRequote();
        vm.expectRevert(PerpVault.NotEngine.selector);
        vault.afterBookRequote(1, 1, 1, 1);
    }

    function _value(address who) internal view returns (uint256 v) {
        (v,,) = vault.ethPosition(who);
    }
}

// ── stand-ins ───────────────────────────────────────────────────────────────

/// slot0 = sqrtPriceX96 2**96 at tick 0: a live pool for `_currentTick`.
contract REPM {
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract RERegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;

    constructor(address t) { currentToken = t; lastSummonAt = block.timestamp; }
    function setQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/// {QuoteRotator}'s surface: an oracle, a curated venue per pair, and a
/// fixed-rate swap that spends what it was sent.
contract RERotator {
    MockQuoteToken public immutable usdg;
    address public immutable quoteOracle;
    uint256 public immutable usdgPerEth;

    constructor(MockQuoteToken u, QuoteOracle o, uint256 r) { usdg = u; quoteOracle = address(o); usdgPerEth = r; }

    function venueFor(address a, address b) external view returns (PoolKey memory k, bool ok) {
        k = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(usdg)), 3000, 60, IHooks(address(0)));
        ok = (a == address(0) && b == address(usdg)) || (a == address(usdg) && b == address(0));
    }

    function swapOnce(PoolKey calldata, address from, address, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 out)
    {
        if (from == address(0)) {
            out = (amountIn * usdgPerEth) / 1 ether;
            usdg.mint(address(this), out);
        } else {
            out = (amountIn * 1 ether) / usdgPerEth;
        }
        require(out >= minOut, "SlippageTooHigh");
    }

    function withdraw(address asset, address to, uint256 amount) external {
        if (asset == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "send");
        } else {
            usdg.transfer(to, amount);
        }
    }

    receive() external payable {}
}
