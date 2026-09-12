// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeRouteLib} from "../../cauldron/FeeRouteLib.sol";

/// @notice Minimal 6-decimal ERC20 (a USDG-shaped quote).
contract X4cToken {
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// @notice A correctly-wired guild: {MiFrensDividend} pulls through `fundToken`.
contract X4cRealGuild {
    function fundToken(address asset, uint256 amount) external {
        X4cToken(asset).transferFrom(msg.sender, address(this), amount);
    }
    /// @dev The native leg is a bare value transfer; the dividend credits it here.
    receive() external payable {}
}

/**
 * @title X4c — a codeless recipient is not a successful pull
 *
 *  {FeeRouteLib._fundGuild} delivers a non-native guild share by `approve` +
 *  `fundToken`, through a low-level call whose success it trusts. The EVM
 *  reports success for a call to an address with NO CODE, and `fundToken`
 *  returns nothing, so returndata cannot distinguish the two. Against a
 *  misconfigured `guild` the library therefore reported delivered, {routeSplit}
 *  emitted `GuildFunded`, and the approval was left standing — while the tokens
 *  never moved and no holder was ever credited. The caller believes the share is
 *  gone and never buffers it to the relaunch reserve, so it has no exit.
 *
 *  `routeSplit` is an `external` linked-library function, so calling it here
 *  delegatecalls into the real deployed bytecode with THIS contract as the
 *  token holder — the same context the hook runs it in.
 */
contract X4cCodelessGuildSuccess is Test {
    X4cToken internal tok;

    uint256 internal constant SHARE = 100e6;

    function setUp() public {
        tok = new X4cToken();
        tok.mint(address(this), 1_000e6);
        vm.deal(address(this), 10 ether);
    }

    function test_X4c_codelessGuildIsNotReportedAsAFundedGuild() public {
        address codeless = address(0xDEAD);
        assertEq(codeless.code.length, 0, "premise: the misconfigured guild has no code");

        uint256 leftover = FeeRouteLib.routeSplit(address(tok), codeless, address(0), SHARE, 0);

        emit log_named_uint("leftover reported to the caller", leftover);
        emit log_named_uint("tokens at the codeless guild  ", tok.balanceOf(codeless));
        emit log_named_uint("allowance left standing       ", tok.allowance(address(this), codeless));

        assertEq(leftover, SHARE, "undelivered, so the caller buffers it to the relaunch reserve");
        assertEq(tok.balanceOf(codeless), 0, "the tokens never moved");
        assertEq(tok.balanceOf(address(this)), 1_000e6, "and are still here, claimable");
        assertEq(tok.allowance(address(this), codeless), 0, "no standing allowance is left behind");
    }

    /// @notice THE NATIVE LEG, which the first cut of this fix left open. It is
    ///         the worse of the two: `guild.call{value:}("")` to a codeless
    ///         address SUCCEEDS and the ether really leaves, so the share was
    ///         gone with a success signal on it and the caller never buffered it.
    function test_X4c_codelessGuildIsNotFundedOnTheNativeLegEither() public {
        address codeless = address(0xDEAD);
        assertEq(codeless.code.length, 0, "premise: the misconfigured guild has no code");
        uint256 share = 1 ether;
        uint256 heldBefore = address(this).balance;

        uint256 leftover = FeeRouteLib.routeSplit(address(0), codeless, address(0), share, 0);

        emit log_named_uint("native leftover reported  ", leftover);
        emit log_named_uint("wei at the codeless guild ", codeless.balance);

        assertEq(leftover, share, "undelivered, so the caller buffers it to the relaunch reserve");
        assertEq(codeless.balance, 0, "not one wei left for an address that credits nobody");
        assertEq(address(this).balance, heldBefore, "the ether is still here, recoverable");
    }

    /// @notice The gate must not break the real thing: a guild that DOES pull is
    ///         still reported delivered and still receives the tokens.
    function test_X4c_realGuildStillPulls() public {
        X4cRealGuild g = new X4cRealGuild();

        uint256 leftover = FeeRouteLib.routeSplit(address(tok), address(g), address(0), SHARE, 0);

        emit log_named_uint("leftover for a real guild", leftover);
        emit log_named_uint("tokens pulled            ", tok.balanceOf(address(g)));

        assertEq(leftover, 0, "a real guild still reports delivered");
        assertEq(tok.balanceOf(address(g)), SHARE, "and the tokens really moved");
        assertEq(tok.allowance(address(this), address(g)), 0, "allowance consumed by the pull");

        // ...and on the native leg too.
        uint256 leftoverNative = FeeRouteLib.routeSplit(address(0), address(g), address(0), 1 ether, 0);
        emit log_named_uint("wei delivered to a real guild", address(g).balance);
        assertEq(leftoverNative, 0, "a real guild still reports delivered (native)");
        assertEq(address(g).balance, 1 ether, "and the ether really moved");
    }
}
