# 08 — The NFT economy

Sources: `contracts/solidity/cauldron/CauldronCollection.sol`,
`CollectionLedger.sol`, `CauldronGachaRouter.sol`, `MiFrensDividend.sol`,
`MintCurvePolicy.sol`, `ICreatorToken.sol`, `CauldronVault.sol`, and the gacha half
of `contracts/solidity/CauldronHook.sol`.

Every mechanism carries the source line it was read from.

---

## 1. The pieces

| contract | role |
|---|---|
| `CauldronCollection` | the per-generation ERC-721. Two disjoint id ranges: art and Liquidatoor badges. |
| `CauldronHook` (gacha half) | holds the mint credit, the curve, the crystal queue and the odds. It is the collection's `minter`. |
| `CauldronGachaRouter` | the user-facing entrypoint: swap, earn credit, open crystals, all in one transaction. |
| `MintCurvePolicy` | an optional pluggable replacement for the linear mint curve. |
| `MiFrensDividend` | the genesis holders' fee dividend — native accumulator plus a bounded ERC20 basket. |
| `CauldronVault` | the ETH floor vault. Deployed, but not funded under the shipped configuration. |
| `CollectionLedger` | the live, token-denominated floor: per-generation entitlement and redemption accounting. |

---

## 2. The collection

`cauldron/CauldronCollection.sol`. An `ERC721` + `ERC2981` + `ICreatorToken`.

### Id ranges and supply

| range | ids | minted by | cap |
|---|---|---|---|
| art | `1 … maxSupply` | `minter` only (`:208`), `tokenId = ++totalMinted` (`:210`) | `totalMinted >= maxSupply` reverts `MintedOut` (`:209`) |
| Liquidatoor badges | `LIQUIDATOR_ID_BASE + n` | `liquidatorMinter` only (`:350`), `tokenId = 1_000_000 + ++liquidatorMinted` (`:351`) | **uncapped** |

`LIQUIDATOR_ID_BASE = 1_000_000` (`:74`). The constructor refuses
`maxSupply_ >= LIQUIDATOR_ID_BASE` (`:148`), so the two ranges can never collide.
`maxSupply` is `immutable` (`:54`, set `:158`).

There is **no public mint and no owner mint** anywhere in the file.

### Authority

| role | set | may do |
|---|---|---|
| `minter` | immutable, constructor (`:155`) | `mint(address)` (`:207`), `setLiquidatorMinter` (`:307`) |
| `deployer` | immutable, the **registry** (`:156`) | `setTransferValidator` (`:193`), `setMetadata` (`:317`), `setRarityOdds` (`:427`), `setLiquidatorURI` (`:329`), `setLiquidatorMinter` (`:307`), `setVault` (`:287`), `setRoyalty` (`:297`), `setLiquidatorRenderer` (`:374`), `custodyTransfer` (`:395`) |
| `configurator` | immutable, the **factory** (`:157`) | `setVault` (`:287`), `setRoyalty` (`:297`), `setLiquidatorRenderer` (`:374`) |
| `vault` | one-shot; a second `setVault` reverts `VaultSet` (`:288`) | `burnFromVault` (`:385`) |

Royalty is capped at 1,000 bps (10%) in both the constructor (`:154`) and the setter
(`:298`).

`setRarityOdds` (`:427`) can only be called while `totalMinted == 0` (`:428`) and
requires `cum[3] == 10_000` with a monotone table (`:429`).

### Transfer validation

`_update` is overridden (`:169-179`): if `transferValidator` is non-zero, every
transfer, mint and burn calls
`ITransferValidator.validateTransfer(caller, from, to, tokenId)` (`:176`). This is
the Limit Break creator-token hook. `transferValidator` is settable by the registry
at any time (`:192-196`), so the collection is **not** transfer-unconditional: a
validator can block transfers.

---

## 3. Rarity: committed at mint, rolled at reveal

**What it does.** It gives each art token a tier `0..3` from a seed that did not
exist when the token was minted.

| step | line | detail |
|---|---:|---|
| mint | 212 | stores `mintBlockOf[tokenId] = uint48(block.number)`. **No rarity is written.** `Minted(to, tokenId, 0)` is emitted with a provisional 0 (`:214`). |
| reveal | 219 / 239 | `reveal(tokenId)` or `revealBatch(uint256[])`, bounded at 50 ids (`:243`) |
| owner check | 248 | `ownerOf(tokenId) != msg.sender` reverts. **Only the current owner can reveal.** |
| maturity | 251 | `block.number <= mb` reverts `NotReady` |
| roll | 269 | `rarity = _rollRarity(keccak256(blockhash(mb), tokenId, address(this)))` |
| bucket | 276-282 | `r = seed % 10_000`; first `rarityCumBps[i]` that `r` falls under |

Default odds table, `rarityCumBps = [7900, 9400, 9900, 10000]` (`:101`) — cumulative
basis points:

| tier | cumulative bps | probability | units |
|---:|---:|---:|---|
| 0 | 7,900 | 79.00% | bps of 10,000 |
| 1 | 9,400 | 15.00% | bps |
| 2 | 9,900 | 5.00% | bps |
| 3 | 10,000 | 1.00% | bps |

The code names no tiers; the tier names Common/Rare/Epic/Ultra appear only in a
comment (`:99`).

### Expired seeds, and what that means for grinding

`blockhash` reaches back only ~256 blocks. When the seed has expired, `_reveal`
**does not revert** — it re-anchors to a fresh future block and returns quietly:

```
if (bh == 0) {
    mintBlockOf[tokenId] = uint48(block.number);      // :265
    emit ReAnchored(tokenId, uint48(block.number));
    return;
}
```

The code's stated reasoning (`:253-263`) is that the alternative — a deterministic
fallback seed — would have handed the holder a second, *fully predictable* draw
computable at mint time, letting them take the better of two; re-anchoring keeps
"exactly ONE unknowable draw".

**Stated honestly, the property that remains:** the current draw *is* computable
off-chain for the 256 blocks in which `blockhash(mb)` is available, and only the
owner may call `reveal` (`:248`). A holder who computes an unfavourable tier can
simply not reveal, wait out the 256-block window, and re-anchor to a fresh seed.
The cost of one re-roll is ~256 blocks of patience plus one transaction. The design
prevents *knowing two draws at once*; it does not prevent *sequential re-rolling*.

---

## 4. Mint credit and the curve

**What it does.** Swap volume becomes credit; credit buys positions on a rising
curve; each position is a crystal.

### Accrual

Inside `_afterSwap` (see `06-HOOK.md` §5, steps 10-14):

```
weighted = absVolume * (isBuy ? buyWeightBps : sellWeightBps) / BPS;   // CauldronHook.sol:889
nftCredit[creditEpoch][player] += weighted;   // saturating            // :892-895
```

| parameter | default | units | line | ceiling |
|---|---|---|---:|---|
| `buyWeightBps` | 15,000 (1.5×) | bps | 423 | `MAX_WEIGHT_BPS = 30_000` (425) |
| `sellWeightBps` | 5,000 (0.5×) | bps | 424 | same |
| `creditUntaggedSwaps` | `true` | — | 430 | — |

`absVolume` is in the volume ledger's unit: **raw quote units** with no oracle,
**USD at 1e18** with one (`06-HOOK.md` §8). All three credit adds saturate at
`type(uint256).max` rather than wrapping (`:892-902`).

`creditEpoch` (`:368`) is bumped on every `setCollection` (`:1977`), which
namespaces credit per generation — old credit is not spendable against a new brew.

### The curve

```
nftPriceAt(k) = volumePerNFT + k * nftPriceStep                        // :2110
```

with a pluggable `ICurvePolicy` tried first and used only if it returns non-zero,
falling back on any revert (`:2102-2110`).

| parameter | default | units | line |
|---|---|---|---:|
| `volumePerNFT` | `0.02 ether` (2e16) | same unit as credit | 374 |
| `nftPriceStep` | `0.00002 ether` (2e13) | same unit, per position | 375 |
| `MAX_MINTS_PER_CALL` | 30 | count | 389 |

`k` is the **curve position**, not the tokenId:

```
_curvePos() = collection.totalMinted() + outstandingOf[collection] - mintBaseline;  // :2122-2124
```

`mintBaseline` (`:383`) is the collection's `totalMinted` at the moment it was wired
to the hook. A brew that *continues* an existing collection therefore starts its
volume mints at curve position 0, not at the collection's absolute supply.

Note that `_curvePos` **includes** unresolved crystals (`outstandingOf`), so the
price rises the moment a crystal is committed, not when it resolves.

### `MintCurvePolicy` — the pluggable alternative

`cauldron/MintCurvePolicy.sol`, a hyperbolic curve:

```
priceAt(k) = base + (spread * k * k) / (k + knee)                      // :99
```

`base`, `spread`, `knee`, `supply` are all `immutable` (`:61-67`) and the
constructor rejects a zero `base`, `knee`, `supply` (`:75`) or `spread` (`:82`).
`totalToMintOut()` (`:108-113`) loops `supply` times summing the curve — a view, not
for on-chain use at scale. The contract is explicitly unit-agnostic: it performs no
scaling.

---

## 5. The gacha

**What it does.** Spending credit does not mint an NFT. It enqueues a **ticket**
whose creature-or-nothing outcome is rolled later, from a block hash that did not
exist when the ticket was bought.

### Commit

`_commitCrystals` (`CauldronHook.sol:2227-2276`):

| step | line | detail |
|---|---:|---|
| room | 2238 | `room = maxSupply - totalMinted - outstandingOf[col]`, saturating at 0 — **unresolved tickets are reserved supply** |
| sold out | 2239 | returns `0`, never reverts |
| start | 2244 | `startPos = minted + reserved - mintBaseline` |
| spend | 2248-2253 | walk `nftPriceAt(startPos + n)` greedily until the next position is unaffordable or `MAX_MINTS_PER_CALL` is hit |
| debit | 2260-2264 | `nftCredit` debited; `committedOf`, `pendingOf`, `outstandingCrystals`, `outstandingOf[col]` all incremented |
| odds | 2266 | `oddsBps = uint16(oddsForPlay(playWei))` — **fixed at commit** |
| enqueue | 2267-2274 | `batches.push(Batch{player, collection, commitBlock: uint48(block.number), oddsBps, count, resolved: 0})` |

The batch stores the **collection address** (`:2269`), so tickets survive a
relaunch and mint into the collection they were bought against.

`commitCrystals` (`:2207`) is gated on `isOpener[msg.sender]` (`:2212`) so the odds
always use a router's honest on-chain play size.

### Odds

`oddsForPlay` (`CauldronHook.sol:2151-2162`):

```
if (oddsFullVolumeWei == 0) return maxOddsBps;                          // :2159
bps = playWei * maxOddsBps / oddsFullVolumeWei;                         // :2160
if (bps > maxOddsBps) bps = maxOddsBps;                                 // :2161
```

A pluggable `IOddsPolicy` is tried first and clamped to `ODDS_HARD_CAP_BPS`
(`:2156`).

| parameter | default | units | line | ceiling |
|---|---|---|---:|---|
| `maxOddsBps` | 9,000 (90%) | bps | 436 | `ODDS_HARD_CAP_BPS = 9_500` (437), enforced 2418 |
| `oddsFullVolumeWei` | `0.5 ether` (5e17) | **same unit as credit** — wei by default, USD-1e18 once an oracle is wired | 435 | — |
| `pityThreshold` | 8 | consecutive misses | 438 | — |
| `NATIVE_COMMIT_MAX` | 4 | crystals per untagged swap | 173 | — |
| `NATIVE_RESOLVE_MAX` | 6 | tickets resolved per untagged swap | 174 | — |

Size never reaches 100% on its own — only the pity counter guarantees a creature
(`:432-434`).

### Resolve

`_resolveTickets` (`CauldronHook.sol:2299-2353`) is FIFO over `batches[batchCursor…]`:

| step | line | detail |
|---|---:|---|
| not yet seeded | 2307 | `block.number <= b.commitBlock` ⇒ **break**, resume next call |
| expired seed | 2316-2318 | `blockhash(commitBlock) == 0` ⇒ re-anchor `commitBlock = block.number` and **break** |
| roll | 2330 | `roll = keccak256(bh, player, batchIndex, ticketIndex) % 10_000` |
| pity | 2331 | `forced = missStreak[player] >= pityThreshold` |
| win | 2332 | `(forced \|\| roll < oddsBps) && minted < max` |
| counters | 2334-2336 | `pendingOf`, `outstandingCrystals`, `outstandingOf[col]` each decremented |
| on win | 2338-2342 | `missStreak = 0`; `opened[player] += 1`; `collection.mint(player)` |
| on miss | 2344 | `missStreak += 1` **only if** `roll >= odds && minted < max` |
| batch done | 2350 | `batchCursor` advances only when a batch is fully resolved; otherwise **break** |

Consequences worth stating:

- **A sold-out collection resolves remaining tickets as misses**, and those misses
  do **not** build the pity counter (`:2332`, `:2344`). The credit is spent and
  nothing is minted. The design justification given is that the swap fee that earned
  the credit already lifted the floor (`:2284-2285`).
- **Resolution is permissionless** (`resolveTickets`, `:2287`) and the router calls
  it on every play (`CauldronGachaRouter.sol:327`, `:361`, `:388`). A player cannot
  resolve only their own batch — the queue is strictly FIFO.
- **A stale head blocks the queue.** An expired-seed batch re-anchors and `break`s
  (`:2318`), so nothing behind it resolves until that batch matures again.
- **`mintedOut()` and the reservation counter disagree.** `mintedOut` compares
  `totalMinted` against `maxSupply` and ignores `outstandingOf` (`:2170-2174`), while
  `_commitCrystals` (`:2238`) and `_curvePos` (`:2122`) both include it. `mintedOut`
  can therefore read `false` while every remaining slot is already spoken for.

### Entropy, stated honestly

The seed is `blockhash(b.commitBlock)`, mixed with the player address, the batch
index and the ticket index (`:2330`).

- **Unknowable at commit.** The commit block's hash does not exist when the batch is
  pushed, so the outcome cannot be foreseen, and a reverting transaction cannot
  re-roll it.
- **The block proposer of the commit block chooses that hash** and can therefore
  influence every ticket seeded by it. This is the standard blockhash-lottery
  caveat and it applies here.
- **One seed, one batch.** All tickets in a batch share `bh`, differentiated only by
  the ticket index. A re-anchor re-rolls the whole remaining batch at once.
- **Deliberate stalling is weak but not impossible.** Because resolution is
  permissionless and the router fires it on every play, a player cannot reliably
  keep their own batch unresolved for 256 blocks in a busy market — but in a quiet
  one, a batch that nobody resolves will re-anchor and get a fresh seed.
- `block.prevrandao` is **not** used in the gacha roll. It appears only in the
  anti-sniper surtax (`cauldron/SurtaxLib.sol:99`).

---

## 6. The gacha router

`cauldron/CauldronGachaRouter.sol`. Owns the pool-manager `unlock` and drives swaps
so a player earns credit and opens crystals in one transaction.

| constant | value | line |
|---|---|---:|
| `POOL_FEE` | 0 | 66 |
| `TICK_SPACING` | 200 | 67 |
| `MAX_MINTS_PER_CALL` | 30 | 68 |
| `MAX_LOOPS` | 10 | 69 |

The pool key is derived per call from the registry
(`_quote()` → `generationQuote(currentGeneration)` at `:204`; `_key()` at `:215-222`),
with the **quote assigned to `currency0` by role, never by address comparison**
(`:216-217`).

### Entrypoints

| function | line | what it does |
|---|---:|---|
| `play` / `playLiq` | 233 / 248 | buy leg and/or sell leg, then commit and resolve. `playLiq` additionally passes perp liquidation hints in `hookData` (`:408`). |
| `openReady` | 345 | no swap — opens crystals already earned. Converts credit back to a play size: `playWei = creditToOpen * 10_000 / buyWeightBps` (`:353`), and deliberately skips the oracle conversion because `costOfNextCrystals` is already in curve units. |
| `playChurn` | 368 | buy-then-sell up to `loops` times against the same pool to manufacture volume, then commit. |

### Denomination handling

`_pullQuote` (`:271-278`) enforces the native/ERC20 distinction strictly: a native
quote requires `quoteIn == 0` and uses `msg.value` (`:272-273`), an ERC20 quote
requires `msg.value == 0` and pulls `quoteIn` (`:275-276`).

`_playInCurveUnits` (`:136-145`) converts the traded notional into the hook's curve
unit: `playWei * usdPerRawUnit(quote) / 1e18`. With no oracle, or a zero factor, or
a revert, it returns `playWei` unchanged (`:138`, `:140`, `:143`) — correct only
while the hook's curve is denominated in the quote's own raw units.

### Refunds — the two fixes landed today

Both `04607bf` and `381b2a1` fixed the same class of bug in `_churn`: an exact-input
swap whose price limit is the extreme tick is **not guaranteed to consume its whole
input** — on a thin pool it runs to liquidity exhaustion.

```
ethBal -= inE;      // :490   was: ethBal = 0
tokBal -= inG;      // :508   was: tokBal = 0
```

Zeroing dropped the remainder from the returned leftover entirely, so `playChurn`
refunded nothing and the quote sat in the router with **no exit at all on an ERC20
generation** (`:477-488`). The sell-side fix is the mirror: unsold creature tokens
were dropped from the sweep at `:513` and never reached the player (`:503-506`).

The checked arithmetic is itself the guard — a pool reporting it consumed more than
it was offered reverts (`:487-488`).

The `play` path already had the equivalent refunds: unconsumed token at `:330-331`
and `quoteOut = sellEthGross + (spend - ethConsumed)` at `:337-338`.

### Slippage

`play` checks the token output against `minTokenOut` **inside** the unlock (`:427`)
and the sell proceeds against `minQuoteOut` **outside** it, only when a sell leg ran
(`:318`). `playChurn` has **no slippage parameter at all** — its price limits are the
extreme ticks (`_limit`, `:517-519`).

---

## 7. Dividends — `MiFrensDividend`

**What it does.** It streams a permanent slice of every generation's fees to the
genesis MiFrens holders. It is not repointed per brew.

### Shares and eligibility

| field | meaning | line |
|---|---|---:|
| `SHARES` | `mifrens.GENESIS_SUPPLY()`, immutable | 51, set 180 |
| `MAX_TOKEN` | `max(MAX_SUPPLY, GENESIS_SUPPLY)` — the eligibility cap | 58, set 182 |
| `ACC` | `1e18` — the accumulator scale | 43 |
| `activeShares` | count of currently **enchanted** tokens | 73 |

### Enchantment — you must opt in to earn

`castSpell(tokenId)` / `castMany` (`:375` / `:380`) → `_castSpell` (`:385-439`):

- owner-only (`:387`), idempotent (`:389`);
- a fresh join collects the enchant fee (`:396`) and increments `activeShares`
  (`:397`);
- markers are set to the **current** accumulators (`:403`, `:435`), so joining earns
  nothing retroactively;
- a re-cast by a new owner banks the previous caster's accrual into `owed` /
  `owedAsset` (`:401`, `:433`).

`onMiFrenTransfer` (`:464-497`) is collection-only (`:465`). It settles the leaver
(`:468`, `:488`), decrements `activeShares` (`:493`) and clears the enchantment
(`:494`). A buyer earns nothing until they cast.

**Enchant fee** (`_collectEnchantFee`, `:445-458`): free for an original OG that has
never moved (`:449`). Otherwise `reg.enchantFee()` (`:450`) denominated in
`reg.currentToken()` (`:452`), pulled from the caster and donated to the reserve
(`:455-457`). A zero registry, zero fee or zero token all short-circuit to free.

### The native accumulator

`receive()` (`:235-249`):

```
totalDeposited += msg.value;
amt = msg.value + residual;
if (activeShares == 0) { residual = 0; forward `amt` to treasury; return; }   // :238-244
inc = amt * ACC / activeShares;  accPerShare += inc;                          // :245-246
residual = amt - (inc * activeShares) / ACC;                                  // :247
```

Two things to note: with **zero enchanted frens the whole deposit goes to the
treasury** (`:240`), and if the treasury rejects it the amount is held in `residual`
and retried on the next deposit (`:241`). `residual` is the only place in the
contract where a rounding remainder is preserved.

### The ERC20 basket

| field | line | note |
|---|---:|---|
| `accPerShareOf[asset]` | 101 | raw units of that asset × `ACC` — **no decimals normalisation**, which is what keeps a 6-decimal and an 18-decimal asset independent |
| `assets[]` | 122 | append-only; **no removal path** |
| `MAX_ASSETS` | 124 | **3** |
| `funder` | 146 | one-shot (`:201`); the only address allowed to call `fundToken` |

`fundToken` (`:273-289`) is `funder`-only (`:278`) and **reverts `NotEnchanted` when
`activeShares == 0`** (`:280`). The deposit is refused, not banked. This is the
mechanism by which `FeeRouteLib._fundGuild` can fail on the ERC20 leg — see
`07-FEES.md` leg 4; the native `receive()` path can never fail this way.

The bound of 3 is argued from measurement (`:108-121`): the asset list is also
walked by `onMiFrenTransfer`, which runs inside the collection's `_update` under a
fixed forwarded gas budget, and a settle costs ~33k per asset carrying a balance.
The live manifest has two non-ETH quotes (USDG, xNVDA); native ETH is not in this
list at all.

The gate exists because the list is bounded with no removal: an ungated `fundToken`
let anyone close the basket permanently with junk tokens, and one token that stops
transferring bricked `claimTokens` for every holder and every asset at once
(`:137-145`).

### Claim paths

| path | line | who | pays | double-claim prevention |
|---|---:|---|---|---|
| `claim` / `claimMany` | 502 / 507 | owner **and** current caster (`:531`, `:532`) | native `(accPerShare − debtOf[id]) / ACC` (`:534`) | marker advanced at `:535` **before** the send; `nonReentrant` |
| `claimTokens` | 307 | owner **and** current caster (`:308`, `:309`) | every basket asset (`:321`) | per-asset marker advanced at `:323` before the push; a failed push banks to `owedAsset` (`:326`) rather than replaying |
| `withdrawOwed` | 518 | any address with a banked balance | native `owed[msg.sender]` | zeroed at `:521` before the send; a revert restores it |
| `withdrawOwedToken` | 333 | any address with a banked balance | `owedAsset[msg.sender][asset]` | zeroed at `:336` before the push; a revert restores it |

The native claim **reverts** on a failed send (`:539`); the token claim **banks**
instead (`:326`). The asymmetry is deliberate: a failing ERC20 must not be able to
brick a multi-asset loop.

All divisions truncate; the dust stays in the accumulator.

---

## 8. Floors and redemption

There are two floor mechanisms in the tree. Only one is funded.

### `CauldronVault` — the ETH floor, deployed but not funded

`cauldron/CauldronVault.sol`.

```
outstanding()  = max(totalMinted - floorOffset, 0) - redeemed        // :55-59
floorPerNFT()  = address(this).balance / outstanding()               // :77-81
redeem(id)     → burn the NFT, pay balance/outstanding               // :94-112
close()        → registry-only; sweep the balance, stop redemption   // :116-125
```

`floorOffset` (`:47`) excludes a genesis tranche that has its own floor.

**Under the shipped configuration this vault never receives ETH.** Both
collection-deployment paths call `hook.setVault(address(0))`
(`CauldronRegistry.sol:1171`, `:1195`), so the fee floor-share becomes token buy
pressure through the legacy buffer instead (`07-FEES.md` §3 step 4). `redeem`
therefore reverts with an explicit `UnifiedFloorActive()` (`CauldronVault.sol:102`)
rather than a bare `NothingToRedeem`, pointing the holder at the live path. The
vault remains load-bearing as a supply oracle: `crystallizeCollection` reads
`outstanding()` to size the entitlement at death (`:92-93`).

### `CollectionLedger` — the live, token-denominated floor

`cauldron/CollectionLedger.sol`. Registry-only on every mutator (`:77-80`).

| field | meaning | units | line |
|---|---|---|---:|
| `entitledTokens[gen]` | the generation's pot | **raw units of the live iteration token** | 45 |
| `retired[gen]` | NFTs that have drawn their floor | count | 48 |
| `frozenSupply[gen]` | supply snapshot at death | count | 52 |
| `crystallized[gen]` | whether the supply is frozen | bool | 55 |
| `totalEntitled` | `Σ entitledTokens[gen]` | token units | 59 |

```
outstanding(gen, mintedNow) = (crystallized ? frozenSupply : mintedNow) - retired   // :86-90
floorPerNFT(gen, mintedNow) = entitledTokens[gen] / outstanding                      // :94-98
```

| mutator | line | effect |
|---|---:|---|
| `credit(gen, tokens)` | 106 | `entitledTokens += tokens`, `totalEntitled += tokens` |
| `redeem(gen, mintedNow)` | 117 | `payout = entitledTokens / outstanding` **rounded down** (`:120`); debits the pot and `totalEntitled`; `retired += 1` |
| `buyback(gen, mintedNow, paid)` | 130 | the inverse: `entitledTokens += paid`, `retired -= 1`; reverts `NothingRetired` if none are out (`:132`) |
| `crystallize(gen, mintedAtDeath, extra)` | 143 | one-shot (`:147`); freezes the supply term (`:148-149`) and optionally adds a final entitlement |

**Denomination warning.** `entitledTokens` is a *number* of the live token. It
survives a generation change unchanged, so its real value changes when the token
does. The ledger holds no oracle and performs no conversion.

**Registry entrypoints** (out of scope — see the registry doc):

| function | line | what it does |
|---|---:|---|
| `recycleCollectionNFT(gen, tokenId)` | `CauldronRegistry.sol:1496` | pays the ledger floor **in the live token, from the shared reserve**, and moves the NFT to the treasury — **not burned** (`:1492-1495`) |
| `buyCollectionNFT(gen, tokenId)` | `CauldronRegistry.sol:1517` | resells a treasury-held NFT at 2× its floor; the payment goes into the reserve and ratchets the floor for everyone else (`:1514-1516`) |
| `materializeLegacyReserve()` | `cauldron/RedemptionExt.sol:147` | the keeper pull that sweeps the hook's `legacyOwedToReserve` tokens into the reserve and credits the ledger in one step |

---

## 9. Supply conservation

### `CauldronCollection`

| direction | line | bound |
|---|---:|---|
| art mint | 213 | `tokenId = ++totalMinted` (`:210`), guarded by `totalMinted >= maxSupply` (`:209`), `minter` only (`:208`) |
| badge mint | 356 | `tokenId = 1_000_000 + ++liquidatorMinted` (`:351`), **uncapped**, `liquidatorMinter` only (`:350`) |
| burn | 386 | `burnFromVault`, **vault only** (`:385`) |
| custody move | 396 | `custodyTransfer`, registry only (`:395`) — moves without burning |

`totalMinted` and `liquidatorMinted` are **never decremented**. A burn removes a
token without freeing its id, so ids stay unique and monotonic. The constructor's
`maxSupply_ >= LIQUIDATOR_ID_BASE` check (`:148`) is what keeps the two ranges
disjoint.

### The hook's reservation counters

The cap that actually governs the gacha is enforced on the hook side:

```
room = maxSupply - totalMinted - outstandingOf[col]                  // CauldronHook.sol:2238
```

so committed-but-unresolved crystals cannot oversubscribe `maxSupply`. The three
counters move in lockstep: `+` at commit (`:2261-2264`), `−` at resolve
(`:2334-2336`), keyed by the **batch's stored collection** so a relaunch does not
mix them. `outstandingCrystals` (`:409`) is the global sum and is what the public
`outstandingTickets()` getter exposes (`:2165`).

### Ledger entitlement

`totalEntitled` moves in lockstep with `entitledTokens[gen]` on all four mutators
(`:108`/`:109`, `:121`/`:123`, `:133`/`:135`, `:151`/`:152`), so
`totalEntitled == Σ entitledTokens[gen]` holds exactly. Redemption rounds **down**
(`:120`), so the sum can only drift *below* the reserve backing it, never above.

One edge with no recovery path: `crystallize(gen, 0, …)` makes that generation's
`outstanding` zero forever, which strands its pot — `redeem` then reverts
`NothingOutstanding` (`:119`) — without destroying it.

---

## Verification

- Documented against `git rev-parse --short HEAD` = **`20d6de2`**, reading each file
  from the committed tree (`git show 20d6de2:<path>`). At the time of writing the
  working tree had further uncommitted edits in `CauldronHook.sol`,
  `CauldronRegistry.sol`, `cauldron/CauldronGachaRouter.sol`,
  `cauldron/CauldronGovernor.sol`, `cauldron/PerpEngine.sol` and
  `cauldron/RedemptionExt.sol`. **Those are not reflected here**, and they shift line
  numbers. Re-check any citation against `20d6de2`, not against the working tree.

### Behaviour changes reflected here

- `04607bf` and `381b2a1` — `_churn` now **debits what the pool actually took**
  (`CauldronGachaRouter.sol:490`, `:508`) instead of zeroing the balance, so a
  partial fill is refunded (`:513`, and `playChurn`'s `ethLeftover` at `:390`).
- `0dd0c91` — comment-only: `_settleBasket`'s note now says `MAX_ASSETS is 3`,
  matching the constant (`MiFrensDividend.sol:124`).

### Documentation debt

1. **`CauldronCollection.sol:22`** — "There is no admin surface at all after
   construction." The file exposes `setMetadata` (`:317`), `setTransferValidator`
   (`:193`), `setRarityOdds` (`:427`), `setLiquidatorURI` (`:329`),
   `setLiquidatorMinter` (`:307`), `setLiquidatorRenderer` (`:374`), `setVault`
   (`:287`) and `setRoyalty` (`:297`).
2. **`CauldronCollection.sol:17`** — metadata is "immutable at deploy"; `setMetadata`
   (`:317-325`) changes both the mode and its source at any time.
3. **`CauldronCollection.sol:99`** — rarity is "Rolled at mint … and stored". The mint
   stores only the block (`:212`); the tier is written at reveal (`:270`).
4. **`CauldronCollection.sol:292`** — the royalty re-point is described as "(deployer
   only)"; the check at `:297` also accepts the `configurator`.
5. **`CauldronCollection.sol:263`** — after a re-anchor "the holder (or a keeper) calls
   `reveal()` again". `_reveal` rejects any caller who is not the current owner
   (`:248`), so **no keeper can**.
6. **`CauldronGachaRouter.sol:210`** — "The QUOTE is always currency0 … an INVARIANT".
   `_key` (`:217-218`) assigns by role and never compares the two addresses, so the
   property is enforced only by the registry's admission rule, not here.
7. **`CauldronGachaRouter.sol:453`** — the churn path encodes only the player into
   `hookData`, while the play path encodes a second word (`:408`). The two paths hand
   the hook different payload shapes.
8. **`MiFrensDividend.sol:460`** — the transfer hook is described as applying to "an
   enchanted genesis fren"; `onMiFrenTransfer` (`:464`) has no eligibility-cap or id
   check at all. Badge ids and forged ids reach it and return early only because
   `enchantedBy` is zero (`:467`).

### Not verified here

- `MiFrensGenesis` is out of this document's scope; the genesis presale, its refund
  path and its own floor are covered elsewhere.
- The registry-side redemption internals (`PoolOps.recycleCollection`,
  `PoolOps.buyCollection`, `PoolOps.materializeLegacy`) were read only at their call
  sites; their bodies are out of scope.
- Whether any `IOddsPolicy` or `ICurvePolicy` is wired on a live deployment — both
  default to the built-in rules.
- The measured "~33k gas per asset carrying a balance" bound for `MAX_ASSETS` is the
  code's own figure (`MiFrensDividend.sol:113-115`), not re-measured here.
