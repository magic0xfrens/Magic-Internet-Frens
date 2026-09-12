// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DefaultFeeRouter} from "../../cauldron/DefaultFeeRouter.sol";
import {RoyaltyRouter} from "../../cauldron/RoyaltyRouter.sol";

/**
 * Z9 — two probes against the least-reviewed contracts in the tree.
 *
 *  Z9a  DefaultFeeRouter does NOT reproduce the hook's built-in split when
 *       `vault == address(0)` (the SHIPPED unified-floor configuration).
 *  Z9b  RoyaltyRouter.receive() cannot survive a 2300-gas royalty payment,
 *       contradicting cauldron/RoyaltyRouter.sol:28 ("the forward cannot fail").
 */

/// @dev Minimal stand-in for CauldronHook.fundLegacyBuffer: one SSTORE, as the
///      real one does (`legacyBuffer += msg.value`, CauldronHook.sol:1178).
contract BufferHook {
    uint256 public legacyBuffer;
    address public legacyBufferAsset;
    function fundLegacyBuffer() external payable {
        legacyBufferAsset = address(0);
        legacyBuffer += msg.value;
    }
}

/// @dev A marketplace that pays royalties with the 2300-gas stipend.
contract StipendPayer {
    /// `send` — returns false instead of reverting.
    function paySend(address to, uint256 v) external payable returns (bool ok) {
        ok = payable(to).send(v);
    }
    /// `transfer` — reverts the whole sale on failure.
    function payTransfer(address to, uint256 v) external payable {
        payable(to).transfer(v);
    }
    /// full-gas control
    function payCall(address to, uint256 v) external payable returns (bool ok) {
        (ok, ) = to.call{value: v}("");
    }
}

contract Z9ScopeProbe is Test {
    uint256 internal constant BPS = 10_000;

    // ── Z9a ────────────────────────────────────────────────────────────────

    /// @dev Literal transcription of CauldronHook.sol:1381-1384 (the built-in
    ///      split the router claims to reproduce):
    ///        wantGuild = (guild != 0 && guildBps > 0) ? feeAmount*guildBps/BPS : 0;
    ///        rem       = feeAmount - wantGuild;
    ///        wantFloor = floorBps > 0 ? (rem * floorBps) / BPS : 0;   // <-- no vault test
    ///        wantRelaunch = rem - wantFloor;
    function _builtIn(uint256 fee, address guild, uint256 guildBps, uint256 floorBps)
        internal
        pure
        returns (uint256 g, uint256 f, uint256 r)
    {
        g = (guild != address(0) && guildBps > 0) ? (fee * guildBps) / BPS : 0;
        uint256 rem = fee - g;
        f = floorBps > 0 ? (rem * floorBps) / BPS : 0;
        r = rem - f;
    }

    struct Split { uint256 g; uint256 f; uint256 r; }

    function _routed(DefaultFeeRouter fr, uint256 fee, address guild, address vault)
        internal
        view
        returns (Split memory s)
    {
        (s.g, s.f, s.r) = fr.route(fee, guild, vault, 1500, 10_000);
    }

    /// REGRESSION (Z-11, fixed): the router must reproduce the built-in split for
    /// EVERY `vault`, including `address(0)` — the value both collection-deployment
    /// paths always set (CauldronRegistry.sol:1189, :1213).
    ///
    ///  BEFORE the fix `DefaultFeeRouter.sol:28` carried an extra
    ///  `vault != address(0) &&` condition the hook does not have, so under the
    ///  shipped unified-floor configuration it returned `toFloor == 0` on every
    ///  swap and 85% of each ETH fee was silently re-routed from the collection's
    ///  token floor into the relaunch reserve — while still summing to `feeAmount`,
    ///  which is the only thing the hook's mismatch check (CauldronHook.sol:1373)
    ///  can see.
    function test_Z9a_DefaultFeeRouterDivergesOnUnifiedFloor() public {
        DefaultFeeRouter fr = new DefaultFeeRouter();
        uint256 fee = 100 ether;
        address guild = address(0xA11CE);

        // positive control: vault wired
        Split memory withVault = _routed(fr, fee, guild, address(0xBEEF));
        (uint256 bg, uint256 bf, uint256 br) = _builtIn(fee, guild, 1500, 10_000);
        assertEq(withVault.g, bg, "Z9a control: guild matches");
        assertEq(withVault.f, bf, "Z9a control: floor matches");
        assertEq(withVault.r, br, "Z9a control: relaunch matches");

        // the shipped configuration: hook.setVault(address(0))
        Split memory unified = _routed(fr, fee, guild, address(0));
        assertEq(unified.g + unified.f + unified.r, fee, "conservation: the split still sums to the fee");
        assertEq(bf, 85 ether, "built-in routes 85 ETH to the floor share");
        assertEq(unified.f, 85 ether, "FIXED: the floor share survives vault == address(0)");
        assertEq(unified.f, bf, "FIXED: router reproduces the built-in split with no vault");
        assertEq(unified.r, 0, "FIXED: nothing is diverted into the relaunch reserve");
        assertEq(unified.g, bg, "guild share unchanged");
        // And the vault address genuinely no longer changes the answer.
        assertEq(unified.f, withVault.f, "FIXED: `vault` no longer gates the floor share");
    }

    // ── Z9b ────────────────────────────────────────────────────────────────

    function _trySend(RoyaltyRouter r, StipendPayer p, uint256 v) internal returns (bool) {
        return p.paySend{value: v}(address(r), v);
    }

    function _tryTransfer(RoyaltyRouter r, StipendPayer p, uint256 v) internal returns (bool ok) {
        try p.payTransfer{value: v}(address(r), v) { ok = true; } catch { ok = false; }
    }

    function test_Z9b_RoyaltyRouterCannotTakeA2300GasPayment() public {
        BufferHook hook = new BufferHook();
        RoyaltyRouter router = new RoyaltyRouter(address(hook));
        StipendPayer payer = new StipendPayer();
        vm.deal(address(payer), 10 ether);

        // full-gas payer works (the happy path the comment describes)
        bool fullGas = payer.payCall{value: 1 ether}(address(router), 1 ether);
        assertTrue(fullGas, "full-gas royalty forwards fine");
        assertEq(hook.legacyBuffer(), 1 ether, "buffer credited on the happy path");

        // 2300-gas stipend: `send` returns false, `transfer` reverts
        bool sendOk = _trySend(router, payer, 1 ether);
        bool xferOk = _tryTransfer(router, payer, 1 ether);

        assertFalse(sendOk, "ATTACK: .send() to RoyaltyRouter returns false (royalty lost)");
        assertFalse(xferOk, "ATTACK: .transfer() to RoyaltyRouter reverts (sale reverts)");
        assertEq(hook.legacyBuffer(), 1 ether, "no stipend payment ever reached the buffer");
        assertEq(address(router).balance, 0, "router still holds nothing (no strand)");
    }
}
