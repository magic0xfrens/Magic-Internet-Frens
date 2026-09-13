# PRIOR_INDEX — every prior finding, lead and refutation, netted

Reconciliation input for the **P3** phase of the 2026-09-13 blind run. Built by reading only the
prior run's artifacts (`audit/FINAL_BLIND_2026-09-11/{RECONCILIATION,LEDGER,CRITICALS,REHUNT,RESUME_PLAN,FINAL_AUDIT_*}.md`,
`audit/FINAL_BLIND_2026-09-11.md`, `hunt/H*.md`, `verify/V*.md`,
`audit/REMEDIATION_2026-09-{08,11}.md`, `git log 1e98bb4..HEAD -- contracts/`). No contract source
was read.

**Netting rules applied.** One row per *mechanism*, not per document — every id for a lineage shares
the first cell, `/`-separated. LEDGER rows are netted last-row-wins; a `CLAIMED` with no later `DONE`
for the same id/title would be `OPEN` (none survived: every CLAIMED row was superseded by a DONE).
`severity then` is the prior run's **final** severity, with the hunter's original in parentheses
where a verifier moved it.

**Statuses.** `FIXED <commit>` · `REFUTED` · `OPEN` · `DESIGN-DECISION` · `LEAD` · `PROVEN-SAFE` · `UNCHECKED`.

**`**` flag** = FIXED, but in the "a prior fix was reported done and did not land, or did not hold"
class (RECONCILIATION §2 *PRIOR FIX FAILED*, REHUNT re-openings, RESUME_PLAN GATE-1/GATE-2
regressions). Highest prior probability of a re-break — attack these first.
`(fix-induced by X)` means the finding lives in code a *previous* remediation wrote: the strongest
regularity in this repo (5 of the prior pass's top findings, then 6 more during its own fix phase).

---

## The table

### Core pool — hook, fee router, surtax, legacy buyback, gacha router

| prior id | title (≤12 words) | file(s):line as cited then | severity then | final status | source doc |
|---|---|---|---|---|---|
| X1a / X4a | legacy buffer books native wei, buyback settles in quote | CauldronHook.sol:1096,1317,1340; LegacyBuyLib.sol:87-94 | Critical (High) | FIXED f9c775f (fix-induced by 577a332) | CRITICALS, V1, V4 |
| X1e | royalty payments revert on an ERC20-quoted generation | RoyaltyRouter.sol:33; CauldronHook.sol:1136-1137 | High | ** FIXED 8fa52c6 (fix-induced by f9c775f) | CRITICALS |
| X1g / ACCESS-MED-02 | buffer gated on denomination but not on wiring; unspendable wei | CauldronHook.fundLegacyBuffer, legacyRegistry==0 return | Medium | FIXED 699af92 | ACCESS_LOGIC, LEDGER |
| X1f / REENT-LOW-01 | sweepLegacyReserve debits the counter, ignores the transfer return | CauldronHook.sol:1102-1109 | Low | FIXED 699af92 | REENTRANCY_ORACLES |
| X1b / O-4 | surtax jitter steerable by a same-tx tick probe | CauldronHook.sol:1402-1408 | Medium (High) | FIXED 69dc15d (fix-induced by d3c10a1) | RECON §2, flat §3 |
| X1h / X8-02 / ACCESS-LOW-01 | jitter is block-shoppable; the rate is a public view | SurtaxLib.sol:100-124, :69-88 | Low | DESIGN-DECISION (accepted; comment corrected c3f5229) | REHUNT, ACCESS_LOGIC |
| T-1 / REENT-MED-01 | legacy buyback executes at a tick the swap's caller set | LegacyBuyLib.buyStep price bound | High | FIXED 20d94d8 | REENTRANCY_ORACLES |
| X1c | setTaxExempt inert without isOpener; snipe wallet pays 99% | CauldronHook.sol:2348; DeployLaunchpad.s.sol:504 | — (prior Medium) | REFUTED | RECON §3, flat §3 |
| X1d / X4f | renounceOwnership live on the hook and the gacha router | CauldronHook, CauldronGachaRouter | Low | FIXED b244177 + d8e4c72 | LEDGER |
| X4c | FeeRouteLib._fundGuild reports a codeless guild as funded | FeeRouteLib._fundGuild (ERC20 leg) | Low | ** FIXED 02f4e8a (incomplete → X4c-2) | H4, LEDGER |
| X4c-2 / REENT-MED-02 | the guard covered only ERC20; the native leg really sent | FeeRouteLib._fundGuild (native leg) | Medium | ** FIXED ddd7284 (fix-induced by 02f4e8a) | REENTRANCY_ORACLES |
| X4e | _deliver trusted the call flag; the native leg drained stakers' 70% | FeeRouteLib._deliver / deliver | High | FIXED a3773fc (found by shape-sweeping X4c) | CRITICALS |
| F-04 | codeless floor vault ate the floor share of every fee | FeeRouteLib._move | Low | FIXED 064b29e (guard had landed in 2 of 3 files) | FIXLAYER |
| X4b + twin | gacha _churn confiscates the partial-fill refund, both sides | CauldronGachaRouter._churn; :504 (sell side) | Medium | FIXED 04607bf + 381b2a1 | H4, CRITICALS |
| Z-11 | DefaultFeeRouter silently zeroes the whole collection floor share | DefaultFeeRouter | Medium | FIXED ebedc7b | FULLSWEEP |
| prior-M / RH-L2 | legacyThreshold a bare scalar vs a per-asset 6-decimal buffer | CauldronHook._maybeLegacyBuyback; LegacyBuyLib.sol:56-63 | Medium | LEAD (next step recorded) | REHUNT L2, flat §3 |
| REHUNT-lead | anti-sniper window in BLOCKS, volume window in SECONDS | CauldronHook / SurtaxLib | — | LEAD | CRITICALS |
| FS-L3 / FS-L4 | setPolicies overwrites all three slots; quoteOracle never unsettable | CauldronHook.sol:1942; :1828-1829 | — | LEAD | FULLSWEEP |
| flat-lead-3 | hook volume collapses with no oracle wired (quoteScale inert) | CauldronHook._toUsd | — | LEAD | flat §4 |
| DOC-1/2/3 | holder tax tiers unimplemented; ETH floor vault never funded; bits understated | CauldronHook.sol:111-113; CauldronRegistry.sol:1171,:1195 | Low/Info | OPEN (tiers, bits) + DESIGN-DECISION (vault) | CRITICALS |
| PS-core | swap-path loops bounded, hookData spoof refused, layout 60/60, gas caps safe, gacha reveal not grindable | _recordVolume, _taxedPlayer, six libs, 4 gas sites | — | PROVEN-SAFE | flat §5 |
| R-1 / V-1 / D-2 / D-3 / P-1 / T-1' / G-1 / S-1 / U-1 | the 09-08 deep-audit set: phantom relaunchETH, stale oracle, dividend bricks, vacuous tests | across hook / dividend / oracle / test suite | High–Medium | FIXED (09-08, both passes) | REMEDIATION_2026-09-08 |

### Governance, rotation, treasury, registry

| prior id | title (≤12 words) | file(s):line as cited then | severity then | final status | source doc |
|---|---|---|---|---|---|
| C-1 | 33,077-gas pool-key squat bricks relaunch() permanently | CauldronHook adoption gate | Critical | FIXED (pre-1e98bb4) | flat §3 |
| C-2 | gas-starved relaunch() strands the entire perp book | relaunch path | Critical | FIXED (pre-1e98bb4) | flat §3 |
| C-4 / M-2 | treasury quorum called a missing function; openOrAddPair blanket catch | TreasuryGovernor quorum; PoolOps.openOrAddPair | Critical / Medium | FIXED (pre-1e98bb4; M-2 fix-induced by C-1) | flat §3 |
| M-1 / X2b | foreign leg proceeds had no reachable exit; recoverLegs unrouted | CauldronRegistry.sol:63; RECOVER_LEGS selector | Medium | FIXED 8237167 | flat §3, H2, V2 |
| X2n / ACCESS-MED-03 | the recoverLegs retry recovered value into a dead end | RedemptionExt recoverLegs retry (quoteOut discarded) | Medium | ** FIXED e6237a3 (fix-induced by 8237167) | ACCESS_LOGIC |
| X2a / C-3 / R-04 | migration envelope starved through a secondary leg | TreasuryGovernor.sol:708-718, :683, :387 | High | FIXED 1b558b8 + 89aa06d (3rd generation on one counter) | RECON §2, V2 |
| X2e / O-10 | primary leg frozen and unrotatable after a completed migration | RedemptionExt.sol:337-345,469; PoolOps.sol:919 | High | FIXED 26c2722 | V2, flat §3 |
| X2d / B-10 / O-6 | 64 filings erase a stockpiled mandate; positional scan window | CauldronGovernor.sol:478-483, :337 | Medium (High) | ** FIXED b3a9026 (dd570c7 claimed complete, was partial) | RECON §2, V2 |
| X2h / O-7 | treasury scan flood pins the O(1) leader hint on a corpse | TreasuryGovernor.sol:164, :593, :430-455 | High | FIXED e377594 | LEDGER, flat §3 |
| X2i / O-5 | execute is missing propose's envelope and cooldown gates | TreasuryGovernor.sol:478-511 | High | FIXED e377594 | LEDGER, flat §3 |
| X2m / flat-lead-2 | arbStep priced both legs off the fail-open cached oracle | QuoteRotator.sol:496-560 | High | FIXED c886f90 | REENTRANCY_ORACLES HIGH-01 |
| X2c / O-1 | oracle cache stamps the attempt, not the success | QuoteOracle.sol:305-312 | Low (prior High) | REFUTED as stated; root cause FIXED c886f90 | RECON §3, V2 |
| X2f / X2g | guardian settable to zero; dead completeRotation; codeless transfer | TreasuryGovernor.sol:523-526; QuoteRotator._safeTransfer | Low | FIXED 1b558b8 + c2e3afa + 8237167 | H2, V2 |
| X2o / REENT-LOW-03 | proposal snapshot counted same-block voting power | TreasuryGovernor snapshot | Low | FIXED 6f7ef41 | REENTRANCY_ORACLES |
| X2k / X2l | quoteScale is write-only; hasClaimed() lies to every integrator | CauldronBase.sol:368,:209; CauldronRegistry.sol:174,1774 | Low | FIXED-as-doc 875a49f + FIXED 7a0dfce | flat §3, CRITICALS |
| REG-1 | registry has NO fallback(); every facet fn needs an explicit stub | CauldronRegistry.sol:1778-1782 (comment says the opposite) | — | OPEN (root cause of X2b, X2g, ART-1) | CRITICALS |
| LEG-01 | every rotateSlice after the first orphans the previous leg | PoolOps.openOrAddPair (measured on Sepolia r40) | Critical | FIXED d49bc3e (99.0% of a completed envelope) | LEDGER |
| R-01 | rotateSlice took the attacker's venue AND the attacker's minOut | QuoteRotator.sol:355, :365-366 | Critical | FIXED (held; independently re-confirmed twice) | REMEDIATION_2026-09-11 |
| R-02 / R-03 | a completed rotation bricked relaunch(); address(0) was overloaded | relaunch / rotation door; TreasuryGovernor envelope | Critical / High | FIXED (pre-1e98bb4) | REMEDIATION_2026-09-11 |
| R-05 / R-06 / R-07 | spent envelope locked governance 30 days; spam wedged winner(); comment stranded engine | TreasuryGovernor cooldown, winner(); PerpEngine header | Medium–High | FIXED (pre-1e98bb4) | REMEDIATION_2026-09-11 |
| ACCESS-LOW-02 / INFO-03 / REENT-INFO-01 | wrong error to a non-owner; selector deploy-ordering; no reentrancy guard | 3 contracts; CauldronRegistry.sol:63; QuoteRotator | Low/Info | OPEN | ACCESS_LOGIC, REENTRANCY_ORACLES |
| RH-L5 | NotPriceable may make "rotate home to ether" unreachable | QuoteRotator.sol:389; usdPerRawUnit(address(0)) | — | LEAD | REHUNT L5 |
| RH-L6 | a 9th stockpiled mandate is invisible to the 8-slot bench forever | CauldronGovernor bench / _recomputeLeader | — | LEAD | REHUNT L6 |
| flat-lead-1 / flat-lead-6 | sequencer-restart grace as a scheduled window; _leadVotes poisoning | QuoteOracle.sol:320-341; TreasuryGovernor._leadVotes | — | LEAD | flat §4 |
| RH-R1 / R2 / R3 / R4 | bench dust eviction, vote replay, consume-split starvation, cheap cooldown burn | TreasuryGovernor.sol:728-731,527-543,463,745-767,868-881 | — | REFUTED | REHUNT §3 |
| RH-R5 / R7 / ACCESS-R1 / ACCESS-R3 | NotPriceable can't brick rebirth; forwarder bubbles; dedupe and getter exist | RedemptionExt.sol:398; CauldronRegistry.sol:1457-1468; CauldronGovernor.sol:434; QuoteOracle.sol:202 | — | REFUTED | REHUNT, ACCESS_LOGIC |
| PS-gov | rotation home to ether works; caller-supplied venue already closed | allowedQuote[0], _requirePriceable; QuoteRotator.sol:355 | — | PROVEN-SAFE (but see RH-L5) | flat §5 |

### Perps — engine, vault, mark source, liquidation

| prior id | title (≤12 words) | file(s):line as cited then | severity then | final status | source doc |
|---|---|---|---|---|---|
| X3a / X3c / H-1 / H-2 / R-08 | rotation redenominates every counter but plv; stale exit queue survives | PerpEngine.sol:1098, :466; PerpVault.sol:295-296 | High ×2 (Critical ×2) | FIXED (fixB) (fix-induced by R-08) | H3, V3, RECON §2 |
| X3b / H-3 | _creditPerp native ingress with no _quoteIsNative() test | PerpEngine._creditPerp / creditPerpFee(Token) | High | FIXED (fixB) | H3, V3 |
| X3d / H-4 | permissionless mark-ring reset collapses the TWAP | PerpEngine observations ring | High | FIXED (fixB) | H3, V3 |
| X3i / ACCESS-MED-01 / RH-R8 | payoutOwedTotal was a one-way ratchet — a free veto on adoption | PerpEngine payoutOwed; _payOut 30k gas stipend | High (Medium) | ** FIXED 1eff1d2 | ACCESS_LOGIC, REHUNT |
| X8-01 | the armed insurance floor makes the widened guard's zero unreachable | PerpEngine.sol:1157,:1679,:1919; DeployPerp.s.sol:94-97 | Critical | ** FIXED 1eff1d2 (self-inflicted by e964d54) | REHUNT |
| F-01 | one dust token-side vault share vetoes quote adoption | PerpVault.sol:86-90,:174-178; PerpEngine.sol:1208 | High | ** FIXED efaed64 (fix-induced by the H-2 fix) | FIXLAYER |
| F-02 | permissionless retirePayout burns a third party's escrow | PerpEngine.retirePayout | Medium | ** FIXED efaed64 (fix-induced by 1eff1d2) | FIXLAYER |
| F-03 | _q() rescales UNITS not VALUE; three thresholds switch off | PerpEngine._q / quoteUnit | Medium | FIXED efaed64 (setRouting gains _quoteOracle) | FIXLAYER |
| F-05 | a quote rotation books the entire live plvToken as stranded | PerpEngine.syncGeneration shortfall | Low | FIXED efaed64 | FIXLAYER |
| F-06 / ACCESS-INFO-01 | hasQuoteStake is dead code; observations lost its public getter | PerpVault.sol:86-90,:101; PerpEngine.sol:48 | Info | OPEN | FIXLAYER, ACCESS_LOGIC |
| O-3 | plvToken is assigned, not adjusted, at sync | PerpEngine.sol:1049-1051 / :1095 | High | ** DESIGN-DECISION → FIXED 1eff1d2 + 6459b85 (GATE-1 regression) | flat §3, RESUME §6.2 |
| O-2 | queued vault exits are 100% senior to live shares | PerpVault.sol:285-295, :263-278 | High | DESIGN-DECISION (owner: stays as-is) | flat §3, RESUME §6.1 |
| T02-1 / flat-lead-4 | PerpMarkSource.primary does not follow a rotation | PerpMarkSource.primary; addPool reverts WrongPair | High | FIXED 1eff1d2 (112,805,296× overstatement) | LEDGER, flat §4 |
| T02-2 / B-02 | absolute wei thresholds vs a quote-denominated amount | PerpEngine.sol:144, :786, :823 | High (prior Medium "fails safe") | FIXED 1eff1d2 | LEDGER, flat §3 |
| LIQ-01 | one large swap leaves a position permanently unliquidatable | PerpEngine.liquidate / LiqCapped (Sepolia r42 pos 3) | Critical | FIXED 9d5cd46 | LEDGER |
| LIQ-02 | a short bigger than the pool's token side is unclosable by anyone | PerpEngine close / liquidate / sweep | Critical | FIXED 03469bb (+31ee31a to free the bytes) | LEDGER |
| S01-x3 | rotation guard swapped refuse→sweep; recovery needed the timelock | PerpEngine.syncGeneration + retirePayout | High (liveness) | ** FIXED 2dd5169 (fix-induced by 1eff1d2) | RESUME gate 2, LEDGER |
| PERP-RENOUNCE | the owner could renounce and lock everyone out of engine and mark | PerpEngine, PerpMarkSource | Low | FIXED b54d785 | LEDGER |
| RH-L1 / RH-L4 | _pullQuote accepts empty returndata; claimPendingEth banks a zero | PerpEngine.sol:196-209; PerpVault.claimPendingEth | — | LEAD | REHUNT L1, L4 |
| ACCESS-R2 / PS-perp-1 / PS-perp-2 | ringArmedAt gate open; :1559/:1653 gated; _killStats casts move no value | PerpEngine ring; :1559,:1653; :1478-1481 | — | REFUTED | ACCESS_LOGIC, flat §5 |
| PS-perp-3 / PS-perp-4 | dust brick and force-close gas refuted; payable credit, bounty order, 1e6 offset safe | 64-position floor, 7.46M gas; PerpEngine/PerpVault | — | REFUTED / PROVEN-SAFE | flat §5 |

### Token, NFT, collection, dividend, ledger

| prior id | title (≤12 words) | file(s):line as cited then | severity then | final status | source doc |
|---|---|---|---|---|---|
| X9a / ART-1 | revealed art always reverts; the repair path is unreachable | CauldronCollection.sol:412-414,:316; FrenRenderer.sol:40-46 | High | FIXED fe6926f | CRITICALS |
| Z-02 | a stranger's ether donation inflates the dead collection's entitlement | CauldronVault.close / PoolOps | High | FIXED 6f2ba20 | FULLSWEEP |
| Z-08 / prior-M | gacha reveal grindable through the expired-seed re-anchor | MiFrensGenesis.sol:532-537 | High | ** FIXED 545cd29 + d552abc (was on the never-re-tested list) | FULLSWEEP, RESUME §7 |
| Z-09 / T-2 | nftSupply unbounded below; a proposal could flatten the mint ladder | CauldronGovernor.propose; MintCurvePolicy | High / Medium | FIXED f96d42f + a59a675 | FULLSWEEP, LEDGER |
| Z-10 | any ERC20 pushed to MiFrensDividend, its own royalties included, is stuck | MiFrensDividend | Medium | FIXED d552abc (adopt / accountedOf) | FULLSWEEP |
| Z-19 | a fully-retired generation traps every later credit | CollectionLedger.credit | Medium | FIXED a84b2cc | FULLSWEEP |
| Z-03 / Z-04 / Z-05 | buyCollection under-credits; _approve unchecked; floor counts burned NFTs | CollectionLedger.buyCollection; approval helper; floor calc | Low | OPEN | FULLSWEEP |
| Z-12 / Z-14 / Z-15 | MAX_PER_WALLET is a balance check; 30k receive(); factory transferOwnership | MiFrensGenesis; RoyaltyRouter.receive; CauldronFactory | Low | OPEN | FULLSWEEP |
| Z-13 / flat-lead-5 | _castSpell mutates activeShares after two external calls, no guard | MiFrensDividend.sol:396-397 | Low | OPEN / LEAD (unreachable today) | FULLSWEEP, flat §4 |
| Z-06 / Z-07 / Z-16 | rounding dust in totalEntitled; creatureFor(0) reverts; no token residual | CollectionLedger, MiFrensDividend | Info | OPEN | FULLSWEEP |
| O-9 | live collection floor divides a forged-only pot by an OG-inclusive count | PoolOps.sol:1382 | High | UNCHECKED (H-1's fix landed 12 lines away, never re-verified) | flat §3, RECON §5 |
| H-1 | the OG tranche can drain the forged tranche's floor | PoolOps.recycleCollection | High | FIXED (pre-1e98bb4) | flat §3 |
| X4d / D-1 | anyone permanently closes the dividend basket with junk | MiFrensDividend.sol:278, :282, :124 | — (prior High) | REFUTED / re-confirmed safe (comment fixed 0dd0c91) | RECON §3, FULLSWEEP #11 |
| FS-L1 | castSpell may be permanently unusable for a whole generation | MiFrensDividend.sol:457; RedemptionExt.sol:181; PoolOps.sol:793 | — | LEAD (would be a brick) | FULLSWEEP |
| FS-L2 / FS-L5 | setDividend re-settable to zero strands the basket; 320k gas floor per move | MiFrensGenesis.sol:343; MiFrensDividend.sol:111,414,545 | — | LEAD | FULLSWEEP |
| FS-R12 / FS-R14 | outstanding() desync and royaltyBps overflow both refuted | CauldronCollection.sol:384-387; CauldronRegistry.sol:602 | — | REFUTED | FULLSWEEP #12, #14 |
| PS-nft | no _safeMint anywhere; per-asset dividend accumulators; proposer-fee asset matches | mint paths; MiFrensDividend; _routeEthFee:1249 | — | PROVEN-SAFE | flat §5 |

### Genesis, seeder, vesting, deploy scripts, ops artefacts

| prior id | title (≤12 words) | file(s):line as cited then | severity then | final status | source doc |
|---|---|---|---|---|---|
| X5a | igniteCauldron never checks `cancelled`; the refund pot is forwarded | MiFrensGenesis.sol:575-586, :289, :305, :584 | High (Critical) | FIXED 038e4d7 | H5, V5 |
| X5c | vault close sweeps native; the divisor is quote-denominated | PoolOps.sol:1356; CauldronRegistry.sol:936-937 | High | FIXED 30b7d58 | H5, V5 |
| Z-01 | _sqrtPrice cannot represent a small 6-decimal quote; revert behind markConsumed | PoolOps._sqrtPrice / seedFunding | High | FIXED 3cf1053 | FULLSWEEP |
| Z-17 | permissionless poke(): unbounded prime buy at a caller-chosen tick | CauldronSeeder.poke | Critical | FIXED 9f04d9f (+12.157 ETH measured) | FULLSWEEP |
| Z-18 / Z-20 | MAX_RANGES fallback halts the stream; fundPrime redirects a funded budget | CauldronSeeder range cap; fundPrime | High / Medium | FIXED 9f04d9f | FULLSWEEP |
| X5f / X5g / O-8 | permissionless vestBatch, unpaginated _release, renounce live | MigrationVesting.sol:153-164, :221-242 | High | FIXED 20d6de2 (MAX_GRANTS 64 / MAX_BATCH 32) | flat §3, LEDGER |
| X5i / REENT-LOW-02 | _release marks a grant released before an unchecked transfer | MigrationVesting._release | Low | FIXED f42ca1a | REENTRANCY_ORACLES |
| X5b / X5e / X5h | sniper calls a nonexistent play(); opener assumption; renounce seals sweep() | LaunchSniper.sol:76; DeployLaunchpad.s.sol; LaunchSniper.sweep | Low | FIXED 79a3fed + 834063c + f990efd | H5, V5, LEDGER |
| X5d / X7c | three files each self-declared the canonical deployment record | deployments/*.json; indexer/deployments/round.json | Low | ** FIXED a6a56f8 → re-fixed 68c9dc1 (pointer aimed at round 20) | H5, CRITICALS |
| RH-L3 | vaultSwept native wei stranded on a non-native rebirth | PoolOps.sol:1077, :1088, :1090 | — | LEAD | REHUNT L3 |
| TEST-INTEGRITY | nine vm.warp helpers CSE'd under via_ir; lifecycle test crosses one gen | test suite, incl. test_FullLifecycle_ToRound3_OnFork | — | UNCHECKED | flat §3/§6, RESUME §7 |
| FS-R13 / FS-R17 / PS-seed | reserveTicks branch unreachable; over-deploy refuted; sniper/seeder/watermark clean | ReserveLib.sol:63-65; PoolOps._greenCandle:466; CauldronSeeder | — | REFUTED / PROVEN-SAFE | FULLSWEEP #13,15,16,17 |
| PS-seed-2 | library entrypoints, V4 unlock reentrancy and autoMigrateBatch all clean | PoolOps/ReserveLib entrypoints; unlock callback; autoMigrateBatch | — | PROVEN-SAFE | FULLSWEEP #1,2,3,18 |

### Off-chain — api/, src/, indexer/, scripts/

| prior id | title (≤12 words) | file(s):line as cited then | severity then | final status | source doc |
|---|---|---|---|---|---|
| X7a / G1 | every spot swap signs minOut = 0 | SwapWidget.tsx:96, :103 | High | FIXED 3a5a156 | CRITICALS (docs pass) |
| X6b + X6f / F1 + F4 | perp UI encodes a nonexistent openLong selector; close signs minOut=0 | src perp UI; registry has no fallback() | High / Medium | FIXED 6a275c5 | H6, V6 |
| X6d / F2 | /api/brand is unauthenticated — `sig` exists only in a comment | api/brand.ts | High | FIXED b502cac | H6, V6 |
| X6c / A-1 / F5 | fren-ask fetches whatever x-forwarded-host names | api/fren-ask.ts:55-64 | Medium (High) | ** FIXED 3c7d009 (A-1 reported fixed 09-08; FREN_DOCS_URL in no commit) | RECON §2, V6 |
| X6a / F3 | UI rotation minOut is a flat ~1 token, never scaled by the slice | TreasuryRotation.tsx:256; QuoteRotator.sol:355,365-366 | Medium (Critical) | FIXED 50839dc (on-chain half PROVEN-SAFE) | CRITICALS, V6 |
| X6e / F6 | keeper.sh binds addresses before sourcing env | scripts/keeper.sh | Medium | FIXED d517e62 | H6, V6 |
| X7b / G2 | marketmaker.sh calls a 4-arg play() against a 5-arg router | scripts/marketmaker.sh:63; CauldronGachaRouter.sol:233 | Medium | FIXED 96b3483 (the market maker had been silently dead) | CRITICALS |
| X6g / F7 | indexer subscribes to UnclaimedBurned, which nothing emits | indexer event table | Low (Medium) | FIXED 7890490 | H6, V6 |
| X6h / X6i / X6j | keys in argv (7 scripts); x-token unthrottled; liquidatoor reads any ?col= | scripts/*.sh; api/x-token; api/cauldron/liquidatoor.ts | Low | FIXED b8ec2b9 + fec94bf + b9e4583 | H6, V6 |
| G3 / G4 / G5 | duplicate /collection-floors; wrong liquidatoor default; phantom indexer getters | indexer routes; api/cauldron/liquidatoor.ts; indexer config | Low | FIXED f516e70 + ca68935 + cde65bd | LEDGER |
| A-4 | unsanitized SVG sinks, and the sanitizer then broke the badge art | src/lib/safeSvg.ts across 5 call sites | Info / Medium | FIXED (09-08, two passes) | REMEDIATION_2026-09-08 |
| A-2 / A-3 / A-5 / A-6 | GraphQL byte cap; indexer freshness gate; immutable emergencyAdmin; fren-teach secret | indexer GraphQL; 19 consumers; deploy wiring; api/fren-teach | Low / Info | UNCHECKED | RECON §5, RESUME §7 |

---

## (A) REFUTED — the argument that killed it, so a rediscovery can be dropped on sight

| id | one-sentence refutation |
|---|---|
| X1c (`setTaxExempt` inert) | `DeployLaunchpad.s.sol:241` **does** call `hook.setOpener(address(gacha), true)`, and `LaunchSniper.sol:76` swaps through `IGachaPlay.play`, so the opener *is* `sender` and `_taxedPlayer` decodes the sniper. |
| X2c / O-1 (oracle cache re-stamp) | Editing `QuoteOracle.sol:309` to stamp only on success changes nothing (`afterOneTtl == afterOneYear == afterTenYears == f0`); the freeze is the documented last-good tail, and the implied fix is strictly worse because a zero factor makes `_oracleFloor` return 0, which fails open. |
| X4d / D-1 (dividend basket cap) | `MiFrensDividend.sol:278 if (msg.sender != funder) revert NotOwner();` runs *before* the `MAX_ASSETS` check, so no stranger can append a slot, and a 4th asset's revert is swallowed by `FeeRouteLib._fundGuild` and rolls to `relaunchAsset[]`. |
| RH-R1 (bench dust eviction) | `_dead` tests only `executed \|\| cancelled \|\| past EXECUTION_WINDOW`, so an open proposal is scored at its full `forVotes`; dust never displaces a voted mandate. |
| RH-R2 (vote-weight replay) | Both governors weigh by `getPastVotes(msg.sender, p.snapshot)` and gate on `hasVoted[id][msg.sender]`, so cycling one MiFren through N addresses yields zero after the snapshot. |
| RH-R3 (consume-split starvation) | `allowance()` reads `movedPrimaryBps`, so a secondary-leg spend leaves the whole migration budget reported and the envelope live; `movedBps` peaks at `2*cap == 20_000`, inside `uint16`. |
| RH-R4 (cheap cooldown burn) | `execute` still requires `_passed` — quorum against `getPastTotalSupply(p.snapshot)` **and** `forVotes > againstVotes` — so burning `lastEnvelopeAt` costs a real majority. |
| RH-R5 (`NotPriceable` bricks rebirth) | The only non-test caller of `swapOnce` is `RedemptionExt.sol:398` inside `rotateSliceFrom`; the teardown/relaunch path never touches it, so the new revert cannot reach `relaunch()`. |
| RH-R7 (relocated bodies no-op) | `CauldronRegistry._forwardToExt` (`:1457-1468`) rejects a zero facet and bubbles returndata and revert data verbatim, so the moved bodies cannot silently no-op. |
| ACCESS-R1 (`_benchRecord` dedupe missing) | The `b == id` de-duplication is at `CauldronGovernor.sol:434`; a comment-stripping diff filter hid it. |
| ACCESS-R2 (`ringArmedAt == 0` blocks opens) | Backwards — `0 + twapWindow` is in 1970, the comparison is false and the gate is open. |
| ACCESS-R3 (`_usdLive` calls a missing function) | `QuoteOracle.usdPerRawUnit(address) external view` exists at `:202`. |
| PS-perp-1 (unchecked `transferFrom`) | `PerpEngine.sol:1559` is `onlyOwner` and `:1653` is `onlyVault`; the vault caller already `_pull`s with a checked return and the token is always a plain OZ ERC20. |
| PS-perp-2 (truncating casts) | The casts live in `_killStats`, whose only consumer is badge metadata — a clamp misreports a collectible, it moves no value. |
| PS-perp-3 (dust brick / force-close gas) | The floor is a full 64-position book, and 64 force-closes cost 7.46M gas, well inside 30M; the damage was the `NotDead()` gate, not gas. |
| FS-R11 (`MAX_ASSETS` junk-fill lockout) | `funder` is the hook and the asset is the hook's `_feeAsset`, adopted only in `_afterInitialize` behind the registry gate, so a stranger cannot choose what the claim loop walks. |
| FS-R12 (`outstanding()` desync) | No burn path shrinks `totalMinted`: both `burnFromVault` sites call `_burn` only, `totalMinted`/`minted` have single writers, and the OG recycle uses `custodyTransfer`. |
| FS-R14 (`royaltyBps` overflow) | `CauldronRegistry.setRoyalty:602` already enforces `_bps > 1000 → TooHigh`, and the default is 500. |
| FS-R13 / FS-R17 (reserve band, seeder over-deploy) | The degenerate `reserveTicks` branch needs `launchTick ≤ -844800` while `_greenCandle:466` is strongly positive; stream acceleration is unreachable from the shipped parameters. |
| PS-gov ("94% of the slice extracted") | Retracted as not reproducible by the session that filed it: `allowedVenue` is keyed by `PoolId` and `_routeMatches` checks both directions. |

## (B) UNCHECKED — explicitly never re-tested; carry into P3 as untested, not as covered

1. **O-9** — live collection floor divides a forged-only pot by an OG-inclusive count (`PoolOps.sol:1382`, 12.11× under-payment). H-1's fix landed 12 lines away in `recycleCollection`; nobody confirmed it closed O-9. *(RECONCILIATION §5)*
2. **Test-suite integrity** — nine `vm.warp` helpers are common-subexpression-eliminated under `via_ir`, including `test_FullLifecycle_ToRound3_OnFork`, which claims three generation lifetimes and crosses one. No agent has ever audited the existing suite. *(flat §3/§6, RESUME_PLAN §7)*
3. **A-2** — unbounded public GraphQL, no byte cap. *(09-08; outside H6's sample)*
4. **A-3** — indexer freshness gate wired on 1 of 19 consumers. *(09-08; outside H6's sample)*
5. **A-5** — immutable `emergencyAdmin`. *(09-08; outside H6's sample)*
6. **A-6** — `fren-teach` admin secret comparison and brute force. *(09-08; outside H6's sample)*

Two items that were on RESUME_PLAN §7's unchecked list at hand-off and have since been closed —
**Z-08** gacha reveal grindability (`545cd29`), treasury scan flood (`e377594`) and unpaginated
vesting release (`20d6de2`) — are indexed above as FIXED, not as unchecked.

The two RESUME_PLAN §6 **DESIGN DECISIONS** — **O-2** perp-vault queue seniority (owner: stays as-is)
and **O-3** `plvToken` assignment (owner: track the shortfall) — are decisions, not open bugs. Do not
re-file them as bugs without new impact.
