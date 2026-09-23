# MiFrensGenesis — complete source traversal, final verification pending

All 986 lines read including every executable body/interface/state declaration.
No production modification. Historical narrative is not treated as fresh proof.

| Function group | Analysis and remaining verification |
|---|---|
| constructor/setMaxPerWallet/remainingGenesisAllowance | Positive genesis/price/cap, art supply below badge ID base. Constructor permits nonbinding cap; setter enforces binding and only decreases after any mint. Lifetime count independent of voting balance. Discount price truncates price/10 (can zero for price<10); deployment inputs must constrain. |
| setRegistry/setUnrevealedURI/setDiscountRoot/setDiscountSetter | One-time nonzero registry without code check; immutable deployer authority. Root publisher can change list, cumulative per-wallet spend survives changes. URI/list centralization is explicit. |
| mint(uint)/mintDiscounted/_mintGenesis | Exact value, genesis supply, lifetime cap, finalized/cancelled checks. Double-hashed fixed-width Merkle leaf binds caller and allowance. Discount counter update rolls back on failed mint. paid records actual discounted amount. NonReentrant plus ordinary _mint prevents receiver callbacks; transfer validator uses external view. No safe receiver guarantee for contract buyers. |
| cancelPresale/refund | Deployer may cancel before finalize including sellout; refund to payer, not current NFT owner. CEI and nonReentrant; rejection restores debt. NFTs and their votes survive cancellation; external governance/funding assumptions need full deployment integration. |
| totalMinted/maxSupply/soldOut/remaining/isGenesis/ogTrait | Minted count includes art only, not badges; isGenesis is ID-range predicate, not existence check. SoldOut doesn't mean ignition is authorized/not cancelled. Consumer must check other flags. |
| onlyDeployerOrRegistry/setMinter/setVault/setDividend | Both authorities remain live after ignition despite pre-ignition wording. Minter can volume-mint before finalized if wired early; no hard finalized/tranche-start gate. Correct deployment sequencing critical. Deployer authority cannot be handed off here. |
| liquidator setters/mintLiquidator/mintLiquidatorWithStats/_mintLiquidator/liqStats/liquidatoorTrait | Dedicated minter, separate monotonic ID space; ordinary mint no receiver callback. Optional stats only if victim nonzero. Deployer/registry/current minter may wire badge minter; renderer/URI deployer-only. Badges not included in minted art. Narrative saying badges vote is obsolete; executable voting excludes them. |
| custodyTransfer/burnFromVault | Registry may transfer without approval; vault burns without explicit holder approval (caller policy supplies authorization). Routes through validator, voting and dividend hooks. Role replacement and registry ownership checks need lifecycle verification. |
| setFinalizer/setMetadata/setRarityOdds/setRoyalty/creator-validator getters+setter | Persistent deployer powers; ordered BPS odds ending10000, royalty<=1000. Metadata/validator can revert token operations via trusted configuration. Validator selector view declaration and supportsInterface checked in source; external marketplace parity not proven. |
| mint(address)/reveal/revealBatch/_reveal/_rollRarity | Authorized volume mint records uint48 block then ordinary mint. Owner-only reveal, batch1..50, known mint-block hash after block advances. One expiry reanchor, then Common on second expiry. Holder can discard first known draw for a second attempt; cap prevents unlimited rerolls, not all optionality. Deployer may change odds before reveal. Privileged/sequencer randomness influence not ruled out. Badge metadata bypasses reveal mappings. |
| igniteCauldron | NonReentrant, registry wired, not finalized/cancelled, genesis soldout and finalizer check. Sets finalized then sends entire balance to summon; failure rolls back. No independent returned-token validation. Trust is one-time registry. No general owner withdrawal. |
| tokenURI | Ownership required; badge renderer/fallback first, volume sealed placeholder, art one-argument renderer or baseURI+id. API parity differs from per-collection rarity/path and needs consumer check. |
| _update/_getVotingUnits/_increaseBalance/supportsInterface | Validator before transfer; only genesis IDs traverse ERC721Votes, then genesis balances updated before optional self-delegation. Non-genesis bypasses voting movement. Existing zero delegation is reset on receipt, including badge receipt. Dividend call after ownership mutation forwards260k with320k minimum; genuine failure swallowed, so full three-asset transfer behavior must be verified. everMoved only genesis; forged enchant-fee logic must account for that. No final conclusion from gas constants alone. |

Remaining: actual deployment/iteration2 mint sequencing, custody+dividend+votes
state invariants, cancellation with governance, full quote-basket transfer gas,
reveal/metadata parity, ABI/build/source/deployment checks. Targeted existing
regressions are running, not yet passing evidence in this worksheet.

Targeted batch completed: 48 executions in11 suites pass, no failures/skips.
Some inherited repeats; no distinct-property count claimed. B02 three-asset
settlement measured201,860 gas under260k forward budget. This narrows gas gap
for tested standard tokens; adversarial dependency and full lifecycle gaps remain.

## Final disposition (2026-09-23)

Final: setTransferValidator is the reachable trigger for FS-gacha-01 (fixed in GachaLib). Presale/ignition/continuation exercised in the local-chain rehearsal. Signed off.
