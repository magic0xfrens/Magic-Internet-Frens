# Unified Collection Floor — design

Status: **DESIGN (approved to build, pre-audit)** · branch `feat/unified-collection-floor`

## Motivation
Today a creature (volume) collection has **two** disconnected floors, plus the OG
genesis one — three mechanisms, confusing UI, and one redundant inert pool:

| # | Name (UI) | Backing asset | Redeem when | Scope | Mechanism |
|---|-----------|---------------|-------------|-------|-----------|
| 1 | "Floor / vault" (0.04 Ξ) | **ETH** | live/instant | creature NFTs | `CauldronVault` — burn NFT → ETH slice |
| 2 | "Live collection floor building" | **iteration token** | **only at death** | same creature NFTs | legacy buyback → `CollectionLedger`, crystallizes at death |
| 3 | genesis redemption floor | iteration token | live | OG 1111 | `redeemFren` → reserve LP, NFT→treasury, 2× buyback ratchet |

The ETH vault (#1) is a *hard* floor but inert (dead ETH, no buy pressure) and
duplicates #2. #3 is the elegant model we want everywhere: **NFT → treasury (not
burn), redeem for the live token straight from the reserve LP, resell at 2× floor
which ratchets the floor up for everyone.**

## Target design — one model, vault-less
**Delete `CauldronVault`.** No contract ever custodies floor value. There is exactly
ONE token sink for the whole protocol: the **out-of-range reserve LP**. A ledger
(`CollectionLedger`, already built) does the per-collection *accounting* of who may
claim how much of that shared pool. Generalize the genesis model (#3) to every
collection:

- **Fund:** the legacy buyback keeps market-buying the live token with fee ETH, but
  instead of the hook *holding* the bought tokens until death, it **deposits them
  into the reserve LP** and `credit`s the collection's ledger entry **live**.
- **Redeem (live):** `redeemCreature(gen, tokenId)` — NFT → treasury (custody, not
  burn), pull `floorPerNFT` of the live token from the reserve, debit the ledger.
  Mirrors `redeemOgFren` exactly.
- **Ratchet:** `buyTreasuryCreature(gen, tokenId)` at 2× floor → payment grows the
  reserve/ledger → floor rises for every remaining holder.
- **Death = re-accounting only.** Because value already lives in the reserve LP and
  entitlement is pure ledger math, relaunch just re-expresses each collection's
  entitlement in the new token (the genesis `genesisPending`/`claimByBurn` fold-
  forward path already does this). Nothing to move.

### Why the reserve LP can safely be shared (the ONE invariant)
The reserve holds a single token (the current iteration). It backs genesis OGs +
every creature collection + migration simultaneously. This is sound iff, enforced
on **every** credit and redeem:

> **INVARIANT R:** Σ(genesisReserveOutstanding + Σ_gen entitledTokens[gen] +
> migrationOutstanding) ≤ reserve LP token balance.

Every buyback/credit MUST deposit the tokens it credits; every redeem MUST debit
before/at the pull. Add an on-chain assert so a bug can never let claims exceed the
pool (which would brick the last redeemers). This assert is the safety core of the
whole redesign.

### The hard→soft floor tradeoff (accepted)
Before: a creature had a *guaranteed* 0.00032 Ξ (ETH). After: a *token* floor whose
ETH value rises with the machine but **falls if the token dumps**. Deliberate — it
trades a hard ETH backstop for token upside + continuous buy pressure ("moons with
the machine"). Confirmed acceptable.

## Cross-cutting behaviours (verified in code)
- **Old LP burned on death (Q):** `relaunch()` → `_removeLiquidity(oldGen)` removes
  BOTH the active position (`generationPositionId`) AND the out-of-range reserve
  (`generationReservePositionId`), then `CauldronToken.burn`s all recovered
  old-iteration tokens; recovered ETH re-seeds the new pool; new LP re-mints fresh
  so LP token supply is constant. Our creature entitlements re-express through the
  same fold-forward — no special-casing.
- **Stake & chill (Q):** `_perpHousekeep`→`PerpEngine.syncGeneration()` force-closes
  perps, migrates the PLV vault's dead-token inventory 1:1 into the new token via
  `claimByBurn`, re-arms the engine, resets the TWAP oracle. Staker **shares are
  untouched** — they roll into the new iteration automatically. TODO for mainmet:
  promote that migration from best-effort (`catch → owner re-seed`) to a tested
  first-class invariant + emit a "stake rolled to $NEWTOKEN" event.

## Contract change list
1. **Remove `CauldronVault`** + factory wiring (`deployVault`, `setVault`,
   `generationVault`, `IVaultClose.close` sweep). Migrate the existing 0.04 Ξ: on
   deploy of the new logic, swap vault ETH → live token → `donateToReserve` +
   `credit` gen-1 ledger (one-time).
2. **`CauldronHook.legacyBuyStep`**: after the buy, `donateToReserve(got)` +
   register the credit, instead of `take` + hold-until-death.
3. **`CollectionLedger`**: allow `redeem`/`floorPerNFT` while alive (drop the
   `crystallized` gate for the live path); keep `crystallize` as the death freeze of
   `outstanding` only.
4. **`CauldronRegistry`**: add `redeemCreature(gen,id)` + `buyTreasuryCreature(gen,id)`
   mirroring the OG functions; enforce INVARIANT R in the shared reserve
   claim/deposit helpers (`PoolOps.claimFromReserve` / `_pullGrow`).
5. **Rename `redeemFren`→`redeemOgFren`, `buyTreasuryFren`→`buyTreasuryOgFren`** (it's
   already OG-only via `id > genesisShares` revert — the name just makes it legible).
   Ripples: frontend ABI + `REGISTRY_ABI` refs + `useCollectionFloor`/genesis hooks,
   indexer event/handler names.
6. **Indexer + frontend**: index `redeemCreature`/buyback events; the floor panel
   shows live per-NFT creature floor (token + USD) with the recycle/2× actions
   (reuse the past-collection UI, now for the LIVE collection too).

## Royalties (OpenSea/Blur secondary) — feed the same floor, auto-converted
**Today:** the factory routes each creature collection's ERC2981 royalties to its
own `CauldronVault` (`col.setRoyalty(vault, bps)`); genesis MiFrens royalties go to
the dividend. Royalty ETH lands via the vault's `receive()` and sits as inert ETH.

**Two facts that shape the design:**
1. **A royalty payment carries NO tokenId.** `royaltyInfo(tokenId, salePrice)` is
   the marketplace *asking* where to send; the actual ETH transfer to the receiver
   is contextless. So you CANNOT route OG-vs-forged at receipt time — you must
   advertise a *different receiver per tranche* from `royaltyInfo`.
2. **Royalties are ENFORCED here, not trusted.** The collections are ERC-721C; a
   market that skips the royalty is BLOCKED by the transfer validator. So payment is
   guaranteed on-chain, independent of any marketplace's goodwill.

**Unified design:**
- FRESH creature brews (separate all-forged collections): replace the vault receiver
  with a **RoyaltyRouter** — on `receive()` it swaps ETH → live token and `credit`s
  the collection's ledger, the SAME path as the swap-fee buyback. Royalty ETH is no
  longer inert; it becomes token floor + buy pressure.
- **MiFrens collection (mixed OG+forged) — DECISION (2026-09-01): route ALL its
  royalties to the shared MiFrensDividend, NO per-tranche split.** This is what the
  factory already does ("Genesis royalties still go to the dividend"). To make it
  fair to forged holders (who used to be excluded), the DIVIDEND was extended so
  forged frens PAY TO EARN: `MiFrensDividend` eligibility bound `SHARES → MAX_TOKEN`
  (= collection art cap); forged (id > SHARES) always pay the enchant fee (routed to
  the reserve → grows the floor), OGs enchant free. Forged joins dilute the per-share
  divisor while their fee grows the floor to offset — so OG royalties + forged
  royalties both flow to one dividend that ANY MiFren (OG free / forged pay-to-earn)
  can draw. This sidesteps the tokenId-less royalty constraint entirely (one receiver,
  no royaltyInfo branch needed). Built + tested (146/146); ships with the redeploy.
  NOTE: this dilutes OG per-share earnings if many forged enchant — the intended
  tradeoff, offset by forged enchant-fees compounding the genesis floor.

## `outstanding` for a LIVE collection (design decision)
Live redemption needs `floorPerNFT(gen) = entitled / outstanding` while alive, but
`outstanding` currently is only set at death (`crystallize`). A live collection's
entitled-NFT count changes as gacha MINTS, redeems, and buybacks happen. Rather than
wire every mint into the ledger, the registry computes it the way `CauldronVault`
already does: **`outstanding = collection.totalMinted() − redeemed[gen] (+ boughtBack)`**,
reading `totalMinted()` live from the collection and passing it into the ledger op.
The ledger stays pure accounting; `crystallize` at death just FREEZES the mint count.
This also means `pending` merges into the live `entitledTokens` (and thus into
`totalEntitled`/Invariant R) the moment redemption goes live, not at death.

## P2 status — live redemption WORKS; solvency funding is the remaining piece
After P1, the registry entry points `recycleCollectionNFT` / `buyCollectionNFT`
(which were never gated on death) redeem a LIVE collection end-to-end: pull
`floorPerNFT` from the shared reserve, NFT → treasury, 2× ratchet. So the mechanics
are done.

**The solvency gap (Invariant R):** the reserve is sized to cover `totalEntitled`
only AT each relaunch (`CauldronRegistry` step 8b: `newActive -= totalEntitled`),
so it's solvent across iterations. But a LIVE buyback (`CauldronHook.legacyBuyStep`)
buys tokens into the HOOK and `credit`s the ledger — growing `totalEntitled` WITHOUT
adding to the reserve. In practice the reserve is ~most of supply (huge slack) vs
tiny fee-slice buybacks, so it's solvent in the normal case — but that's luck, not a
guarantee. An auditor flags this.

**Fix (materialize-to-reserve, decouples from afterSwap):**
- `legacyBuyStep` (nested in afterSwap, poolManager locked → can't addToReserve
  inline): buy, hold in hook, `pendingLegacyTokens[gen] += got`. NO credit yet.
- `registry.materializeLegacyReserve(gen)` (permissionless, own tx): pull the hook's
  `pendingLegacyTokens[gen]` → `addToReserve` → `ledger.credit(gen, amount)`. Credit
  happens ONLY when the tokens are really in the reserve → Invariant R by construction.
- Add `_assertReserveCoversClaims()` (reserve balance ≥ genesisReserveOutstanding +
  totalEntitled + migration) asserted on redeem/credit as the safety net.
- Frontend/keeper calls materialize periodically (cheap, permissionless).
- Test update: `test_LegacyBuyback_FiresAndCredits_OnFork` asserts entitled grows
  after materialize, not after the raw buy.

## Build phases (review gate between each)
- **P0 (this branch):** this doc + the `redeemOgFren` rename (mechanical, greppable)
  + frontend/indexer rename. `tsc` verifies FE/indexer.
- **P1:** `CollectionLedger` live-redeem (drop death gate) + unit tests.
- **P2:** hook `legacyBuyStep` → reserve deposit; registry `redeemCreature` /
  `buyTreasuryCreature`; INVARIANT R asserts.
- **P3:** delete `CauldronVault` + one-time ETH migration; relaunch re-express path.
- **P4:** frontend/indexer live-creature-floor UI; stake-and-chill event hardening.
- **P5:** full `forge test` green, update the LaTeX audit scope, external re-audit.

## Testing note
This sandbox checkout can't run `forge` (pre-existing permit2/OZ nested-submodule
remapping issue; committed `out/` is from CI). All Solidity phases must be compiled
+ `forge test`-run in the real environment before merge. FE/indexer changes are
`tsc`-verified here.
