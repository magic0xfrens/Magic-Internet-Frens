<div align="center">

# 🧙‍♂️ Magic Internet Frens

**2222 on-chain pixel wizards, and the eternal token machine they govern.**

*The Cauldron is a Uniswap v4 hook that launches a token, lets the market trade it,
notices when it dies, recovers the liquidity, and launches the next one — forever,
funded entirely by its own swap fees.*

[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-2A1F54)](contracts/solidity)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4%20hook-d5fd51)](https://docs.uniswap.org/contracts/v4/overview)
[![Tests](https://img.shields.io/badge/forge%20test-322%20passing-brightgreen)](contracts/solidity/test)
[![Network](https://img.shields.io/badge/live-Sepolia-blue)](https://sepolia.etherscan.io)

[Website](https://www.mifrens.xyz) · [Docs](https://www.mifrens.xyz/#/docs) · [X](https://x.com/magic0xfrens)

</div>

---

## Table of contents

- [What this actually is](#what-this-actually-is)
- [Why a hook and not a router](#why-a-hook-and-not-a-router)
- [Architecture](#architecture)
- [The eternal cycle](#the-eternal-cycle)
- [Launch mechanics](#launch-mechanics)
- [The money map](#the-money-map)
- [Floors: what backs a fren](#floors-what-backs-a-fren)
- [The crystal gacha](#the-crystal-gacha)
- [Perps](#perps)
- [Governance and custody](#governance-and-custody)
- [Repository layout](#repository-layout)
- [Quickstart](#quickstart)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security posture](#security-posture)
- [gm fren](#gm-fren)

---

## What this actually is

Most "launchpads" are a factory contract and a frontend. The Cauldron is a **state
machine that lives inside a Uniswap v4 pool** and refuses to die.

The loop, in one paragraph: 1111 genesis MiFrens are sold. Every wei of that sale
is forwarded — with no owner withdraw path — into the first pool. That pool trades
an iteration token with a fixed supply of 777,000,000. Swaps pay a fee in ETH,
which funds a genesis dividend, a collection floor, and the next launch. When the
pool's rolling 24-hour volume drops below a threshold, it is **dead**: governance
has already picked a successor, so anyone can permissionlessly call `relaunch()`,
which recovers the liquidity, burns the recovered tokens, and summons the next
iteration in the same transaction. Holders migrate 1:1. Then it happens again.

Three properties make it more than a gimmick:

1. **It is self-funding.** No team treasury tops it up. Rebirth liquidity comes
   from fees the previous iteration already earned.
2. **100% of supply reads as liquidity.** The migration supply, the genesis floor
   and every collection's entitlement live in a single-sided v4 position parked
   *out of range* below spot. There is no whale-looking treasury wallet — and none
   of it is sellable, because it only leaves against a burn or a debited claim.
3. **Value survives the reset.** Each iteration's NFT collection keeps the floor
   its own volume earned, forever, through every future rebirth.

### At a glance

| | |
| --- | --- |
| **Genesis frens** | 1111 (`tokenId 1..1111`) — electorate + perpetual fee class |
| **Total collection** | 2222 (the rest are forged from volume) |
| **Iteration token** | 777,000,000 fixed, non-mintable, non-freezable |
| **Swap fee** | 3% in ETH (hard cap 10%); Uniswap LP tier is 0 |
| **Genesis dividend** | 15% of every fee, forever |
| **Contracts** | 32 Solidity files, ~10,800 lines (26 of them contracts + libraries) |
| **Tests** | 322 passing across 66 suites |
| **Live on** | Ethereum Sepolia · target: Robinhood Chain (Arbitrum Orbit) |

---

## Why a hook and not a router

Everything interesting happens **inside the swap**, in `beforeSwap` / `afterSwap`.
That is not an aesthetic choice — it is what makes the mechanics non-bypassable.

A router-based design can always be sidestepped: trade directly against the pool
and you skip the fee, the volume accounting, and the gacha. Because the logic is a
hook, **a raw Uniswap swap from any aggregator is charged, counted, and can forge
an NFT**. There is no privileged path and no way around it.

It also means leverage moves the real chart. A perp open is an actual pool swap
with actual price impact, not a bet settled against an oracle.

### The re-entrant spine

One user swap can reach five contracts inside a single `PoolManager` unlock:

```
user swap
  └─ CauldronHook.beforeSwap          charge the ETH fee on buys
  └─ PoolManager executes the swap
  └─ CauldronHook.afterSwap
       ├─ legacy buyback              nested swap, buys the token back
       ├─ CauldronSeeder.pokeInSwap   streams the next liquidity sliver
       ├─ PerpEngine.sweepLiquidations  real settlement swaps, in-lock
       ├─ native gacha step           commits + resolves crystals, may mint
       └─ charge the ETH fee on sells
```

Every side-effect is **gas-bounded and result-ignored**: called with a reserved
budget, failure swallowed. An optional step can never revert a user's swap or run
it out of gas. Each participant settles its own Uniswap deltas in its own frame.

### The two ledgers

The single most load-bearing decision in the protocol.

- **Ledger A — the active band.** Tradeable depth. Either one full-range position
  (atomic launch) or the seeder's distributed mini-positions (progressive launch).
- **Ledger B — the reserve.** A single-sided token position parked **out of range,
  below spot**. Holds the migration supply, the genesis floor, and every
  collection's legacy entitlement. It leaves *only* against a 1:1 migration burn or
  a properly-debited floor claim.

The seeder can only ever touch ledger A. It has no code path that names the
registry's reserve position.

---

## Architecture

Twenty-six contracts and libraries across `contracts/solidity/`. Three are
re-entrant by design, and that is where the interesting behaviour lives.

| Contract | Role |
| --- | --- |
| `CauldronRegistry` | The brain. Summon, relaunch, migration, LP custody, emergency paths. Owns both v4 positions. |
| `CauldronHook` | The v4 hook. Fees, volume, death detection, gacha, seeder nudges, liquidations. |
| `PerpEngine` | Hook-native longs and shorts. Executes real pool swaps from inside `afterSwap`. |
| `RedemptionExt` | A **delegatecall facet** of the registry holding OG-redemption ops. Split out for EIP-170 headroom. |
| `CauldronBase` | **Shared storage** for the registry and its facet. Layouts must be byte-identical. |
| `PoolOps` | Linked library: all v4 PositionManager encoding. Delegatecalled, so it runs *as* the registry. |
| `CauldronSeeder` | Progressive launch liquidity, placed via **core** `modifyLiquidity` so it can run inside a swap. |
| `CauldronGovernor` | Permissionless proposals, checkpointed MiFren voting, 3-day window. |
| `MiFrensGenesis` | Genesis collection: ERC721 + ERC721Votes + ERC-721C, plus ignition. |
| `MiFrensDividend` | The perpetual genesis fee dividend ("cast the spell"). |
| `CauldronCollection` | Per-iteration ERC-721C volume collection. |
| `CollectionLedger` | Cap table for per-collection token floors. |
| `MigrationVesting` | Optional anti-dump escrow that drips 1:1 migration claims. |
| `PerpVault` | Two-sided community perp liquidity vault (ETH side + token side). |
| `CauldronGachaRouter` | One-click play: swap, tag the buyer, commit and resolve crystals. |
| `CauldronFactory` | Deploys each brew's collection and vault. |
| `ReserveLib` / `SeedLib` | Pure math: reserve ticks and liquidity; stream schedule and band geometry. |
| `TimelockController` | OpenZeppelin's audited timelock. Owns the hook and engine; registry's emergency admin. |

**Why the facet split.** `CauldronRegistry` hit the EIP-170 24KB bytecode limit.
Rather than reach for an upgradeable proxy, storage moved into `CauldronBase` and
redemption into `RedemptionExt`, reached by `delegatecall`. Storage layout is
pinned by [`docs/registry-storage-baseline.txt`](docs/registry-storage-baseline.txt)
and asserted every run by `FacetLayoutInvariant`. One gotcha worth knowing:
`immutable` values live in bytecode, not storage, so they do **not** survive a
`delegatecall` into the facet.

---

## The eternal cycle

### Ignition

`MiFrensGenesis` sells the genesis tranche. On sellout, `finalize()` forwards the
**entire** contract balance to `CauldronRegistry.summon()`. There is no owner
withdraw path — the ETH has exactly one exit, into the first pool.

Two safety valves: a `finalizer` role can restrict who calls `finalize()` so the
atomic summon-and-buy can't be front-run, and `cancelPresale()` + `refund()` lets
every minter reclaim 100% of their ETH if the sale never sells out.

### Summon

In one transaction, the registry:

1. Deploys a fixed-supply `CauldronToken` with **plain `CREATE`** — deliberately
   not `CREATE2`. A `CREATE2` address keyed on the generation number would be
   predictable, so anyone could squat it and permanently brick relaunch.
2. Sizes the genesis bonus and OG airdrop reserve.
3. Creates the v4 pool and seeds **both** ledgers.
4. Optionally spends owner-provided prime-buy ETH on a real first-block buy.
5. Deploys the iteration's NFT collection and points the hook at it.

### Life

Swaps pay an ETH fee. Volume accrues crystal credit. Perps open against real
depth. The hook records volume into **24 hourly buckets on a rolling wall-clock
day**.

### Death

`isDead(poolId)` is true when rolling 24h volume falls under `deathThreshold`. The
window is denominated in **seconds, not blocks** — which matters enormously on the
target L2, where `block.number` is the *parent chain's* number and a
block-denominated window would mean something entirely different.

The rule is **pluggable**: an `IDeathChecker` module can replace it (unique
traders, depth, a schedule) with no upgradeable proxy. A reverting module falls
back to the built-in rule, so it can never brick a relaunch.

### Rebirth

`relaunch()` is **permissionless** and takes no parameters:

1. Verify the pool is dead and `minLifetime` has elapsed — a grace period so a
   brand-new pool reading "dead" at zero volume can't be killed before it trades.
2. Require a settled winning governance proposal. **No silent fallback** — rebirth
   is governance-gated.
3. **Force-close every perp** while the old pool is still alive, oldest-first and
   deterministic, so settlement swaps still have a market.
4. Recover ETH and tokens from both positions (unwinding the seeder on a
   progressive generation), then **burn** the recovered tokens.
5. Drain matured gacha tickets so pending winners mint while the floor is funded.
6. Close the dying vault and pull the hook's accumulated fee reserve.
7. Launch the winner: deploy the token, record the proposer, seed both ledgers.
8. Re-arm the perp engine on the new token, migrating inventory 1:1.

Steps 3, 5 and 8 are **best-effort with reserved gas** — a full perp book or a
large ticket backlog can never starve the rebirth. Leftovers are cleared by
permissionless keeper paths.

> **Iteration #2 is special.** It does not deploy a fresh collection — it
> *continues the genesis MiFrens*, minting the forged tranche (`1112..`) from
> volume. The hook anchors the rising mint curve to the collection's current
> `totalMinted`, so pricing starts at curve position zero even though 1111 exist.

---

## Launch mechanics

Two seeding paths, chosen by governance before the summon.

**Atomic — the green candle (default).** The reserve is minted into existence with
a real market buy, entirely inside the launch transaction, so nothing can front-run
it and the chart opens with a genuine candle rather than a silent parked bag.

**Progressive — the streamed seed.** `CauldronSeeder` places liquidity as a series
of fresh single-sided positions, streamed **in-swap** via core `modifyLiquidity`.
No keeper: each swap nudges the seeder forward. The in-swap poke enforces a **gas
floor** so it only fires when it can complete — a half-finished poke would corrupt
the book. A two-sided base is established automatically at summon so perps work on
a progressive generation from the start.

**Anti-snipe.** A launch surtax decays over an opening window, so a first-block
sniper pays materially more than an organic buyer.

---

## The money map

Every swap pays a fee **taken in ETH**, on both legs — the protocol never accrues
value in a token that is about to die.

- **Uniswap v4 LP fee tier: 0.** The LP is protocol-owned and recovered at
  relaunch, so a second LP tax would be redundant. Traders pay only the hook fee.
- **Hook fee: 3%** (`defaultTaxBps = 300`), owner-tunable, hard-capped at 10%.
- **Buys** are charged in `beforeSwap` (skim ETH off the input). **Sells** in
  `afterSwap` (skim ETH off the output).
- **Exact-output sells revert** (`ExactOutSellUnsupported`). That is the one swap
  quadrant where the unspecified currency is the token, so v4's return-delta
  mechanism physically cannot take an ETH fee. Rather than serve it free, the hook
  refuses; the exact-input sell is economically identical and unaffected.

The rate is resolved for the **trader**, not the router — trade through the gacha
router or an aggregator and you still get your own tier. Only a trusted opener may
name a different player in `hookData`, which is what stops anyone tagging an exempt
address to dodge the fee.

### How an ETH fee splits, from the top

| Slice | Default | Goes to |
| --- | --- | --- |
| Proposer | 0.5% (`proposerBps = 50`) | Author of the winning proposal — **pull**, never pushed |
| Guild | **15%** (`guildBps = 1500`) | Genesis dividend |
| Legacy buyback | 40% of the remainder | Market-buys the live token to back the collection floor |
| Floor share | 100% of what's left | Joins the buyback buffer (see below) |
| Relaunch reserve | remainder | Funds the next rebirth's liquidity |

The proposer slice is a pull, not a push, for a specific reason: `activeProposer`
is attacker-controlled, and pushing would put an untrusted external call in the
swap hot path. A rejecting sink never bricks a swap — its share rolls into the
relaunch reserve.

**Royalties.** Secondary sales pay 5% (EIP-2981 + ERC-721C enforcement). Genesis
royalties go to the dividend; volume-collection royalties route through
`RoyaltyRouter` into the buyback buffer, backing that collection's own floor.

**Perp fees route differently:** 30% to the genesis dividend, 70% to perp stakers,
side-attributed — buys credit the ETH side, sells the token side.

---

## Floors: what backs a fren

### The genesis dividend

Genesis MiFrens share every iteration's fees, forever. A holder **"casts the
spell"** to switch their fren's earning on; transferring it breaks the enchantment
(re-enchanting costs a fee). This is a real founder's cut — the OGs bootstrapped
the machine with their mint ETH.

### The genesis redemption floor

Each genesis fren has a live floor denominated in whatever token is running now,
and the design **ratchets it up**. Burn a fren, receive its share of the reserve.

> ⚠️ **Read this caveat, it is real.** The floor is claimable while the token
> trades below its per-iteration **reserve ceiling**. Above the ceiling, claims
> are bounded. The mechanism, the exact bound and the reasoning are documented in
> §7.4 of the [full spec](src/components/docs/magicfrens-llm.md).

A **timelock-gated circuit breaker** can pause redemption, and arming the
emergency path **forces the redemption exit open** so holders can leave first.

### Collection floors

Every iteration's collection earns a token-denominated floor from its own volume
and royalties, and keeps it **forever** through every future rebirth.
`CollectionLedger` is the cap table. Recycle an NFT to claim its share; a
treasury buy at 2× grows the floor for everyone still holding.

Because the floor is funded by an in-hook live buyback rather than a keeper, it
accrues during the generation's life, not only at its death.

---

## The crystal gacha

Trading volume forges NFTs, through a commit-reveal roll.

1. **Trade.** Volume banks credit — **buys weighted 1.5×, sells 0.5×**. Buying
   pressure is rewarded.
2. **Commit crystals.** Credit is spent along a rising price curve, enqueuing a
   ticket batch. Nothing mints yet.
3. **Resolve.** Each ticket rolls from its **commit block's hash** — a value that
   did not exist when you played. A win mints; a miss builds your pity counter.
4. **Reveal.** A minted NFT arrives **unrevealed**, showing a shared placeholder.
   `reveal(tokenId)` rolls rarity from the mint block's hash and flips the art.

> **Crystals are tickets, not tokens.** A "sealed crystal" is accounting inside the
> hook, not a tradeable ERC-721. What *is* tradeable is the unrevealed NFT you
> receive on a win — a real ERC-721 with a placeholder image until revealed.

Max win chance from bet size is capped at 90%, with a pity counter for the unlucky.

**Grind resistance.** On an L2 sequencer, naive `block.prevrandao` entropy is
grindable. Randomness is derived from a commit block hash that postdates the
player's decision, and the limits of that guarantee are documented rather than
hand-waved.

---

## Perps

Leveraged **longs and shorts** on the live iteration token. Every open, close and
liquidation is an **actual Uniswap v4 swap**, so leverage moves the real chart.
**No external oracle.**

### Leverage tiers

Max leverage is the **minimum** of a depth-based tier and a governance ceiling
(currently **3×**).

| Active ETH depth | Tier |
| --- | --- |
| `< 25 Ξ` | 2× |
| `25 – 100 Ξ` | 3× |
| `100 – 300 Ξ` | 4× |
| `300 Ξ +` | 5× |

### Risk parameters

| Parameter | Default |
| --- | --- |
| Open fee | 6.9% **of collateral** (genesis holders: half price) |
| Liquidation penalty | 6.9% |
| Maintenance margin | 15% |
| Per-position notional cap | ≤5% of depth |
| Per-side OI cap | ≤30% of depth |
| Per-interval liquidation cap | ≤20% of depth |
| Funding rate | 1%/day at full imbalance, bounded |
| Minimum collateral | 0.003 ETH |
| Max simultaneous positions | 64 |

The open fee is charged on **collateral, not notional** — a notional fee would
start a 3× position roughly 20% underwater on day one.

### Mechanics worth calling out

- **Shorts are reflexive.** Opening sells borrowed token (price down); closing
  buys back *exactly* the borrowed size with an exact-output swap, so inventory is
  always made whole and the close is a real squeeze.
- **Two-sided community vault.** The ETH side fronts longs; the token side is lent
  to shorts. Token principal is structurally protected — a short's buy-back always
  returns inventory in full, so the ETH shortfall of a bad short is borne by the
  ETH side and the insurance buffer.
- **Insurance first.** Shortfalls hit an insurance buffer before depositor
  principal, and the buffer can't be skimmed below a minimum scaled to live OI.
- **Settlement can never be frozen.** If a payout can't be pushed, it is credited
  as a claimable balance instead of reverting — otherwise one hostile contract
  could make its own position unsettleable and strand the vault across a rebirth.
- **Liquidations mark off a TWAP** from the engine's own observation ring;
  execution still happens at spot. `warmup` gates *opening*, not liquidation, so
  the oracle has history before anything is marked against it.
- **No keeper required.** Normal swaps trigger liquidation sweeps, with a small cut
  to whoever's swap did the work.

---

## Governance and custody

Proposals are **permissionless**; voting is checkpointed MiFren ownership over a
3-day window. When the brew dies, the top proposal is summoned next.

**Break-glass, stated plainly.** There is no unilateral or instant team withdrawal.
There *is* a governed emergency path that can move protocol-owned liquidity. It is:

- restricted to an immutable admin (the governance timelock),
- announced and time-delayed,
- guardian-vetoable, and
- **arming it forces the redemption exit open**, so holders can leave at the floor
  first.

Nobody can mint, freeze, or remove tokens or NFTs from your wallet.

**Upgrades without a proxy.** Policy modules (`IDeathChecker`, surtax, odds, mint
curve, fee router) are swappable behind interfaces, so rules can change without
making the core contracts upgradeable. A reverting module falls back to built-in
behaviour rather than bricking the machine.

---

## Repository layout

```
contracts/solidity/
  cauldron/           the protocol — registry, hook, engine, seeder, ledgers
  test/               322 tests: unit, fork, invariant, adversarial, audit PoCs
  deploy/             Foundry deployment + operational scripts
  audit/              security audit reports (PDF + LaTeX source)
indexer/              Ponder indexer — the app's read layer
  deployments/        THE deployment manifest (frontend + indexer both read it)
src/                  React 19 + viem/wagmi frontend
  components/docs/    the full protocol spec, rendered at /docs
api/                  serverless routes (candles, docs assistant)
docs/                 design docs, runbooks, storage baselines
archive/              superseded code and docs, kept for reference
```

### One manifest, two consumers

`indexer/deployments/round.json` is the **single source of truth** for the live
deployment. Both the indexer (`ponder.config.ts`) and the frontend
(`src/config/cauldron.ts`) read the same file.

This is deliberate and load-bearing. When addresses were duplicated across the two
sides, they drifted on every redeploy — and the failure is silent: the frontend
reads one deployment while the indexer serves another, which surfaces as stale or
blank data rather than an error anyone notices. The manifest physically lives
inside `indexer/` because `railway up` only uploads that directory.

> **Never** duplicate these values as hosting env vars. An env override silently
> wins over the file, and the two drift the moment one is updated alone.

---

## Quickstart

**Prerequisites:** Node 20+, [Foundry](https://book.getfoundry.sh/getting-started/installation), git.

```bash
git clone --recurse-submodules https://github.com/magic0xfrens/Magic-Internet-Frens.git
cd Magic-Internet-Frens
npm install
```

Already cloned without submodules? `git submodule update --init --recursive`.
The Foundry dependencies (v4-core, v4-periphery, openzeppelin-contracts) are
**pinned to exact commits** — tracking branch tips breaks the build when upstream
moves.

### Run the frontend

```bash
npm run dev            # http://localhost:5173
```

It works with **zero configuration**: contract addresses come from the committed
manifest, and it falls back to the public indexer. Copy `.env.example` to
`.env.local` only if you want a dedicated RPC (recommended — public Sepolia nodes
rate-limit hard under a polling dApp) or your own indexer.

### Build the contracts

```bash
cd contracts/solidity
FOUNDRY_PROFILE=cauldron forge build
```

The `cauldron` profile is required: it enables `via_ir` (needed to compile v4's
PositionManager) and low `optimizer_runs` to keep the registry under EIP-170.

### Run the indexer

```bash
cd indexer && npm install && npm run dev
```

Defaults to in-memory SQLite. Set `DATABASE_URL` for Postgres.

---

## Testing

```bash
cd contracts/solidity
FOUNDRY_PROFILE=cauldron forge test
```

```
Ran 66 test suites: 322 passed, 0 failed, 2 skipped
```

| Suite | Covers |
| --- | --- |
| `test/*.t.sol` | Unit + integration: summon, launchpad, seeder, vesting, ledger |
| `test/invariants/` | System invariants, storage-layout, ledger and vesting fuzz |
| `test/attacks/` | Adversarial: CREATE2 squat, depth manipulation, relaunch gas-brick, fee bypass, governance lockout, L2 block-clock |
| `test/audit/` | Proof-of-concept exploits from audit passes |
| `test/final/` | Custody + consent, L2 semantics, reserve ceiling |

The **2 skipped** are fork-only invariants. Set `FORK_RPC` to an archive-capable
endpoint to run them:

```bash
FORK_RPC=$SEPOLIA_RPC_URL FOUNDRY_PROFILE=cauldron forge test
```

Frontend: `npm run type-check` (clean), `npm run lint`, `npm run test:unit`.

---

## Deployment

Live on **Ethereum Sepolia**. Addresses rotate every iteration and every rebirth,
so they are **not hardcoded in this README on purpose** — read them from the
manifest, or from the registry itself:

```solidity
registry.currentGeneration()          // which iteration is live
registry.currentToken()               // its ERC-20
registry.generationCollection(gen)    // its NFT collection
registry.generationPoolId(gen)        // its v4 pool
```

The [`/docs`](https://www.mifrens.xyz/#/docs) page renders live addresses from the
same manifest the app reads, and verifies them against the chain.

**Target chain: Robinhood Chain**, an Arbitrum Nitro/Orbit L2 with ETH as native
gas. `VITE_NETWORK` flips the whole app between testnet and mainnet in one env
change. The L2 semantics that actually matter — second-denominated windows,
grind-resistant randomness, per-timestamp liquidation throttling — are covered in
[`docs/ROBINHOOD_L2_REVIEW.md`](docs/ROBINHOOD_L2_REVIEW.md).

---

## Security posture

Three security reviews live in [`contracts/solidity/audit/`](contracts/solidity/audit)
as PDF reports with their LaTeX sources, alongside a Uniswap hook-allowlist brief.

Findings were fixed and, where possible, **pinned by a regression test** — the
`test/attacks/` and `test/audit/` suites are largely proof-of-concept exploits
that now assert the attack fails.

Documented hardening includes: CREATE2 squat prevention on relaunch, gas-bounded
re-entrant side-effects, O(n) deterministic force-close, exact-out sell fee bypass,
reserve ceiling enforcement, governance spam and lockout resistance, storage-layout
invariance across the delegatecall facet, and L2 block-clock semantics.

**Known limitations are documented rather than hidden** — see §15 of the
[full spec](src/components/docs/magicfrens-llm.md). If you find something, please
open an issue.

### Feed the whole thing to your AI

[`src/components/docs/magicfrens-llm.md`](src/components/docs/magicfrens-llm.md)
is the entire protocol in one self-contained document — every mechanic, fee split,
tier weight, parameter and limitation, written against the source rather than the
roadmap. It is published at [`/llms-full.txt`](https://www.mifrens.xyz/llms-full.txt)
and regenerated on every build, so it can't fall behind the code.

---

## gm fren 🐸

<div align="center">

**ser.** you have read this far. the wizards have noticed. 🧙‍♂️✨

</div>

look — the machine is 12,000 lines of Solidity that argues with itself about tick
math at 4am, and somewhere in there a pixel wizard mints because someone swapped
0.4 ETH. both things are true. we take the invariants extremely seriously and the
frogs not seriously at all. 🐸

the cauldron does not care about your feelings. it cares about 24-hour volume. keep
it fed, and it brews forever. let it go quiet, and it dies — then governance picks
the next brew, the liquidity comes back, and your bags migrate 1:1 like nothing
happened. **death is a feature.** wagmi.

- **gib tendies?** cast the spell on your genesis fren and it earns 15% of every
  brew's fees. forever. even the brews that don't exist yet. 🍗
- **rekt?** the floor ratchets *up*, ser. read §7.4 first though — we wrote the
  caveat down instead of hiding it.
- **ngmi?** skill issue. the contracts are open, the tests are green, the docs are
  exhaustive. go read them. 🔮

*built with 🧙‍♂️ by frens, for frens. no roadmap, no promises, just a machine that
refuses to die.*

<div align="center">

**[mifrens.xyz](https://www.mifrens.xyz)** · **[@magic0xfrens](https://x.com/magic0xfrens)** · **[/docs](https://www.mifrens.xyz/#/docs)**

</div>
