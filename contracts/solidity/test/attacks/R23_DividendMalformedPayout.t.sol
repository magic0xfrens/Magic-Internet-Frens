// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {DividendBasketTest} from "../DividendBasket.t.sol";

contract R23PayoutToken {
    mapping(address => uint256) public balanceOf;
    bool public malformed;
    function mint(address to, uint256 n) external { balanceOf[to] += n; }
    function setMalformed(bool value) external { malformed = value; }
    function transferFrom(address from, address to, uint256 n) external returns (bool) {
        balanceOf[from] -= n; balanceOf[to] += n; return true;
    }
    function transfer(address to, uint256 n) external returns (bool) {
        if (malformed) assembly ("memory-safe") { mstore(0, 2) return(0, 32) }
        balanceOf[msg.sender] -= n; balanceOf[to] += n; return true;
    }
}

contract R23DividendMalformedPayout is DividendBasketTest {
    function test_R23_MalformedAssetCannotBlockHealthyBasketClaim() public {
        _mintTo(alice, 1);
        vm.prank(alice); div.castSpell(1);
        R23PayoutToken bad = new R23PayoutToken();
        bad.mint(address(this), 100);
        div.fundToken(address(bad), 100);
        div.fundToken(address(usdg), 1000e6);
        bad.setMalformed(true);
        vm.prank(alice); div.claimTokens(1);
        assertEq(usdg.balanceOf(alice), 1000e6, "healthy asset must be paid");
        assertEq(div.owedAsset(alice, address(bad)), 100, "failed payout retained");
        assertEq(bad.balanceOf(address(div)), 100, "failed asset remains in custody");
        bad.setMalformed(false);
        vm.prank(alice); div.withdrawOwedToken(address(bad));
        assertEq(bad.balanceOf(alice), 100);
        assertEq(div.owedAsset(alice, address(bad)), 0);
    }
}
