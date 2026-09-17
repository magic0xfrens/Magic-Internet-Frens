# FUNCTIONAL COHERENCE — does the protocol do what it says? (P5, 2026-09-13)

Three agents, one per pair of spec sections, each answering five questions per claim: does the
contract do it (`file:line`), does the frontend expose it correctly (ABI, units, native-vs-ERC20,
`minOut` source, approvals, addresses vs `indexer/deployments/round.json`, chain switch), does the
indexer record it, does any UI/doc promise what the contracts cannot do (or the reverse), and does
the mechanism make economic sense as built. Inputs: `audit/spec/sections/*`, `docs/protocol/*`,
`src/components/docs/magicfrens-llm.md`, the six "model from code" sections from the P1 hunt, and
the ledger's DONE rows. Full per-claim tables: `coherence/Ca_A_B.md`, `coherence/Cb_C_ED.md`,
`coherence/Cc_F_G.md`.

## Totals

| sections | High+ | Medium | Low | Info | can any row lose a user's funds? |
|---|---|---|---|---|---|
| A genesis/NFT + B lifecycle | 0 | 3 | 5 | 3 | no |
| C volume/credit/death + E-D spine/rotation/perps | 0 | 4 | 7 | 0 | no |
| F dividends + G floors/redemption | 1 | 3 | 3 | 5 clean checks | no (funds survive as `owedAsset`; the UI cannot reach them) |
| **total** | **1** | **10** | **15** | | **none** |

## Mismatch table (High and Medium; Lows are in the section reports)

| id | sev | claim | reality | frontend / indexer | fix owner |
|---|---|---|---|---|---|
| FG-1 | High | Guild dividend is claimable per generation (spec F; docs 07/08) | Contracts hold a full ERC20 basket (`MiFrensDividend.sol:273,295,307,333`) | `src/hooks/useMiFrensDividend.ts:197,225,238,245` and `indexer/abis/DividendAbi.ts:4-31` know only ether: on a non-ether generation 100% of the guild slice renders as zero with no claim button | fixCOH |
| B-01 | Med | Streamed progressive launch, `SEED_BASE_WAD = 0.15e18` (`03-GENESIS-AND-SEEDING.md:241,268`, `magicfrens-llm.md:262-266`) | `PoolOps.sol:168` = `1e18` by design (`40b9608`): every launch is the atomic full-range base; `startSeed` (`:410`) never runs; `deploy/DeployLaunchpad.s.sol:368-373` still arms the seeder | docs only | fixCOH (docs) |
| A-01 | Med | Reveal re-anchor is unlimited (`08-NFT-ECONOMY.md:116-117`, spec A3) | `CauldronCollection.sol:300-312` caps it at one; second expiry commits tier 0 | no UI clock, no `ReAnchored` indexer handler | fixCOH (docs) |
| A-02 | Med | Rarity tiers | `CauldronCollection.sol:99-101` = `0 Common, 1 Rare, 2 Epic, 3 Ultra` | `src/components/wizards/ForgedCreatures.tsx:33` uses a 5-entry table, every non-Common tier renders one slot low; `CreatureModal.tsx:10` is correct | fixCOH |
| C-1 | Med | "The book is provably empty … safe without a new guard" (`13-PERPS.md:553-560`) | `RedemptionExt.sol:617` swallows `VaultStaked`; the engine parks as dead until the timelock override (`PerpEngine.sol:1388-1389`, `:1883`) | `src/config/perp.ts:168` tells the user "the token died" | fixCOH + docs |
| C-2 | Med | Unarmed `weightedTick` returns tick 0 (`13-PERPS.md:242,638-641`) | reverts `NotArmed` (`PerpMarkSource.sol:183`); `markSource` cleared on every sync, must be re-armed via `setRouting` | no frontend error map knows `NotArmed`; the re-arm duty is undocumented | fixCOH + docs |
| C-3 | Med | Vault errors are surfaced | `PerpVault.sol:178,274` `QueueInsolvent`; `:171` `TokYieldForfeited` | `PERP_VAULT_ABI` (`src/config/perp.ts:142-160`) declares zero errors → raw hex; the event is decoded nowhere | fixCOH |
| C-4 | Med | Indexer tracks position size | `PerpEngine.sol:525` `PartiallyClosed`, `:531` `TokenDebtWrittenOff` | `indexer/abis/PerpEngineAbi.ts` lacks both, so partial fills leave stale `perpPosition`/`perpStat` sizes | fixCOH |
| FG-2 | Med | "A royalty must not wait on a keeper" (`RoyaltyRouter.sol:36-39`) | `sweep(address)` is permissionless | zero callers in `src/`/`indexer/`; no `royaltyRouter` key in `round.json` | fixCOH |
| FG-3 | Med | "Any ether sent to RoyaltyRouter reverts" (`07-FEES.md:32,342`) | `RoyaltyRouter.sol:83-93` swallows the forward and never reverts a sale | docs only | fixCOH (docs) |
| FG-4 | Med | SPIN (churn) works on any quote | `playChurn` now carries `minTokenOut`, wired correctly (`src/config/cauldron.ts:437-449`; zero floor refused `useCauldronSwap.ts:298-300`) | `useCauldronSwap.ts:308-310` hard-codes native `value` with no ERC20 branch → SPIN fails safe on a rotated quote | fixCOH |

Clean checks worth recording (the 09-11 run's suspects): the surtax is additive in code and docs
now agree; holder-tax tiers are documented as conditional; `redeemCreature` naming, genesis floor
events and the royalty destination split all match.

## Verdict (≤ 200 words)

The protocol as built is structured sensibly, and after today's fixes the contracts are the most
coherent layer: the multi-asset dividend basket, the per-generation ledger floor, the 2× ratchet,
the live-token denomination, the full-range base at summon, the bench-ordered governors and the
banded death path all do what sections A–G say. The incoherence is above the contracts. The
frontend and indexer lag three contract generations of ABI: they cannot show or claim an ERC20
dividend (FG-1, the only High), do not decode the new perp events or errors, hard-code native
value on the churn path, and mislabel rarities. The docs and the LLM-facing page describe the
launch mechanism that was deliberately switched off in `40b9608`, the unlimited re-anchor that is
capped, and a router that "reverts" but now never does. None of these can make a user sign a
losing transaction; several make a real payout invisible or a real state ("parked", not "dead")
misreported. The incentive that breaks first is not economic but operational: two new duties —
re-arming the mark source after every sync and calling the royalty sweep — have no caller and no
documentation, so they will simply not happen unless the keeper or the UI does them.
