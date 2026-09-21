// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockToken} from "../attacks/K3b_TokYieldLockout.t.sol";
import {StubPM, StubRegistry, StubHook, StubERC721} from "../attacks/K3c_RotationStrandsPerpEngine.t.sol";

contract RejectingYieldStaker {
    bool public reject = true;
    function deposit(MockToken token, PerpVault vault, uint256 amount) external {
        token.approve(address(vault), amount);
        vault.depositToken(amount);
    }
    function claim(PerpVault vault) external returns (uint256) { return vault.claimTokYield(); }
    function acceptPayments() external { reject = false; }
    receive() external payable { require(!reject, "reject reward"); }
}

/// Production engine AND vault; registry transitions and pool prices are stubs.
/// No target storage writes; fees enter via the production hook-only entrypoint.
contract PerpVaultEngineWriteoffTest is Test {
    PerpEngine engine;
    PerpVault vault;
    StubRegistry registry;
    StubHook hook;
    MockToken token;
    MockToken quote;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant TREASURY = address(0x7777);

    function setUp() public {
        token = new MockToken();
        quote = new MockToken();
        registry = new StubRegistry(address(token));
        hook = new StubHook();
        engine = new PerpEngine(IPoolManager(address(new StubPM())), address(hook),
            address(registry), address(new StubERC721()), address(0xD1), TREASURY, address(this));
        vault = new PerpVault(address(engine), address(registry));
        engine.setVault(address(vault));
        token.mint(ALICE, 1000 ether);
        token.mint(BOB, 9000 ether);
        vm.prank(ALICE); token.approve(address(vault), type(uint256).max);
        vm.prank(BOB); token.approve(address(vault), type(uint256).max);
        vm.deal(address(hook), 20 ether);
    }

    function _accrue(uint256 amount) internal {
        vm.prank(address(hook));
        engine.creditPerpFeeToken{value: amount}();
    }

    function _roundTrip() internal {
        uint256 pot = engine.tokYieldEth();
        uint256 cumulative = engine.tokYieldCumulative();
        uint256 treasuryBefore = TREASURY.balance;
        registry.setGenerationQuote(1, address(quote));
        engine.syncGeneration();
        assertEq(engine.tokYieldEth(), 0);
        assertEq(engine.tokYieldCumulative(), cumulative);
        assertEq(TREASURY.balance - treasuryBefore, pot);
        registry.setGenerationQuote(1, address(0));
        engine.syncGeneration();
        assertEq(engine.quote(), address(0));
    }

    function test_ProductionEngineRepeatedWriteoffsDoNotResurrectClaims() public {
        vm.prank(ALICE); vault.depositToken(1000 ether);
        _accrue(5 ether);
        _roundTrip();
        _accrue(1 ether);
        vm.prank(BOB); vault.depositToken(9000 ether);
        assertEq(vault.yieldEpoch(), 1);
        assertApproxEqAbs(vault.pendingTokYield(ALICE), 1 ether, 1e9);
        assertEq(vault.totalTokYieldPulled() + engine.tokYieldEth(), engine.tokYieldCumulative());
        _roundTrip();
        _accrue(10 ether);
        vm.prank(ALICE); uint256 a = vault.claimTokYield();
        vm.prank(BOB); uint256 b = vault.claimTokYield();
        assertApproxEqAbs(a, 1 ether, 1e9);
        assertApproxEqAbs(b, 9 ether, 1e9);
        assertEq(ALICE.balance, a);
        assertEq(BOB.balance, b);
        assertEq(vault.yieldEpoch(), 2);
        assertLe(a + b, 10 ether);
        assertEq(token.balanceOf(address(engine)), 10_000 ether);
        assertEq(engine.totalTokenAssets(), 10_000 ether);
    }

    function testFuzz_ProductionWriteoffPreviewAndReverseClaims(uint96 rawReward) public {
        uint256 reward = bound(uint256(rawReward), 1e12, 5 ether);
        vm.prank(ALICE); vault.depositToken(1000 ether);
        _accrue(reward);
        _roundTrip();
        _accrue(reward);
        vm.prank(BOB); vault.depositToken(9000 ether);
        assertEq(vault.yieldEpoch(), 1);
        _roundTrip();
        assertEq(vault.pendingTokYield(ALICE), 0, "preview retires Alice's old reward");
        assertEq(vault.pendingTokYield(BOB), 0);
        _accrue(reward);
        uint256 aliceDue = vault.pendingTokYield(ALICE);
        uint256 bobDue = vault.pendingTokYield(BOB);
        uint256 dustBound = vault.tokShares() / 1e18 + 4;
        assertApproxEqAbs(aliceDue, reward / 10, dustBound);
        assertApproxEqAbs(bobDue, reward * 9 / 10, dustBound);
        assertLe(aliceDue + bobDue, reward);
        vm.prank(BOB); assertEq(vault.claimTokYield(), bobDue);
        assertEq(vault.pendingTokYield(ALICE), aliceDue, "first claim cannot change second entitlement");
        vm.prank(ALICE); assertEq(vault.claimTokYield(), aliceDue);
        assertEq(ALICE.balance, aliceDue);
        assertEq(BOB.balance, bobDue);
        assertEq(engine.tokYieldEth(), reward - aliceDue - bobDue);
        assertEq(vault.totalTokYieldPulled() + engine.tokYieldEth(), engine.tokYieldCumulative());
        assertEq(vault.yieldEpoch(), 2);
        assertEq(engine.totalTokenAssets(), 10_000 ether);
    }

    function test_ZeroAndDuplicateClaimsCannotAdvanceWriteoffAccounting() public {
        vm.prank(ALICE); vault.depositToken(1000 ether);
        _accrue(5 ether);
        _roundTrip();
        uint256 watermark = vault.totalTokYieldPulled();
        uint256 cumulative = engine.tokYieldCumulative();
        vm.prank(ALICE);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimTokYield();
        assertEq(vault.yieldEpoch(), 0, "reverted sync cannot persist an epoch");
        assertEq(vault.totalTokYieldPulled(), watermark);
        assertEq(engine.tokYieldCumulative(), cumulative);
        assertEq(engine.tokYieldEth(), 0);
        assertEq(vault.pendingTokYield(ALICE), 0);

        _accrue(1 ether);
        uint256 due = vault.pendingTokYield(ALICE);
        vm.prank(ALICE); assertEq(vault.claimTokYield(), due);
        assertEq(vault.yieldEpoch(), 1);
        watermark = vault.totalTokYieldPulled();
        uint256 pot = engine.tokYieldEth();
        uint256 paidBalance = ALICE.balance;
        vm.prank(ALICE);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimTokYield();
        assertEq(vault.yieldEpoch(), 1);
        assertEq(vault.totalTokYieldPulled(), watermark);
        assertEq(engine.tokYieldEth(), pot);
        assertEq(ALICE.balance, paidBalance);
        assertEq(vault.pendingTokYield(ALICE), 0);
    }

    function test_RejectingStakerPreservesRewardAndDoesNotBlockOtherStaker() public {
        RejectingYieldStaker receiver = new RejectingYieldStaker();
        token.mint(address(receiver), 1000 ether);
        receiver.deposit(token, vault, 1000 ether);
        _accrue(5 ether);
        _roundTrip();
        _accrue(1 ether);
        vm.prank(BOB); vault.depositToken(9000 ether);
        _roundTrip();
        _accrue(10 ether);
        uint256 due = vault.pendingTokYield(address(receiver));
        uint256 bobDue = vault.pendingTokYield(BOB);
        uint256 watermark = vault.totalTokYieldPulled();
        vm.expectRevert(PerpEngine.EthSend.selector);
        receiver.claim(vault);
        assertEq(engine.tokYieldEth(), 10 ether, "failed send cannot consume pot");
        assertEq(vault.totalTokYieldPulled(), watermark);
        assertEq(vault.yieldEpoch(), 1, "failed claim rolls back second epoch sync");
        assertEq(vault.pendingTokYield(address(receiver)), due);
        assertEq(address(receiver).balance, 0);
        vm.prank(BOB); assertEq(vault.claimTokYield(), bobDue);
        assertEq(vault.pendingTokYield(address(receiver)), due);
        receiver.acceptPayments();
        assertEq(receiver.claim(vault), due);
        assertEq(address(receiver).balance, due);
        assertEq(BOB.balance, bobDue);
        assertEq(vault.yieldEpoch(), 2);
        assertEq(engine.tokYieldEth(), 10 ether - due - bobDue);
        assertEq(vault.totalTokYieldPulled() + engine.tokYieldEth(), engine.tokYieldCumulative());
    }
}
