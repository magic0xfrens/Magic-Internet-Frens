// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeRouteLib} from "../../cauldron/FeeRouteLib.sol";

/// @notice Minimal 6-decimal ERC20 (a USDG-shaped quote).
contract X9eToken {
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

/// A real floor vault: a contract, which is what the timelock is supposed to set.
contract X9eVault {
    receive() external payable {}
}

/**
 * X9e — REGRESSION for F-04.
 *
 * `ddd7284` (guild) and `a3773fc` (perp stakers) both established that a CODELESS
 * recipient is not a successful delivery: on the native branch
 * `to.call{value: amount}("")` to an address with no code SUCCEEDS and the ether
 * really leaves, so reporting `true` made {routeSplit} emit its funded event and
 * made the caller skip its `leftover` reserve fallback — the money was gone with a
 * success signal on it. The FLOOR leg (`_move`) was the sibling that never got the
 * guard, so a non-zero but codeless `vault` (an operator typo, or a CREATE address
 * that was never deployed) lost the floor share of EVERY fee the hook routes.
 *
 * `routeSplit` is an `external` linked-library function, so calling it here
 * delegatecalls into the real deployed bytecode with THIS contract as the value
 * holder — the same context the hook runs it in.
 */
contract X9eCodelessFloorVault is Test {
    X9eToken internal tok;
    X9eVault internal realVault;

    address internal constant CODELESS = address(0xF100F100);
    uint256 internal constant FLOOR_SHARE = 100e6;

    function setUp() public {
        tok = new X9eToken();
        realVault = new X9eVault();
        tok.mint(address(this), 1_000e6);
        vm.deal(address(this), 10 ether);
    }

    function test_CodelessFloorVaultIsNotASuccessfulDelivery() public {
        // ── 1. the NATIVE leg — the one that actually lost the money ─────────
        uint256 heldBefore = address(this).balance;
        uint256 leftoverNative = FeeRouteLib.routeSplit(address(0), address(0), CODELESS, 0, 1 ether);
        uint256 strandedNative = CODELESS.balance;
        uint256 heldAfter = address(this).balance;

        // ── 2. the ERC20 leg ─────────────────────────────────────────────────
        uint256 leftoverAsset =
            FeeRouteLib.routeSplit(address(tok), address(0), CODELESS, 0, FLOOR_SHARE);
        uint256 strandedAsset = tok.balanceOf(CODELESS);

        // ── 3. a REAL vault is still funded on both legs (no gate weakened) ──
        uint256 leftoverRealNative =
            FeeRouteLib.routeSplit(address(0), address(0), address(realVault), 0, 1 ether);
        uint256 leftoverRealAsset =
            FeeRouteLib.routeSplit(address(tok), address(0), address(realVault), 0, FLOOR_SHARE);

        // ── assertions ───────────────────────────────────────────────────────
        assertEq(leftoverNative, 1 ether, "a codeless floor vault reports UNDELIVERED, so the caller buffers it");
        assertEq(strandedNative, 0, "and not one wei left for an address with no code");
        assertEq(heldAfter, heldBefore, "the value is still here, where the reserve fallback can reach it");

        assertEq(leftoverAsset, FLOOR_SHARE, "same answer on the ERC20 leg");
        assertEq(strandedAsset, 0, "and no tokens moved");

        assertEq(leftoverRealNative, 0, "a real vault is funded natively");
        assertEq(address(realVault).balance, 1 ether, "and receives the ether");
        assertEq(leftoverRealAsset, 0, "a real vault is funded in the asset");
        assertEq(tok.balanceOf(address(realVault)), FLOOR_SHARE, "and receives the tokens");
    }
}
