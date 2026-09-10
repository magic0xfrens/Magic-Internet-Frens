// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Test.sol";
import {YBase} from "../attacks/YBase.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-19 — progressive seeding is native-only; a non-native brew must not brick
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `CauldronSeeder.startSeed` is `payable` and asserts
 *  `msg.value == cfg.ethTotal` (CauldronSeeder.sol:133). It pulls only the TOKEN
 *  side via `transferFrom` (:169) and has no ERC20 path for the quote at all.
 *
 *  `PoolOps.createAndSeedProgressive` called it as
 *  `startSeed{value: ethAmount}` regardless of the generation's quote. For a
 *  USDG-denominated brew the registry holds no ether, so the assert fails — and
 *  that revert lands inside `CauldronRegistry._seedGeneration` (:1000), which
 *  runs AFTER `governor.markConsumed(winId)` (:912). The consumption rolls back,
 *  the same proposal keeps winning `_bestUnconsumed()`, and every later rebirth
 *  dies identically: a permanent freeze.
 *
 *  Both preconditions are ordinary — the seeder is owner-armed, and a non-native
 *  quote is a normal governance choice from the treasury allowlist.
 *
 *  FIXED by degrading rather than reverting: a non-native generation takes the
 *  ATOMIC seed path (which already handles any quote), so the brew launches, it
 *  simply does not stream.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B19_ProgressiveNonNative is YBase {
    CauldronSeeder internal seeder;
    MockQuoteToken internal usdg;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        // ARM PROGRESSIVE SEEDING — the first of the two preconditions.
        seeder = new CauldronSeeder(address(registry), posm, address(pm));
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(900);

        // And allow a non-native quote — the second.
        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        registry.setAllowedQuote(address(usdg), true, 1e18);
    }

    /// @notice A rebirth with progressive seeding armed AND a non-native winning
    ///         proposal must complete rather than freeze.
    ///
    ///  WHAT THIS TEST ACTUALLY EXERCISES, stated precisely. The dying pool here
    ///  still holds recovered liquidity, so `PoolOps.seedFunding` selects NATIVE
    ///  (its "never strand `recovered`" rule) and the newborn is native — the log
    ///  below shows the resulting quote. So this asserts the JOURNEY survives; it
    ///  does NOT by itself reach the non-native progressive dispatch.
    ///
    ///  Reaching that dispatch needs `recovered == 0` (a fully drained pool) so
    ///  that funding picks the proposal's quote, which this fork fixture cannot
    ///  arrange. The guard is therefore covered here only in combination with
    ///  {test_B19_NativeStillStreams}, which proves the native branch is intact,
    ///  and by inspection of the branch itself. Recorded rather than overclaimed.
    function test_INVARIANT_B19_NonNativeRebirthSurvivesArmedProgressiveSeeding() public {
        vm.skip(!active);

        // Fund the registry with the quote so the rebirth has something to seed
        // with, and point the governor's winner at USDG.
        usdg.mint(address(registry), 500_000e6);
        registry.setGovernor(address(new UsdgGov(address(usdg))));

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        vm.roll(vm.getBlockNumber() + 60);

        uint256 genBefore = registry.currentGeneration();
        registry.relaunch();

        assertEq(registry.currentGeneration(), genBefore + 1, "the rebirth must complete");
        // Printed so the degradation is visible rather than assumed: this is the
        // quote funding actually chose, not the one the proposal asked for.
        console2.log("gen quote after rebirth:", registry.generationQuote(genBefore + 1));
    }

    /// @notice REGRESSION: a NATIVE brew must still stream. The fix must degrade
    ///         only the non-native case, not disable progressive seeding.
    function test_B19_NativeStillStreams() public {
        vm.skip(!active);

        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        vm.roll(vm.getBlockNumber() + 60);

        registry.relaunch(); // the default governor proposes a NATIVE brew
        assertTrue(seeder.seeding(), "a native rebirth must still hand off to the seeder");
    }
}

/// @dev A governor whose winner is denominated in USDG.
contract UsdgGov {
    address public immutable usdg;
    constructor(address _usdg) { usdg = _usdg; }
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external view returns (uint256, BrewSpec19 memory spec) {
        spec = BrewSpec19({
            name: "Stable", symbol: "STABLE", mode: MetadataMode19.BaseURI,
            baseURI: "ipfs://s/", renderer: address(0), website: "s.xyz",
            socials: "x.com/s", quote: usdg, nftSupply: 1000,
            volumePerNFT: 0, proposer: address(0xBEEF)
        });
        return (1, spec);
    }
}

enum MetadataMode19 { BaseURI, Renderer }

struct BrewSpec19 {
    string name; string symbol; MetadataMode19 mode; string baseURI;
    address renderer; string website; string socials; address quote;
    uint256 nftSupply; uint256 volumePerNFT; address proposer;
}
