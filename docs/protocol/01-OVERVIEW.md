# Cauldron — Overview

Every mechanism below carries a `file:line` that was read at the commit named in
the Verification footer. Where a comment, README or older spec disagreed with the
code, the code is documented and the disagreement is listed in the footer.

---

## 1. What the protocol does

Cauldron runs a chain of fixed-supply ERC-20 tokens on Uniswap V4. One token is
"live" at a time; each one is a **generation**.

- A generation is a freshly deployed `CauldronToken` with a fixed 777,000,000e18
  supply, minted once in its constructor and never mintable again
  (`contracts/solidity/CauldronToken.sol:29`, `:46`). The only supply-changing
  function is `burn`, callable only by the registry (`CauldronToken.sol:58`).
- That token gets a V4 pool with two liquidity positions: a full-range **active**
  position that sets the price, and an out-of-range single-sided **reserve**
  position that holds the rest of the supply
  (`contracts/solidity/cauldron/PoolOps.sol:722`, `:770`).
- A `CauldronHook` on that pool measures rolling 24-hour volume in 24 hourly
  buckets (`contracts/solidity/CauldronHook.sol:1555`) and takes a fee on every
  swap. The ETH fee accumulates in the hook as `relaunchETH`
  (`CauldronHook.sol:286`).
- When 24-hour volume drops below `deathThreshold` (`CauldronHook.sol:206`,
  `:1628`), **anyone** may call `CauldronRegistry.relaunch()`
  (`contracts/solidity/CauldronRegistry.sol:785`). That one transaction pulls the
  dead pool's liquidity back, deploys the next generation's token, and seeds its
  pool with what it recovered plus the hook's accumulated fees.
- A holder of any past generation can burn those tokens and receive the same
  number of live-generation tokens, 1:1, out of the reserve position
  (`CauldronRegistry.sol:1243`).

Around that spine sit an NFT collection per generation, a genesis MiFrens guild
that votes on what launches next, a perp engine, and a treasury that can rotate
its liquidity into a different quote asset. The perp engine and the quote-rotation
machinery are documented elsewhere; this set of documents covers the spine.

---

## 2. The three central promises, stated exactly

### Promise 1 — it runs forever

`relaunch()` takes no parameters and no ETH (`CauldronRegistry.sol:785-789`). It
funds the next generation from three sources it already controls: the dead pool's
recovered liquidity, the hook's fee reserve, and the dying generation's floor
vault (`PoolOps.sol:1000-1093`).

What that promise actually costs, in code: the single most dangerous thing in this
protocol is a revert **after** `governor.markConsumed(winId)`
(`CauldronRegistry.sol:995`). A revert there rolls the consumption back, the same
proposal keeps winning, and every later `relaunch()` dies at the identical line —
permanent. The design response is that everything downstream of that line clamps
instead of reverting:

| Input | Clamped to | Cite |
|---|---|---|
| Winning proposal's quote asset | native ETH if de-listed | `CauldronRegistry.sol:915` |
| Winning proposal's NFT supply | `MAX_NFT_SUPPLY` | `CauldronRegistry.sol:925-927` |
| Token address mining | plain CREATE against ETH if no salt sorts above the watermark | `PoolOps.sol:715-718` |
| Seed funding asset | whatever the protocol actually holds | `PoolOps.sol:1075-1093` |
| Progressive seeding on a non-native quote | degrades to the atomic path | `PoolOps.sol:296-311` |
| New active band > total supply | `TOTAL_SUPPLY` | `CauldronRegistry.sol:1074` |
| Legacy entitlement >= active supply | `GEN1_ACTIVE_TOKENS`, plus a `ReserveShortfall` event | `CauldronRegistry.sol:1057-1063` |
| Dust-sized reserve tranche | no reserve position at all (returns 0) | `PoolOps.sol:792` |

**Limits on this promise.** `relaunch()` still reverts, before the consumption
point, if any of these hold: the protocol was never summoned
(`CauldronRegistry.sol:790`), the pool is not dead (`:797`), the live generation is
younger than `minLifetime` (`:801`), no governor is wired or it has no settled
proposal (`:805`), or funding came to zero (`:994`). It also reverts if the perp
book still holds open positions after the force-close — deliberately, so a
gas-starved rebirth can be retried rather than leaving positions unsettleable
(`CauldronRegistry.sol:1125-1145`).

### Promise 2 — it relaunches permissionlessly

`relaunch()` is `external` and carries only `nonReentrant`
(`CauldronRegistry.sol:785-789`). There is no owner check, no keeper allowlist,
and no caller reward. The gates are the five state checks listed above, and each
is a fact about the protocol rather than about the caller.

The same is true of `CauldronSeeder.poke()` (`cauldron/CauldronSeeder.sol:231`),
`CauldronRegistry.autoMigrateBatch` (`:1346`),
`MiFrensGenesis.igniteCauldron()` unless a finalizer was set
(`cauldron/MiFrensGenesis.sol:591`), and `TreasuryGovernor.execute`
(`cauldron/TreasuryGovernor.sol:550`).

### Promise 3 — per-generation claims are honoured

`claimByBurn(fromGen, amount)` burns the caller's old-generation tokens and
releases the same amount of the live token from the reserve position
(`CauldronRegistry.sol:1243-1267`). It is 1:1, it mints nothing, and it is bounded
by the caller's own balance (`:1257`).

If the reserve cannot cover the claim, the call **reverts** — the burn rolls back
with it, so a holder never pays in full and receives less
(`PoolOps.sol:1281-1284`, tolerance `CLAIM_DUST = 1e12` at `PoolOps.sol:1253`).

**Limits on this promise.**
- Migration is optional. An old token is never frozen; it stays transferable
  forever (`CauldronToken.sol:18-21` — and the contract has no freeze function).
- The reserve is sized at each relaunch to cover migration demand plus the OG
  genesis floor plus every collection's legacy entitlement. When it cannot cover
  all three, the registry emits `ReserveShortfall`
  (`CauldronRegistry.sol:1035`, `:1060`) and claims become first-come.
- Governance can route migration through a vesting escrow. Setting a non-zero
  `claimGate` makes `claimByBurn`, `claimByBurnUpTo` and `autoMigrateBatch` revert
  `VestingEnforced` for ordinary holders (`CauldronRegistry.sol:1252-1254`,
  `:1354`). Setting it is armed, timelocked and guardian-vetoable; clearing it is
  immediate (`CauldronRegistry.sol:518-522`).

---

## 3. The actors

| Actor | Who they are | What they can do | Cite |
|---|---|---|---|
| **Holder** | Anyone holding a generation token | `claimByBurn`, `enableAutoMigrate` / `disableAutoMigrate` | `CauldronRegistry.sol:1243`, `:1306`, `:1334` |
| **MiFren (voter)** | Holder of a `MiFrensGenesis` ERC-721 | Propose a brew, vote on brews, propose and vote on treasury rotations | `cauldron/CauldronGovernor.sol:294`, `:383`; `cauldron/TreasuryGovernor.sol:415`, `:457` |
| **Proposer** | The MiFren whose brew won | Earns a share of the live iteration's swap fees; claims via `claimProposerFees` | `CauldronRegistry.sol:1007`; `CauldronHook.sol:2103`, `:2118` |
| **Keeper** | Anyone | `relaunch`, `autoMigrateBatch`, `CauldronSeeder.poke`, `MigrationVesting.claimFor`, `TreasuryGovernor.execute` | `CauldronRegistry.sol:785`, `:1346`; `CauldronSeeder.sol:231`; `MigrationVesting.sol:255`; `TreasuryGovernor.sol:550` |
| **Owner** | The registry's `Ownable` owner, intended to be a governance timelock | Wire the governor, factory, seeder, seed window, reserve ceiling, collection ledger, redemption facet, and curate the quote allowlist | `CauldronRegistry.sol:184`, `:197`, `:308`, `:327`, `:350`, `:579`, `:589`, `:1479` |
| **Igniter** | One delegated address (the presale) | Call `summon()` once, without holding ownership | `cauldron/CauldronBase.sol:313`; `CauldronRegistry.sol:414`, `:695` |
| **Emergency admin** | Immutable break-glass address, intended to be a multisig | Arm an emergency, pause redemption, withdraw LP, sweep, set successor, migrate to successor, set the claim gate, tune `minLifetime` and the enchant fee | `CauldronRegistry.sol:128`, `:363-366`, `:420`, `:453`, `:469`, `:482`, `:499`, `:518`, `:534`, `:584` |
| **Registry guardian** | Set by the emergency admin or owner | Veto (cancel) an armed emergency action. Nothing else. | `CauldronRegistry.sol:428`, `:438` |
| **Treasury guardian** | A separate seat inside `TreasuryGovernor` | Cancel a treasury proposal or a live envelope; set the quote oracle; hand the seat on | `TreasuryGovernor.sol:608`, `:623`, `:935` |
| **Prime funder** | Owner-nominated, pre-summon | Fund and reclaim a personal first-block market buy | `CauldronRegistry.sol:649`, `:659`, `:665` |
| **Liquidator** | Anyone who triggers a perp liquidation | Earns a Liquidatoor badge NFT in a separate id range. Perp internals are out of scope for these documents. | `cauldron/MiFrensGenesis.sol:181`, `:365` |

Two distinct guardians exist and they are not the same role. The registry's
guardian only cancels armed custody actions. The treasury governor's guardian only
cancels rotation proposals and envelopes and sets that governor's oracle.

---

## 4. System map

### The spine

| Contract | Job | File |
|---|---|---|
| `CauldronRegistry` | The orchestrator. Summons generation 1, relaunches every generation after it, holds every LP position NFT, runs 1:1 migration. | `contracts/solidity/CauldronRegistry.sol` |
| `CauldronBase` | The abstract base holding **all** shared storage, constants and errors for the registry and its delegatecall facet. Both children add no state, so their layouts are identical by construction. | `contracts/solidity/cauldron/CauldronBase.sol:95` |
| `RedemptionExt` | A delegatecall facet running on the registry's storage. Holds the OG-redemption ops, the quote-rotation entrypoints, the leg bookkeeping and `claimByBurnUpTo`. Its internals are out of scope here; the registry's forwarders are documented in `05-ARCHITECTURE.md`. | `contracts/solidity/cauldron/RedemptionExt.sol` |
| `PoolOps` | A linked, delegatecalled library holding every V4 PositionManager encoding, the token deployer, the seeding paths and the funding decision. Exists so the registry fits under EIP-170. | `contracts/solidity/cauldron/PoolOps.sol:125` |
| `CauldronToken` | One per generation. Fixed supply, no mint, registry-only burn, never freezable. | `contracts/solidity/CauldronToken.sol:26` |
| `CauldronHook` | The V4 hook. Volume tracking, fee collection, death detection, NFT credit, the fee reserve that funds the next launch. | `contracts/solidity/CauldronHook.sol` |

### Genesis and seeding

| Contract | Job | File |
|---|---|---|
| `MiFrensGenesis` | The founding NFT collection and the presale. Sells the OG tranche for ETH, then ignites the registry with the whole pot. Also the governance electorate (`ERC721Votes`). | `contracts/solidity/cauldron/MiFrensGenesis.sol:48` |
| `CauldronFactory` | Deploys each generation's NFT collection + floor vault + royalty router, and wires them. Split out for EIP-170. | `contracts/solidity/cauldron/CauldronFactory.sol:16` |
| `CauldronSeeder` | Optional progressive launch: streams the active tranche into the pool over a window instead of placing it all at once. Also runs a tranched "prime buy". | `contracts/solidity/cauldron/CauldronSeeder.sol:59` |
| `SeedLib` | Pure math for the progressive schedule and band geometry. | `contracts/solidity/cauldron/SeedLib.sol` |
| `LaunchSniper` | Optional: ignites the presale and buys the fresh pool in one transaction, so nothing can execute in between. | `contracts/solidity/cauldron/LaunchSniper.sol:51` |
| `MigrationVesting` | Optional anti-dump escrow. Turns instant 1:1 migration into a linear drip. | `contracts/solidity/cauldron/MigrationVesting.sol:63` |
| `CauldronVault` | A per-generation NFT floor vault. Under the shipped configuration it holds no ETH and serves only as a supply counter — see `02-LIFECYCLE.md`. | `contracts/solidity/cauldron/CauldronVault.sol:26` |

### Governance

| Contract | Job | File |
|---|---|---|
| `CauldronGovernor` | Who proposes and who wins the **next brew**. 1 MiFren = 1 vote, snapshotted. | `contracts/solidity/cauldron/CauldronGovernor.sol:28` |
| `TreasuryGovernor` | Whether and how far the treasury may **rotate its LP** into another approved quote asset. Approves an envelope, not a transaction. | `contracts/solidity/cauldron/TreasuryGovernor.sol:84` |

### Supporting

| Contract | Job | File |
|---|---|---|
| `CollectionLedger` | The cap table for per-generation NFT collection floors. Pure accounting; holds no tokens. | `contracts/solidity/cauldron/CollectionLedger.sol:38` |
| `CauldronCollection` | The per-generation volume-minted NFT collection. | `contracts/solidity/cauldron/CauldronCollection.sol` |
| `MiFrensDividend` | The genesis-holder fee dividend. | `contracts/solidity/cauldron/MiFrensDividend.sol` |
| `CauldronGachaRouter` | The user-facing swap + crystal-open router. | `contracts/solidity/cauldron/CauldronGachaRouter.sol` |
| `ReserveLib`, `FeeRouteLib`, `SurtaxLib`, `LegacyBuyLib` | Linked libraries carrying the reserve-band math, fee routing, anti-sniper surtax and legacy buyback. | `contracts/solidity/cauldron/` |

### Out of scope here (documented separately)

`PerpEngine`, `PerpVault`, `PerpSwapLib`, `PerpMarkSource`, `PerpStakerOracle`,
`QuoteRotator`, `QuoteOracle`, and the internals of `RedemptionExt`.

---

## 5. How the parts fit

```
                        MiFrens holders (the guild)
                          |                    |
              propose/vote|                    |propose/vote
                          v                    v
                 CauldronGovernor        TreasuryGovernor
                    (next brew)          (rotation envelope)
                          |                    |
                   winner()|                   |allowance()/consume()
                          v                    v
  MiFrensGenesis --> CauldronRegistry <--delegatecall--> RedemptionExt
    (presale,    summon()  |   ^  |                 (shared CauldronBase storage)
     ignition)             |   |  |
                  delegatecall  |  |
                          v   |  v
                      PoolOps  |  CauldronFactory --> CauldronCollection
                          |    |                   --> CauldronVault
                          v    |                   --> RoyaltyRouter
               Uniswap V4 PoolManager / PositionManager
                          ^    |
                          |    | afterInitialize / afterSwap
                          |    v
     CauldronSeeder <--- CauldronHook ---> CollectionLedger
     (streamed seed)      (volume, fees,        (legacy floors)
                           death, credit)
```

The three arrows that matter:

1. **The guild decides what launches.** `relaunch()` reads the winner out of
   `CauldronGovernor` and refuses to proceed without one
   (`CauldronRegistry.sol:805`, `:867`). There is no admin fallback and no
   automatic default brew.
2. **The hook decides when.** `relaunch()` cannot proceed until
   `hook.isDead(oldPoolId)` is true (`CauldronRegistry.sol:797`), which is a pure
   function of on-chain volume with no oracle and no keeper
   (`CauldronHook.sol:1628-1647`).
3. **The registry holds everything.** Every position NFT, every generation's
   token supply, the migration reserve and the recovered liquidity all sit at the
   registry address. `PoolOps` and `RedemptionExt` run *as* the registry under
   delegatecall, which is why they can move that custody without holding it.

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

- **Documentation debt found** — see the consolidated list at the end of
  `05-ARCHITECTURE.md`. The items touching this file:
  - `contracts/solidity/CauldronRegistry.sol:1778-1782` states "the fallback
    delegatecalls any unknown selector to the facet". There is no `fallback()` in
    the contract — only `receive()` at `:572` and explicit stubs. The
    contradicting note at `:1411-1420` is the correct one.
  - `docs/PROTOCOL_SPEC.md`, `docs/TOKENOMICS.md`, `docs/FLYWHEEL_ECONOMICS.md`,
    `docs/DEATH_SPIRAL_ANALYSIS.md`, `docs/SECURITY_ANALYSIS.md`,
    `docs/DEPLOYMENT_GUIDE.md`, `docs/PHOENIX_SYSTEM.md` and
    `docs/PHOENIX_TAX_SYSTEM.md` described an OP_NET / Bitcoin-L1 lending protocol
    that does not exist in this tree. They have been moved to
    `archive/superseded-docs/opnet-era/`. Do not cite them.
- **Unverified:** the live deployed addresses (read from repo manifests, not from
  chain); EIP-170 byte margins (last measured 2026-09-10, before the ~30 fix
  commits in this branch); whether the tree compiles at this commit.
