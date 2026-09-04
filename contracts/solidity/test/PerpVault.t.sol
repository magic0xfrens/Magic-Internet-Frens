// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerpVault} from "../cauldron/PerpVault.sol";

/**
 * Unit coverage for the Community PLV (PerpVault) — NO fork needed. A mock engine
 * stands in for the PerpEngine's PLV accounting so we can exercise share pricing,
 * yield accrual (share price rises), utilization-limited withdrawals, the exit
 * queue, and the structurally-protected token side, deterministically.
 */
contract PerpVaultTest is Test {
    MockEngine engine;
    MockToken token;
    PerpVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new MockToken();
        engine = new MockEngine(token);
        vault = new PerpVault(address(engine), address(engine)); // engine doubles as registry
        engine.setVault(address(vault));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        token.mint(alice, 1_000_000 ether);
        token.mint(bob, 1_000_000 ether);
    }

    // ── ETH side ──────────────────────────────────────────────────────────────

    function test_FirstDeposit_RedeemsOneToOne() public {
        vm.prank(alice);
        uint256 shares = vault.depositEth{value: 1 ether}();
        // Shares are virtual-offset scaled (1e6×), but what matters is redeemable
        // value ~= deposit (audit V-02: offset defeats inflation attacks).
        assertEq(shares, 1 ether * 1e6, "shares = assets x OFFSET");
        assertEq(engine.plv(), 1 ether, "ETH forwarded to the engine PLV");
        (uint256 redeemable,,) = vault.ethPosition(alice);
        assertApproxEqAbs(redeemable, 1 ether, 2, "redeemable ~= deposit");
    }

    /// Donation / first-depositor inflation attack is defeated by the offset: a
    /// 1-wei first deposit + a large direct PLV donation must NOT let the attacker
    /// steal a later depositor's funds (victim still gets fair redeemable value).
    function test_InflationAttack_Defeated() public {
        vm.prank(alice);
        vault.depositEth{value: 1 wei}();          // attacker seeds 1 wei
        engine.accrueYield{value: 10 ether}();     // attacker "donates" 10 ETH to plv

        vm.prank(bob);
        vault.depositEth{value: 1 ether}();        // victim deposits 1 ETH
        (uint256 bobRedeem,,) = vault.ethPosition(bob);
        // Bob must be able to redeem ~his 1 ETH (not lose it to the attacker).
        assertApproxEqAbs(bobRedeem, 1 ether, 0.01 ether, "victim keeps ~his deposit");
    }

    function test_Yield_RaisesSharePrice() public {
        vm.prank(alice);
        vault.depositEth{value: 1 ether}();

        // Simulate fees routed into the PLV (the engine leaves yield in plv).
        engine.accrueYield{value: 1 ether}();

        (uint256 redeemable,,) = vault.ethPosition(alice);
        assertApproxEqAbs(redeemable, 2 ether, 2, "alice's share now worth ~2x");

        // A new depositor pays the HIGHER price → redeems ~his deposit, and holds
        // ~half the share-value of alice (who's now worth ~2 ETH).
        vm.prank(bob);
        vault.depositEth{value: 1 ether}();
        (uint256 bobRedeem,,) = vault.ethPosition(bob);
        assertApproxEqAbs(bobRedeem, 1 ether, 1e12, "bob redeems ~his 1 ETH");
    }

    function test_Withdraw_LimitedToFree_ThenQueueAndClaim() public {
        vm.prank(alice);
        uint256 shares = vault.depositEth{value: 1 ether}();

        // Engine lends 0.9 ETH to a long → only 0.1 ETH free (high utilization).
        engine.lend(0.9 ether);
        assertEq(engine.freeEth(), 0.1 ether, "0.1 free");

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawEth(shares);
        assertApproxEqAbs(paid, 0.1 ether, 2, "paid the free buffer instantly");
        assertApproxEqAbs(queued, 0.9 ether, 2, "rest queued");
        assertApproxEqAbs(alice.balance - balBefore, 0.1 ether, 2, "alice got the instant part");

        // Position closes → liquidity returns → alice claims the queued remainder.
        engine.repay(0.9 ether, 0);
        vm.prank(alice);
        uint256 claimed = vault.claimPendingEth();
        assertApproxEqAbs(claimed, 0.9 ether, 2, "claimed the queued part");
        assertApproxEqAbs(alice.balance - balBefore, 1 ether, 3, "alice made whole");
    }

    function test_QueuedExit_StopsEarningYield() public {
        // Alice and Bob each stake 1 ETH.
        vm.prank(alice); vault.depositEth{value: 1 ether}();
        vm.prank(bob); vault.depositEth{value: 1 ether}();

        // Lend everything so a withdrawal must queue.
        engine.lend(2 ether);

        // Alice exits fully → her whole claim queues (0 free).
        uint256 aliceShares = vault.ethShareOf(alice);
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawEth(aliceShares);
        assertEq(paid, 0, "nothing free");
        assertApproxEqAbs(queued, 1 ether, 2, "alice's 1 ETH queued");

        // Now yield accrues. It must benefit BOB (still staked), not Alice (queued).
        engine.repay(2 ether, 0);         // free the liquidity back
        engine.accrueYield{value: 1 ether}();

        (uint256 aliceRedeem,, uint256 alicePending) = vault.ethPosition(alice);
        assertEq(aliceRedeem, 0, "alice has no live shares");
        assertApproxEqAbs(alicePending, 1 ether, 2, "alice's queued claim is FIXED (no yield)");

        (uint256 bobRedeem,,) = vault.ethPosition(bob);
        assertApproxEqAbs(bobRedeem, 2 ether, 3, "bob captured ALL the yield");
    }

    // ── TOKEN side ────────────────────────────────────────────────────────────

    function test_TokenDeposit_Withdraw() public {
        vm.startPrank(alice);
        token.approve(address(vault), type(uint256).max);
        uint256 shares = vault.depositToken(1000 ether);
        vm.stopPrank();
        assertEq(shares, 1000 ether * 1e6, "shares = assets x OFFSET");
        assertEq(engine.plvTok(), 1000 ether, "inventory forwarded to engine");

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawToken(shares);
        assertApproxEqAbs(paid, 1000 ether, 2, "instant (nothing lent)");
        assertEq(queued, 0, "no queue");
        assertApproxEqAbs(token.balanceOf(alice) - balBefore, 1000 ether, 2, "token returned");
    }

    function test_TokenWithdraw_QueuesUnderUtilization() public {
        vm.startPrank(alice);
        token.approve(address(vault), type(uint256).max);
        uint256 shares = vault.depositToken(1000 ether);
        vm.stopPrank();

        engine.lendTok(900 ether); // shorts borrowed most of the inventory
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawToken(shares);
        assertApproxEqAbs(paid, 100 ether, 2, "only free inventory paid");
        assertApproxEqAbs(queued, 900 ether, 2, "rest queued");

        engine.repayTok(900 ether);
        vm.prank(alice);
        uint256 claimed = vault.claimPendingToken();
        assertApproxEqAbs(claimed, 900 ether, 2, "queued token claimed after shorts close");
    }
}

// ── mocks ───────────────────────────────────────────────────────────────────

contract MockEngine {
    MockToken public immutable token;
    address public vault;
    uint256 public plv;       // free ETH
    uint256 public lentEth;   // ETH lent to longs
    uint256 public plvTok;    // free token inventory
    uint256 public lentTok;   // token lent to shorts

    constructor(MockToken _t) { token = _t; }
    function setVault(address v) external { vault = v; }

    // IVaultRegistry
    function currentToken() external view returns (address) { return address(token); }

    // IPerpEngineVault
    function fundFromVault() external payable { plv += msg.value; }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "free");
        plv -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "send");
    }
    function fundTokenFromVault(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        plvTok += amount;
    }
    function withdrawPlvTokenTo(uint256 amount, address to) external {
        require(amount <= plvTok, "free");
        plvTok -= amount;
        token.transfer(to, amount);
    }
    function totalEth() external view returns (uint256) { return plv + lentEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external view returns (uint256) { return plvTok + lentTok; }
    function freeToken() external view returns (uint256) { return plvTok; }
    // side-attributed token-side ETH reward accrual marker (read on token deposit).
    uint256 public tokYieldCumulative;
    function withdrawTokYieldTo(uint256 amount, address to) external { (bool ok,) = to.call{value: amount}(""); require(ok); }

    // simulation helpers
    function lend(uint256 a) external { plv -= a; lentEth += a; }
    function repay(uint256 a, uint256 profit) external { lentEth -= a; plv += a + profit; }
    function accrueYield() external payable { plv += msg.value; }
    function lendTok(uint256 a) external { plvTok -= a; lentTok += a; }
    function repayTok(uint256 a) external { lentTok -= a; plvTok += a; }
    receive() external payable {}
}

contract MockToken {
    string public name = "Mock"; string public symbol = "MCK"; uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) { _move(msg.sender, to, a); return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _move(f, to, a); return true;
    }
    function _move(address f, address to, uint256 a) private {
        balanceOf[f] -= a; balanceOf[to] += a;
    }
}
