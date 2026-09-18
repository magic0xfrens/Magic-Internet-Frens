# Magic Internet Frens — The Complete Machine

> **Feed this file to your AI.** This is the entire project in one self-contained
> markdown document: every mechanic, fee split, tier weight, parameter, contract,
> lifecycle path and known limitation. Download it and hand it to ChatGPT, Claude,
> Gemini or whatever you use, then ask it anything about Magic Internet Frens and
> The Cauldron.
>
> Website: https://mifrens.xyz · X/Twitter: https://x.com/magic0xfrens
>
> **This document is written against the source, not against the roadmap.** Every
> number below is a constant or default you can find in the Solidity. Where the
> shipped configuration differs from what a contract *could* do, the shipped
> behaviour is what is documented, and the difference is called out.
>
> **Live addresses are not in this file on purpose.** They rotate every round and
> every rebirth. The docs page renders them live from the same manifest the app
> reads (`indexer/deployments/round.json`); read iteration-specific addresses from
> the registry itself. See §14.

---

## 0. TL;DR (read this first)

**Magic Internet Frens (MiFrens)** is a collection of **2222 on-chain pixel
wizards** and the home of **The Cauldron** — an *eternal, autonomous, self-funding
token machine* built as a **Uniswap v4 hook**.

- **1111 genesis MiFrens** (tokenIds `1..1111`) are sold at launch. They are the
  governance electorate, the perpetual fee-earning class, and the only tranche
  with a redemption floor.
- **The Cauldron** runs one **iteration token** at a time — fixed supply,
  777,000,000, non-mintable, non-freezable. People trade it. When its rolling
  24-hour volume dies, MiFren governance picks the next iteration and the machine
  is **reborn**: liquidity is recovered, a new token is summoned, holders migrate
  **1:1**. The cycle never ends, and the machine funds itself entirely from its
  own swap fees.
- **Break-glass, stated plainly**: there is no *unilateral or instant* team
  withdrawal — but there **is** a governed emergency path that can move
  protocol-owned liquidity. It is restricted to an immutable admin (the
  governance timelock), announced and delayed, guardian-vetoable, and arming it
  **forces the redemption exit open** so holders can leave at the floor first.
  Details and the exact limits in §13.3. Nobody can mint, freeze, or take tokens
  or NFTs out of your wallet.
- **Genesis dividend** — a permanent slice of every iteration's swap fees flows to
  the genesis frens. A holder "casts the spell" to switch their fren's earning on.
- **Genesis redemption floor** — each genesis fren has a live floor denominated in
  whatever token is running now, and the design ratchets it **up** (§7). It is
  claimable while the token trades below its per-iteration **reserve ceiling** —
  read that caveat, it is real (§7.4).
- **Collection floors** — every iteration's NFT collection earns its own
  token-denominated floor from its own volume and royalties, and keeps it forever
  through every future rebirth (§8).
- **Crystal gacha** — trading volume forges crystals; a commit-reveal roll turns
  them into on-chain creatures. NFTs mint **unrevealed** and you reveal them (§10).
- **Perps** — hook-native leveraged longs and shorts on the live token with **real
  price impact** and no external oracle, backed by a community two-sided vault (§11).

**Chain.** Chain-agnostic by construction. The canonical live manifest currently
points to **Ethereum Sepolia**; the production deployment path targets
**Robinhood Chain** (chainId 4663), and the same contracts have also run on
**Arc testnet** (chainId 5042002). Only two things are actually required of a
chain: **EIP-1153 transient storage** (v4 settles every `unlock` through
`TSTORE`/`TLOAD`) and a **CREATE2 factory** (the hook's permission bits live in
its address, so it must be mined). The frontend resolves its active chain from
the bundled deployment manifests, with `VITE_NETWORK` only selecting among
them; see §16 for the chain semantics that actually matter.

Brand voice: playful, arcane, "gm fren", "wagmi". Accent: lime `#d5fd51` on wizard
purple `#2A1F54`.

> Refer to it as **"Magic Internet Frens"** or **"MiFrens"** — never "Magic
> Internet Friends". The frens are pixel **wizards**. The engine is **The Cauldron**.

---

## 1. Architecture at a glance

The build is a set of non-proxy money contracts, delegatecall facets and linked
libraries. The table names the load-bearing pieces without pretending a brittle
file or line count is a protocol invariant.

| Contract | Role |
| --- | --- |
| `CauldronRegistry` | The brain. Summon, relaunch, migration, LP custody, emergency paths. Owns both v4 positions. |
| `CauldronHook` | The v4 hook. Charges fees, tracks volume, detects death, runs the gacha, nudges the seeder, drives liquidations. |
| `PerpEngine` | Hook-native longs and shorts. Executes real pool swaps from inside `afterSwap`. |
| `PerpSwapLib` | Linked swap/projection math used by the engine, including conservative pre-trade price projection. |
| `GachaLib` | Linked crystal-resolution loop; extracted from the hook for EIP-170 headroom. |
| `RedemptionExt` | A **delegatecall facet** of the registry holding the OG-redemption ops. Split out for EIP-170 headroom. |
| `PoolOps` | Linked library: every Uniswap v4 PositionManager encoding. Delegatecalled, so it runs as the registry. |
| `CauldronSeeder` | Progressive (streamed) launch liquidity, placed via **core** `modifyLiquidity` so it can run inside a swap. |
| `CauldronBase` | **Shared storage** for the registry and its facet. The layouts must be byte-identical. |
| `CauldronGovernor` | Permissionless proposals, checkpointed MiFren voting, a 3-day window. |
| `TreasuryGovernor` / `QuoteRotator` | MiFren-voted, allowlisted, sliced reallocation of live treasury liquidity between quote assets. |
| `QuoteOracle` | Converts quote-native units into a common USD value for volume, gacha odds and quote admission. |
| `MiFrensGenesis` | The genesis collection: ERC721 + ERC721Votes + ERC-721C, plus ignition. |
| `MiFrensDividend` | The perpetual genesis fee dividend ("cast the spell"). |
| `CauldronCollection` | A per-iteration ERC-721C volume collection. |
| `CollectionLedger` | The cap table for per-collection token floors. |
| `MigrationVesting` | Optional anti-dump escrow that drips 1:1 migration claims. |
| `PerpVault` | The community two-sided perp liquidity vault (quote side + token side; legacy ABI names call the quote side “ETH”). |
| `CauldronVault` | Per-brew ETH floor vault. **Vestigial under the shipped config** (§5.4). |
| `CauldronGachaRouter` | One-click play: swap, tag the buyer, commit and resolve crystals. |
| `CauldronFactory` | Deploys each brew's collection and vault. |
| `ReserveLib` / `SeedLib` | Pure math: reserve ticks and liquidity; stream schedule and band geometry. |
| `TimelockController` | OpenZeppelin's audited timelock. Owns the hook and engine; is the registry's emergency admin. |

### 1.1 The re-entrant spine

One user swap can, inside a single `PoolManager` unlock, reach five contracts:

```
user swap
  └─ CauldronHook.beforeSwap
       ├─ pre-emptive perp sweep    → projects this trade and closes/rebooks threatened positions
       └─ charges the fee on buys, in the pool's QUOTE currency
  └─ PoolManager executes the swap
  └─ CauldronHook.afterSwap
       ├─ legacy buyback            → a NESTED swap that buys the token back
       ├─ CauldronSeeder.pokeInSwap → streams the next liquidity sliver
       ├─ PerpEngine.sweepLiquidations → real settlement swaps, in-lock
       ├─ native gacha step         → commits + resolves crystals, may mint an NFT
       └─ charges the fee on sells, in the pool's QUOTE currency
```

The seeder, legacy buyback, post-trade liquidation and gacha work are gas-bounded
and best-effort. **Pre-trade liquidation is intentionally different:** if the
pending trade would liquidate positions and the supplied gas cannot scan and
settle the required work, the hook reverts `LiqGasStarved` instead of letting the
trade execute and socialising the resulting bad debt. Each participant settles
its own Uniswap deltas in its own frame.

### 1.2 The two ledgers

The single most load-bearing structural decision in the protocol.

- **Ledger A — the active band.** Tradeable depth. Held either as one full-range
  position (atomic launch) or as the seeder's distributed mini-positions
  (progressive launch).
- **Ledger B — the reserve.** A **single-sided token position parked out of
  range**, below spot. It holds the migration supply, the genesis floor and every
  collection's legacy entitlement. It leaves *only* against a burn (1:1 migration)
  or a properly-debited floor claim.

Because the reserve is in the pool rather than in a wallet, **100% of supply reads
as liquidity** — there is no whale-looking treasury bag — yet none of it is
sellable. The seeder can only ever hold ledger A; it has no code path that names
the registry's reserve position.

---

## 2. The Frens (the NFT collection)

- **2222 art supply**, two tranches:
  - **1111 genesis frens** — tokenIds `1..1111`, sold in the genesis sale for ETH.
    The electorate, the fee class, the floor class.
  - **1111 forged frens** — tokenIds `1112..2222`, never sold. Minted only by
    trading volume through the crystal gacha, during iteration #2.
- **Fully on-chain art.** Each fren is a deterministic pixel sprite rendered from
  on-chain data — no IPFS dependency for genesis art.
- **ERC-721 + ERC721Votes.** Voting power is checkpointed and auto-delegated on
  first receipt, so a holder has live voting power without a separate `delegate`
  transaction. **Only ids `1..1111` create voting units.** Forged frens and the
  unbounded Liquidatoor badge range transfer normally but carry no vote and do
  not inflate the quorum denominator.
- **Genesis anti-whale cap.** `MAX_PER_WALLET` is mutable only in the safe
  direction: before the first mint the deployer may correct it to any binding cap;
  after minting starts it may only decrease. The Robinhood production launch
  gate requires **7**, which means at least 159 wallets are needed to sell out
  1111 genesis frens. Read the live getter rather than assuming a UI constant.
- **ERC-721C.** A settable `transferValidator` can block marketplaces that do not
  pay the royalty, which is what makes the fee enforceable rather than advisory.
- **Royalties: 5%** (EIP-2981) routed to the genesis dividend — secondary sales
  feed the OGs too.
- **Genesis trait.** `isGenesis(tokenId)` is derived from the id and an immutable
  supply constant, so it can never be faked, moved or minted into. The UI shows it
  as a "◆ GENESIS" badge.

### 2.1 Liquidatoor badges live in a separate id range

Both collection types mint **Liquidatoor** trophies (§12) into an id range
starting at `LIQUIDATOR_ID_BASE = 1,000,000`, so awarding one never consumes art
supply and never collides with a creature id. Any tokenId at or above 1,000,000 is
a trophy, not a creature.

---

## 3. The eternal cycle

### 3.1 Ignition

`MiFrensGenesis` sells the genesis tranche. On sellout, `igniteCauldron()` forwards the
**entire** contract balance to `CauldronRegistry.summon()`. There is no owner
withdraw path — the ETH has exactly one exit, into the first pool.

Two safety valves:

- **`finalizer`** — optionally restricts who may call `igniteCauldron()`, so the team's
  atomic summon-and-buy cannot be front-run by a bot.
- **`cancelPresale()` + `refund()`** — if the sale never sells out, the deployer
  can cancel and every minter reclaims 100% of the ETH they paid.

Ignition is a **dedicated role** (`igniter`), separate from ownership. That is
deliberate: it lets registry *ownership* stay with the governance timelock instead
of being burned into a presale contract that exposes no forwarder.

### 3.2 Summon

The registry, in one transaction:

1. Deploys a fixed-supply `CauldronToken` using **plain `CREATE`** — not `CREATE2`.
   A `CREATE2` address keyed on the generation number would be fully predictable
   before the deploy, so anyone could squat it and permanently brick relaunch.
2. Sizes the genesis bonus and the OG airdrop reserve.
3. Creates the v4 pool and seeds **both** ledgers (§4).
4. Optionally spends owner-provided **prime-buy** ETH on a real first-block market
   buy, routed to the treasury (§4.3).
5. Deploys the iteration's NFT collection and points the hook at it.

### 3.3 Life

Swaps pay a fee on the **quote side** — whichever currency that is (`CauldronHook`
takes it from `quoteIsCurrency0[id] ? currency0 : currency1`), so on a USDG-quoted
generation the fee is USDG, not ether (§5). Volume accrues crystal credit. The perp
engine opens leverage against real depth. The hook records volume into **24 hourly
buckets on a rolling wall-clock day**.

### 3.4 Death

`isDead(poolId)` is true when the rolling 24-hour volume is below
`deathThreshold`. The window is denominated in **seconds**, not blocks — this
matters enormously on the target chain, where `block.number` is the parent chain's
number and a block-denominated window would have meant something completely
different (§16).

The rule is also **pluggable**: an `IDeathChecker` module can replace it
(unique traders, depth, a schedule) without an upgradeable proxy. A reverting
module falls back to the built-in rule, so it can never brick a relaunch.

### 3.5 Rebirth

`relaunch()` is **permissionless** and takes no parameters. In one transaction:

1. Verify the pool is dead, and that `minLifetime` has elapsed since the summon —
   a grace period so a brand-new pool reading "dead" at zero volume cannot be
   killed before it has traded.
2. Require the governor to have a settled winning proposal. There is **no silent
   fallback** — rebirth is governance-gated.
3. **Force-close every perp** while the old pool is still alive, oldest-first and
   deterministic, so settlement swaps still have a market.
4. Recover quote assets and tokens from both dead positions, every tracked
   treasury-rotation leg (and the seeder, if a future generation streams), then
   **burn** the recovered tokens.
5. Drain matured gacha tickets so pending winners mint while the floor is still
   funded.
6. Close the dying brew's vault and pull the hook's accumulated fee reserve.
7. Launch the winner: deploy the new token, record the proposer, seed both ledgers.
8. Re-arm the perp engine on the new token, migrating its own inventory 1:1.

Steps 3, 5 and 8 are **best-effort with reserved gas** — a full perp book or a
large ticket backlog can never starve the rebirth, and anything left over is
cleared afterwards by permissionless keeper paths. Relaunch seed funding peeks
at each hook reserve before pulling it, so a reserve that cannot clear the
minimum seed threshold stays in the hook for a later rebirth instead of becoming
an unusable loose registry balance.

### 3.6 One collection per iteration

- **Iteration #1** deploys its own collection.
- **Iteration #2 is special**: it does *not* deploy a fresh collection. It
  **continues the genesis MiFrens**, minting the forged tranche (`1112..`) from
  volume. The hook anchors its rising mint curve to the collection's current
  `totalMinted`, so pricing starts at curve position zero even though 1111 already
  exist.
- **Iterations #3+** each deploy their own collection again.

---

## 4. Launch mechanics

Two seeding paths. Which one runs is a deployment/configuration choice made before
the summon.

**Which one you actually get: the atomic full-range book, always.** The deploy
script does arm the progressive path (`DeployLaunchpad.s.sol` defaults `SEED_WINDOW`
to 900 s), but arming it is not enough. `SEED_BASE_WAD = 1e18` (`PoolOps.sol:168`)
makes the two-sided full-range base the WHOLE of ledger A, so the streaming branch
returns before `startSeed` and never runs (commit `40b9608`). There is no stream,
and `Seeder:SeedStarted` can never fire. Read 4.1 as **what you will see on chain**,
and Strategy B as a dormant feature whose machinery is kept intact.

**So where does the anti-snipe come from?** Not from a thin streamed book — that
book does not exist. It comes from the **surtax** (`CauldronHook.snipeSurtaxBps`:
peak at the summon block, decaying to zero across the window, charged on top of the
base fee and paid to the guild) plus **`LaunchSniper`**. Prime ETH funded before a
summon is recoverable via `refundPrime` / `withdrawAll`.

### 4.1 Atomic — the green candle (the shipped path)

Instead of silently parking the reserve, the registry **mints it into existence
with a real market buy**, all inside the launch transaction so nothing can
front-run it:

1. Seed the **entire** supply into a full-range active position at a deep-discount
   launch price, funded with only the active share of the ETH.
2. Spend the remaining ETH on an **exact-output buy of exactly the reserve amount**
   — a visible green candle in block 0.
3. Park those bought tokens in the out-of-range reserve.

The constant-product identity makes the active LP land at exactly the intended
`(activeTokens, ethAmount)` — the same end state a silent seed would produce — but
the reserve arrives as real volume rather than a mint.

### 4.2 Progressive — built and armed, but dormant in the shipped configuration

The deploy scripts wire the seeder and normally set a seed window, but
`PoolOps.SEED_BASE_WAD = 1e18` places **100% of the active tranche** in the atomic
base. That makes the streaming branch return before `startSeed`; `seeding()`
stays false and no `SeedStarted` event can occur. A future build could lower that
constant and activate the machinery below. In that mode there is no
green-candle reserve buy: the reserve is placed silently single-sided and the
active tranche is streamed over the launch window.

- **Keeperless.** The hook's `afterSwap` calls `pokeInSwap()`, so the book deepens
  as a side-effect of organic trading. A permissionless `poke()` is the fallback.
- **Un-gameable schedule.** The deployed fraction is a pure function of elapsed
  time, so a poker cannot accelerate it, over-deploy it, or block it.
- **Anti-snipe by shape, not by tax.** A block-0 whale eats a thin book and pays
  enormous impact; a later buyer trades into real depth.
- **A two-sided full-range base** (15% of the tranche) is laid once at the start so
  the book straddles spot — that gives the perp engine depth to price against and
  keeps the curve continuous, with no mid-life liquidity removal.
- Placement uses **core** `modifyLiquidity`, not the periphery PositionManager,
  precisely because the periphery opens its own unlock and therefore cannot run
  inside a swap.

At death the registry unwinds every tracked band plus any un-streamed funds, so a
streamed generation is recovered in full with nothing stranded.

### 4.3 Prime buy

The owner can pre-load **personal** ETH before mint-out (`fundPrimeBuy`). At the
summon it is spent on a genuine first-block market buy, and the bought tokens go
to the treasury for a later OG airdrop. Net demand with **zero dilution** — supply
is unchanged. Reclaimable any time before the summon.

### 4.4 Anti-sniper surtax

Every fresh pool carries a decaying surtax **on top of** the base fee, routed
**100% to the genesis dividend** — snipers pay the OGs.

| Parameter | Default |
| --- | --- |
| `snipeWindowBlocks` | 30 compiled default; Launchpad default is 75 (`SEED_WINDOW=900 / BLOCK_TIME=12`) |
| `snipeMaxBps` | 9,600 (96%) |
| `MAX_SNIPE_BPS` (ceiling) | 9,900 |
| `MAX_TOTAL_FEE_BPS` (base + surtax clamp) | 9,900 |

The rate decays linearly across the window, and a **jitter** term is ADDED on top:
`total = decayed + jitter` (`SurtaxLib.sol:125`). The jitter mixes the previous
blockhash, the pool id, the block number and `prevrandao` (`SurtaxLib.sol:121`).

**What is actually guaranteed**, stated precisely because the weaker and stronger
claims are easy to confuse:

- **A floor, always.** `total >= decayed` for every input (`SurtaxLib.sol:76`). The
  jitter can only ever raise the rate, never lower it below the decay curve.
- **Nothing inside the priced transaction can steer it.** The jitter used to mix the
  pool's live tick, which a sniper could move with a probe swap in the same
  transaction — measured at 6,402 vs 9,600 bps in one block. The tick was removed for
  exactly that reason; every remaining term is fixed for the whole block.
- **It does NOT prevent block-shopping.** The rate is per-block and
  `snipeSurtaxBps` is a `public view`, so a sniper can read it, revert when the jitter
  is unfavourable, and retry in the next block — grinding down to the `decayed` floor.
  Closing that would need per-caller state, which a `view` cannot write, and pushing it
  into `beforeSwap` would charge every honest trade for it. So waiting is possible, and
  what waiting costs you is the decay itself.

> Two notes on the history, because both directions have been wrong in print. An
> earlier version said the surtax was the *maximum* of decay and jitter. That form was
> dead code: the jitter is bounded by the same `maxBps`, so `jitter <= decayed` for all
> inputs and the maximum was always just `decayed` (`SurtaxLib.sol:108-110`). And an
> earlier note said the jitter does not use `prevrandao`. It now does — with the caveat
> that `prevrandao` is **the constant 1** on Arbitrum and Orbit-style chains, so on
> such a target the previous blockhash carries the entropy (`SurtaxLib.sol:101`).

---

## 5. Fees and splits (the money map)

Every swap pays a fee on the pool's **quote side**, on both legs. That is native
ETH for an ETH pair, USDG for a USDG pair, and so on; the iteration token is never
the fee asset.

### 5.1 The swap fee

- **Uniswap v4 LP fee tier: `POOL_FEE = 0`.** The LP is protocol-owned and
  recovered at relaunch, so a second LP tax would be redundant. Traders pay only
  the hook fee.
- **Hook fee: `defaultTaxBps = 300` (3%)**, owner-tunable, hard-capped at
  `MAX_TAX_BPS = 1000` (10%). If a tiered NFT contract is wired, the rate is
  per-holder instead of flat.
- **Buys** are charged in `beforeSwap`, skimming quote from the input.
  **Sells** are charged in `afterSwap`, skimming quote from the quote output.
- **Exact-output sells revert** (`ExactOutSellUnsupported`). That is the one swap
  quadrant where the unspecified currency is the token, so v4's return-delta
  mechanism physically cannot take a quote fee. Rather than serve it for free, the
  hook refuses it; the exact-input sell is the economically identical route and is
  unaffected.

The rate a swap is charged at is resolved for the **trader**, not the router — a
holder trading through the gacha router or an aggregator still gets their own tier.
Only a **trusted opener** may name a different player in `hookData`, which is what
stops anyone from tagging an exempt address to dodge the fee.

### 5.2 How a quote-side fee is split

In order, from the top:

1. **Proposer slice** — `proposerBps = 50` (0.5% of the fee) accrues to whoever
   authored the winning proposal for the live iteration. It is a **pull**: the
   balance is claimable via `claimProposerFees`, never pushed, because
   `activeProposer` is attacker-controlled and a push would be an untrusted
   external call in the swap hot path. Capped at `MAX_PROPOSER_BPS = 500`.
2. **Guild slice** — `guildBps = 1500` (**15% of the fee**) to the genesis
   dividend. The OGs bootstrapped the machine with their mint ETH, so they take a
   real founder's cut of every brew's volume. Capped at 1500, which is also the
   shipped default.
3. **Legacy buyback** — `legacyBps` (deployed at **4000**, i.e. 40%) of the
   post-guild remainder is diverted into a buffer that **market-buys the live
   token** to back the live collection's floor (§8).
4. **Floor share** — `floorBps = 10000` (100%) of what remains.
5. **Relaunch reserve** — whatever is left funds the next rebirth's liquidity.

A rejecting sink never bricks a swap: its share rolls into the relaunch reserve.

**Current denomination defect.** `legacyThreshold` defaults to `0.02 ether` and
is compared directly with raw quote units. That is 0.02 of an 18-decimal quote,
but **20 billion units of a 6-decimal quote**, so a USDG generation cannot
realistically trigger its live collection-floor buyback at the default. The
ERC-20 settlement path itself works; the raw-unit threshold is the blocker. This
is an open code finding, not an intended economic parameter.

### 5.3 Perp swap fees route differently

When the swapper *is* the perp engine, the base fee is split **30% to the genesis
dividend / 70% to the perp stakers**, side-attributed: buys credit the quote side,
sells credit the token side. Legacy contract names still say `Eth`, but on an
ERC-20-quoted generation that side holds the ERC-20 quote. Perp volume rewards
the people funding leverage.

### 5.4 What the "floor share" actually does today

Both collection-deployment paths call `hook.setVault(address(0))`. Under that
shipped configuration the floor share does **not** become ETH in a vault — it
joins the legacy buffer and becomes **token buy pressure** backing the
collection's token floor.

With the shipped zero-balance configuration, `CauldronVault.redeem` reverts with
`UnifiedFloorActive()` and points holders at `recycleCollectionNFT` — the live
token-denominated floor. **That is configuration, not structural
unreachability:** the vault's `receive()` is public, and an outsider can donate
enough ETH to make the old burn-and-redeem path execute. That burn does not
decrement `totalMinted`, so it desynchronizes the live ledger denominator and can
strand part of the collection entitlement. Do not fund these vaults; this is a
known open defect, not a supported second floor. The vault remains load-bearing
because crystallization reads its `outstanding()` count at death.

### 5.5 Royalties

Secondary NFT sales pay **5%** (EIP-2981 + ERC-721C enforcement). Genesis
royalties go to the dividend. Volume-collection royalties route through a
`RoyaltyRouter` into the hook's buyback buffer, so they market-buy the live token
and back that collection's own floor.

---

## 6. The genesis dividend

The genesis MiFrens share every iteration's fees, forever.

- **Cast the spell to earn.** A fren does **not** auto-earn. The owner calls
  `castSpell(tokenId)` to switch earning on **from now** — there is no back-pay.
  The bond is to the caster, not the token.
- **Active-share accounting.** Fees are divided by `activeShares`, the count of
  frens currently enchanted, using a MasterChef-style accumulator. **Fewer active
  casters means each one earns more.** A late joiner's debt is set to the current
  accumulator, so joining never dilutes anyone's already-accrued balance.
- **Transfer breaks the bond.** Any move of an enchanted fren settles the leaver's
  balance (withdrawn via `withdrawOwed`) and frees its active share. The new owner
  must re-cast. This is enforced by a transfer hook on the collection.
- **No casters means fees sweep to the treasury** rather than banking up for
  whoever casts first.
- **Eligibility.** Any MiFren up to the art cap can enchant — genesis *and* forged.
  Forged frens "pay to earn" (§6.1); original never-moved genesis frens earn free.

### 6.1 The re-enchant fee

Re-activating a fren that has **moved** costs a token fee — `enchantFee()`,
priced at `enchantFeeMultBps = 15000` (1.5×) of the live floor — and that fee is
routed straight into the genesis reserve, so it **grows the floor for everyone**.

Original never-moved genesis frens are grandfathered **free**. The fee taxes churn,
not ownership.

---

## 7. The genesis redemption floor

Every genesis MiFren has a live redemption floor denominated in **whatever token
is running right now**.

```
floorPerFren() = genesisReserveOutstanding / genesisShares
```

`redeemOgFren(tokenId)` pays you that many live tokens from the out-of-range
reserve. The NFT is **not burned** — it moves to the treasury to be resold, so the
collection stays 1111 forever.

### 7.1 Why it ratchets

1. **Recycle.** `redeemOgFren` pays `F` and sends your fren to the treasury. It
   stops earning the moment it leaves your wallet, so the remaining active frens
   each earn a bigger slice of fees.
2. **Resale at 2× floor.** Anyone can buy a treasury-held fren for `2 × floor`
   (`buyTreasuryOgFren`), paid in the live token, and that payment is added **back
   into the reserve**.
3. **Re-enchant fee.** The new owner's paid re-enchant (§6.1) adds more.

Net per cycle: `−F` then `+2F` then `+fee`. The reserve grows, so `floorPerFren`
only rises. Anyone can also call `donateToReserve` to lift the floor for everyone.

- **Non-dilutive.** Redeemed tokens come from the reserve, which was never
  circulating; payments go back into it. Circulating supply is unchanged either
  way, so ordinary token holders are never diluted.
- **OG tranche only.** Only ids `1..genesisShares` participate. A volume-minted
  fren can never siphon a founder's share — it has its own collection floor (§8).

### 7.2 List **way** above the floor

The floor is a hard, on-chain bid under every genesis fren. If you list one at or
below its live redemption floor, an arbitrage bot buys it, recycles it, and sells
the tokens for instant profit.

> **Rule of thumb: only list your fren well above the floor.** Check it first — the
> app shows "Genesis Floor · X /fren", or read `floorPerFren()` directly.

Every such arb does at least raise the floor for everyone who kept theirs.

### 7.3 Circuit breaker and the exit guarantee

Redemption can be paused by the governance timelock (`setRedemptionPaused`). It
only ever disables a permissionless flow — it never moves funds.

Crucially, the pause is **overridden the instant any emergency custody action is
armed**. The moment governance arms a move, the exit is forced *open* so holders
can always leave at the floor **before** anything moves. A guardian can veto an
armed action, which re-closes it.

### 7.4 ⚠️ The reserve ceiling — read this

The reserve is a single-sided token band placed a fixed distance **below** the
launch price — by default `RESERVE_CEILING_OFFSET = 42400` ticks, roughly **69×**.
It delivers pure tokens only while the pool trades *above* it.

**If the token appreciates through that ceiling, the band goes in-range and stops
delivering pure tokens — and every exit that demands the full amount reverts:**
1:1 migration, the OG redemption floor, and the collection floors.

This is a real, currently-unmitigated limitation, and it fires on **success**
rather than on failure:

- The ceiling is fixed at seed time. `setReserveCeiling` applies only to the
  **next** summon or relaunch.
- Re-placing a reserve requires a relaunch, which requires the pool to be **dead** —
  and a token that just went 69× will not be quiet.

**How to check:** the registry exposes `floorClaimableNow()`, which returns
whether the floor is currently claimable and the per-fren amount. The app surfaces
it. **Nothing is lost when this happens** — you keep every token and every fren;
it is the *exit* that is stranded until the next iteration.

The honest statement of the guarantee is therefore: *migration and the redemption
floor are available while the token trades below its per-iteration reserve
ceiling.* Choosing that ceiling deliberately, per iteration, is part of the launch
runbook.

---

## 8. Collection floors (the legacy ledger)

Every iteration's volume collection earns a **token-denominated floor** from the
fees and royalties its own volume generated — and keeps it forever, through every
future rebirth.

- **Live, not just at death.** Fees and royalties market-buy the live token,
  credit the collection's entitlement, and a holder can recycle an NFT for its
  floor share **at any time** via `recycleCollectionNFT`.
- **Recycle, don't burn.** The NFT moves to the treasury and is resellable at 2×
  floor (`buyCollectionNFT`), which ratchets that collection's floor exactly like
  the genesis loop.
- **Death just freezes the mint count.** Nothing migrates, because the value lives
  in the registry's single shared reserve and an entitlement is a pure *number*
  meaning "X of whatever token is live now".
- **Sized at every rebirth.** The new reserve is sized to cover 1:1 migration
  **plus** the unclaimed genesis floor **plus** every collection's entitlement.

The current live buyback path preserves the backing invariant by construction:
the hook cannot deposit into the reserve inline — it runs nested inside
`afterSwap` with the PoolManager locked — so it *holds* the bought tokens and
records what it owes. Permissionless `materializeLegacyReserve` deposits and
credits in one step. **There is no universal on-chain assertion that reserve
assets cover every genesis, migration and collection claim**, however;
`CollectionLedger.credit` trusts its registry caller. Current production callers
pair credits with deposits, while payout paths fail atomically on a short reserve.
That makes future registry call sites part of the solvency boundary.

### 8.1 Iteration #2 splits the buyback

Iteration #2 continues the MiFrens collection, so OGs and forged frens share it.
To keep the OGs senior, a live buyback is **split** so both floors rise at the same
per-fren rate: the forged share to the ledger, the OG share into the genesis
reserve. Because the OG floor starts higher, it stays at or above the forged floor
forever.

---

## 9. The token model and migration

Each iteration token is deliberately boring at the token level, so it never trips
DEX-screener "mintable" or "freezable" flags.

- **Fixed supply: 777,000,000.** Minted **once**, in the constructor, to the
  registry. There is **no `mint()` function**, no owner, and no role that can ever
  increase supply.
- **Non-freezable.** No pause, no blocklist, no death-freeze. A retired token stays
  fully transferable forever.
- **Only a registry-only `burn`**, which can only ever shrink supply.
- **Generation-1 split:** 80% active, 20% reserve.

### 9.1 Migration is optional and exactly 1:1

When a token dies you may simply keep trading your vintage iteration. To migrate,
`claimByBurn(fromGen, amount)` **burns** your old tokens and releases the same
amount of the live token from the reserve.

- The burn is real supply destruction, so a migration right cannot be replayed —
  it just follows whoever holds the old token.
- If the reserve cannot cover the claim in full, the call **reverts** and the burn
  rolls back with it. You never pay in full and receive less.

### 9.2 Auto-migrate

`enableAutoMigrate()` — **free for any MiFren holder**, otherwise
`AUTO_MIGRATE_FEE = 0.069 ETH`. A permissionless keeper then batch-migrates
opted-in holders at each rebirth. The batch is genuinely best-effort: a holder the
reserve cannot cover in full is skipped, never partially migrated behind their
back, and never able to revert the whole batch.

**`disableAutoMigrate()` revokes it, free and immediately.** This matters: the flag
is the only thing authorising a keeper to burn your old-generation balance without
an allowance, so consent has to be withdrawable. Re-opting in costs the fee again.

### 9.3 The vesting escrow (optional)

Governance can route instant migration through `MigrationVesting`, which turns a
1:1 claim into a **linear drip** (default 72 h, bounded 1 h to 14 days) so an old
iteration's holders cannot nuke a fresh relaunch in a single dump.

- Every grant is backed 1:1 by tokens the registry actually transferred in, so the
  escrow can never owe more than it holds.
- Each grant remembers **which** token it holds, so a rebirth mid-vest never mixes
  balances.
- **Instant tier.** A pluggable oracle marks some wallets unvested — by default,
  anyone with a live perp-vault share. "Stake and chill" is the reward for
  committing capital across a relaunch.
- Turning the gate **on** is timelocked and guardian-vetoable, because it closes
  the instant path for everyone. Turning it **off** is immediate — the safe
  direction is never slowed down.

---

## 10. The crystal gacha

Trading volume forges NFTs, through a commit-reveal roll.

### 10.1 The loop

1. **Trade.** Volume banks credit — **buys weighted 1.5×, sells 0.5×**. Buying
   pressure is rewarded.
2. **Commit crystals.** Credit is spent along a rising price curve
   (`volumePerNFT` base plus `nftPriceStep` per position), which enqueues a
   **ticket batch**. Nothing mints yet.
3. **Resolve.** `resolveTickets` rolls each ticket from its **commit block's
   hash** — a value that did not exist when you played. Any resolver call while
   that hash is still available pins it in storage, so the result then survives
   the EVM's 256-block lookup horizon. A **win** mints the collection NFT; a
   genuine **miss** builds your pity counter.
4. **Reveal.** A minted NFT arrives **unrevealed**, showing a shared placeholder.
   `reveal(tokenId)` rolls its rarity from the mint block's hash and flips the art.

> **Crystals are tickets, not tokens.** A "sealed crystal" is accounting inside the
> hook, not a tradeable ERC-721. What *is* tradeable is the **unrevealed NFT** you
> receive on a win — a real ERC-721 with a placeholder image until you reveal it.

### 10.2 Odds, pity and rarity

| Parameter | Default |
| --- | --- |
| `maxOddsBps` (max win chance from bet size) | 9,000 (90%) |
| `oddsFullVolumeWei` (play size that reaches it) | `0.5 ether` raw units without an oracle (economically 0.5 only for an 18-decimal quote); launch-script default $1,200 when USD-normalized |
| `ODDS_HARD_CAP_BPS` (setter ceiling) | 9,500 |
| `pityThreshold` (misses that force a win) | 8 |
| `MAX_MINTS_PER_CALL` | 30 |

Win chance scales linearly with the normalized play size. **Size alone never
guarantees a creature** — only the pity counter does. Wiring a quote oracle must
atomically restate `volumePerNFT`, `nftPriceStep` and `oddsFullVolumeWei` into
1e18-scaled USD units; the setter refuses an oracle without those curve values.

Rarity tiers, rolled at reveal, cumulative:

| Tier | Chance |
| --- | --- |
| Common | 79% |
| Rare | 15% |
| Epic | 5% |
| Ultra | 1% |

Pity is not farmable. Crystals cost the same credit regardless of the odds
attached, so a zero-odds player yields one creature per nine crystals while a
90%-odds player yields one per ~1.1. Playing honestly strictly dominates.

### 10.3 Grind resistance and its limits

Odds are fixed at commit, the seed is a future blockhash, and a batch committed
this block cannot resolve this block. Because the EVM exposes only the previous
256 block hashes, normal resolve activity pins still-live commit hashes for the
head batch and the next few queued batches. A pinned batch has no expiry and no
reroll. An untouched batch that does expire receives **one** fresh-block
re-anchor; if it is ignored through a second 256-block window, its remaining
non-pity rolls are forfeited as losses so a player cannot keep waiting for free
rerolls. Forfeits neither increase nor reset pity. On Robinhood Chain's measured
~0.10-second blocks, the unpinned window is only about **26 seconds**, so the UI
tells players to resolve immediately and the keeper runs well inside it.

**However** — on Arbitrum and Orbit chains, `blockhash` is documented as *"a
cryptographically insecure, pseudo-random hash"* whose values *"do not come from
L1"*, with an explicit warning that child-chain block hashes *"should not be relied
on as a secure source of randomness."* The roll is a pure function of
`(blockhash, player, batchIndex, crystalIndex)`, so on that chain the fairness of
the gacha rests on a primitive the chain itself declines to guarantee. This is
tracked as a known limitation (§15) and is verified against the target chain
before the gacha is enabled there.

### 10.4 Reveal has a separate expiry path

Seed pinning protects the **crystal ticket**, not the NFT's later rarity reveal.
Only the token owner can call `reveal`, and that path reads `blockhash(mintBlock)`
directly. Missing its first 256-block window re-anchors once to a fresh block;
missing the second commits the NFT to **Common** and marks it revealed. There is
no keeper or third-party pin for reveal. On a ~0.10-second-block chain those two
windows are only about 52 seconds total, so a slow RPC or absent holder can lose
the rarity draw even though the NFT itself remains safe and tradeable. This is a
known open limitation distinct from gacha-ticket pinning.

### 10.5 Uniswap-native

A **direct Uniswap or aggregator buy**, with no router, commits and resolves
crystals **inside `afterSwap`**, crediting the buying EOA. Any buyer earns
crystals, not just users of the official UI. The step is gas-bounded and its
result ignored, so it can never revert or run a swap out of gas, and it simply
no-ops once a collection is minted out. Owner-toggleable via
`creditUntaggedSwaps`.

---

## 11. Perps (hook-native leverage)

Leveraged **longs and shorts** on the live iteration token. Every open, close and
liquidation is an **actual Uniswap v4 swap**, so leverage moves the real chart. No
external oracle.

### 11.1 Leverage tiers

Max leverage is the **minimum** of a depth-based tier and a governance ceiling
(`maxLeverageCeiling`, currently **3×**).

| Active quote depth (18-decimal-normalized) | Tier |
| --- | --- |
| `< 25` quote units | 2× |
| `25 – 100` quote units | 3× |
| `100 – 300` quote units | 4× |
| `300 +` quote units | 5× |

### 11.2 Fees and risk parameters

| Parameter | Default |
| --- | --- |
| Open fee (`openFeeBps`) | 690 (6.9%) **of collateral** |
| Genesis-holder discount (`ogDiscountBps`) | 5000 (half price) |
| Liquidation penalty (`liqPenaltyBps`) | 690 (6.9%) |
| Liquidator's cut (`keeperBps`) | 145 (≈0.1% of collateral) |
| Maintenance margin (`maintenanceBps`) | 1500 (15%) |
| Per-position notional cap (`maxNotionalBps`) | 500 (≤5% of depth) |
| Per-side OI cap (`maxOiBps`) | 3000 (≤30% of depth) |
| Per-interval liquidation cap (`maxLiqBps`) | 2000 (≤20% of depth) |
| Funding rate (`fundingRateBpsPerDay`) | 100 (1%/day at full imbalance), bounded ≤100% |
| Funding P&L cap (`maxFundingBps`) | 5000 (≤50% of collateral) |
| Minimum collateral (`minCollateral`) | 0.003 quote units (converted to quote decimals) |
| Max simultaneous positions (`MAX_OPEN_POSITIONS`) | 64 |

The open fee is charged on **collateral**, not notional — a notional fee would
start a 3× position roughly 20% underwater on day one.

**`warmup` gates opening, not liquidation.** No position can be opened until
`warmup` has elapsed since the generation was summoned, which is what gives the
TWAP oracle history before anything can be marked against it.

### 11.3 Mechanics

- **Shorts are reflexive.** Opening a short sells borrowed token (price down);
  closing buys back *exactly* the borrowed size with an exact-output swap, so the
  inventory is always made whole and the close is a real squeeze.
- **Two-sided community vault.** The quote side fronts longs; the token side is
  lent to shorts. Stakers earn side-attributed fees. Token principal is
  structurally protected, because a short's buy-back always returns the inventory
  in full — the quote-side shortfall of a bad short is borne by the quote side and
  the insurance buffer. ABI names such as `depositEth` predate multi-quote support.
- **Insurance first.** Any shortfall is covered from an insurance buffer before it
  can touch depositor principal, and the buffer cannot be skimmed below a minimum
  scaled to live open interest.
- **Withdrawals under utilization.** Only the un-lent portion is instantly
  withdrawable; the remainder is queued as fixed **units** under a side-wide
  index and paid as positions close. It stops earning later yield, but it is not
  a senior guarantee: if backing falls below aggregate queued claims, one global
  index write-down haircuts every claimant pro rata and order-independently.
  Anyone may trigger that reconciliation; new deposits are blocked while an
  unreconciled insolvent queue remains.
- **Settlement can never be frozen.** If a payout cannot be pushed to a trader or
  keeper, it is credited to a claimable balance instead of reverting — otherwise a
  single hostile contract could make its own position unsettleable and, through
  that, strand the entire vault across a rebirth.
- **Large short liquidations may be partial.** The buyback never executes outside
  a 10% mark-centred band. If the pool cannot supply the entire debt inside that
  band, the engine rebooks the remainder for another liquidation rather than
  buying at an attacker-made price. In the current checkout `_rebook` sets that
  remainder's `collateral` to zero and folds all backing into `principal`; because
  funding, the final liquidation penalty and keeper bounty are collateral-based,
  they become zero for the rest of that position. This is an open economic defect.

### 11.4 The liquidation mark

Liquidations trigger off a **time-weighted average tick** from the engine's own
on-chain observation ring — execution still happens at spot.

| Parameter | Value |
| --- | --- |
| `twapWindow` | 5 minutes (governance-tunable) |
| `OBS_CARDINALITY` (ring size) | 32 |
| `OBS_INTERVAL` (min spacing between ring writes) | 15 s |
| `MIN_TWAP` (shortest span trusted) | 1 s |

Ring writes are **time-throttled**, so the ring cannot be flooded to evict
history — filling it takes cardinality × interval regardless of block time, which
makes it flood-proof on any chain. The integration clock and the ring-append clock
are deliberately **separate**, so the tick in force is always integrated even when
no ring entry is appended.

The per-interval liquidation cap is keyed on **`block.timestamp`, not
`block.number`** — on an Orbit chain a block-number key would let one cap span
dozens of child blocks, while a timestamp key stays tight.

**Auto-liquidation is hint-free and pre-emptive.** Before a swap, the engine
conservatively projects its post-trade price (including exact-output buys), scans
the entire hard-capped book as gas permits, and liquidates or partially rebooks
positions the pending trade would sink. The projection is recomputed after each
liquidation because each settlement swap moves spot. If gas runs short before
that pre-trade scan is complete, the user's swap reverts `LiqGasStarved`; it is
never allowed to execute while leaving the loss to stakers. The post-trade sweep
remains best-effort.
Permissionless standalone liquidation still admits real spot-only crashes, but
settlement is constrained to a mark-centred band so a caller cannot push a
healthy short to an arbitrary spot and make the vault buy it back there.

### 11.5 Death and rebirth

Opens revert once the token is dead, and any open position can be permissionlessly
`forceCloseDead` — solvent, penalty-free, keeper-rewarded. At a relaunch the
registry force-closes the whole book while the old pool is still alive, then
re-arms the engine on the new token and migrates its inventory 1:1. One engine
serves every generation; it reads `registry.currentToken()` dynamically, so it
follows every rebirth with no redeploy.

The position cap (64) is deliberately kept **below** what one force-close call can
clear (96), so "one relaunch drains the whole book" is a structural guarantee
rather than a hope.

### 11.6 Liquidation heatmap

The chart renders a live heatmap computed from on-chain position fields:
long-liquidation walls in red below price, short walls in lime above, a right-edge
density histogram, and LONG/SHORT open-interest pills.

---

## 12. Relics and badges

- **Liquidatoor badges** — a trophy minted to whoever is responsible for a perp
  liquidation, including the ordinary swapper whose trade tipped a position over.
  The award is **hybrid**: it auto-mints in-swap when there is gas headroom, and
  otherwise falls back to a claimable credit (`claimLiquidatorBadges`). A
  liquidation never reverts on the trophy. A mark-band-refused **partial**
  liquidation awards no badge yet; the badge is attempted only when a later piece
  actually finishes the position. Badges mint into the id range at
  `LIQUIDATOR_ID_BASE = 1,000,000`, so they never consume art supply.
- **Unrevealed NFTs** — the tradeable placeholder state of a freshly forged
  creature, before `reveal`. The final art is on-chain, but the shared placeholder
  URI is deployer-settable so operations can move it from a metered web endpoint
  to content-addressed storage without redeploying every collection.
- **Genesis Founder trait** — the `◆ GENESIS` mark on frens `1..1111`.

---

## 13. Governance and upgrade paths

### 13.1 Proposals

- **Who can propose:** any MiFren holder with live voting power. A proposal names
  the token, ticker, metadata source, collection size and mint-out volume target.
- **Voting:** weight is the caller's **checkpointed** power at the proposal's
  snapshot block, so transferring frens to a fresh wallet after the snapshot
  cannot mint new votes. One vote per address per proposal.
- **`VOTING_PERIOD = 3 days`.** Votes close **before** a proposal becomes eligible
  to win, which removes the last-instant front-run of a permissionless relaunch.
- **Bounded leader selection.** A live leader/runner cache is backed by an
  eight-slot, vote-priced bench. The fallback never scans the proposal list, so
  gas-only proposal spam cannot push an already-supported mandate out of a
  positional window or raise rebirth cost without bound.
- **Untrusted input is bounded at the boundary.** A proposal's collection size is
  validated on submission and clamped again at launch, because a revert deep
  inside `relaunch()` would roll back the "consumed" mark and let a poisoned
  proposal win forever.

### 13.2 The timelock

An OpenZeppelin `TimelockController` — an audited standard, not an upgradeable
proxy — owns the hook and the perp engine and is the registry's **immutable**
emergency admin. Every parameter, policy and custody action is
**schedule → wait → execute**.

### 13.3 Guarded custody actions

| Action | Guard |
| --- | --- |
| `emergencyWithdrawLP`, `emergencySweep` | armed + timelocked + guardian-vetoable |
| `migrateToSuccessor` | armed + timelocked + guardian-vetoable |
| `setClaimGate` (restricting only) | armed + timelocked |
| `setRedemptionPaused` | immediate — it only ever disables a flow |
| Hook controller swap | announced + a **7-day** delay that the owner cannot shorten |

The **guardian** can only ever *cancel* an armed action — never propose one, never
move funds. A pure-upside safety role.

**What `emergencyWithdrawLP` actually does, without euphemism.** It removes a
generation's liquidity and transfers **both legs — quote assets and tokens — to the
emergency admin**. `emergencySweep` does the same for the registry's loose ETH or
any ERC-20 it holds. These are genuine custody-removal powers over
protocol-owned liquidity, and the protocol should not be described as having
"no withdrawal path."

What makes them defensible rather than a rug switch:

- **The admin is immutable.** It is fixed in the constructor and there is no
  setter, so it cannot be re-pointed at a fresh wallet after the fact. It is the
  governance timelock.
- **They are announced and delayed**, so the intent is public on-chain before
  anything moves — and **vetoable** by the guardian during that window.
- **Arming forces the exit open.** `_redeemBlocked()` returns false the moment
  `emergencyReadyAt != 0`, so the redemption circuit-breaker cannot be used to
  trap holders ahead of a custody move. Holders exit at the floor first.
- **They cannot reach your wallet.** No path here touches a user-held token or
  NFT; it is protocol-owned liquidity only.

**On the delay, and why arming is mandatory.** Arming is required for *every*
custody action, at any configured delay. That is deliberate and it is a fix: the
arm used to be skipped entirely when `emergencyDelay == 0`, which meant
`emergencyReadyAt` was never set — and since the forced-open exit is keyed on
exactly that variable, a zero-delay deployment silently had **no exit guarantee at
all**. The arm now decides whether the window *exists*; the delay decides how
*long* it is. A zero delay degrades the window to a transaction boundary instead
of deleting it.

**Still verify per deployment rather than assume.** `emergencyDelay` is
`immutable`, so only a redeploy changes it — a non-zero value is what turns the
window from a transaction boundary into real time to act. Read
`emergencyAdmin()`, `emergencyDelay()`, `guardian()` and `owner()` on the live
registry, and check that `owner()` is the timelock rather than a contract that
cannot forward calls.

The hook's `registry` pointer is **one-shot**; the upgrade path replaces it only
through the announced 7-day process, and **flushes the accumulated fee reserve to
the outgoing registry first**, so a controller swap can never capture ETH the
previous controller accrued.

### 13.4 Upgrading without a proxy

The money contracts are not upgradeable. Instead, the *rules* are pluggable, and
every module is a clamped, fallback-guarded view that can never move funds:

- `IDeathChecker` — the death rule.
- `ISurtaxPolicy`, `IOddsPolicy`, `ICurvePolicy` — the launch and gacha curves.
- `IFeeRouter` — the fee **split structure**. The router only returns amounts; the
  hook does the sends and falls back to the built-in split on any mismatch, so
  swapping it never exposes a fund-flow.

### 13.5 V2 handoff

`setSuccessor` then `migrateToSuccessor` hands the live liquidity to a V2
controller by **transferring the position NFTs' ownership** — not by withdrawing
them. Price and liquidity are completely untouched; only the owner of record
changes. On a progressive generation the seeder is unwound in the same
transaction, so both ledgers move together and nothing is stranded behind the
outgoing controller.

### 13.6 The delegatecall facet

`CauldronRegistry` is within a few hundred bytes of the EIP-170 24,576-byte
contract-size limit, so the OG-redemption operations live in `RedemptionExt`, which
the registry **delegatecalls**. The facet runs against the registry's storage and
custody, so semantics are byte-for-byte what a monolith would do.

This is only safe because the two contracts' storage layouts are **identical**.
Both derive from `CauldronBase` and add no state of their own, which makes the
layouts identical *by construction* rather than by discipline — verified
mechanically at 53 entries matching in label, slot, offset and type. The three
former immutables (`poolManager`, `positionManager`, `hook`) are deliberately
**storage**, because an immutable lives in the executing contract's own code and
would read as zero inside the facet.

### 13.7 Treasury quote rotation

Treasury rotation has its own `TreasuryGovernor`; it does not reuse the brew-name
governor. A proposal is an **envelope**: permission to move up to a budget of the
current generation's liquidity into one destination quote before an expiry.

- **Only genesis votes count.** Opening a proposal requires 5 live votes; ballots
  use snapshot voting power and passage requires a strict majority plus 10% of
  the snapshot genesis voting supply.
- **Mainnet defaults are immutable per deployment:** 3-day vote, 3-day execution
  window, 30-day envelope lifetime and 7-day cooldown. Testnet deployments may
  use shorter constructor values, so clients read the getters instead of
  hard-coding this prose.
- **The vote cannot widen the asset or venue allowlists.** The timelock admits
  quote assets, the oracle must be able to price a target, and the
  `QuoteRotator` owner admits swap venues. These checks run again at execution
  and movement time.
- **Execution is permissionless and atomic per slice.** `rotateSliceFrom` removes
  at most 25% of the selected live leg, swaps only its quote side with a
  caller-supplied `minOut`, folds any existing destination leg into one tracked
  position, and redeploys immediately. A failed slice consumes no envelope.
- **The envelope is a spend budget, not a percentage of the original position.**
  The hard maximum is 30,000 bps; twelve 25% slices move about 96.8% because each
  slice applies to what remains. Secondary-leg rebalancing cannot consume or
  falsely complete the primary mandate.
- **Redenomination is explicit.** A budget below 10,000 bps is partial and never
  changes `generationQuote`. When a whole-position mandate is exhausted against
  the leg holding the current denomination, the registry changes the quote and
  best-effort re-syncs the empty perp engine in the same transaction. Rotation
  back to native quote and rotation from an already-rotated leg are both built.
- **Liveness.** The guardian can cancel but cannot redirect. An envelope with
  zero progress stops blocking replacement after one cooldown; any successful
  slice makes it non-stalled. Spent envelopes deactivate immediately rather than
  suppressing new proposals until their nominal expiry.

Every rotated leg is recorded and recovered at rebirth. A geometric migration
can leave a small tail in an older pair; that tail remains tracked liquidity, not
a claim that the denomination changed with literally 100% of value converted.

---

## 14. Deployment and verification

**Addresses are intentionally not hard-coded in this document.** They rotate every
round, and iteration-specific addresses rotate at every rebirth. The docs page
renders the live set directly from the same manifest the application reads.

- **The canonical manifest** is `indexer/deployments/round.json`. It physically
  lives inside `indexer/` because the deploy tooling only uploads that directory,
  and both the frontend and the indexer read it — so the two can never drift.
- **Iteration-specific addresses** (token, collection, vault, pool id) come from
  the registry at runtime: `currentToken()`, `currentGeneration()`,
  `generationCollection(gen)`, `generationPoolId(gen)`.

**Build and test.** Foundry, `FOUNDRY_PROFILE=cauldron`. The profile uses
`via_ir = true` with `optimizer_runs = 1` — that configuration is load-bearing for
deployability. The current size audit reports the hook with only tens of bytes of
margin, the registry with hundreds, and the refactored engine with about 1.3 KB;
all numbers are profile-dependent and must be re-measured before deployment.

**Test coverage.** The repository contains unit, adversarial regression, fuzz,
handler-driven invariant and fork suites that drive **live Uniswap v4** on an
Ethereum-Sepolia fork. Exact test and suite counts change with every audit pass,
so the source tree and current test runner output — not a copied count here — are
the authority. Fork suites no-op without an RPC configured.

**Audit.** The system has been through multiple internal and adversarial audit
passes against its target L2 semantics. Reports, ledgers and executable proofs of
concept live under `audit/`, `contracts/solidity/audit/` and the adversarial test
tree; those artifacts describe review coverage, not a third-party certification.

---

## 15. Security posture and known limitations

Stated plainly, because a docs page that only lists strengths is not documentation.

### 15.1 Properties that hold structurally

These are not enforced by careful bookkeeping — the code cannot express the
violation:

- **Supply is fixed.** No mint function exists. Only a burn, which shrinks supply.
- **Token addresses are unpredictable.** Plain `CREATE`, so the next generation's
  address derives from the registry's own nonce and cannot be squatted.
- **The seeder can never reach the reserve.** It places core positions it owns
  itself; there is no code path by which it names the registry's reserve position.
- **Registry and facet layouts are identical.** By construction, and verified.
- **One relaunch clears the whole perp book.** The position cap is strictly below
  the force-close bound.
- **Migration is 1:1 or it reverts.** A short reserve rolls the burn back.

### 15.2 Known limitations

| Limitation | Status |
| --- | --- |
| **Reserve ceiling** — appreciating past ~69× closes migration and every floor until the next iteration (§7.4). | Open. Mitigate by choosing the ceiling per iteration; check `floorClaimableNow()`. |
| **Gacha and rarity randomness** rest on `blockhash`, which Arbitrum documents as insecure and explicitly warns against (§10.3). | Open on L2. Verified against the target chain before the gacha is enabled there. |
| **Rarity reveal is not seed-pinned.** On a ~0.10 s chain, missing two 256-block windows commits Common (§10.4). | Open. Only the holder can reveal; do it immediately after mint. |
| **Anti-snipe surtax is block-denominated**, so on an L2 its decay is a ~12-second step function rather than a smooth ramp. | Accepted. The window keeps its intended wall-clock length; only resolution is lost. |
| **The TWAP floor (`MIN_TWAP = 1 s`)** is not a meaningful manipulation defence on a sub-second-block chain. | Configuration. `twapWindow` is set from real pool depth, never near the floor. |
| **Funding is not strictly zero-sum** — an insolvent payer pays less than it owes while the receiver draws in full, from insurance first. | Bounded. The funding rate is capped, as is per-position funding P&L. |
| **Partial short rebooking erases collateral-based economics** — future funding, final penalty and keeper bounty become zero (§11.3). | Open code defect in `_rebook`; solvency backing remains, but incentives/accounting do not. |
| **Pre-trade liquidation can require millions of gas.** A four-short measured cascade needed about 3M gas; fixed-cap routers may see `LiqGasStarved`. | Safety trade-off: the swap reverts instead of externalizing bad debt. Wallet estimation should find the required gas. |
| **The default live-buyback threshold is denomination-unsafe** for 6-decimal quotes (§5.2). | Open. `0.02 ether` becomes an unreachable 20-billion-token raw threshold on USDG. |
| **The old ETH vault can be donation-rearmed** despite the unified-floor configuration, and burning there desynchronizes the ledger denominator (§5.4). | Open. Do not send ETH to per-brew vaults; use the registry's token-floor recycle path. |
| **Progressive seeding is dormant** while `SEED_BASE_WAD = 1e18`; wiring a seeder and a window does not activate it (§4.2). | Shipped configuration. Launches use the atomic green-candle path. |
| **A completed quote migration leaves a geometric tail** in the previous pair because each slice removes a fraction of what remains (§13.7). | Accepted and tracked. Every leg, including the tail, is recovered at rebirth. |
| **The unrevealed placeholder URI is deployer-settable.** Final revealed art remains on-chain, but the temporary shared image is an operational metadata pointer. | Deliberate escape hatch from a metered endpoint; deployments should point it at IPFS/Arweave. |
| **EIP-170 headroom is thin and profile-dependent** — especially the hook; the registry is also close, while the refactored engine has roughly 1.3 KB in the latest size ledger. | Process risk. The mainnet deploy performs a clean-build size gate. |

### 15.3 What governance can and cannot do

**Can:** tune fees, risk parameters, the death rule, the launch curves and the fee
split structure; pause redemption; hand off to a V2 controller; and — through the
announced, delayed, guardian-vetoable break-glass — **remove protocol-owned
liquidity and sweep the registry's balances to the emergency admin** (§13.3).
That last one is a real custody power and is listed here deliberately.

**Cannot:** mint tokens, freeze balances, pause transfers, or touch any token or
NFT held in a user's wallet; drain the perp vault (re-pointing it is blocked while
it holds funds); shorten its own announced delays; or use the redemption pause to
trap holders ahead of a custody move — arming forces that exit open.

---

## 16. Portability: what the protocol assumes about a chain

**Hard requirements — two.** `EIP-1153` transient storage, because Uniswap v4
settles every `unlock` through `TSTORE`/`TLOAD` and this protocol *is* a v4 hook;
and a **CREATE2 factory**, because the hook's permission bits are encoded in its
address, so the address must be mined. Everything else below is a difference the
code is already written against rather than a requirement.

**Native gas token — not assumed to be 18-decimal ETH.** Arc's is
USD-denominated. Two consequences, both load-bearing:

- The oracle prices such a native asset by **peg**, not by feed — there is no
  exchange rate to observe, and a Chainlink address from another chain is a
  codeless address whose revert `QuoteOracle` degrades to `0` ("cannot judge").
  That would make the hook record **zero volume for every trade**, which silently
  breaks the mint ladder *and* makes `isDead` read a busy generation as dying.
- A **6-decimal** native would be a genuine blocker, not a config change:
  `PoolOps._sqrtPrice` cannot represent a quote below `TOTAL_SUPPLY / 2^64`, which
  at 6 decimals is ~674 raw units — so an ordinary seed would brick the launch
  behind `markConsumed`. Verify decimals before deploying; Arc's gas token is
  USD-denominated but **18**-decimal, which is why it ported cleanly.

**Block semantics on L2s.** Four differences are load-bearing on rollups, and the
code is written against them:

- **`block.number` is the parent chain's number**, updating only periodically —
  it is constant across the many sub-second child blocks inside one parent block.
  The protocol therefore denominates its **death clock in wall-clock seconds**, not
  blocks. A block-denominated 24-hour window would have meant roughly 30 minutes on
  a fast chain, letting any passer-by retire a healthy token an hour after launch.
- **`block.timestamp`** comes from the sequencer's clock per child block. Every
  time-sensitive guard — the volume window, funding, the TWAP, the liquidation
  throttle, vesting, the seed schedule — is keyed on it.
- **`prevrandao` and `difficulty` return the constant 1.** The surtax jitter does
  mix `prevrandao`, but on these chains it contributes no entropy; the previous
  blockhash is the remaining variable input.
- **`blockhash`** is documented as insecure pseudo-randomness that does not come
  from L1. This is the basis of §15.2's open randomness item.

Also relevant: the sequencer is single and **first-come, first-served** — there is
no priority gas auction, so transaction ordering is a matter of arrival time rather
than fee bidding. Transaction cost has an L1 calldata component on top of L2
execution gas, which is why the gas reserves that bound the hook's optional
side-effects are re-tuned per chain.

---

## 17. Risks (read before you ape)

- **Experimental DeFi.** Despite audits, invariant testing and extensive fork
  tests, bugs can exist. Do not risk funds you cannot lose.
- **Testnet parameters are not production parameters.** Thin liquidity, short death
  windows and low warmups are tuned for *testing*.
- **Token death is a feature.** An iteration is *designed* to die when volume dries
  up. If you hold and do not migrate, your vintage token may become illiquid.
- **The reserve ceiling.** See §7.4 — a large enough pump closes migration and the
  floors until the next iteration.
- **Leverage.** Perps liquidate. Liquidations are real swaps and move the price; a
  thin pool moves hard.
- **The gacha is a lottery.** Crystals miss. Odds scale with play size; pity caps
  the pain but guarantees nothing about profit.
- **Governance powers.** Parameters are timelock-tunable. On mainnet those roles
  sit behind a multisig with a longer delay; on testnet a single key holds them.
- **Migration is opt-in.** You must actively migrate, or opt into auto-migrate, to
  follow the machine forward.
- **List NFTs above the floor.** A below-floor listing is free money for arb bots
  (§7.2).

---

## 18. Glossary

- **Iteration / Generation** — the current live token in the eternal cycle.
- **Summon** — deploy and seed a new iteration.
- **Relaunch / Rebirth** — retire the dead token, recover liquidity, summon the next.
- **Genesis fren** — one of the OG NFTs (ids `1..1111`): electorate, fee class, floor class.
- **Forged fren** — a volume-minted MiFren (ids `1112..2222`).
- **Cast the spell / Enchant** — switch a fren's fee-earning on.
- **Ledger A / Ledger B** — the tradeable active band / the out-of-range reserve.
- **Reserve ceiling** — the price above which the reserve stops delivering tokens (§7.4).
- **Crystal** — a gacha ticket. Not an NFT; a win mints one.
- **Green candle** — the real first-block market buy that funds a new reserve.
- **Progressive seed** — streaming the active tranche in over a launch window.
- **PLV** — the community Perp Liquidity Vault (two-sided: ETH and token).
- **Guild share** — the slice of each swap fee sent to the genesis dividend.
- **Death threshold** — the 24-hour volume floor below which a token can be reborn.
- **Liquidatoor badge** — a trophy NFT minted to whoever triggers a liquidation.
- **Materialize** — deposit the hook's held buyback tokens into the reserve and credit the ledger.

---

## 19. FAQ

**Q: What is the difference between a genesis fren and a forged fren?**
A: Genesis frens are ids `1..1111`, sold at launch. They vote, they earn the
dividend, and they have a redemption floor. Forged frens (`1112..2222`) are minted
by trading volume; they can enchant to earn (paying the re-enchant fee) but they do
not vote and they have a *collection* floor rather than the genesis one.

**Q: How do I earn fees?**
A: Hold a fren and call `castSpell(tokenId)`. You earn from that moment on — there
is no back-pay. Selling breaks the bond; the new owner must re-cast.

**Q: What happens to my tokens when an iteration dies?**
A: Nothing forced. Keep trading the old token, or burn it 1:1 for the new one, or
opt into auto-migrate (free for frens, else 0.069 ETH).

**Q: Is the token mintable or freezable?**
A: No. Supply is fixed at 777,000,000 and minted once; there is no mint function
and no pause, freeze or blocklist. Only a registry burn that shrinks supply exists.

**Q: How much are the fees?**
A: 3% by default (owner-tunable, capped at 10%), plus a decaying anti-sniper
surtax over a deployment-configured block window. The contract starts at 30
blocks, while the default Launchpad wiring sets 75 from its 900-second seed window
and 12-second parent-block assumption. The Uniswap LP fee tier is 0. Of the
quote-side fee, 0.5% goes to the iteration's proposer and 15% to the genesis
dividend before the rest splits between the collection floor and the relaunch
reserve.

**Q: Can the team rug?**
A: Answered honestly, because the naive version of this answer is wrong.

**Nobody can touch what is in your wallet.** Governance cannot mint, cannot
freeze, cannot pause transfers, and has no path to move tokens or NFTs you hold.

**Protocol-owned liquidity is a different question.** A break-glass path exists:
`emergencyWithdrawLP(gen)` removes a generation's LP and sends both legs to the
emergency admin, and `emergencySweep` takes the registry's loose ETH or an ERC-20.
Anyone claiming this protocol has "no withdrawal path" has not read the code.

What constrains it:
- The admin is **immutable**, fixed at construction — it cannot be re-pointed at
  a fresh wallet later. It is the governance timelock.
- Actions are **announced and delayed** (`armEmergency` → wait `emergencyDelay` →
  execute), so the intent is on-chain before anything moves.
- An independent **guardian can veto** during that window. The guardian can only
  ever cancel — it can never propose or move funds.
- Arming **forces the redemption exit open**: the pause is overridden the instant
  an action is armed, so holders can redeem at the floor *before* anything moves.

**Verify it yourself rather than trusting this page.** Read `emergencyAdmin()`,
`emergencyDelay()` and `guardian()` on the live registry. `emergencyDelay` is
immutable — a `0` there does not remove the exit guarantee (arming is mandatory
regardless), but it does shrink the window to a transaction boundary, and only a
redeploy changes it. That is exactly the check we would want you to run.

**Q: What are the odds in the crystal gacha?**
A: Up to 90%, scaling linearly with normalized play size, with a guaranteed win
after 8 consecutive misses. The raw no-oracle contract default reaches the cap at
`0.5 ether` raw units (economically 0.5 only for an 18-decimal quote); the
oracle-enabled launch-script default is $1,200. Rarity
on reveal is 79 / 15 / 5 / 1 for
Common / Rare / Epic / Ultra. Resolve promptly: a normal resolver call pins the
commit seed forever, but an entirely untouched batch has only one expiry
re-anchor before its non-pity rolls are forfeited.

**Q: How much leverage can I use?**
A: 2× to 5× depending on pool depth, capped by a governance ceiling (currently 3×).
Open fee is 6.9% of collateral, halved for genesis holders; liquidation penalty is
6.9%.

**Q: Is there an oracle?**
A: No external oracle. Liquidation marks use the engine's own on-chain TWAP of the
pool (5-minute window by default); spot is used only for execution.

**Q: Why did my redemption or migration revert?**
A: Most likely the token has traded above its reserve ceiling — see §7.4. Check
`floorClaimableNow()`. Nothing is lost; the exit reopens at the next iteration.

---

*gm fren. The Cauldron stirs. wagmi.* 🔮
