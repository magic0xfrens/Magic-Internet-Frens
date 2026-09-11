# AREA G — Floors, redemption, and the 2x treasury ratchet

All line numbers verified by reading the cited file at that path in this checkout
(branch `fix/b05-b07-relaunch-totality`). `contracts/solidity/` is the root for all
paths below unless stated otherwise.

---

## G1 — Genesis (OG) floor — LIVE

**Mechanism:** genesis holds a single scalar, `genesisReserveOutstanding`
(`cauldron/CauldronBase.sol:198`), against the shared out-of-range reserve LP
position (`generationReservePositionId[gen]`, `CauldronBase.sol:193`).
`floorPerFren() = genesisReserveOutstanding / genesisShares`
(`CauldronBase.sol:368-372`) — a `view` on the base contract, inherited by both
the registry and the delegatecall facet.

**Entrypoints (delegatecall facet `cauldron/RedemptionExt.sol`, forwarded from
`CauldronRegistry.sol`):**

| Function | Facet body | Registry forwarder (thin stub) |
|---|---|---|
| `redeemOgFren(id)` | `RedemptionExt.sol:73-101` | `CauldronRegistry.sol:1336-1338` |
| `buyTreasuryOgFren(id)` | `RedemptionExt.sol:110-122` | `CauldronRegistry.sol:1342-1344` |
| `donateToReserve(amt)` | `RedemptionExt.sol:131-135` | `CauldronRegistry.sol:1348-1350` |
| `materializeLegacyReserve()` | `RedemptionExt.sol:142-155` | `CauldronRegistry.sol:1354-1356` |

**Actual authority.** All four are externally callable by anyone; the registry
forwarders carry NO `onlyOwner`/allowlist. Authority is enforced inside the
facet body: `redeemOgFren` requires `IERC721(mifrens).ownerOf(id) == msg.sender`
(`RedemptionExt.sol:79`); `buyTreasuryOgFren` requires the NFT currently sit in
the treasury, i.e. `ownerOf(id) == address(this)` (`:114`). The forwarding is a
raw `delegatecall` of the full calldata (`CauldronRegistry.sol:1404-1415`); the
facet's own storage (if called directly) is empty, so a direct call to the
deployed `RedemptionExt` reverts before touching value (`RedemptionExt.sol:33-39`
NatSpec, verified against the guard checks each function opens with).

**Preconditions:** `summoned == true`; `mifrenTokenId` in `1..genesisShares`
(OG-only, `RedemptionExt.sol:78,112`); redemption not paused
(`_redeemBlocked()`, `CauldronBase.sol:374-380`, checked in `redeemOgFren` only,
`RedemptionExt.sol:74` — `buyTreasuryOgFren`/`donateToReserve` are NOT gated by
`_redeemBlocked()`).

**Behavior — `redeemOgFren` (`RedemptionExt.sol:73-101`):**
1. `F = floorPerFren()`; revert `BadConfig` if 0.
2. Debit `genesisReserveOutstanding -= F` (checks-effects, before the pull).
3. `custodyTransfer(msg.sender, address(this), tokenId)` — NFT moves to the
   registry (treasury), **not burned**; breaks its dividend spell.
4. `PoolOps.claimFromReserve(...)` pulls `F` of `generationToken[currentGeneration]`
   from the out-of-range reserve position straight to `msg.sender`
   (`PoolOps.sol:1132-1161`).
5. If `amount + 1e12 < F`, revert `NoBalance` — a short reserve rolls back the
   NFT move and the debit together (`RedemptionExt.sol:99`, cites "Audit H-03").

Value moved: `F` units of `generationToken[currentGeneration]` (the CURRENT
iteration's token — always read live, never the token that was current when the
fren was minted).

**Behavior — `buyTreasuryOgFren` (`RedemptionExt.sol:110-122`):**
1. `paid = 2 * floorPerFren()`.
2. `_pullGrow(msg.sender, paid)` — `transferFrom` the buyer, then
   `PoolOps.addToReserve(...)` deposits it back into the same reserve position
   (`RedemptionExt.sol:160-179`); `genesisReserveOutstanding += added` — **the
   floor ratchets up for every remaining OG**, denominated in the current token.
3. NFT moves treasury → buyer via `custodyTransfer`.

`_pullGrow` reverts `NoBalance` if `addToReserve` returns 0 (out-of-range
liquidity rounds the deposit to nothing) — "PAY-FOR-NOTHING GUARD", audit F-07
(`RedemptionExt.sol:168-176`) — so a donation/buyback that can't reach the
reserve is never collected.

**Postconditions / invariants:** `genesisReserveOutstanding` strictly decreases
by exactly `F` on redeem and increases by exactly what `addToReserve` actually
consumed on buy/donate — never assumed equal to the requested amount.

**Events:** `FrenRedeemed(tokenId, holder, amount, gen)`, `FrenBought(tokenId,
buyer, paid, gen)`, `FloorGrew(added, newReserve, newFloorPerFren)`
(`CauldronBase.sol:136-143`).

**Denomination:** paid/priced in `generationToken[currentGeneration]`, read
**live** at call time (`currentGeneration`, `RedemptionExt.sol:89,161`) — never
the quote asset (ETH/USDG/etc.), never a value captured at credit time.
`DENOMINATION: quote-agnostic — RedemptionExt.sol:89,161; ReserveLib.sol` (the
reserve math (`cauldron/ReserveLib.sol`) operates purely on `currency1` = the
iteration token, never touches the quote's decimals).

---

## G2 — Creature (collection) floor: three mechanisms, classified

| # | Mechanism | Entry point | Status | Evidence |
|---|---|---|---|---|
| 1 | ETH vault | `CauldronVault.redeem` | **DEPRECATED-PRESENT** (deployed, neutered, still load-bearing for sizing) | see below |
| 2 | Ledger crystallization / live redeem | `CauldronRegistry.recycleCollectionNFT` / `buyCollectionNFT` → `CollectionLedger.redeem`/`buyback` | **LIVE** (works both alive and dead) | see below |
| 3 | Unified `redeemCreature`/`buyTreasuryCreature` | — | **ABSENT** — does not exist in this tree | `grep -rn "redeemCreature\|buyTreasuryCreature"` over `contracts/solidity` (excluding `out/`) returns zero matches |

### 1. ETH vault — `CauldronVault` — DEPRECATED-PRESENT

`CauldronFactory` still deploys one on **every** brew:
- fresh brew: `CauldronFactory.sol:75-76` — `new CauldronVault(col, registry, 0)`
  then `col.setVault(address(v))`.
- iteration-#2 MiFrens continuation: `CauldronRegistry._continueMiFrens` calls
  `factory.deployVault(mifrens, address(this), genesisShares)`
  (`CauldronRegistry.sol:1142`), `IMiFrensContinuable(col).setVault(vlt)`
  (`:1145`).

Both deploy paths immediately neuter it: `_deployCollection`
(`CauldronRegistry.sol:1124`) and `_continueMiFrens` (`:1148`) call
`hook.setVault(address(0))` right after wiring the collection to its vault —
this is the setter that feeds the vault ETH via `_takeEthFee`'s floor share
(`CauldronHook.sol` fee routing, `:1298-1309`). With `hook`'s `vault` pointer
zero, the floor-share fee is routed instead into the legacy buyback buffer
(`CauldronHook.sol:1304`, `wantFloor` folds into `legacyBuffer`/`wantRelaunch`)
— **no ETH ever reaches the deployed `CauldronVault`**.

`CauldronVault.redeem` (`CauldronVault.sol:94-112`) computes
`amount = balance/outstanding`; since balance is permanently 0, `amount == 0`
and the function explicitly reverts `UnifiedFloorActive()` rather than the
generic `NothingToRedeem` (`:101-104`) — the contract's own NatSpec documents
this exact state (`CauldronVault.sol:85-93`, "audit L-07").

**Still load-bearing:** `PoolOps.crystallizeCollection` reads
`IVaultRedeemedOps(vault).outstanding()` to size the death-time NFT count
(`PoolOps.sol:1348`, `vault == address(0) ? 0 : ...outstanding()`) — the vault
contract is kept alive purely as a supply counter
(`generationVault[gen] = vlt; // kept for crystallize's supply count (holds no ETH)`,
`CauldronRegistry.sol:1119,1144`). `CauldronVault.close()`
(`CauldronVault.sol:116-125`) is still wired from `PoolOps.sol:998` at
relaunch (`try IVaultCloseOps(oldVault).close() ... catch {}`), best-effort,
sweeping a balance that is always 0 under this config.

**No ETH leaks in anywhere else:** `receive()` (`CauldronVault.sol:72-74`) is
still open to anyone, so a direct `send`/`transfer` to the vault address would
still credit it — but no protocol code path does this; the only wired feeder
(`hook`'s fee router) is disconnected.

`DENOMINATION: ETH-only — CauldronVault.sol:80 (balance/outstanding, raw
address(this).balance)`. Since it is inert under the shipped config this is
not currently a live denomination break, but the contract construction itself
cannot pay in anything but native ETH.

### 2. Ledger crystallization / live redeem — `CollectionLedger` — LIVE

`CollectionLedger.redeem` (`cauldron/CollectionLedger.sol:117-125`) is
`onlyRegistry` (`:77-80`) and IS reached in production:

```
CauldronRegistry.recycleCollectionNFT(gen, tokenId)   (CauldronRegistry.sol:1461-1474)
  -> PoolOps.recycleCollection(...)                    (PoolOps.sol:1356-1374)
    -> ILedgerOps(ledger).redeem(gen, mintedNow)        (PoolOps.sol:1368)
```

and the buy-back leg:

```
CauldronRegistry.buyCollectionNFT(gen, tokenId)        (CauldronRegistry.sol:1479-1491)
  -> PoolOps.buyCollection(...)                         (PoolOps.sol:1379-1397)
    -> ILedgerOps(ledger).buyback(gen, mintedNow, added) (PoolOps.sol:1395)
```

Neither `recycleCollectionNFT` nor `buyCollectionNFT` gates on the collection
being dead — `CollectionLedger`'s NatSpec states redemption works "both before
and after" death, only the `outstanding()` supply source switches
(`CollectionLedger.sol:24-34,86-90`). `crystallize` (`:143-155`) only freezes
`frozenSupply`/`crystallized` at death and optionally folds a final
`extraEntitled` — it does NOT gate `redeem`/`buyback`, confirmed by reading
`redeem`/`buyback` bodies (`:117-137`), which check only `outstanding(gen,...) >
0` / `retired[gen] > 0`, never `crystallized[gen]`.

**Preconditions:** `collectionLedger != address(0)` and
`generationCollection[gen] != address(0)`, else `BadConfig`
(`CauldronRegistry.sol:1466,1483`); redemption-pause circuit breaker checked
only on `recycleCollectionNFT` (`:1464`, `_redeemBlocked()`), NOT on
`buyCollectionNFT`.

**Behavior — `recycleCollectionNFT` → `PoolOps.recycleCollection`
(`PoolOps.sol:1356-1374`):**
1. `require ownerOf(tokenId) == caller`.
2. `mintedNow = collection.totalMinted()` (live read, `:1367`).
3. `payout = ledger.redeem(gen, mintedNow)` — debits `entitledTokens[gen]` by
   `entitledTokens[gen]/outstanding` (round down), `retired[gen] += 1`
   (`CollectionLedger.sol:117-125`).
4. `custodyTransfer(caller, address(this), tokenId)` — NFT to treasury, not
   burned.
5. `claimFromReserve(...)` pulls `payout` from the **current generation's**
   shared reserve (`ReserveRef` built from `generationReservePositionId[g]`
   where `g = currentGeneration`, `CauldronRegistry.sol:1467-1471`) to the
   caller.
6. `amount + CLAIM_DUST < payout` reverts `"reserve short"` — ledger debit and
   NFT move roll back with the pull (`PoolOps.sol:1373`).

**Behavior — `buyCollectionNFT` → `PoolOps.buyCollection`
(`PoolOps.sol:1379-1397`):** `paid = 2 * ledger.floorPerNFT(gen, mintedNow)`;
pulls `paid` tokens from caller; `addToReserve`; `ledger.buyback(gen,
mintedNow, added)` (credits `entitledTokens[gen] += added`, un-retires one
NFT) — floor ratchets up; NFT treasury → buyer.

**Events:** `CollectionRecycled(gen, tokenId, holder, payout)`,
`CollectionBought(gen, tokenId, buyer, paid)` (`CauldronRegistry.sol:1421-1422`);
`CollectionLedger` also emits `Credited`/`Redeemed`/`BoughtBack`/`Crystallized`
(`:61-64`).

**Denomination:** always `generationToken[currentGeneration]`
(`CauldronRegistry.sol:1467,1484` — comment "pay in the LIVE token, from the
shared reserve"), read live, regardless of which (possibly long-dead)
generation `gen` the NFT collection belongs to.
`DENOMINATION: quote-agnostic — CauldronRegistry.sol:1467,1484;
CollectionLedger.sol (entitledTokens is a raw uint256, no asset reference)`.

**Independent corroboration:** `test/functional/F11_FloorsAndRedemption.t.sol`
(header `:9-37`) reaches the identical conclusion by tracing the same call
chain and asserting it at runtime (`test_F11_LedgerFloorIsTheLiveMechanism`,
`:58-96`): mechanism 1 inert (vault balance == 0), mechanism 2 reachable and
token-denominated, mechanism 3 absent from the tree.

### 3. Unified `redeemCreature`/`buyTreasuryCreature` — ABSENT

`grep -rn "redeemCreature\|buyTreasuryCreature"` across `contracts/solidity`
(excluding `out/` build artifacts) returns **zero matches** in any `.sol`
file. `CauldronRegistry.recycleCollectionNFT`/`buyCollectionNFT`
(`:1461-1491`) — the functions the design doc's build-phase notes actually
call "P2" — **are** the unified creature path in substance (NFT → treasury,
live-token floor from the shared reserve, 2× ratchet, mirrors
`redeemOgFren`/`buyTreasuryOgFren`), just under the pre-rename names. No
branch `feat/unified-collection-floor` exists: `git branch -a` lists only
`fix/b01-perp-guild-strand`, `fix/b05-b07-relaunch-totality` (current), `main`
and their `origin/*` mirrors — the branch named in
`COLLECTION_FLOOR_UNIFY.md:3` does not exist, local or remote.

**DELTA:** `COLLECTION_FLOOR_UNIFY.md:3` states `Status: DESIGN (approved to
build, pre-audit)`. The doc's own "P2 status" section (`:138-142`) says P2
("registry entry points `recycleCollectionNFT`/`buyCollectionNFT` ... redeem a
LIVE collection end-to-end") is already done, and code confirms it — this is
live on `main`, not a design/pre-audit branch. The header status line is
stale relative to the code and relative to the doc's own body.

---

## G3 — INVARIANT R (safety core)

Formula, per the doc: `Σ(genesisReserveOutstanding + Σ_gen entitledTokens[gen]
+ migrationOutstanding) ≤ reserve LP token balance`.

**Grep result: `migrationOutstanding` names no variable anywhere in
`contracts/solidity`** (`grep -n "migrationOutstanding"` over `CauldronRegistry.sol`
and `cauldron/*.sol` returns nothing). The general 1:1 holder-migration path
(`claimByBurn`/`claimByBurnUpTo`, `CauldronRegistry.sol:1178,1216`, used by
ordinary holders, `MigrationVesting`, and `PerpEngine`'s inventory sync) has no
tracked outstanding-claims counter. Reserve sizing for it is implicit:
`newActive` at relaunch is set to `tokensFromLP` (recovered from the dying
LP) minus the two EXPLICIT carve-outs below, and the reserve is
"everything else" (comment, `CauldronRegistry.sol:960-966`) — migration
coverage is structural (whatever the dead LP didn't already give back to
migrants during its life), not asserted against a counter.

**Table — every function that changes a term of Invariant R, and whether the
change is checked against reserve balance:**

| Function | Term changed | Direction | On-chain balance check? |
|---|---|---|---|
| `redeemOgFren` (`RedemptionExt.sol:86`) | `genesisReserveOutstanding` | `-= F` | No pre-check; the `claimFromReserve` call it's paired with reverts (`amount+1e12<F`, `:99`) if short — debit + NFT move roll back together |
| `_pullGrow` / `buyTreasuryOgFren`, `donateToReserve` (`RedemptionExt.sol:177`) | `genesisReserveOutstanding` | `+= added` (added = actual `addToReserve` result, not requested) | N/A — a deposit can't over-claim; guarded against zero-add (`NoBalance`, `:176`) |
| `CollectionLedger.redeem` (`CollectionLedger.sol:117-125`) | `entitledTokens[gen]`, `totalEntitled` | `-= payout` | No reserve check inside the ledger (pure accounting, no external calls, `:35-37`); the caller (`PoolOps.recycleCollection`) checks the *paired* `claimFromReserve` result (`PoolOps.sol:1373`) |
| `CollectionLedger.credit` (`:106-111`) | `entitledTokens[gen]`, `totalEntitled` | `+=` | **None.** No check that the credited amount is or will be backed. Called from `PoolOps.doLegacyNote` (`:1296,1298`) only after `materializeLegacy`'s `toReserve` branch has *already* deposited the same amount (`PoolOps.sol:1320-1327`) — backed by construction on that path, but the ledger function itself is unguarded, confirmed live by `test_F11_InvariantRIsEnforcedAtPayoutNotAtCredit` (`F11_FloorsAndRedemption.t.sol:102-115`), which credits `type(uint128).max` with no reserve and no revert. |
| `CollectionLedger.buyback` (`:130-137`) | `entitledTokens[gen]`, `totalEntitled` | `+= paid` | No internal check; caller (`PoolOps.buyCollection`) always deposits `paid` via `addToReserve` **before** calling `buyback` and passes the deposited `added`, not the requested `paid` (`PoolOps.sol:1394-1395`) — backed by construction |
| `CollectionLedger.crystallize` (`:143-155`) | `entitledTokens[gen]`, `totalEntitled` | `+= extraEntitled` | No check; `extraEntitled` comes from `crystallizeCollection`'s `swept*activeBase/totalETH` sizing (`PoolOps.sol:1341`), backed indirectly by the relaunch reserve resize that follows in the same `relaunch()` call (`CauldronRegistry.sol:999-1015`) |
| `PoolOps.claimFromReserve` (`:1132-1161`) | reserve LP balance | `-=` (actual, capped at position liquidity, `:1144-1146`) | Caps itself at what the position holds and **returns short rather than reverting** — the revert-on-short behavior lives entirely in the CALLERS (`redeemOgFren`, `recycleCollection`, `migrateOne`), not here |
| `PoolOps.addToReserve` (`:1172-1200`) | reserve LP balance | `+=` (actual consumed) | Self-consistent; returns 0 rather than pretending to add what it couldn't |

**Conclusion:** Invariant R is **not enforced by any single on-chain assert**
comparing `reserve LP balance` against the sum of all three terms. No
function named `_assertReserveCoversClaims` (or equivalent) exists anywhere in
`contracts/solidity` (`grep -rn "_assertReserveCoversClaims\|assertReserve"`
returns only the design doc and a test comment — no `.sol` implementation). It
holds, where it holds, **by construction on individual call paths**: every
credit-then-reserve pairing in the current code deposits before or atomically
with crediting (`materializeLegacy`'s `toReserve` branch, `buyCollection`'s
deposit-then-buyback ordering), and every payout path (`claimFromReserve`)
reverts its caller on short delivery. The one call that credits WITHOUT a
paired backing check is `CollectionLedger.credit` itself — safe today only
because its sole caller (`doLegacyNote`) is only ever invoked with an amount
that was just, in the same transaction, actually deposited
(`PoolOps.sol:1320-1327`). `test_F11_InvariantRIsEnforcedAtPayoutNotAtCredit`
(`F11_FloorsAndRedemption.t.sol:102-115`) documents this as a deliberate
characterization ("R is a payout-time property"), and `LedgerInvariants.t.sol`
fuzzes only the ledger's *internal* bookkeeping closure (`totalEntitled == Σ`,
`:101-105`) — it never touches a real reserve-LP balance, so no test in the
tree exercises the cross-contract inequality either.

The `COLLECTION_FLOOR_UNIFY.md:158` "Fix" bullet (`_assertReserveCoversClaims()`
"asserted on redeem/credit as the safety net") describes exactly the missing
piece: it has not been implemented.

---

## G4 — Fold-forward

**Genesis:** `genesisPending` (accrued OG share of iteration-#2 live buybacks,
`RedemptionExt.sol:153`, `CauldronRegistry.sol:1454`) is folded into
`genesisReserveOutstanding` at the START of every `relaunch()`
(`CauldronRegistry.sol:970-971`: `genesisReserveOutstanding += genesisPending;
genesisPending = 0;`), and that combined scalar (`unclaimedGenesis`) is
subtracted from `newActive` before the new reserve is sized
(`:972-987`) — so genesis re-expresses fully in the new token every relaunch.
`claimByBurn` (`CauldronRegistry.sol:1178`) is the **general** 1:1
old-token-burn / new-token-claim primitive for ordinary holders (and
`MigrationVesting`, `PerpEngine`) — it is not genesis-specific, despite the
prompt's framing; genesis's own fold-forward mechanism is the
`genesisPending`/`genesisReserveOutstanding` pair above.

**Creatures:** yes, they fold forward too, by the same relaunch step. At
`relaunch()`:
1. `_flushLegacyAtRelaunch(oldGen, oldToken)` (`CauldronRegistry.sol:1447-1455`)
   sweeps the dying generation's un-materialized `legacyOwedToReserve` from the
   hook, burns the swept dead-gen tokens, and credits the ledger with the
   **number** via `doLegacyNote` (`PoolOps.materializeLegacy`, `toReserve=false`
   branch, `PoolOps.sol:1323-1327`).
2. `crystallizeCollection` (`PoolOps.sol:1335-1350`) freezes the dying
   collection's NFT count and folds in the final swept-ETH sizing.
3. `uint256 legacy = collectionLedger.totalEntitled();` — the **aggregate**
   across every past collection generation's entitlement, not just the dying
   one — is subtracted from `newActive` (`CauldronRegistry.sol:999-1015`,
   clamped to zero with an `ReserveShortfall` event on shortfall, "audit
   Z-12").
4. `newReserve = TOTAL_SUPPLY - newActive` — the fresh new-generation reserve
   is sized to cover genesis + the FULL cross-generation legacy ledger.

Crucially, `recycleCollectionNFT`/`buyCollectionNFT` always read `g =
currentGeneration` for the `ReserveRef` (`CauldronRegistry.sol:1467,1484`) —
an NFT from generation 1's collection redeems against generation N's reserve
position, in generation N's token, years after generation 1 died. No gap: no
`claimByBurn`-equivalent is needed for creatures because the ledger's
`entitledTokens[gen]` is a pure number keyed to the collection, never to an
asset, and the reserve it draws against is always "whichever position is
current."

---

## DENOMINATION SPINE

1. **What asset does each redeem path pay in — live or captured at credit
   time?** All three redemption paths (`redeemOgFren`, `recycleCollectionNFT`,
   and the inert `CauldronVault.redeem`) read `generationToken[currentGeneration]`
   / `address(this).balance` **live** at call time
   (`RedemptionExt.sol:89`; `CauldronRegistry.sol:1467`; `CauldronVault.sol:80`
   respectively). Nothing captures an asset reference at credit time — credits
   (`CollectionLedger.credit`/`buyback`, `genesisReserveOutstanding +=`) store
   only raw `uint256` amounts, never a token address.

2. **Does the 2× ratchet work in a non-ETH asset? With 6 decimals?** The
   ratchet operates entirely on `generationToken[gen]` (`cauldron/CauldronToken.sol:26`,
   plain `ERC20` with no `decimals()` override → 18 decimals, confirmed by
   grep — no override found), never on the QUOTE asset. `ReserveLib.sol`'s
   liquidity math (`liquidityForTokenOut`/`tokenOutForLiquidity`,
   `ReserveLib.sol:75-106`) operates on raw `currency1` amounts and never reads
   or assumes any decimals value. So the ratchet is unaffected by the quote's
   decimals (e.g. a 6-decimal USDG quote after rotation) — the floor is always
   denominated in the protocol's own 18-decimal iteration token, not the quote.
   `DENOMINATION: quote-agnostic — ReserveLib.sol:75-106; CauldronToken.sol:26`.

3. **Is `CauldronVault` (ETH-only by construction) live for creatures?** No —
   see G2 §1: deployed on every brew but neutered via `hook.setVault(address(0))`
   at both collection-deploy call sites (`CauldronRegistry.sol:1124,1148`); its
   `redeem()` reverts `UnifiedFloorActive()` unconditionally under the shipped
   config (`CauldronVault.sol:85-104`). Not a live denomination break today,
   but the contract itself remains hard-wired ETH-only
   (`DENOMINATION: ETH-only — CauldronVault.sol:80`) and would reintroduce one
   the moment anything re-wires `hook.setVault` to a non-zero address.

4. **After a rotation, is a floor credited PRE-rotation still redeemable, and
   in which asset?** Yes, in the NEW (post-rotation) quote's paired token
   position — but the floor entitlement itself is unaffected by a QUOTE
   rotation, because `rotateSlice`/`rotateSliceFrom` (`RedemptionExt.sol:255-454`)
   only moves the ACTIVE liquidity leg (`generationPositionId`/
   `generationLegs`) between quote pairs; it never touches
   `generationReservePositionId[gen]` (the reserve the floors draw from) or
   `genesisReserveOutstanding`/`CollectionLedger.entitledTokens`. A completed
   rotation flips `generationQuote[gen]` (`RedemptionExt.sol:413`,
   `CauldronRegistry.sol:951` for the write at summon/relaunch) — the pair the
   ACTIVE pool trades against — but the floor is still paid in
   `generationToken[gen]` itself (the iteration token, unaffected by which
   quote it's paired with). So: still redeemable, still in the (unchanged)
   iteration token, regardless of quote rotation.
   `DENOMINATION: quote-agnostic — RedemptionExt.sol:89,promoted via CauldronBase.sol:332 generationQuote only gates the ACTIVE pair, not the reserve`.

---

## Open deltas

1. **Doc status is stale.** `COLLECTION_FLOOR_UNIFY.md:3` claims `Status:
   DESIGN (approved to build, pre-audit) · branch feat/unified-collection-floor`.
   That branch does not exist (`git branch -a`, checked both local and
   `origin/*`). The functionality the doc calls "P2" — live creature
   redemption via `recycleCollectionNFT`/`buyCollectionNFT` — is merged on
   `main` today, not gated behind a design branch.

2. **Naming mismatch.** `redeemCreature`/`buyTreasuryCreature` (the names the
   doc's change-list, `COLLECTION_FLOOR_UNIFY.md:83-84`, says to add) do not
   exist. `recycleCollectionNFT`/`buyCollectionNFT` are the actual, already-live
   unified path (G2 §2) under the pre-rename name. An auditor or indexer
   grepping for the doc's proposed names will conclude the feature is
   unbuilt; it is not.

3. **`CollectionLedger.credit` has no reserve-backing check of its own** — it
   is safe only because every current caller happens to deposit first. A
   future caller of `credit` that does not maintain that discipline breaks
   Invariant R with no on-chain guard to catch it. Confirmed empirically by
   `test_F11_InvariantRIsEnforcedAtPayoutNotAtCredit`
   (`F11_FloorsAndRedemption.t.sol:102-115`), which credits
   `type(uint128).max` successfully with zero reserve backing.

4. **No tracked `migrationOutstanding` term.** The third term of the doc's own
   Invariant R formula (`COLLECTION_FLOOR_UNIFY.md:45-46`) names no on-chain
   variable (`grep -n "migrationOutstanding"` — zero hits in `.sol`). Migration
   coverage in the relaunch reserve-sizing math is structural
   (`CauldronRegistry.sol:960-987`), not asserted against a counter, so the
   doc's formula cannot be checked as written even in principle without first
   defining what `migrationOutstanding` would read.

5. **No on-chain `_assertReserveCoversClaims` exists anywhere** — the
   doc's own proposed fix (`COLLECTION_FLOOR_UNIFY.md:158-159`) for the
   solvency gap it identifies has not been implemented. Invariant R currently
   holds (where it holds) only by the per-path construction documented in the
   G3 table above, verified only by unit/invariant tests that never touch a
   real reserve-LP balance (`LedgerInvariants.t.sol`) — not by any runtime
   check comparing the reserve's actual balance to outstanding claims.

6. **`CauldronVault` is fully deprecated-present, not merely "legacy code
   nobody runs."** It is deployed fresh on every single brew
   (`CauldronFactory.sol:75-76`, `CauldronRegistry.sol:1142`) purely to serve
   as a NFT-count oracle for `crystallizeCollection` (`PoolOps.sol:1348`). A
   full removal (as `COLLECTION_FLOOR_UNIFY.md`'s "Contract change list" item
   1 proposes) requires first replacing that sizing input, not just deleting
   the deploy calls.
