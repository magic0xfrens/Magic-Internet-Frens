// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";

/// @dev Minimal 6-decimal ERC20, same shape as the one in DividendBasket.t.sol.
contract Coin {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/**
 * @title B-02 — the dividend transfer hook does not fit in its forwarded gas budget
 *
 *  STATUS: FIXED. GAS_DIVIDEND_FWD/MIN were raised to 260k/320k to cover the
 *  measured 3-asset worst case (see MiFrensGenesis.sol:97-98 and the note above
 *  them). This file is now a REGRESSION suite: the invariant + per-basket-size
 *  tests pass on the fixed contract and fail if the budget is ever lowered or
 *  MAX_ASSETS raised without it; the consequence tests assert the damage
 *  (stranded share, seller paid for buyer's window) no longer occurs. The
 *  narrative below is preserved in the past tense as the finding record.
 *
 *  MiFrensGenesis.sol:671-675 calls the dividend's `onMiFrenTransfer` inside
 *  `_update` with a HARD cap of GAS_DIVIDEND_FWD (was 180,000)
 *  and swallows any failure in a bare `catch {}`. A `gasleft() < GAS_DIVIDEND_MIN`
 *  (240,000) precondition at MiFrensGenesis.sol:672 exists to stop a SELLER from
 *  choosing failure by sizing the transaction's gas (audit F-09).
 *
 *  That precondition bounds what the CALLER supplies. It does nothing about what
 *  the CALLEE costs. The forwarded amount is a constant, so if the hook's real
 *  worst case exceeds 180,000 the call OOGs on an ORDINARY, full-gas transfer —
 *  no griefing required, and the F-09 guard cannot fire because the caller did
 *  supply the gas.
 *
 *  The comment at MiFrensGenesis.sol:664-666 sizes that worst case at
 *  "~39k: one cold zero-to-nonzero `owed` SSTORE plus three cold nonzero updates".
 *  That estimate predates the fee basket. {MiFrensDividend.onMiFrenTransfer}
 *  (MiFrensDividend.sol:459-468) now also walks up to MAX_ASSETS = 3 assets, and
 *  each iteration can cost two cold zero-to-nonzero SSTOREs — `owedAsset[cur][a]`
 *  (22,100) and `debtOfAsset[tokenId][a]` (20,000) — plus three cold SLOADs. The
 *  comment and the code disagree.
 *
 *  The existing coverage does not reach it: F01_CustodyAndConsent's `_wireDividend`
 *  (test/final/F01_CustodyAndConsent.t.sol:260-262) funds ETH ONLY, so
 *  `assets.length == 0` and the loop those tests are meant to bound never runs.
 *  `test_F09_TheEntireGriefWindowIsClosed` sweeps a gas window against an EMPTY
 *  basket.
 *
 *  IMPACT — this is precisely the state F-09 and M-06 were written to prevent,
 *  now reachable on the honest path:
 *    - the sold fren stays in `activeShares`, diluting every honest holder while
 *      earning for nobody (its slice of every future deposit is unclaimable and
 *      permanently locked in the contract);
 *    - `enchantedBy` keeps pointing at the SELLER, so accrual over the BUYER's
 *      ownership is later paid to the SELLER via `_castSpell`'s stale branch
 *      (MiFrensDividend.sol:398-402);
 *    - that stale branch skips `_collectEnchantFee`, so the buyer re-enchants
 *      free and the reserve never receives the fee a moved fren owes.
 */
contract B02_DividendGasBudgetOverrun is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;
    Coin[3] coins;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address treasury = address(0x7EA);

    /// Mirrors MiFrensGenesis.sol:97 (post-fix value).
    uint256 constant GAS_DIVIDEND_FWD = 260_000;

    /// @dev Enchant BEFORE any asset exists, then fill the basket. That leaves
    ///      `debtOfAsset[id][a] == 0` for every asset, so the settle loop's write
    ///      is the expensive zero-to-nonzero case — and `owedAsset[alice][a]` is
    ///      likewise cold and zero. This is the ordinary lifecycle for any fren
    ///      enchanted before a quote rotation, not a contrived ordering.
    function setUp() public {
        mifrens = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div));
        vm.prank(treasury);
        div.setFunder(address(this));

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        mifrens.mint{value: 0.01 ether}(1); // id 1

        vm.prank(alice);
        div.castSpell(1); // activeShares = 1, basket still empty

        // Fill the basket to MAX_ASSETS = 3 (MiFrensDividend.sol:124).
        for (uint256 i; i < 3; ++i) {
            coins[i] = new Coin();
            coins[i].mint(address(this), 1_000_000e6);
            coins[i].approve(address(div), type(uint256).max);
            div.fundToken(address(coins[i]), 1000e6);
        }

        // ETH inflow too, so the `owed[cur]` SSTORE is also zero-to-nonzero.
        (bool ok,) = address(div).call{value: 0.05 ether}("");
        require(ok, "fund eth");
    }

    /* ── The invariant ──────────────────────────────────────────────────── */

    /// @notice INVARIANT (the protocol's own, asserted verbatim at
    ///         test/final/F01_CustodyAndConsent.t.sol:198): a transfer that
    ///         SETTLES always breaks the spell.
    ///
    ///         The transfer is sent with a full, ordinary gas budget — no attacker,
    ///         no gas tuning. FAILED pre-fix (share left active); PASSES post-fix.
    function test_B02_INVARIANT_SettledTransferAlwaysBreaksTheSpell() public {
        assertEq(div.activeShares(), 1, "precondition: one active share");

        vm.prank(alice);
        mifrens.transferFrom(alice, bob, 1);

        assertEq(mifrens.ownerOf(1), bob, "transfer settled");
        assertEq(div.activeShares(), 0, "a settled transfer always breaks the spell");
        assertEq(div.enchantedBy(1), address(0), "enchantment cleared");
    }

    /* ── The fix: the callee now fits what the caller forwards ─────────── */

    /// @notice REGRESSION — measures the hook's real cost with a full 3-asset
    ///         basket and shows it now fits inside the forwarded budget. Pre-fix
    ///         this cost ~202k against a 180k forward (silent OOG); post-fix the
    ///         forward is 260k. FAILS if the budget is lowered below the true cost.
    function test_B02_REGRESSION_HookFitsForwardedBudget() public {
        uint256 before = gasleft();
        vm.prank(address(mifrens));
        div.onMiFrenTransfer(1, alice);
        uint256 used = before - gasleft();

        emit log_named_uint("onMiFrenTransfer gas, 3-asset basket", used);
        emit log_named_uint("forwarded by MiFrensGenesis.sol:673      ", GAS_DIVIDEND_FWD);

        assertLe(
            used,
            GAS_DIVIDEND_FWD,
            "hook no longer fits its forwarded budget - B-02 regressed"
        );
    }

    /// @notice CONTROL — with an EMPTY basket the hook fits comfortably, which is
    ///         why the existing F-09 sweep passes. PASSES. This isolates the
    ///         basket loop as the cause rather than a general gas regression.
    function test_B02_Control_EmptyBasketFitsAndSettles() public {
        MiFrensGenesis f2 = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        MiFrensDividend d2 = new MiFrensDividend(address(f2), treasury);
        f2.setDividend(address(d2));

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        f2.mint{value: 0.01 ether}(1);
        vm.prank(bob);
        d2.castSpell(1);
        (bool ok,) = address(d2).call{value: 0.05 ether}("");
        require(ok, "fund");

        vm.prank(bob);
        f2.transferFrom(bob, alice, 1);
        assertEq(d2.activeShares(), 0, "empty basket: spell breaks normally");
    }

    /* ── The consequences no longer occur ──────────────────────────────── */

    /// @notice REGRESSION of CONSEQUENCE 1 — pre-fix the sold fren stayed in
    ///         `activeShares`, so a later honest holder was diluted by a dead share
    ///         whose cut nobody could claim. Post-fix the normal transfer frees the
    ///         share, so the next holder earns the WHOLE deposit and nothing locks.
    function test_B02_REGRESSION_NoDeadShareAfterNormalTransfer() public {
        vm.prank(alice);
        mifrens.transferFrom(alice, bob, 1); // settles + frees the share now
        assertEq(div.activeShares(), 0, "the sold fren was freed");

        // A single honest holder joins.
        address carol = address(0xCAA0);
        vm.deal(carol, 1 ether);
        vm.prank(carol);
        mifrens.mint{value: 0.01 ether}(1); // id 2
        vm.prank(carol);
        div.castSpell(2);
        assertEq(div.activeShares(), 1, "only the live holder counts");

        uint256 deposit = 1 ether;
        (bool ok,) = address(div).call{value: deposit}("");
        require(ok, "deposit");

        // No dead share => carol earns the full deposit, none is stranded.
        assertApproxEqAbs(div.pending(2), deposit, 1e9, "carol earns the whole deposit");
    }

    /// @notice REGRESSION of CONSEQUENCE 2 — pre-fix the seller was paid for the
    ///         BUYER's window via `_castSpell`'s stale branch. Post-fix the transfer
    ///         cleared `enchantedBy`, so the buyer's re-cast is a FRESH join earning
    ///         only from that point, and the seller is credited nothing for it.
    function test_B02_REGRESSION_SellerNotPaidForBuyersWindow() public {
        vm.prank(alice);
        mifrens.transferFrom(alice, bob, 1); // spell broken, enchantedBy[1] == 0
        assertEq(div.enchantedBy(1), address(0), "enchantment cleared by the transfer");

        uint256 aliceOwedBefore = div.owed(alice);

        // Buyer re-enchants — a FRESH join (not the stale re-point).
        vm.prank(bob);
        div.castSpell(1);
        assertEq(div.enchantedBy(1), bob, "buyer freshly enchanted");

        // Fees accrue while BOB owns AND is enchanted → they are BOB's.
        (bool ok,) = address(div).call{value: 1 ether}("");
        require(ok, "deposit");

        assertApproxEqAbs(div.pending(1), 1 ether, 1e9, "the buyer earns their own window");
        assertEq(div.owed(alice), aliceOwedBefore, "seller credited nothing for the buyer's window");
    }
}

/**
 * @dev Where the cliff is, measured with COLD storage.
 *
 *  Fixture construction happens in `setUp()`, which the EVM treats as a separate
 *  transaction, so every slot the settle loop touches is cold when the transfer
 *  runs — the same conditions as a real user's `transferFrom`. Building the
 *  fixture inside the test body instead leaves those slots warm and understates
 *  the cost by ~39k, which is enough to hide the finding.
 *
 *  Each child fixes one basket size and asserts the protocol's own invariant.
 */
abstract contract B02_BasketSize is Test {
    MiFrensGenesis f;
    MiFrensDividend d;
    address holder = address(0xA11CE);
    address buyer = address(0xB0B);

    function _n() internal pure virtual returns (uint256);

    function setUp() public {
        f = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        d = new MiFrensDividend(address(f), address(0x7EA));
        f.setDividend(address(d));
        vm.prank(address(0x7EA));
        d.setFunder(address(this));

        vm.deal(holder, 1 ether);
        vm.prank(holder);
        f.mint{value: 0.01 ether}(1);
        vm.prank(holder);
        d.castSpell(1);

        uint256 n = _n();
        for (uint256 i; i < n; ++i) {
            Coin c = new Coin();
            c.mint(address(this), 1_000_000e6);
            c.approve(address(d), type(uint256).max);
            d.fundToken(address(c), 1000e6);
        }
        (bool ok,) = address(d).call{value: 0.05 ether}("");
        require(ok, "fund");
    }

    /// The protocol's invariant (test/final/F01_CustodyAndConsent.t.sol:198):
    /// a transfer that settles always breaks the spell.
    function test_SettledTransferBreaksTheSpell() public {
        vm.prank(holder);
        f.transferFrom(holder, buyer, 1);
        assertEq(f.ownerOf(1), buyer, "transfer settled");
        assertEq(d.activeShares(), 0, "settled transfer must break the spell");
    }

    /// Cost of the hook under cold storage, for the record.
    function test_MeasureHookGas() public {
        uint256 before = gasleft();
        vm.prank(address(f));
        d.onMiFrenTransfer(1, holder);
        uint256 used = before - gasleft();
        emit log_named_uint(string.concat("assets=", vm.toString(_n()), " cold gas"), used);
        emit log_named_uint("budget forwarded (MiFrensGenesis.sol:97)", 180_000);
    }
}

contract B02_Basket0 is B02_BasketSize { function _n() internal pure override returns (uint256) { return 0; } }
contract B02_Basket1 is B02_BasketSize { function _n() internal pure override returns (uint256) { return 1; } }
contract B02_Basket2 is B02_BasketSize { function _n() internal pure override returns (uint256) { return 2; } }
contract B02_Basket3 is B02_BasketSize { function _n() internal pure override returns (uint256) { return 3; } }
