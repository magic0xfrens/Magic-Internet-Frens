// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeRouteLib} from "../../cauldron/FeeRouteLib.sol";

/// @notice Minimal 6-decimal ERC20 (a USDG-shaped quote).
contract X4eToken {
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// @notice A correctly-wired perp engine: it must be TOLD about a fee, because it
///         cannot tell a deposit from a stray transfer by looking at its balance.
contract X4eEngine {
    uint256 public nativeCredited;
    uint256 public assetCredited;

    function creditPerpFee() external payable { nativeCredited += msg.value; }

    function creditPerpFeeAsset(address asset, uint256 amount) external {
        X4eToken(asset).transferFrom(msg.sender, address(this), amount);
        assetCredited += amount;
    }
}

/**
 * @title X4e — a codeless delivery target is not a successful delivery
 *
 *  The twin of X4c, on the staker side. {FeeRouteLib._deliver} (and its public
 *  {FeeRouteLib.deliver}) hand a perp fee to the engine through a low-level call
 *  and trusted the success flag. The EVM reports success for a call to an
 *  address with NO CODE, and the pull entrypoints return nothing, so returndata
 *  cannot distinguish the two.
 *
 *  Against a misconfigured `perpEngine` the ERC20 path reported delivered while
 *  the tokens never moved and the approval was left standing; the NATIVE path
 *  was worse — the ether really left and sat at a codeless address with no way
 *  back. Either way the caller believed the share was routed and never buffered
 *  it to the relaunch reserve, so it had no exit.
 *
 *  `routePerp` is an `external` linked-library function, so calling it here
 *  delegatecalls the real deployed bytecode with THIS contract as the fee
 *  holder — the same context {CauldronHook._routePerpFee} runs it in.
 */
contract X4eCodelessDeliverTarget is Test {
    X4eToken internal tok;
    address internal constant CODELESS = address(0xBADC0DE);
    uint256 internal constant SHARE = 100e6;

    function setUp() public {
        tok = new X4eToken();
        tok.mint(address(this), 1_000e6);
        vm.deal(address(this), 10 ether);
    }

    function test_X4e_codelessEngineIsNotReportedAsDelivered() public {
        assertEq(CODELESS.code.length, 0, "premise: the misconfigured engine has no code");

        uint256 leftover = FeeRouteLib.routePerp(
            address(tok),
            address(0), // no guild leg: isolate the staker delivery
            CODELESS,
            0,
            SHARE,
            X4eEngine.creditPerpFee.selector,
            X4eEngine.creditPerpFeeAsset.selector
        );

        emit log_named_uint("leftover reported to the caller", leftover);
        emit log_named_uint("tokens at the codeless engine ", tok.balanceOf(CODELESS));
        emit log_named_uint("allowance left standing       ", tok.allowance(address(this), CODELESS));

        assertEq(leftover, SHARE, "undelivered, so the caller buffers it to the relaunch reserve");
        assertEq(tok.balanceOf(CODELESS), 0, "the tokens never moved");
        assertEq(tok.balanceOf(address(this)), 1_000e6, "and are still here, recoverable");
        assertEq(tok.allowance(address(this), CODELESS), 0, "no standing allowance is left behind");
    }

    /// @notice The native leg is the one that used to actually lose the money.
    function test_X4e_codelessEngineKeepsTheNativeShareRecoverable() public {
        uint256 share = 1 ether;
        uint256 heldBefore = address(this).balance;

        uint256 leftover = FeeRouteLib.routePerp(
            address(0), address(0), CODELESS, 0, share,
            X4eEngine.creditPerpFee.selector,
            X4eEngine.creditPerpFeeAsset.selector
        );

        emit log_named_uint("leftover reported to the caller", leftover);
        emit log_named_uint("ether at the codeless engine   ", CODELESS.balance);

        assertEq(leftover, share, "undelivered, so the caller buffers it to the relaunch reserve");
        assertEq(CODELESS.balance, 0, "not one wei left for an address that can never send it back");
        assertEq(address(this).balance, heldBefore, "the ether is still here, recoverable");
    }

    /// @notice The gate must not break the real thing, on either leg.
    function test_X4e_realEngineStillReceivesBothLegs() public {
        X4eEngine e = new X4eEngine();

        uint256 leftoverErc20 = FeeRouteLib.routePerp(
            address(tok), address(0), address(e), 0, SHARE,
            X4eEngine.creditPerpFee.selector,
            X4eEngine.creditPerpFeeAsset.selector
        );
        uint256 leftoverNative = FeeRouteLib.routePerp(
            address(0), address(0), address(e), 0, 1 ether,
            X4eEngine.creditPerpFee.selector,
            X4eEngine.creditPerpFeeAsset.selector
        );

        emit log_named_uint("erc20 credited to a real engine", e.assetCredited());
        emit log_named_uint("wei credited to a real engine  ", e.nativeCredited());

        assertEq(leftoverErc20, 0, "a real engine still reports delivered (ERC20)");
        assertEq(leftoverNative, 0, "a real engine still reports delivered (native)");
        assertEq(e.assetCredited(), SHARE, "and the tokens really moved");
        assertEq(e.nativeCredited(), 1 ether, "and the ether really moved");
        assertEq(tok.allowance(address(this), address(e)), 0, "allowance consumed by the pull");
    }

    receive() external payable {}
}
