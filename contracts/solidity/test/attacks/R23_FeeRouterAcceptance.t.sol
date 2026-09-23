// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReauditLocalManagers} from "../audit_reaudit/RotationTotalityLocal.t.sol";

contract R23FeeSink { receive() external payable {} }

contract R23SizedFeeRouter {
    uint256 immutable mode;
    constructor(uint256 m) { mode = m; }
    function route(uint256 amount, address, address, uint256, uint256)
        external view returns (uint256, uint256, uint256)
    {
        uint256 m = mode;
        if (m == 0) return (0, 0, 0); // wrong sum
        if (m == 1) { assembly ("memory-safe") { mstore(0, amount) return(0, 32) } }
        if (m == 2) return (amount, 0, 0);
        // ABI-compatible trailing data must not invalidate a valid prefix.
        bytes memory out = abi.encode(amount, uint256(0), uint256(0), uint256(123));
        assembly ("memory-safe") { return(add(out, 32), mload(out)) }
    }
}

contract R23FeeRouterAcceptance is ReauditLocalManagers {
    function _check(uint256 mode, bool custom) internal {
        _boot(20 ether, 0);
        R23FeeSink sink = new R23FeeSink();
        hook.setGuild(address(sink));
        hook.setGuildBps(1000);
        hook.setDefaultTaxBps(300);
        hook.setActiveProposer(address(0));
        hook.setSnipeParams(0, 0);
        hook.setLegacyBuyback(address(0), 0, 0);
        hook.setFeeRouter(mode == 4 ? address(0xBEEF) : address(new R23SizedFeeRouter(mode)));
        vm.roll(block.number + 40);
        assertGt(_buy(0.01 ether, victim), 0);
        uint256 fee = 0.01 ether * 300 / 10_000;
        assertEq(address(sink).balance, custom ? fee : fee / 10,
            "custom routing or built-in fallback amount must be exact");
    }
    function test_wrongSumUsesBuiltIn() public { _check(0, false); }
    function test_shortResponseUsesBuiltIn() public { _check(1, false); }
    function test_validCustomSplitHonored() public { _check(2, true); }
    function test_validPrefixWithTrailingDataHonored() public { _check(3, true); }
    function test_codelessRouterUsesBuiltIn() public { _check(4, false); }
}
