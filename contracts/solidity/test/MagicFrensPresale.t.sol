// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../MagicFrensPresale.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1111 * 1e18);
    }
}

contract MagicFrensPresaleTest is Test {
    MagicFrensPresale presale;
    MockToken token;
    address treasury;
    address user1;
    address user2;

    function setUp() public {
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy presale
        presale = new MagicFrensPresale(treasury);

        // Deploy mock token
        token = new MockToken();

        // Give users some ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function test_Deployment() public view {
        assertEq(presale.treasury(), treasury);
        assertEq(presale.PRESALE_PRICE(), 0.01 ether);
        assertEq(presale.MAX_PRESALE_TOKENS(), 1111);
        assertTrue(presale.presaleActive());
        assertFalse(presale.paused());
    }

    function test_Contribute() public {
        vm.startPrank(user1);

        // Contribute 1 token worth (0.01 ETH)
        presale.contribute{value: 0.01 ether}();

        // Check contribution recorded
        (uint256 amount, uint256 tokens, bool claimed) = presale.getContribution(user1);
        assertEq(amount, 0.01 ether);
        assertEq(tokens, 1);
        assertFalse(claimed);

        // Check stats updated
        (
            uint256 raised,
            uint256 sold,
            uint256 remaining,
            bool active,
            bool isPaused
        ) = presale.getPresaleStats();
        assertEq(raised, 0.01 ether);
        assertEq(sold, 1);
        assertEq(remaining, 1110);
        assertTrue(active);
        assertFalse(isPaused);

        vm.stopPrank();
    }

    function test_ContributeMultiple() public {
        vm.startPrank(user1);

        // First contribution
        presale.contribute{value: 0.1 ether}(); // 10 tokens

        // Second contribution
        presale.contribute{value: 0.2 ether}(); // 20 tokens

        // Check total
        (uint256 amount, uint256 tokens, ) = presale.getContribution(user1);
        assertEq(amount, 0.3 ether);
        assertEq(tokens, 30);

        vm.stopPrank();
    }

    function test_ContributeMaxPerAddress() public {
        vm.startPrank(user1);

        // Contribute max (100 tokens = 1 ETH)
        presale.contribute{value: 1 ether}();

        // Try to contribute more - should revert
        vm.expectRevert("Exceeds max per address");
        presale.contribute{value: 0.01 ether}();

        vm.stopPrank();
    }

    function test_ContributeBelowMinimum() public {
        vm.startPrank(user1);

        vm.expectRevert("Below minimum");
        presale.contribute{value: 0.001 ether}();

        vm.stopPrank();
    }

    function test_ContributeNotMultiple() public {
        vm.startPrank(user1);

        vm.expectRevert("Must be multiple of presale price");
        presale.contribute{value: 0.015 ether}();

        vm.stopPrank();
    }

    function test_PresaleSoldOut() public {
        // Fast-forward: sell all tokens
        uint256 batchSize = 100;
        uint256 batches = 1111 / batchSize;
        uint256 remainder = 1111 % batchSize;

        for (uint256 i = 0; i < batches; i++) {
            address buyer = makeAddr(string(abi.encodePacked("buyer", i)));
            vm.deal(buyer, 100 ether);
            vm.prank(buyer);
            presale.contribute{value: uint256(batchSize) * 0.01 ether}();
        }

        if (remainder > 0) {
            address lastBuyer = makeAddr("lastBuyer");
            vm.deal(lastBuyer, 100 ether);
            vm.prank(lastBuyer);
            presale.contribute{value: uint256(remainder) * 0.01 ether}();
        }

        // Presale should auto-end
        assertFalse(presale.presaleActive());

        // New contributions should fail
        vm.startPrank(user1);
        vm.expectRevert("Presale ended");
        presale.contribute{value: 0.01 ether}();
        vm.stopPrank();
    }

    function test_EndPresale() public {
        // Only owner can end presale
        vm.prank(user1);
        vm.expectRevert();
        presale.endPresale();

        // Owner ends presale
        presale.endPresale();
        assertFalse(presale.presaleActive());
    }

    function test_SetTokenAddress() public {
        // Set token address
        presale.setTokenAddress(address(token));
        assertEq(presale.magicFrensToken(), address(token));

        // Can't set again
        vm.expectRevert("Already set");
        presale.setTokenAddress(address(token));
    }

    function test_ClaimTokens() public {
        // User contributes
        vm.startPrank(user1);
        presale.contribute{value: 0.1 ether}(); // 10 tokens
        vm.stopPrank();

        // End presale
        presale.endPresale();

        // Set token address
        presale.setTokenAddress(address(token));

        // Transfer tokens to presale contract
        token.transfer(address(presale), 10 * 1e18);

        // User claims tokens
        vm.startPrank(user1);
        presale.claimTokens();

        // Check user received tokens
        assertEq(token.balanceOf(user1), 10 * 1e18);

        // Check claim recorded
        (, , bool claimed) = presale.getContribution(user1);
        assertTrue(claimed);

        // Can't claim again
        vm.expectRevert("Already claimed");
        presale.claimTokens();
        vm.stopPrank();
    }

    function test_ClaimTokensBeforePresaleEnd() public {
        vm.startPrank(user1);
        presale.contribute{value: 0.1 ether}();

        vm.expectRevert("Presale still active");
        presale.claimTokens();
        vm.stopPrank();
    }

    function test_Withdraw() public {
        // User contributes
        vm.prank(user1);
        presale.contribute{value: 1 ether}();

        // Check presale balance
        assertEq(address(presale).balance, 1 ether);

        // Owner withdraws
        uint256 ownerBalanceBefore = address(this).balance;
        presale.withdraw();
        uint256 ownerBalanceAfter = address(this).balance;

        assertEq(ownerBalanceAfter - ownerBalanceBefore, 1 ether);
        assertEq(address(presale).balance, 0);
    }

    function test_Pause() public {
        // Owner pauses
        presale.togglePause();
        assertTrue(presale.paused());

        // Contributions fail when paused
        vm.startPrank(user1);
        vm.expectRevert("Presale paused");
        presale.contribute{value: 0.01 ether}();
        vm.stopPrank();

        // Owner unpauses
        presale.togglePause();
        assertFalse(presale.paused());

        // Contributions work again
        vm.prank(user1);
        presale.contribute{value: 0.01 ether}();
    }

    function test_Whitelist() public {
        // Enable whitelist-only mode
        presale.toggleWhitelistOnly();
        assertTrue(presale.whitelistOnly());

        // Non-whitelisted user can't contribute
        vm.startPrank(user1);
        vm.expectRevert("Not whitelisted");
        presale.contribute{value: 0.01 ether}();
        vm.stopPrank();

        // Add user1 to whitelist
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        presale.addToWhitelist(addresses);
        assertTrue(presale.whitelist(user1));

        // Now user1 can contribute
        vm.prank(user1);
        presale.contribute{value: 0.01 ether}();

        // Disable whitelist mode
        presale.toggleWhitelistOnly();
        assertFalse(presale.whitelistOnly());

        // Non-whitelisted users can contribute again
        vm.prank(user2);
        presale.contribute{value: 0.01 ether}();
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        // Only owner can set treasury
        vm.prank(user1);
        vm.expectRevert();
        presale.setTreasury(newTreasury);

        // Owner sets new treasury
        presale.setTreasury(newTreasury);
        assertEq(presale.treasury(), newTreasury);
    }
}
