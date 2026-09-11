// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolOps} from "../../cauldron/PoolOps.sol";

contract X5LedgerMock {
    uint256 public lastEntitled;
    uint256 public lastCount;
    bool public called;
    function crystallized(uint256) external pure returns (bool) { return false; }
    function crystallize(uint256, uint256 mintedAtDeath, uint256 extraEntitled) external {
        called = true; lastCount = mintedAtDeath; lastEntitled = extraEntitled;
    }
}

/// @dev The dying floor vault. `close()` returns `address(this).balance` in the
///      real thing (CauldronVault.sol:119) — ALWAYS native wei, whatever the
///      newborn's quote turns out to be. `receive()` is open, so any stranger can
///      set this number by donating.
contract X5VaultMock {
    uint256 public sweptOnClose;
    bool public closed;
    constructor(uint256 s) { sweptOnClose = s; }
    function close() external returns (uint256) { closed = true; return sweptOnClose; }
    function outstanding() external pure returns (uint256) { return 1000; }
    function redeemed() external pure returns (uint256) { return 0; }
}

/// @dev The two reserve entrypoints `seedFunding` pulls, and nothing else.
contract X5HookMock {
    uint256 public ethReserve;
    mapping(address => uint256) public assetReserve;
    function setEth(uint256 a) external { ethReserve = a; }
    function setAsset(address a, uint256 v) external { assetReserve[a] = v; }
    function releaseRelaunchETH() external returns (uint256 g) { g = ethReserve; ethReserve = 0; }
    function releaseRelaunchAsset(address a) external returns (uint256 g) { g = assetReserve[a]; assetReserve[a] = 0; }
}

/// @notice X5c — REGRESSION (was: the vault sweeps native wei, the divisor is in
///         quote units).
///
///  `CauldronVault.close()` (:119) sweeps `address(this).balance` — native wei.
///  `PoolOps.seedFunding` returned that figure from EVERY branch, including the
///  two that return a NON-NATIVE `quoteUsed` (:1054 / :1064), and the registry
///  feeds it straight into `crystallizeCollection` as the numerator over
///  `totalETH`, which is denominated in the CHOSEN QUOTE
///  (CauldronRegistry.sol:1026-1028 -> PoolOps.sol:1356
///  `mulDiv(swept, activeBase, totalETH)`). On a 6-decimal quote, ~20 gwei
///  donated to the dying vault crystallized the dead collection at 100% of the
///  newborn's active tranche, permanently (CollectionLedger.sol:143-154 has no
///  downward adjuster).
///
///  FIX: only the native branch — the ONLY branch that folds `vaultSwept` into
///  the amount it returns — may report it. Numerator and denominator now always
///  come out of the same addition. `crystallizeCollection`'s signature is
///  unchanged and the registry was not edited.
///  Test name kept from the PoC; the assertions are inverted.
contract X5cVaultSweptDenomination is Test {
    address constant NATIVE = address(0);
    address constant USDG = address(0x11515D6);   // 6-decimal quote
    address constant OTHER = address(0xBEEF);

    uint256 constant ACTIVE_BASE = 800_000_000e18; // newborn active tranche (18dp)

    X5HookMock hook;

    function setUp() public {
        hook = new X5HookMock();
    }

    function _crystallize(uint256 swept, uint256 totalETH, address vault) internal returns (uint256) {
        return PoolOps.crystallizeCollection(
            address(new X5LedgerMock()), address(0xC011EC), vault, 1, swept, ACTIVE_BASE, totalETH
        );
    }

    // ---- the attack, now refused -----------------------------------------

    function test_Attack_TwentyGweiCrystallizesTheWholeActiveSupply() public {
        uint256 usdgSeed = 20_000e6;  // 20k USDG of seed funding for the newborn
        uint256 donation = usdgSeed;  // the attacker donates the SAME NUMBER, in wei

        // BRANCH 1 — the winning proposal asks for USDG, nothing is recovered, and
        // the hook holds a USDG relaunch reserve.
        X5VaultMock v1 = new X5VaultMock(donation);
        hook.setAsset(USDG, usdgSeed);
        (address q1, uint256 amt1, uint256 swept1) =
            PoolOps.seedFunding(address(hook), USDG, NATIVE, 0, address(v1));

        // BRANCH 3 — the dying generation was already USDG and its LP was
        // recovered, so the rebirth falls back to the dying quote.
        X5VaultMock v3 = new X5VaultMock(donation);
        (address q3, uint256 amt3, uint256 swept3) =
            PoolOps.seedFunding(address(hook), OTHER, USDG, usdgSeed, address(v3));

        emit log_named_uint("attacker wei donated to the dying vault", donation);
        emit log_named_uint("branch 1 reported swept                ", swept1);
        emit log_named_uint("branch 3 reported swept                ", swept3);

        assertTrue(v1.closed() && v3.closed(), "the vault is still closed either way");
        assertEq(q1, USDG, "branch 1 seeds in USDG");
        assertEq(amt1, usdgSeed, "branch 1 amount is the USDG reserve");
        assertEq(q3, USDG, "branch 3 falls back to the dying USDG quote");
        assertEq(amt3, usdgSeed, "branch 3 amount is the recovered USDG");

        assertEq(swept1, 0, "FIXED: no wei is reported alongside a non-native quote");
        assertEq(swept3, 0, "FIXED: no wei is reported alongside a non-native quote");

        // and therefore the crystallization the registry performs with that pair
        // is untouched by the donation
        uint256 e1 = _crystallize(swept1, amt1, address(v1));
        uint256 e3 = _crystallize(swept3, amt3, address(v3));
        assertEq(e1, 0, "a wei donation buys none of the newborn's USDG-priced supply");
        assertEq(e3, 0, "a wei donation buys none of the newborn's USDG-priced supply");
    }

    // ---- positive control: the NATIVE rebirth still sizes correctly --------

    function test_Positive_NativeRebirthStillCrystallizesProportionally() public {
        // 1 ETH of floor swept out of the dying vault, 99 ETH recovered from the
        // dead LP -> 100 ETH seeds the newborn and the collection is entitled to
        // exactly 1% of the active tranche.
        X5VaultMock v = new X5VaultMock(1 ether);
        (address q, uint256 amt, uint256 swept) =
            PoolOps.seedFunding(address(hook), NATIVE, NATIVE, 99 ether, address(v));

        assertEq(q, NATIVE, "native rebirth");
        assertEq(swept, 1 ether, "the native branch DOES report the sweep");
        assertEq(amt, 100 ether, "and folds it into the seed: 99 recovered + 1 swept");

        uint256 entitled = _crystallize(swept, amt, address(v));
        assertEq(entitled, ACTIVE_BASE / 100, "1 ETH of 100 == 1% of the newborn supply");

        // the invariant that was broken: the numerator can never exceed the
        // denominator, because the native branch adds the numerator INTO it.
        assertLe(swept, amt, "swept is part of the seed it is measured against");
        assertLe(entitled, ACTIVE_BASE, "entitlement can never exceed the active tranche");
    }

    // ---- the general property, over every branch --------------------------

    function testFuzz_SweptIsNeverReportedWithoutTheQuoteItIsDenominatedIn(
        uint96 donation,
        uint96 recovered,
        bool wantNative
    ) public {
        vm.assume(recovered > 0);
        X5VaultMock v = new X5VaultMock(donation);
        hook.setAsset(USDG, 1);
        (address q, uint256 amt, uint256 swept) = PoolOps.seedFunding(
            address(hook), wantNative ? NATIVE : USDG, USDG, recovered, address(v)
        );
        if (q == NATIVE) {
            assertLe(swept, amt, "native: the sweep is inside the seed it divides");
        } else {
            assertEq(swept, 0, "non-native: a wei figure is never reported as a quote figure");
        }
    }

    receive() external payable {}
}
