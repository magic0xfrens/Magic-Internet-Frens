# Known issues — Solidity re-audit 2026-09-23

One line per issue, so reviewers do not re-report it. Everything marked FIXED is
fixed in this round's source; trying to BREAK a fix is in scope and welcome.
Evidence, test logs and the auditors' reasoning are deliberately not shipped.

| ID | Severity | Component | Finding | Status |
|---|---|---|---|---|
| FS-relaunch-01 | High | `CauldronRegistry._perpHousekeep` | A relaunch reaching the perp housekeeping step with <= 8M gas skipped the force-close and completed with open positions stranded. | FIXED |
| FS-badge-floor-01 | High | `PoolOps.recycleCollection/buyCollection`, `CauldronVault.redeem` | Liquidation badge IDs were admitted as art and could redeem art-only floor backing. | FIXED |
| FS-gacha-01 | Medium | `GachaLib.resolveTickets` | A win whose mint reverted still reset the player's pity streak and counted as opened. | FIXED |
| FS-successor-01 | Medium | `CauldronRegistry.migrateToSuccessor`, `RedemptionExt.recoverLegs` | Successor handoff left rotated leg NFTs behind with no recovery path. | FIXED |
| FS-surtax-01 | Medium | `SurtaxLib.surtaxBps` | A malformed surtax-policy reply escaped the fallback and reverted fee-bearing swaps. | FIXED |
| FS-feerouter-01 | Medium | `CauldronHook` fee split | A malformed or overflowing fee-router reply escaped the built-in fallback. | FIXED |
| FS-oracle-01 | Medium | `QuoteOracle` reads | A malformed feed reply dropped recorded trade volume instead of using the retained price. | FIXED |
| FS-vesting-01 | Medium | `MigrationVesting._isInstant` | A malformed instant-tier policy reply blocked new migrations. | FIXED |
| FS-dividend-01 | Medium | `MiFrensDividend.receive` | The native rounding residual could be credited repeatedly. | FIXED |
| FS-dividend-02 | Medium | `MiFrensDividend._tryPush` | One malformed basket token blocked payouts of every other asset. | FIXED |
| FS-ledger-01 | Medium | `CollectionLedger.crystallize` | Pre-death credit stayed booked after a zero-claimant freeze. | FIXED |
| FS-perpvault-01 | Medium | `PerpVault.hasStakers` | Vault replacement ignored earned, unclaimed token-side rewards. | FIXED |
| FS-perpmark-01 | Medium | `PerpEngine._currentTick` | An out-of-range mark tick poisoned observations and disabled the beforeSwap sweep. | FIXED |
| FS-venueseed-01 | Medium | `VenueSeeder.seed/seedBand` | Re-seeding overwrote the only recoverable position id. | FIXED |
| FS-registry-L01 | Low | `CauldronRegistry.emergencyWithdrawLP` | Recovered quote was paid as native ether even for an ERC20-quoted generation. | FIXED |
| FS-registry-L02 | Low | `CauldronRegistry.relaunch` | The OG share of relaunch-flushed buybacks was folded one generation late. | FIXED |
| FS-hook-L01 | Low | `CauldronHook.nftPriceAt` | A malformed curve-policy reply escaped the fallback. | FIXED |
| FS-router-L01 | Low | `CauldronGachaRouter._playInCurveUnits` | A malformed or overflowing oracle reply escaped the fallback. | FIXED |
| FS-treasury-L01 | Low | `TreasuryGovernor.vote/winner` | Equal support followed vote order instead of the documented lower id. | FIXED |
| FS-treasury-L02 | Low | `TreasuryGovernor.cancel` | Cancelling a stale executed id deactivated the current envelope. | FIXED |
| FS-artbuffer-01 | Low | `FrenRenderer` buffer | Dense valid owner-uploaded art overflowed a fixed render buffer. | FIXED |
| FS-venueband-L01 | Low | `VenueSeeder.seedBand` | Band tick width was ten times the documented band. | FIXED |
| FS-deployhook-01 | Low | `DeployCauldron.s.sol` | Legacy script mined an obsolete hook permission mask. | FIXED |
| FS-deployfactory-01 | Low | `FixFactoryWiring.s.sol` | The execute run encoded a different factory than the scheduled operation. | FIXED |
| FS-deployvesting-01 | Low | `DeployMigrationVesting.s.sol` | The script ignored the emergency arm that `setClaimGate(nonzero)` consumes. | FIXED |
| FS-deployperp-I01 | Info | `DeployPerp.s.sol` | Mark-source ownership handoff keyed on an env flag, not on creation. | ACCEPTED |
| FS-rotation-I01 | Info | `RedemptionExt.rotateSlice*` | No reentrancy guard; every callback in the path is owner-curated. | ACCEPTED |
| R23-L1 | Info | `PerpEngine._doSweep` | Cascade pass exits clean after kills without re-checking earlier survivors (comment says only a no-condemned pass is clean). | ACCEPTED |
