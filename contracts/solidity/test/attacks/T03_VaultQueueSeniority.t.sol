// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/**
 * T03 — PerpVault exit-queue seniority.
 *
 * PerpVault.sol:263-287 claims the `_haircut` rule makes a vault loss shared
 * "in proportion rather than by reaction speed", quoting a measured 84%/0%
 * split as the bug it fixes.
 *
 * `_haircut(owed, backing, claims)` (PerpVault.sol:280-287) compares the queue
 * against `engine.totalEth()` — the WHOLE vault, live-share equity included —
 * so it only writes a queued claim down once the queue alone exceeds every
 * asset in the vault. Below that line the queue is paid in full and
 * `assetsEth()` (PerpVault.sol:162-165) saturates at zero for whoever stayed.
 *
 * This test reproduces the exact scenario the comment says is fixed.
 *
 * No fork needed — the vault talks only to IPerpEngineVault/IVaultRegistry.
 */
contract T03_VaultQueueSeniority is Test {
    T03Engine engine;
    PerpVault vault;

    address lpA = address(0xA11CE); // reacts: queues an exit before the loss
    address lpB = address(0xB0B);   // does nothing

    function setUp() public {
        engine = new T03Engine();
        vault = new PerpVault(address(engine), address(engine));
        engine.setVault(address(vault));
        vm.deal(lpA, 100 ether);
        vm.deal(lpB, 100 ether);
    }

    /// A 50% vault loss is borne 0% by the LP who queued first and 100% by the
    /// LP who stayed staked — despite identical share counts at the moment the
    /// loss lands.
    function test_QueuedExitIsSeniorToLiveShares() public {
        // ── both LPs stake 1 ETH ────────────────────────────────────────────
        vm.prank(lpA);
        uint256 sharesA = vault.depositEth{value: 1 ether}();
        vm.prank(lpB);
        uint256 sharesB = vault.depositEth{value: 1 ether}();
        assertApproxEqRel(sharesA, sharesB, 1e12, "equal stakes, equal shares");
        assertEq(engine.plv(), 2 ether, "2 ETH in the PLV");

        // ── the engine lends everything to open longs (utilization 100%) ────
        engine.lend(2 ether);
        assertEq(engine.freeEth(), 0, "nothing instantly withdrawable");

        // ── lpA queues a full exit. Costs nothing; no fee, no penalty. ──────
        vm.prank(lpA);
        (uint256 paid, uint256 queued) = vault.withdrawEth(sharesA);
        assertEq(paid, 0, "no free buffer, so it all queues");
        assertApproxEqAbs(queued, 1 ether, 2, "lpA's whole 1 ETH is now a fixed claim");
        assertEq(vault.pendingEth(), queued, "queue = 1 ETH");

        // lpB did nothing at all.
        assertEq(vault.ethShareOf(lpB), sharesB, "lpB still fully staked");

        // ── a 1 ETH bad debt lands (positions closed 1 ETH short) ───────────
        // 2 ETH was lent; only 1 ETH comes back. Vault-wide loss = 50%.
        engine.closeWithLoss(2 ether, 1 ether);
        assertEq(engine.totalEth(), 1 ether, "vault backing halved");

        // ── who eats it? ────────────────────────────────────────────────────
        // _haircut: backing (1 ETH) >= claims (1 ETH) -> NO write-down at all.
        vm.prank(lpA);
        uint256 aClaimed = vault.claimPendingEth();

        vm.prank(lpB);
        (uint256 bPaid, uint256 bQueued) = vault.withdrawEth(sharesB);

        console2.log("vault-wide loss (wei)      :", uint256(1 ether));
        console2.log("lpA (queued first) recovered:", aClaimed);
        console2.log("lpB (stayed staked) paid    :", bPaid);
        console2.log("lpB (stayed staked) queued  :", bQueued);
        console2.log("engine.totalEth() after     :", engine.totalEth());

        assertApproxEqAbs(aClaimed, 1 ether, 2, "lpA recovered 100% of a 50%-impaired vault");
        assertEq(bPaid + bQueued, 0, "lpB recovered 0% - he ate the ENTIRE loss");

        bool reached = true;
        assertTrue(reached, "T03: queued exits are senior; the documented pro-rata fix never engages");
    }

    /// The same mechanism as a strictly-dominant strategy: queueing is free and
    /// reversible-in-effect (re-deposit later), so every rational LP queues the
    /// moment bad debt looks possible. The last LP left holding shares is the
    /// residual claimant on the whole book.
    function test_QueueingIsFreeAndDominant() public {
        vm.prank(lpA);
        uint256 sharesA = vault.depositEth{value: 1 ether}();
        vm.prank(lpB);
        vault.depositEth{value: 1 ether}();
        engine.lend(2 ether);

        // lpA queues. Measure what it costs him if NOTHING bad happens.
        vm.prank(lpA);
        vault.withdrawEth(sharesA);
        engine.closeWithLoss(2 ether, 2 ether); // no loss at all
        uint256 before = lpA.balance;
        vm.prank(lpA);
        vault.claimPendingEth();
        uint256 recovered = lpA.balance - before;
        console2.log("lpA recovery when NOTHING goes wrong:", recovered);
        assertApproxEqAbs(recovered, 1 ether, 2, "queueing costs the queuer nothing");

        bool reached = true;
        assertTrue(reached, "T03: the escape hatch is free, so using it is dominant");
    }
}

/// @dev Minimal IPerpEngineVault/IVaultRegistry stand-in with an explicit
/// bad-debt lever. Mirrors PerpEngine's real accounting:
/// totalEth() = plv + longOiEth, freeEth() = plv.
contract T03Engine {
    address public vault;
    uint256 public plv;      // free quote (PerpEngine.plv)
    uint256 public lent;     // PerpEngine.longOiEth
    uint256 public plvTok;
    uint256 public lentTok;
    uint256 public tokYieldCumulative;

    function setVault(address v) external { vault = v; }
    function currentToken() external view returns (address) { return address(this); }
    function quote() external pure returns (address) { return address(0); }

    function fundFromVault(uint256 amount) external payable { plv += amount; }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "free");
        plv -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "send");
    }
    function fundTokenFromVault(uint256 amount) external { plvTok += amount; }
    function withdrawPlvTokenTo(uint256, address) external {}
    function withdrawTokYieldTo(uint256 amount, address to) external {
        (bool ok,) = to.call{value: amount}(""); require(ok, "send");
    }
    function totalEth() external view returns (uint256) { return plv + lent; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external view returns (uint256) { return plvTok + lentTok; }
    function freeToken() external view returns (uint256) { return plvTok; }

    // ── simulation levers ──
    function lend(uint256 a) external { plv -= a; lent += a; }
    /// A position closes returning `back` against `principal` lent out; the gap
    /// is bad debt that PerpEngine._absorbPlvLoss/_replenishPlv socialises.
    function closeWithLoss(uint256 principal, uint256 back) external {
        lent -= principal;
        plv += back;
        payable(address(0xdead)).transfer(principal - back);
    }
    receive() external payable {}
}
