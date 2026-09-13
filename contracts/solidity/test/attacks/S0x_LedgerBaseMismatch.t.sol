// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";

/**
 * @notice S0x — THE LIVE FLOOR BASE AND THE FROZEN FLOOR BASE ARE DIFFERENT SETS.
 *
 *  Two call sites feed {CollectionLedger} the NFT count its floor is divided by,
 *  and on the iteration-#2 MiFrens CONTINUATION they measure different things:
 *
 *    PoolOps.sol:1528  (recycleCollection)  mintedNow = collection.totalMinted()
 *    PoolOps.sol:1551  (buyCollection)      mintedNow = collection.totalMinted()
 *    PoolOps.sol:1484  (crystallizeCollection)
 *                      nftCount = IVaultRedeemedOps(vault).outstanding()
 *
 *  `CauldronVault.outstanding()` (CauldronVault.sol:60-64) EXCLUDES the genesis
 *  tranche: `eligible = minted > floorOffset ? minted - floorOffset : 0`, and
 *  `CauldronRegistry._continueMiFrens` (:1243) deploys that vault with
 *  `floorOffset = genesisShares`. `collection.totalMinted()` INCLUDES it.
 *
 *  The genesis tranche is explicitly barred from ever drawing this pot —
 *  `PoolOps.recycleCollection` reverts "og tranche" for `tokenId <= ogCount`
 *  (PoolOps.sol:1525) — and the pot is credited with the FORGED share only
 *  (`PoolOps.doLegacyNote`, :1428-1433). So while the generation is ALIVE the
 *  floor is divided by ~1111 NFTs that can never claim it.
 *
 *  Numbers below are the real ones: GENESIS_SUPPLY = 1111, MAX_SUPPLY = 2400
 *  (MiFrensGenesis.sol:116-117), 100 forged minted so far -> totalMinted = 1211,
 *  vault.outstanding() = 100.
 */
contract S0xLedgerBaseMismatch is Test {
    CollectionLedger ledger;

    uint256 constant GEN = 2;          // the MiFrens continuation
    uint256 constant GENESIS = 1111;   // MiFrensGenesis.GENESIS_SUPPLY
    uint256 constant FORGED = 100;     // forged so far
    //  ── FIXED. THIS FILE IS A MODEL, SO SAY WHAT IT MODELS NOW ──────────────
    //  `LIVE_BASE` was `GENESIS + FORGED` — raw `collection.totalMinted()`, the
    //  number the two live PoolOps sites used to pass. That is the bug: it counts
    //  1111 genesis NFTs that {CauldronVault.redeem} REFUSES
    //  (CauldronVault.sol:157, "genesis tranche has its own floor"), so the live
    //  floor was `pot/1211` while the post-death entitlement was `pot/100`.
    //  `PoolOps._eligible` now nets the genesis tranche out of BOTH live sites, so
    //  the live base and the frozen base are the same quantity and the two
    //  assertions below become "no gap" instead of "6.06x gap".
    //
    //  CAVEAT, STATED PLAINLY: this harness calls {CollectionLedger} directly and
    //  never executes PoolOps (`ledger = new CollectionLedger(address(this))`), so
    //  updating this constant MIRRORS the fix rather than proving it. The
    //  authoritative checks are `PoolOps._eligible` itself and the suites that do
    //  run the real path — test/CollectionLedger.t.sol (12 + 2 invariants at
    //  128,000 calls), T9b (3), T9d (2), all passing.
    uint256 constant LIVE_BASE = FORGED;             // PoolOps._eligible(collection, ogCount)
    uint256 constant FROZEN_BASE = FORGED;           // vault.outstanding()
    uint256 constant POT = 1_000e18;                 // credited forged share

    function setUp() public {
        ledger = new CollectionLedger(address(this)); // this test IS the registry
    }

    // ── helpers: each mirrors exactly one PoolOps call site ──────────────────

    /// PoolOps.buyCollection:1551-1552 — `2 * floorPerNFT(gen, totalMinted())`
    function _treasuryAskPrice() internal view returns (uint256) {
        return 2 * ledger.floorPerNFT(GEN, LIVE_BASE);
    }

    /// PoolOps.recycleCollection:1528-1529 — redeem at the LIVE base
    function _liveRecycle() internal returns (uint256) {
        return ledger.redeem(GEN, LIVE_BASE);
    }

    /// PoolOps.crystallizeCollection:1484-1485 — freeze at the VAULT's base
    function _die() internal {
        ledger.crystallize(GEN, FROZEN_BASE, 0);
    }

    // ── 1. EXTRACTION: the treasury sells an NFT for a sixth of its claim ────

    function test_TreasuryResaleUnderpricesThePostDeathEntitlement() public {
        ledger.credit(GEN, POT);

        // A holder recycles one forged NFT: it lands in the treasury (retired += 1).
        uint256 holderGot = _liveRecycle();

        // The attacker buys that treasury NFT at the quoted 2x LIVE floor.
        uint256 pricePaid = _treasuryAskPrice();
        ledger.buyback(GEN, LIVE_BASE, pricePaid);

        // The generation dies. The base collapses from 1211 to 100.
        _die();

        // The attacker recycles the same NFT at the FROZEN floor.
        uint256 attackerGot = ledger.redeem(GEN, FROZEN_BASE);

        emit log_named_decimal_uint("holder got (live floor)   ", holderGot, 18);
        emit log_named_decimal_uint("attacker paid (2x live)   ", pricePaid, 18);
        emit log_named_decimal_uint("attacker got (frozen floor)", attackerGot, 18);

        //  FLIPPED TO THE FIXED BEHAVIOUR. Before: paid 1.6515, received 10.0083
        //  = 6.06x, taken from the shared reserve LP that also backs the OG floor
        //  and 1:1 migration. After `PoolOps._eligible` nets the barred genesis
        //  tranche out of the live base: paid 20.0, received 10.1 — the treasury
        //  sells at ~2x the real floor, which is what the 2x ratchet should mean.
        assertLt(attackerGot, pricePaid, "FIXED: a treasury resale is no longer underpriced");
    }

    // ── 2. PERMANENT TRAP: the forged tranche recycles out, 91.7% of the pot
    //       is stranded in `totalEntitled` forever, taxing every future
    //       generation's active tranche (CauldronRegistry.sol:1090-1099). ─────

    function test_ForgedTrancheFullyRecycledTrapsThePotForever() public {
        ledger.credit(GEN, POT);

        uint256 paidOut;
        for (uint256 i; i < FORGED; ++i) paidOut += _liveRecycle();

        // While ALIVE this is not a dead end: outstanding = 1211 - 100 = 1111.
        bool deadWhileAlive = ledger.isDeadEnd(GEN);
        uint256 liveOutstanding = ledger.outstanding(GEN, LIVE_BASE);

        _die(); // frozenSupply = 100, retired = 100

        bool deadAfter = ledger.isDeadEnd(GEN);
        uint256 stranded = ledger.entitledTokens(GEN);
        uint256 taxed = ledger.totalEntitled();

        // Both exits really are shut: no NFT can be outstanding again and the
        // floor is 0, so PoolOps.buyCollection's `require(paid > 0, "no floor")`
        // (PoolOps.sol:1553) can never pass to un-retire one.
        uint256 floorAfter = ledger.floorPerNFT(GEN, FROZEN_BASE);
        vm.expectRevert(CollectionLedger.NothingOutstanding.selector);
        ledger.redeem(GEN, FROZEN_BASE);

        emit log_named_decimal_uint("pot credited        ", POT, 18);
        emit log_named_decimal_uint("paid out to 100 NFTs", paidOut, 18);
        emit log_named_decimal_uint("stranded forever    ", stranded, 18);

        assertFalse(deadWhileAlive, "not a dead end while alive");
        assertEq(liveOutstanding, 0, "FIXED: the live base counts only claimable NFTs");
        assertTrue(deadAfter, "frozen at the forged base => dead end");
        assertEq(floorAfter, 0, "floor 0 => buyback unsatisfiable => retired never falls");
        //  Before: 917.42 of a 1000 pot trapped forever (91.7%), which
        //  CauldronRegistry.sol:1084 subtracted from EVERY future generation.
        assertEq(stranded, 0, "FIXED: nothing is stranded in totalEntitled");
        assertEq(taxed, 0, "FIXED: no permanent tax on future generations");
        assertEq(paidOut, POT, "FIXED: the rightful claimants received the whole pot");
    }
}
