<div align="center">

# 🧙‍♂️ Magic Internet Frens

**2222 on-chain pixel wizards, and the eternal token machine they govern.**

*The Cauldron is a Uniswap v4 hook that launches a token, lets the market trade it,
notices when it dies, recovers the liquidity, and launches the next one — forever,
funded entirely by its own swap fees.*

[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-2A1F54)](contracts/solidity)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4%20hook-d5fd51)](https://docs.uniswap.org/contracts/v4/overview)
[![Feedback](https://img.shields.io/badge/Uniswap-FEEDBACK.md-ff007a)](FEEDBACK.md)
[![Tests](https://img.shields.io/badge/forge%20test-611%20passing-brightgreen)](contracts/solidity/test)
[![Sepolia](https://img.shields.io/badge/live-Sepolia-blue)](https://sepolia.etherscan.io)
[![Arc](https://img.shields.io/badge/live-Arc%20testnet-7B5BF5)](https://testnet.arcscan.app/address/0x4e60D157E951898521A97dD5217e50D6187aB432)

[Website](https://www.mifrens.xyz) · [Docs](https://www.mifrens.xyz/#/docs) · [X](https://x.com/magic0xfrens)

</div>

---

## Table of contents

- [Hackathon: tracks and partner prizes](#hackathon-tracks-and-partner-prizes)
- [Verify the Uniswap v4 integration](#verify-the-uniswap-v4-integration)
- [Live deployments](#live-deployments)
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

## Hackathon: tracks and partner prizes

Submitted to **ETHGlobal** on the **Continuity** track (this is an ongoing protocol,
not a from-scratch build).

| Track / prize | What we're claiming |
|---|---|
| 🏆 **Best DeFi or Agentic Application** — Continuity | The hook *is* the application: perps that liquidate themselves inside the swap, NFTs minted by on-chain activity, and a liquidity book that outlives the tokens it prices. |
| 🏆 **Launch on Arc Testnet & Push to Mainnet** — Continuity | Full stack live on Arc testnet, **including Uniswap v4 core, which we deployed ourselves** because it wasn't on Arc yet. Zero contract changes to port. Deployment-ready for Arc mainnet. |
| 🦄 **Uniswap Foundation** | A v4 hook using both return-delta permissions, hook-initiated swaps inside its own `unlock`, a tick TWAP built from the pool itself, and direct singleton liquidity management. We've also applied to the **Uniswap Foundation Audit Subsidy** programme. |
| 🔵 **Arc** | Ported an entire DeFi stack to Arc with configuration only — pricing the USD-denominated gas token by peg rather than by feed, and verifying its decimals empirically. |

### Why each sponsor's tech is load-bearing here

**Uniswap v4** — not a dependency, the substrate. `POOL_FEE = 0`: there is no LP fee
at all, and 100% of revenue is a quote-denominated hook fee taken through
`beforeSwapReturnDelta`/`afterSwapReturnDelta` on both legs. Perpetual futures open,
close and liquidate as real `poolManager.swap` calls, marked off a cumulative-tick
TWAP the hook maintains from the pool's own ticks — and **liquidations are swept from
`afterSwap`, so any swap on any interface auto-liquidates underwater positions**, with
no keeper network and no external oracle. Trading volume forges NFTs inside the same
callback, and liquidating a perp mints the liquidator a **Liquidatoor badge with the
kill engraved on-chain** (victim, side, leverage, entry, the mark that killed them,
your bounty). `hookData` is optional throughout, so a plain swap from the Uniswap
interface or any aggregator does all of the above with no custom router.

**Arc** — the second chain, and the one that proved the design is portable.
Uniswap v4 wasn't deployed there, so [`DeployV4Core.s.sol`](contracts/solidity/deploy/DeployV4Core.s.sol)
stands up `PoolManager` + `PositionManager` first, then the launchpad runs on top
unchanged. Two facts made it work, both established by measurement rather than
assumption: Arc supports **EIP-1153 transient storage** (verified with a raw
`eth_call` executing `TSTORE`/`TLOAD` — without it v4 cannot run at all), and its
USD-denominated gas token is **18-decimal**, not 6. That second one matters more than
it sounds: `PoolOps._sqrtPrice` cannot represent a quote below `TOTAL_SUPPLY / 2^64`,
which at 6 decimals is ~674 raw units, so a 6-decimal native would have bricked an
ordinary launch behind a state-consuming flag.

### Verify the Uniswap v4 integration

Uniswap asks that the README point at the exact code. Line numbers are verified against
this commit. Full developer feedback, including our audit-subsidy application and our
request for hook review, is in **[`FEEDBACK.md`](FEEDBACK.md)**.

| What | File and line |
| --- | --- |
| Hook permissions — **both** return-delta flags enabled | [`CauldronHook.sol:576-597`](contracts/solidity/CauldronHook.sol#L576-L597) |
| `POOL_FEE = 0` — no LP fee at all | [`cauldron/CauldronBase.sol:157`](contracts/solidity/cauldron/CauldronBase.sol#L157) |
| Fee taken on the **quote side**, currency-agnostic | [`CauldronHook.sol:1520`](contracts/solidity/CauldronHook.sol#L1520) |
| `poolManager.take` realises the accrued delta | [`CauldronHook.sol:1522`](contracts/solidity/CauldronHook.sol#L1522) |
| `afterSwap` returns the fee as a delta, not a transfer | [`CauldronHook.sol:1006`](contracts/solidity/CauldronHook.sol#L1006) |
| **Keeper-free liquidation swept inside `afterSwap`** | [`CauldronHook.sol:953`](contracts/solidity/CauldronHook.sol#L953) |
| NFT minted from volume, inside the swap, routerless | [`CauldronHook.sol:970`](contracts/solidity/CauldronHook.sol#L970) → [`:2436`](contracts/solidity/CauldronHook.sol#L2436) |
| Liquidation mints a badge with the kill engraved | [`cauldron/PerpEngine.sol:2116`](contracts/solidity/cauldron/PerpEngine.sol#L2116) |
| Router-optional paths (`hookData` absent) | [`:846`](contracts/solidity/CauldronHook.sol#L846), [`:877`](contracts/solidity/CauldronHook.sol#L877), [`:959`](contracts/solidity/CauldronHook.sol#L959) |
| Hook-initiated `poolManager.swap` inside our own `unlock` | [`cauldron/PerpSwapLib.sol:248`](contracts/solidity/cauldron/PerpSwapLib.sol#L248) |
| Native `sync` → `settle` → `take` | [`cauldron/PerpSwapLib.sol:278-287`](contracts/solidity/cauldron/PerpSwapLib.sol#L278-L287) |
| Cumulative-tick TWAP ring from the pool's own ticks | [`cauldron/PerpEngine.sol:268-290`](contracts/solidity/cauldron/PerpEngine.sol#L268-L290) |
| Multi-range book via `modifyLiquidity` on the singleton | [`cauldron/PoolOps.sol:543`](contracts/solidity/cauldron/PoolOps.sol#L543) |
| One LP recovered and re-seeded into a new `PoolKey` | [`CauldronRegistry.sol:858`](contracts/solidity/CauldronRegistry.sol#L858) |
| EIP-1153 transient flags for self-trading reentrancy | [`CauldronHook.sol:339-344`](contracts/solidity/CauldronHook.sol#L339-L344) |
| **v4 core deployed by us, on a chain that lacked it** | [`deploy/DeployV4Core.s.sol:71-83`](contracts/solidity/deploy/DeployV4Core.s.sol#L71-L83) |

---

## Live deployments

Addresses rotate every iteration and rebirth, so **per-generation addresses are read
from the registry, never hardcoded** (see [Deployment](#deployment)). The permanent
infrastructure is below.

### Arc testnet — chain `5042002`

Uniswap v4 did not exist on Arc. We deployed it, then our stack on top of it.

| Contract | Address |
|---|---|
| **PoolManager** (we deployed this) | [`0x6495341CF36fD399d74b58A5B125c07E15747d54`](https://testnet.arcscan.app/address/0x6495341CF36fD399d74b58A5B125c07E15747d54) |
| **PositionManager** (we deployed this) | [`0x6EEA2bDee8c49168146f7015D717D9fe8fD252ae`](https://testnet.arcscan.app/address/0x6EEA2bDee8c49168146f7015D717D9fe8fD252ae) |
| CauldronHook | [`0x8864eE50a7fb9Ed8Dd8b78aA4BBfBaf3Aa9310cc`](https://testnet.arcscan.app/address/0x8864eE50a7fb9Ed8Dd8b78aA4BBfBaf3Aa9310cc) |
| CauldronRegistry | [`0x4e60D157E951898521A97dD5217e50D6187aB432`](https://testnet.arcscan.app/address/0x4e60D157E951898521A97dD5217e50D6187aB432) |
| PerpEngine | [`0x12962E69CD005A42ed1d7669e43A8Ad81ac16A22`](https://testnet.arcscan.app/address/0x12962E69CD005A42ed1d7669e43A8Ad81ac16A22) |
| PerpVault | [`0x0F4eE6f937bAb5450beb453953D7c46EFe84d5E7`](https://testnet.arcscan.app/address/0x0F4eE6f937bAb5450beb453953D7c46EFe84d5E7) |
| MiFrensGenesis | [`0x5ddCd156fc0ff37eC3dD20b53f070f7Ff8B4f48a`](https://testnet.arcscan.app/address/0x5ddCd156fc0ff37eC3dD20b53f070f7Ff8B4f48a) |
| Timelock | [`0x95ab3D345e25A8B180Af3Ca6071ed3C595df8BcB`](https://testnet.arcscan.app/address/0x95ab3D345e25A8B180Af3Ca6071ed3C595df8BcB) |
| Generation 1 token | [`0xf5E9b44260CDaC047593583DF540A8589cEd2df9`](https://testnet.arcscan.app/address/0xf5E9b44260CDaC047593583DF540A8589cEd2df9) |
| Generation 1 collection — *Gnomeland* | [`0x016a5E7577D6B34b2a662D49940854B385C757D8`](https://testnet.arcscan.app/address/0x016a5E7577D6B34b2a662D49940854B385C757D8) |

**The Uniswap v4 deployment transaction**, if you want the receipt rather than the
address: [`0x52e0a244…3484b33`](https://testnet.arcscan.app/tx/0x52e0a2446730d9aef3e2b6ca6d5adc547d04a48c42976858c261c59403484b33)

Generation 1 is live: the 1111-fren genesis presale minted out, the pool summoned
through the hook, and it holds real liquidity. Reproduce the whole bring-up with
[`scripts/deploy-arc.sh`](scripts/deploy-arc.sh) then
[`scripts/arc-ignite.sh`](scripts/arc-ignite.sh).

### Ethereum Sepolia

The long-running deployment, where the full lifecycle has been exercised repeatedly
— summon, trade, perps, liquidations, quote rotation by governance, death and rebirth
across dozens of generations. Uniswap v4 is canonical there:
`PoolManager 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`.

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
| **Live on** | Ethereum Sepolia · Arc testnet (chain 5042002, incl. Uniswap v4 deployed by us) |

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
611 tests passed, 0 failed
(+5 fork-only tests that require FORK_RPC — see below)
```

| Suite | Covers |
| --- | --- |
| `test/*.t.sol` | Unit + integration: summon, launchpad, seeder, vesting, ledger |
| `test/invariants/` | System invariants, storage-layout, ledger and vesting fuzz |
| `test/attacks/` | Adversarial: CREATE2 squat, depth manipulation, relaunch gas-brick, fee bypass, governance lockout, L2 block-clock |
| `test/audit/` | Proof-of-concept exploits from audit passes |
| `test/final/` | Custody + consent, L2 semantics, reserve ceiling |

172 test files, **96 of them adversarial PoCs** in `test/attacks/` — each one an
attack that was actually landed against the protocol first, then fixed, then pinned
so it can never come back.

The fork-only tests need an archive-capable endpoint, and **fail loudly rather than
skipping silently** if it is missing — a fork test that quietly passes with no fork
is worse than no test:

```bash
FORK_RPC=$SEPOLIA_RPC_URL FOUNDRY_PROFILE=cauldron forge test
```

Frontend: `npm run type-check` (clean), `npm run lint`, `npm run test:unit`.

### What has been exercised on live Sepolia

Unit tests prove the code does what we meant. These are the things that only a real
chain can tell you, run against live Sepolia rather than a fork:

| Exercised on-chain | Evidence |
| --- | --- |
| **43 deployment rounds**, each a full 14-contract stack | current manifest is `round: 43` |
| **6 complete death-and-rebirth cycles** on the current round alone — pool dies, liquidity is recovered, next token summoned, holders migrate 1:1 | `registry.currentGeneration() == 7` |
| Genesis presale minted out and ignited into a live v4 pool | `MiFrensGenesis.igniteCauldron()` |
| Perps opened, marked, and **liquidated inside a swap** with no keeper | `PerpEngine` live, insurance buffer funded |
| **Governance quote rotation executed live**: ETH → USDG across 12 permissionless slices through a curated venue | exercised on round 42 |
| Crystal gacha: volume-forged NFT mints from plain swaps, no router | `CauldronGacha` + in-swap `nativeGachaStep` |
| Proposals raised, voted, and executed through the timelock | `CauldronGovernor` + `TreasuryGovernor` |
| Break-glass recovery of stranded LP after an armed emergency delay | `rescueSeeder` / `withdrawAll` paths |

Four things that only showed up on a real chain, and are now written down in the
deploy scripts because no unit test would ever have caught them: a perp engine
deployed before the summon keeps `syncedToken == 0` and silently **inverts every
trade** (a "long" fills as a sell, marks at zero, and does not revert); a 24-hour
perp warmup and a 5-minute TWAP window are correct for mainnet and make a testnet
perp look broken; and a rotation slippage floor left at its 3% default makes the
whole rotation feature undemonstrable against any venue you can afford to seed.

---

## Deployment

Live on **Ethereum Sepolia** and **Arc testnet** (addresses under
[Live deployments](#live-deployments)). Per-generation addresses rotate every
iteration and every rebirth, so they are **not hardcoded in this README on purpose** —
read them from the manifest, or from the registry itself:

```solidity
registry.currentGeneration()          // which iteration is live
registry.currentToken()               // its ERC-20
registry.generationCollection(gen)    // its NFT collection
registry.generationPoolId(gen)        // its v4 pool
```

The [`/docs`](https://www.mifrens.xyz/#/docs) page renders live addresses from the
same manifest the app reads, and verifies them against the chain.

**Chain-agnostic by construction.** Exactly two things are required of a chain:
**EIP-1153 transient storage** (Uniswap v4 settles every `unlock` through
`TSTORE`/`TLOAD`, so v4 — and therefore this protocol — cannot run without it) and a
**CREATE2 factory** (the hook's permission bits live in its address, so the address
must be mined). Everything else is a config value: `VITE_CHAIN_ID`, `VITE_RPC_URL`,
`VITE_EXPLORER_URL` and the native currency's symbol/decimals, with `VITE_NETWORK`
flipping the whole app between chains in one env change.

Nothing assumes the gas token is 18-decimal ETH, because on Arc it is not —
`QuoteOracle` prices a USD-denominated native asset by **peg** rather than by feed,
which is not a shortcut but the accurate model: there is no exchange rate to observe,
and a price feed could only introduce a way to fail.

The rollup semantics that actually matter — second-denominated windows (`block.number`
is the parent chain's on many L2s), grind-resistant randomness (`prevrandao` is a
constant on several rollups, and this protocol uses none of it), and per-timestamp
liquidation throttling — are covered in
[`docs/ROBINHOOD_L2_REVIEW.md`](docs/ROBINHOOD_L2_REVIEW.md), written against an
Arbitrum Orbit target but applicable to any rollup.

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
