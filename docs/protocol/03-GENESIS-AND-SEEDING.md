# Cauldron — Genesis and seeding

What this document covers: the presale that funds generation 1, the refund path,
ignition, how a pool is created and which way round its currencies sit, the two
seeding strategies, the optional vesting escrow, and the launch runbook.

---

## 1. The presale — `MiFrensGenesis`

`MiFrensGenesis` is both the founding NFT collection and the fundraise. It is
`ERC721`, `ERC721Votes`, `ERC2981` and an ERC-721C creator token
(`cauldron/MiFrensGenesis.sol:48`).

### Parameters, all immutable, all set at construction

| Parameter | Meaning | Cite |
|---|---|---|
| `GENESIS_SUPPLY` | The OG tranche sold in the presale (ids `1..GENESIS_SUPPLY`) | `MiFrensGenesis.sol:116` |
| `MAX_SUPPLY` | Total art cap including later volume mints | `:117` |
| `PRICE` | ETH per MiFren, exact | `:118` |
| `MAX_PER_WALLET` | Anti-whale cap | `:119` |
| `deployer` | May wire the registry, cancel, and configure metadata. **No funds power.** | `:126` |

Construction rejects a zero genesis supply, price or wallet cap (`:236`), and
requires `genesisSupply_ <= maxSupply_ < LIQUIDATOR_ID_BASE` (`:239`).
`LIQUIDATOR_ID_BASE = 1_000_000` (`:181`) is the base of a separate, uncapped id
range for Liquidatoor badges, so art ids and badge ids can never collide.

### Minting

`mint(quantity)` (`:262`) requires, in order: not finalized (`:263`), not
cancelled (`:264`), `quantity > 0` (`:265`), `minted + quantity <= GENESIS_SUPPLY`
(`:266`), **exact** payment `msg.value == PRICE * quantity` (`:267`), and
`balanceOf(sender) + quantity <= MAX_PER_WALLET` (`:268`).

It records `paid[msg.sender] += msg.value` (`:270`) — this is the exact refundable
amount — and marks each minted id `revealed` immediately (`:278`). The OG tranche
is never a gacha; only the later volume tranche rolls rarity.

### Refunds

`cancelPresale()` (`:289`) is deployer-only (`:290`), only valid pre-finalize
(`:291`), and irreversible (`:292`). It exists because `igniteCauldron` needs a
full sellout — without a cancel, a stalled presale would trap buyer funds.

`refund()` (`:300`) pays back `paid[msg.sender]` in full, zeroing it before the
send (CEI, `:304-306`). Your genesis NFTs are **not** burned; they stay in your
wallet as orphaned art (`:297-299`).

**A cancelled sale can never be ignited.** `igniteCauldron` reverts on `cancelled`
(`:587`). Without that gate, "cancelled AND sold out" is a reachable state —
`cancelPresale` has no sell-out precondition — and the un-refunded pot would have
been forwarded into liquidity while the refund debt survived.

### Ignition

`igniteCauldron()` (`:575`). Gates: registry wired (`:576`), not already finalized
(`:577`), not cancelled (`:587`), `minted >= GENESIS_SUPPLY` (`:588`), and — if a
`finalizer` was set — only that address (`:591`).

It sets `finalized = true`, then forwards the entire balance:
`registry.summon{value: bal}()` (`:593-595`).

The function was renamed from `finalize()`; the storage flag and the `Finalized`
event deliberately keep their old names because the indexer and the `/presale`
endpoint read them (`:571-574`).

---

## 2. Ignition, registry side — `summon()`

`summon()` (`CauldronRegistry.sol:686`) is `payable`, `nonReentrant`, and gated to
`owner()` **or** `igniter` (`:695`). One-shot on `summoned` (`:696`), and it
requires non-zero value (`:697`).

### Why the igniter role exists

An earlier deploy handed registry *ownership* to the presale so that ignition
could reach `summon()`. `MiFrensGenesis` calls exactly one registry function and
exposes no forwarder and no fallback, so that handoff permanently burned every
`onlyOwner` setter — `setGovernor`, `setFactory`, `setSeeder`, `setSeedWindow`,
`setReserveCeiling`, `setCollectionLedger`. Splitting ignition into its own role
(`cauldron/CauldronBase.sol:301-313`, set at `CauldronRegistry.sol:414`) lets
ownership stay with the governance timelock.

The same reasoning disables `renounceOwnership()` outright: it reverts
`RenounceDisabled` (`CauldronBase.sol:446-451`). Ownership is transferable, never
renounceable.

### What summon does with the money

1. Token deployed; full 777,000,000e18 minted to the registry
   (`CauldronRegistry.sol:709`; `CauldronToken.sol:29`, `:46`).
   `generationQuote[1]` stays zero = native ETH, deliberately: generation 1
   launches before any proposal exists to name a quote (`:712-714`).
2. **Genesis bonus** sized, if wired: `pool = TOTAL_SUPPLY * genesisBonusBps /
   10_000`, split into `genesisShares` equal shares
   (`:721-726`). `setGenesisBonus` caps `_bonusBps` at 3000 and must run
   pre-summon (`:625-635`). This is a number, not a transfer — it lives inside
   the reserve position and becomes the OG redemption floor.
3. **Airdrop reserve** carved out, if wired: `setAirdropReserve` caps the amount
   at 2000 bps of total supply and must run pre-summon (`:640-646`). At summon it
   is transferred outright to `airdropWallet` (`:731-734`). This is the only
   tranche that leaves the LP at genesis.
4. `activeTokens = GEN1_ACTIVE_TOKENS` = 80% of supply
   (`CauldronBase.sol:160`); `reserveTokens` is the remainder less the airdrop
   (`:729-734`).
5. Pool created and seeded with the whole `msg.value` (`:742`).
6. **Prime buy**, if pre-funded: `primeBuyEth` is spent on an exact-input market
   buy of the fresh pool, routed to `airdropWallet` (falling back to
   `primeFunder`) (`:750-758`). It runs *after* the reseed so it hits the intended
   starting price. `fundPrimeBuy` / `sweepPrimeBuy` are gated to `primeFunder`
   (`:659`, `:665`), which is itself owner-set pre-summon (`:649`).
7. Genesis NFT collection deployed and the hook pointed at it (`:761`).

---

## 3. Pool creation and orientation

### The invariant: quote is always `currency0`

Uniswap V4 orders a pool's currencies by address. Every liquidity routine in
`PoolOps` is written for exactly one orientation — quote = `currency0`, iteration
token = `currency1`. Native ETH is `address(0)` so it satisfied that for free; an
ERC-20 quote does not.

Rather than write every routine twice, the **token is mined to sort above a fixed
watermark**:

| Constant | Value | Cite |
|---|---|---|
| `QUOTE_WATERMARK` | `0xf000000000000000000000000000000000000000` | `PoolOps.sol:647`, mirrored at `CauldronBase.sol:110` |
| `SALT_TRIES` | 1024 | `PoolOps.sol:620` |

`deployTokenAbove` (`PoolOps.sol:682`) computes the CREATE2 address for salt
`keccak256(gen, i)` and deploys at the first one that sorts above
`max(quote, QUOTE_WATERMARK)` (`:692`, `:701-712`). It asserts the mined address
equals the prediction (`:710`).

Two properties fall out:

- **Adoptability is an invariant, not a hope.** `setAllowedQuote` refuses any
  quote at or above the watermark (`CauldronRegistry.sol:320`), so *any*
  allowlisted quote sorts below *any* token, and any generation can migrate to any
  approved pair forever.
- **It cannot be front-run.** The CREATE2 deployer baked into the address is
  `address(this)` — and because `PoolOps` is delegatecalled, that is the registry
  (`PoolOps.sol:660-669`).
- **It cannot brick.** If no salt in `SALT_TRIES` lands above the quote, it does
  **not** revert: it deploys unmined and reports `address(0)`, so the caller
  launches against ETH (`:715-718`). The registry records what came back, never
  what it asked for (`CauldronRegistry.sol:934`, `:1000`).

Note this is deliberately **not** the public deterministic deployer
(`0x4e59b448…`): the initcode is fully predictable from the winning proposal, so a
permissionless factory would let anyone deploy the address first and make
`relaunch()` revert (`PoolOps.sol:664-669`).

### Pool parameters

| Parameter | Value | Cite |
|---|---|---|
| LP fee | `POOL_FEE = 0` | `CauldronBase.sol:157` |
| Tick spacing | `TICK_SPACING = 200` | `CauldronBase.sol:158` |
| Hooks | the `CauldronHook` | `PoolOps.sol:212-218` |
| Reserve ceiling offset | `RESERVE_CEILING_OFFSET = 42400` (≈69×), per-iteration tunable within `[4000, 138000]` | `CauldronBase.sol:159`; `CauldronRegistry.sol:197-200` |

### The adoption gate

`CauldronHook._afterInitialize` (`CauldronHook.sol:622`) contains
`require(sender == registry)` (`:631`). Any `initialize` on a key naming this hook
from any other sender **reverts**.

This is load-bearing. The next generation's token address is CREATE2-mined from
public inputs, so its `PoolKey` is computable before the token exists, and
`PoolOps._greenCandle` calls `initialize` bare (`PoolOps.sol:467`). Without the
gate, anyone could initialize that key first and make every future `relaunch()`
revert `PoolAlreadyInitialized` — invisible to every protocol read, and permanent.
Merely declining to *track* a foreign pool would not have closed it.

On a successful adoption the hook records which side is the quote by asking the
registry's allowlist about `currency0` (`CauldronHook.sol:645-652`), marks the
pool tracked, and anchors the anti-sniper window to the init block.

---

## 4. Seeding — two positions, two strategies

Every generation ends up with the same two positions:

- **ACTIVE** — full-range, holds the funding asset and the tradeable token slice,
  sets the price (`PoolOps._seedActive`, `:722`).
- **RESERVE** — single-sided token, placed out of range *below* post-buy spot, so
  it is pure `currency1` until the token appreciates ~69× into it
  (`PoolOps._seedReserve`, `:770`). This is the migration + genesis pot. Placing
  it in the pool rather than a wallet means 100% of supply reads as LP, yet it can
  only leave against a burn.

A dust-sized reserve maps to zero Uniswap liquidity, which would revert
`CannotUpdateEmptyPosition` inside the PositionManager — and a revert inside
`relaunch()` is fatal. `_seedReserve` therefore returns 0 and places nothing
(`PoolOps.sol:792`); every consumer already handles a zero reserve id.

### Strategy A — the green candle (default)

`createAndSeedWithBuy` (`PoolOps.sol:375`) → `_greenCandle` (`:448`). In one
transaction:

1. Seed **all** tokens (`activeTok + reserveTok`) into the full-range position at
   a deep-discount price, funded with only
   `ethActive = ethAmt * activeTok / totalTokens`, minus a fixed buffer
   (`:460-471`).
2. Buy exactly `reserveTok` back out with the remainder — an exact-output swap, so
   the reserve is funded to the wei (`:474-478`).
3. Re-park the bought tokens out of range, below the **post-buy** tick — read from
   `getSlot0`, not the launch tick (`:482-486`).

The constant-product identity `ethActive * total == ethAmt * activeTok` lands the
active LP at exactly `(activeTokens, ethAmount)` — the same end state a silent
seed produces — but the reserve arrives as a real market buy with a visible
candle. Candle multiplier is `(1 + reserveTok/activeTok)^2` (`:421`).

| Constant | Value | Why | Cite |
|---|---|---|---|
| `BUY_SETTLE_BUFFER` | 64 base units | An exact-output buy rounds **up**. When `ethAmt * activeTok` divides exactly, the floor takes nothing and the buy asks for one unit more than the caller holds. Native was masked by dust in the registry's balance; an ERC-20 quote has no such slack. | `PoolOps.sol:625`, `:425-446` |
| `MIN_SQRT_LIMIT` | `4295128740` | `TickMath.MIN_SQRT_PRICE + 1`; never binds on the bounded exact-output buy | `PoolOps.sol:165` |

The buy body is `PoolOps.executeBuy` (`:498`), delegatecalled from the registry's
`unlockCallback`. Settlement is quote-aware: native pays with `settle{value:}`
(`:539`), an ERC-20 quote does `sync` → checked `transfer` → `settle`
(`:541-566`). The transfer's return value is checked because a USDT-shaped token
that returns `false` would move nothing, `settle` would credit nothing, and the
unlock would end `CurrencyNotSettled()` — behind `markConsumed`, i.e. permanent
(`:542-562`).

The registry arms `_seedBuyUnlocked` for exactly that window
(`CauldronRegistry.sol:1727`, `:1740`), and `unlockCallback` requires both the
PoolManager as caller and the flag armed (`:1765-1766`).

### Strategy B — progressive streaming (opt-in)

Armed only when **both** `seeder != address(0)` and `nextSeedWindow > 0`
(`CauldronRegistry.sol:1728`). Wired by the owner via `setSeeder`
(`:327`, which also propagates to the hook) and `setSeedWindow`, bounded to 0 or
`[60 seconds, 7 days]` (`:350-354`).

`PoolOps.createAndSeedProgressive` (`:252`):

- **Non-native quote → degrades to the atomic path** (`:296-311`).
  `CauldronSeeder.startSeed` is `payable` and asserts `msg.value == cfg.ethTotal`
  (`CauldronSeeder.sol:179`); it pulls only the token side by `transferFrom`
  (`:215`) and has no ERC-20 path for the quote. Reverting there would land after
  `markConsumed`. The brew launches; it just does not stream.
- **Native quote → hybrid.** A `SEED_BASE_WAD = 15%` slice of ledger A is placed
  as the green-candle base, the reserve is bought out of it in the ignition
  transaction, and the remaining 85% is handed to the seeder
  (`PoolOps.sol:145`, `:335-350`). Before this, a progressive launch opened with
  no trade at all, and because the seeder only streams on `poke`/`pokeInSwap`, no
  buyer meant no poke meant no stream — 76.5% of ledger A was measured still
  sitting in the seeder after the window closed (`:313-327`).

| Progressive constant | Value | Cite |
|---|---|---|
| `SEED_FLOOR_WAD` | `0.1e18` — 10% placed immediately | `PoolOps.sol:137` |
| `SEED_MINSTEP_WAD` | `0.02e18` — poke throttle | `PoolOps.sol:138` |
| `SEED_BANDWIDTH` | 2000 ticks per mini-band | `PoolOps.sol:139` |
| `SEED_BASE_WAD` | `0.15e18` — two-sided full-range base | `PoolOps.sol:145` |
| `MAX_RANGES` | 64 distinct bands, so teardown gas is bounded | `CauldronSeeder.sol:115` |
| `PRIME_MIN_WEI` | `0.001 ether` dust throttle on prime tranches | `CauldronSeeder.sol:141` |

**Three ledgers, kept apart** (`CauldronSeeder.sol:47-51`, `:117-141`):

- **Ledger A** — the streamed active tranche. The only thing the seeder custodies.
- **Ledger B** — the redemption reserve. Placed by the registry directly into the
  pool; the seeder can never touch it. This is what makes "minter redemption stays
  safe" structural rather than a promise.
- **Ledger C** — the prime budget: external ETH spent buying the token in tranches
  that ride the same schedule as the liquidity stream, so each tranche meets a
  deeper book than the one before (`:117-136`).

**How it streams.** The target deployed fraction is a pure function of elapsed
time (`SeedLib.deployedTargetWad`, `cauldron/SeedLib.sol`), so it cannot be
accelerated, over-deployed or blocked. Two entrypoints share one body:

| Entry | Caller | Unlock | Cite |
|---|---|---|---|
| `pokeInSwap()` | the hook, inside `afterSwap` | already held | `CauldronSeeder.sol:307-308` |
| `poke()` | **anyone** | opens its own | `CauldronSeeder.sol:231` |

Placement uses core `poolManager.modifyLiquidity` at salt 0, so repeated
placements into the same tick range **merge** and the tracked range set stays
bounded (`:363-413`). Each step lays an ASK band (token, just below spot) and a
BID band (ETH, just above spot). At the `MAX_RANGES` cap it degrades to the last
tracked band **on the matching side** rather than halting — feeding an ask amount
into a range above spot would demand ETH the contract does not hold and revert the
whole stream (`:536-556`).

**Teardown.** `withdrawAll(to)` is `onlyRegistry` (`:565`); it removes every
tracked range plus all loose balances and forwards them
(`:417-451`). `rescue(to)` is the break-glass for an aborted campaign and
deliberately does **not** set `seeding = false` — both registry paths to
`withdrawAll` are gated on that flag, so clearing it would make the placed book
unreachable forever (`:579-602`). The registry reaches `rescue` through
`rescueSeeder()`, which is emergency-admin gated and timelocked
(`CauldronRegistry.sol:339-343`).

**The known trade-off, stated plainly:** the progressive book is single-sided
apart from the base, so it has no liquidity straddling spot except the
`SEED_BASE_WAD` tranche. A large sell that walks past the bands teleports toward
the reserve. That is accepted by design (`PoolOps.sol:128-136`).

---

## 5. The optional vesting escrow — `MigrationVesting`

Off by default. It engages only when the emergency admin sets
`claimGate` to a deployed escrow (`CauldronRegistry.sol:518`), which closes the
instant path and makes the escrow the only migration route for ordinary holders.

| Constant | Value | Cite |
|---|---|---|
| `MIN_WINDOW` | 1 hour | `MigrationVesting.sol:85` |
| `MAX_WINDOW` | 14 days | `MigrationVesting.sol:86` |
| `MAX_GRANTS` | 64 open grants per beneficiary | `MigrationVesting.sol:113` |
| `MAX_BATCH_GRANTS` | 32 — the slice a **third party** may fill | `MigrationVesting.sol:116` |

**Flow.** Approve the escrow for your dead-generation token, call `startVest`
(`:167`). The escrow pulls the dead tokens, calls `registry.claimByBurn` (which
burns them and hands the escrow the same amount of the live token), and books a
linear grant (`:207-241`). `claim()` (`:248`) or the permissionless `claimFor`
(`:255`) releases the vested-so-far portion. Vesting is linear from `start` to
`start + window`; `window == 0` is instant (`:287-292`).

**Why the two caps.** `_release` walks the grant array and is the only exit for
tokens (`:263-284`); an over-long array reverts without partial progress, locking
the balance forever. `vestBatch` is permissionless and books a grant for any
holder who has an allowance — which every holder who migrated once has, given
infinite approvals — so dusting a victim with one wei converts into another grant.
2,000 forced grants were measured to put `claimFor` over a 30,000,000-gas block
(`:88-109`). `MAX_GRANTS` bounds the loop absolutely; `MAX_BATCH_GRANTS` reserves
the remaining 32 slots for the holder's own `startVest`.

**The instant tier.** An `IStakerOracle` may mark wallets instant (`window = 0`)
— by default perp PLV stakers (`:45-48`). Unset means nobody is instant, which is
the safe default (`:294-300`), and a reverting oracle is treated as "not instant".

`renounceOwnership()` is disabled (`:358-360`): the owner is the only party who
can swap the instant-tier oracle, and pinning a wrong oracle forever would defeat
the point of it being swappable.

**The perp engine is always exempt** from the claim gate, so its own inventory
migration during `relaunch()` is never blocked
(`CauldronRegistry.sol:1252`).

---

## 6. The launch flow, end to end

### Deploy-time wiring (owner, pre-ignition)

| Step | Call | Gate | Cite |
|---|---|---|---|
| 1 | `setRedemptionExt(ext)` — **one-shot, frozen after** | `onlyOwner`; rejects a code-less target | `CauldronRegistry.sol:184-192` |
| 2 | `setFactory(f)` | `onlyOwner` | `:589` |
| 3 | `setGovernor(g)` | `onlyOwner` | `:579` |
| 4 | `CauldronGovernor.setRegistry(r)` — one-shot | `onlyOwner` | `cauldron/CauldronGovernor.sol:251-256` |
| 5 | `setGenesisBonus(mifrens, bps<=3000, shares)` | `onlyOwner`, pre-summon | `:625-635` |
| 6 | `setGenesisMetadata(mode, baseURI, renderer)` | `onlyOwner` | `:609` |
| 7 | `setRoyalty(dividend, bps<=1000)` | `onlyOwner` | `:601-605` |
| 8 | `setNftMaxSupply(n<=100_000)` | `onlyOwner` | `:594-597` |
| 9 | `setAirdropReserve(wallet, amt<=20%)` | `onlyOwner`, pre-summon | `:640-646` |
| 10 | `setCollectionLedger(l)` (optional) | `onlyOwner` | `:1479` |
| 11 | `setSeeder(s)` + `setSeedWindow(w)` (optional) | `onlyOwner` | `:327`, `:350` |
| 12 | `setIgniter(presale)` | `onlyOwner` | `:414` |
| 13 | `setGuardian(who)` | emergency admin **or** owner | `:428-434` |
| 14 | `MiFrensGenesis.setRegistry(registry)` — one-shot | deployer | `MiFrensGenesis.sol:249-254` |
| 15 | `hook.setTaxExempt(registry, true)` + `setOpener` as needed | hook owner/registry | `CauldronHook.sol:2427`, `:2417` |

The registry must be tax-exempt on the hook before the green candle runs, or the
seed buy pays the launch surtax (`PoolOps.sol:372-373`).

### Launch

- **Plain:** mint out the presale, then anyone calls
  `MiFrensGenesis.igniteCauldron()`.
- **Front-run-proof:** deploy `LaunchSniper`, set it as the presale's `finalizer`
  (`MiFrensGenesis.sol:423-426`), mark it tax-exempt, then call
  `LaunchSniper.launch{value: fundingETH}(...)` (`cauldron/LaunchSniper.sol:69`,
  `onlyOwner` `:76`). In one transaction it ignites (`:81`), reads the summoned
  token off the registry (`:82`), buys through the gacha router with
  `quoteIn = 0` because generation 1 is always native-quoted (`:87-92`), and
  forwards the bought tokens to the airdrop wallet (`:95-96`).

Because it is atomic, nothing can execute between pool creation and the buy.

---

## 7. Limitations worth stating

- **Generation 1 is always native-quoted.** `summon()` hard-passes `address(0)`
  as the quote (`CauldronRegistry.sol:709`) and leaves `generationQuote[1]` at
  zero (`:712-714`). There is no path to launch generation 1 against anything
  else.
- **The airdrop reserve leaves the LP.** Unlike every other tranche at genesis, it
  is an outright transfer (`:733`). It is capped at 20% of supply (`:643`), but it
  is a genuine off-LP allocation, not backed liquidity.
- **A cancelled presale leaves orphaned NFTs.** Refunds return ETH; the minted
  genesis ids stay with their holders and the collection never launches
  (`MiFrensGenesis.sol:297-299`).
- **`CauldronSeeder.positionManager` is unused.** It is kept only for
  constructor/ABI compatibility with the deploy script and tests
  (`CauldronSeeder.sol:81-83`).
- **The presale is the only source of generation-1 liquidity.** After genesis the
  protocol never requires external ETH again (`CauldronRegistry.sol:37-49`), but
  the first pool's depth is exactly what the presale raised, less any airdrop
  reserve.

---

## Verification

- **Commit documented against:** `880220a`. The tree was under active edit
  throughout this pass — `CauldronHook.sol`, `CauldronBase.sol`,
  `TreasuryGovernor.sol`, `CauldronGovernor.sol`, `LaunchSniper.sol` and
  `CauldronRegistry.sol` all shifted while these documents were written, some by
  90+ lines. Every `file:line` above was mechanically re-mapped and then
  spot-verified against the tree at this commit. `CauldronBase.sol`,
  `TreasuryGovernor.sol`, `LaunchSniper.sol`, `PerpEngine.sol` and `PerpVault.sol`
  still carried uncommitted working-tree edits at the end of the pass, so a later
  commit may shift them again.

- **Disagreements between a prior doc/comment and the code:**
  - `cauldron/MiFrensGenesis.sol:35-36` states "after deploy, the
    CauldronRegistry's ownership is transferred to this contract, so `finalize()`
    (and only it) can summon." That is no longer how it works, and the code
    documents why: `summon()` accepts `owner()` **or** `igniter`
    (`CauldronRegistry.sol:695`) precisely so ownership can stay with the
    timelock (`CauldronBase.sol:301-313`).
  - `cauldron/MiFrensGenesis.sol:29-30` says ignition unlocks at
    `minted == MAX_SUPPLY` and that it "becomes callable by ANYONE". Both are
    wrong against the code: the gate is `minted >= GENESIS_SUPPLY` (`:588`) —
    `MAX_SUPPLY` includes the later volume tranche — and the call is restricted
    to `finalizer` when one is set (`:591`) and blocked entirely on a cancelled
    sale (`:587`).
  - `cauldron/MiFrensGenesis.sol:30`, `:36` and `:562-565` all name the entry
    `finalize()`; the function is `igniteCauldron()` (`:575`). The contract
    self-flags the rename at `:571-574`.
  - `cauldron/PoolOps.sol:247-251` says the progressive entry is "pending a ~450B
    reclaim" and that the registry "will call this ... once its EIP-170 wiring
    lands". The registry calls it today (`CauldronRegistry.sol:1729`).
  - `cauldron/PoolOps.sol:285-287` cites
    "`CauldronRegistry._seedGeneration`, called at :1000 — AFTER
    `governor.markConsumed(winId)` at :912". The real lines are `:1083` and
    `:995`. Cross-file line references in comments have drifted throughout this
    tree; treat them as pointers to a *concept*, not a location.
- **Unverified:** the numbers quoted inside source comments as measurements
  (76.5% of ledger A stranded on round 35; 2,000 grants over a 30M block; the
  settlement-rounding figures) were not re-measured in this pass — they are
  reported as the source states them. `SeedLib.deployedTargetWad`'s exact
  arithmetic was read only in its header comment and signature, not line by line.
