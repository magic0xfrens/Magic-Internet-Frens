// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";

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

/// @dev A registry whose `donateToReserve` re-enters `castSpell` on the SAME
///      tokenId. `_castSpell` collects the enchant fee (an external call) BEFORE
///      `activeShares += 1` and carries no reentrancy guard.
contract ReentrantRegistry {
    MiFrensDividend public div;
    Coin public tok;
    uint256 public fee;
    uint256 public target;
    bool armed;
    constructor(Coin _t, uint256 _fee) { tok = _t; fee = _fee; }
    function wire(MiFrensDividend d) external { div = d; }
    function arm(uint256 id) external { target = id; armed = true; }
    function enchantFee() external view returns (uint256) { return fee; }
    function currentToken() external view returns (address) { return address(tok); }
    address public poke;
    function setPoke(address p) external { poke = p; }
    function donateToReserve(uint256 amount) external {
        tok.transferFrom(msg.sender, address(this), amount);
        //  Re-enter THROUGH THE OWNER, because `_castSpell` checks
        //  `ownerOf(tokenId) == msg.sender`. Any re-entrant path that reaches the
        //  owner's code during the fee collection satisfies that check.
        if (armed) { armed = false; Holder(poke).recast(); }
    }
}

/// @dev A contract that owns the fren and re-casts when poked mid-fee-collection.
contract Holder {
    MiFrensDividend public div;
    uint256 public id;
    constructor(MiFrensDividend d, uint256 i) { div = d; id = i; }
    function cast() external { div.castSpell(id); }
    function recast() external { div.castSpell(id); }
    function approveFee(address t, address to) external {
        Coin(t).approve(to, type(uint256).max);
    }
    function send(address col, address to) external {
        MiFrensGenesis(col).transferFrom(address(this), to, id);
    }
}

contract T9bDividendConservation is Test {
    MiFrensGenesis col;
    MiFrensDividend div;
    Coin usdg;
    Coin nvda;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address carol = address(0xCA401);
    address treasury = address(0x7EA);

    function setUp() public {
        col = new MiFrensGenesis("MiFrens", "MIF", 3, 6, 0.01 ether, 3, "ipfs://mf/");
        div = new MiFrensDividend(address(col), treasury);
        col.setDividend(address(div));
        vm.prank(treasury); div.setFunder(address(this));
        usdg = new Coin(); nvda = new Coin();
        usdg.mint(address(this), 1e12); nvda.mint(address(this), 1e24);
        usdg.approve(address(div), type(uint256).max);
        nvda.approve(address(div), type(uint256).max);
        vm.deal(alice, 10 ether); vm.deal(bob, 10 ether); vm.deal(carol, 10 ether);
    }

    function _mint(address who, uint256 n) internal {
        vm.prank(who); col.mint{value: 0.01 ether * n}(n);
    }

    // ── REFUTATION 1: 6-decimal + 18-decimal basket, casts / transfers / claims
    //    interleaved. Total paid out must never exceed total funded, and a second
    //    claim must pay zero.
    function test_R1_BasketConservesAcrossTransfersAndDecimals() public {
        _mint(alice, 1); _mint(bob, 1); _mint(carol, 1);
        vm.prank(alice); div.castSpell(1);
        vm.prank(bob);   div.castSpell(2);

        div.fundToken(address(usdg), 1_000e6);      // 6dp, 2 active
        div.fundToken(address(nvda), 3e18);         // 18dp, 2 active

        vm.prank(carol); div.castSpell(3);          // joins AFTER the deposits
        div.fundToken(address(usdg), 999e6);        // 3 active, indivisible by 3

        vm.prank(alice); div.claimTokens(1);
        vm.prank(alice); div.claimTokens(1);        // double-claim attempt

        vm.prank(bob); col.transferFrom(bob, alice, 2);   // bob leaves mid-stream
        vm.prank(bob); div.withdrawOwedToken(address(usdg));
        vm.prank(bob); div.withdrawOwedToken(address(nvda));

        div.fundToken(address(usdg), 100e6);        // 2 active now
        vm.prank(carol); div.claimTokens(3);
        vm.prank(alice); div.claimTokens(1);
        vm.prank(alice); div.castSpell(2);
        vm.prank(alice); div.claimTokens(2);

        uint256 fundedU = 1_000e6 + 999e6 + 100e6;
        uint256 outU = usdg.balanceOf(alice) + usdg.balanceOf(bob) + usdg.balanceOf(carol);
        uint256 fundedN = 3e18;
        uint256 outN = nvda.balanceOf(alice) + nvda.balanceOf(bob) + nvda.balanceOf(carol);

        assertLe(outU, fundedU, "never pays out more USDG than was funded");
        assertLe(outN, fundedN, "never pays out more xNVDA than was funded");
        // Dust bound: <= activeShares-1 raw units per deposit, 4 deposits.
        assertGe(outU, fundedU - 12, "USDG loss is bounded by rounding dust");
        assertGe(outN, fundedN - 12, "xNVDA loss is bounded by rounding dust");
        assertEq(usdg.balanceOf(address(div)), fundedU - outU, "residue is exactly the dust");
        // Carol, who joined after the first two deposits, got no back-pay.
        assertLt(usdg.balanceOf(carol), 400e6, "late joiner drew no history");
    }

    // ── REFUTATION 2: ETH path, same shape.
    function test_R2_EthConservesAcrossTransfers() public {
        _mint(alice, 1); _mint(bob, 1);
        vm.prank(alice); div.castSpell(1);
        vm.prank(bob);   div.castSpell(2);

        (bool ok, ) = address(div).call{value: 1 ether}(""); assertTrue(ok, "fund");
        uint256 a0 = alice.balance; uint256 b0 = bob.balance;

        vm.prank(alice); div.claim(1);
        vm.prank(alice); div.claim(1);                 // double claim
        vm.prank(bob); col.transferFrom(bob, carol, 2);
        vm.prank(bob); div.withdrawOwed();
        vm.prank(bob); div.withdrawOwed();             // double withdraw

        uint256 got = (alice.balance - a0) + (bob.balance - b0);
        assertLe(got, 1 ether, "no over-payment");
        assertGe(got, 1 ether - 2, "no silent loss beyond dust");
        assertEq(address(div).balance, 1 ether - got, "residue = dust");
    }

    // ── FINDING PROBE: `_castSpell` makes an external call (the enchant fee →
    //    `registry.donateToReserve`) BEFORE `activeShares += 1` and has no
    //    reentrancy guard, so a re-entering registry double-counts the divisor
    //    for a single token — permanently, with no path to correct it.
    function test_F_CastSpellReentrancyDoubleCountsActiveShares() public {
        ReentrantRegistry reg = new ReentrantRegistry(usdg, 10e6);
        reg.wire(div);
        vm.prank(treasury); div.setRegistry(address(reg));

        _mint(alice, 1);
        Holder h = new Holder(div, 1);
        vm.prank(alice); col.transferFrom(alice, address(h), 1); // everMoved -> fee applies
        usdg.mint(address(h), 1_000e6);
        h.approveFee(address(usdg), address(div));
        reg.setPoke(address(h));

        //  CONTROL: a non-re-entering cast counts exactly one share.
        assertEq(div.activeShares(), 0, "nobody enchanted yet");

        reg.arm(1);
        h.cast();

        assertEq(div.activeShares(), 2, "ONE enchanted fren counted TWICE in the divisor");
        assertEq(div.enchantedBy(1), address(h), "single token, single caster");

        // The over-count is permanent: the only decrement is one per transfer.
        h.send(address(col), carol);
        assertEq(div.activeShares(), 1, "a phantom share survives the transfer");
        assertEq(div.enchantedBy(1), address(0), "with no token behind it");

        // Consequence: every later deposit is divided by a divisor larger than the
        // real claimant set, so the difference is stranded in the contract.
        usdg.mint(carol, 1_000e6);
        vm.prank(carol); usdg.approve(address(div), type(uint256).max);
        vm.prank(carol); div.castSpell(1);
        (bool ok, ) = address(div).call{value: 2 ether}(""); assertTrue(ok, "fund");
        assertEq(div.activeShares(), 2, "2 counted, 1 real");
        assertEq(div.pending(1), 1 ether, "carol can only ever draw HALF the pot");
        assertEq(address(div).balance, 2 ether, "the other half is stranded");
    }
}
