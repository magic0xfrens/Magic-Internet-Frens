// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolOps} from "../../cauldron/PoolOps.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-13 — A DUST BALANCE IN THE REQUESTED QUOTE DIVERTS THE WHOLE REBIRTH
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `PoolOps.seedFunding` decides what the newborn generation is seeded WITH.
 *  It tries three denominations in order (PoolOps.sol:892-904):
 *
 *      1. the winning proposal's requested quote
 *      2. native
 *      3. the dying generation's own quote
 *
 *  The intent is stated at CauldronRegistry.sol:836-839: "narrows the request to
 *  what the protocol ACTUALLY HOLDS ... A quote nobody can fund degrades to one
 *  we can."
 *
 *  The test for "can fund" is `p > 0`:
 *
 *      uint256 p = (oldQuote == wantQuote ? recovered : 0) + _pullAsset(hookAddr, wantQuote);
 *      if (p > 0) return (wantQuote, p, vaultSwept);
 *
 *  One wei satisfies it, and the `return` is unconditional — so native and the
 *  old quote are never even consulted. A generation that recovered 20 ETH from
 *  its dead LP and holds a 5 ETH relaunch reserve will seed its successor with
 *  1 wei of USDG if 1 wei of USDG happens to sit in `relaunchAsset[USDG]`.
 *
 *  HOW THE DUST GETS THERE. `relaunchAsset` is keyed per asset and credited from
 *  whatever asset a fee was collected in (`_creditReserve`, CauldronHook.sol:1150,
 *  keyed on `_feeAsset` set per-swap at :1378). Any pool the registry opens is
 *  marked `trackedPools` and charges fees (`_afterInitialize`, :599). So a guild
 *  that has ever diversified into a second quote — the live manifest offers
 *  USDG and xNVDA — accrues a balance in it from ordinary trading.
 *
 *  CONSEQUENCE. `seedFunding`'s return is the newborn's entire seed: `relaunch()`
 *  passes it straight to `_seedGeneration(token, newActive, totalETH, ...)`
 *  (CauldronRegistry.sol:1000). `totalETH == 1` passes the
 *  `if (totalETH == 0) revert NoLiquidityToSeed()` guard at :911, so the
 *  generation is born with a dust book, while the recovered 20 ETH remains in
 *  the registry unseeded and the 5 ETH reserve stays in the hook unpulled.
 *
 *  No attacker is required — ordinary diversified trading produces the dust.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B13_SeedFundingDustPreference is Test {
    HookStub13 internal hook;
    address constant USDG = address(0x000000000000000000000000000000000000D6D6);

    function setUp() public {
        hook = new HookStub13();
    }

    /// @notice THE DELIBERATE BEHAVIOUR CHANGE, asserted rather than hidden.
    ///
    ///  Pre-fix this returned (USDG, 10_000e6): a well-funded request in a
    ///  DIFFERENT asset from the recovery was honoured, and the 20 ETH recovered
    ///  plus the 5 ETH reserve were left behind. The fix refuses that trade — it
    ///  will not abandon value already in hand to honour a denomination change.
    ///
    ///  The cost is real and is stated plainly: a guild that votes a new quote
    ///  while the dying pool still holds value does NOT get its new quote at this
    ///  rebirth. It gets a native rebirth, and the USDG stays in
    ///  `relaunchAsset[USDG]` — still recoverable at a later rebirth, unlike the
    ///  ETH the old path stranded in the registry, which only `emergencySweep`
    ///  could reach. The supported way to rotate is to convert the treasury first
    ///  via {QuoteRotator}, after which `recovered` is already in the new quote
    ///  and `oldQuote == wantQuote` honours it (see the B08 Leg-1 case).
    ///
    ///  Ranking the two amounts properly would need a price, and an oracle has no
    ///  business in the one function that must never be the reason the machine
    ///  cannot be reborn.
    function test_CHANGED_B13_RequestInAnotherAssetNoLongerAbandonsRecovery() public {
        hook.setAsset(USDG, 10_000e6);
        hook.setEth(5 ether);

        (address quoteUsed, uint256 amount,) =
            PoolOps.seedFunding(address(hook), USDG, address(0), 20 ether, address(0));

        assertEq(quoteUsed, address(0), "seeds where the recovered value already is");
        assertEq(amount, 25 ether, "20 recovered + 5 reserve, nothing abandoned");
        assertEq(hook.asset(USDG), 10_000e6, "and the USDG is left claimable, not stranded");
    }

    /// @notice INVARIANT: a dust balance in the requested quote must not be
    ///         preferred over a native reserve orders of magnitude larger.
    ///
    ///  Pre-fix this returned (USDG, 1) and the newborn was seeded with one wei
    ///  of USDG while 25 ETH of real backing went unused.
    function test_INVARIANT_B13_DustMustNotOutrankRealBacking() public {
        hook.setAsset(USDG, 1);        // one wei of a second quote, from ordinary trading
        hook.setEth(5 ether);          // a real relaunch reserve

        (address quoteUsed, uint256 amount,) =
            PoolOps.seedFunding(address(hook), USDG, address(0), 20 ether, address(0));

        emit log_named_address("quote chosen", quoteUsed);
        emit log_named_uint("amount seeded", amount);

        assertTrue(
            !(quoteUsed == USDG && amount == 1),
            "one wei of the requested quote must not outrank a 25 ETH position"
        );
        assertEq(quoteUsed, address(0), "it seeds in the denomination the value is actually in");
        assertEq(amount, 25 ether, "and uses all of it: 20 recovered + 5 reserve");
    }

    /// @notice The same abandonment, one level down: a NON-native dying quote
    ///         must not be abandoned in favour of a native reserve either.
    function test_INVARIANT_B13_NativeReserveMustNotStrandANonNativeRecovery() public {
        hook.setEth(5 ether);            // a native reserve exists
        hook.setAsset(USDG, 10_000e6);   // and so does the dying quote's reserve

        // Dying generation was quoted in USDG and returned 50,000 USDG.
        (address quoteUsed, uint256 amount,) =
            PoolOps.seedFunding(address(hook), address(0xBEEF), USDG, 50_000e6, address(0));

        assertEq(quoteUsed, USDG, "seeds in the dying generation's own quote");
        assertEq(amount, 60_000e6, "recovered 50k + the 10k reserve, none abandoned");
    }

    /// @notice REGRESSION: with nothing recovered, the requested quote is still
    ///         honoured from fees exactly as before. The guard must not remove
    ///         the ability to launch a new-quote generation from a drained pool.
    function test_FIXED_B13_NoRecoveryStillHonoursTheRequest() public {
        hook.setAsset(USDG, 10_000e6);
        hook.setEth(5 ether);

        (address quoteUsed, uint256 amount,) =
            PoolOps.seedFunding(address(hook), USDG, address(0), 0, address(0));

        assertEq(quoteUsed, USDG, "a drained pool may still rotate quote");
        assertEq(amount, 10_000e6, "funded from the per-asset reserve");
    }

    /// @notice REGRESSION: the guard must never turn a fundable rebirth into an
    ///         unfundable one — `totalETH == 0` is what reverts NoLiquidityToSeed.
    function test_FIXED_B13_NeverReturnsZeroWhenValueExists() public {
        hook.setEth(0);
        hook.setAsset(USDG, 0);

        (, uint256 amount,) =
            PoolOps.seedFunding(address(hook), address(0xBEEF), USDG, 50_000e6, address(0));

        assertGt(amount, 0, "recovered value always yields a fundable answer");
    }
}

/// @dev The two reserve entrypoints `seedFunding` pulls, and nothing else.
contract HookStub13 {
    mapping(address => uint256) public asset;
    uint256 public eth;

    function setAsset(address a, uint256 v) external { asset[a] = v; }
    function setEth(uint256 v) external { eth = v; }

    function releaseRelaunchAsset(address a) external returns (uint256 amt) {
        amt = asset[a];
        require(amt > 0, "NoETHToRelease"); // mirrors the real revert-at-zero
        asset[a] = 0;
    }

    function releaseRelaunchETH() external returns (uint256 amt) {
        amt = eth;
        require(amt > 0, "NoETHToRelease");
        eth = 0;
    }
}
