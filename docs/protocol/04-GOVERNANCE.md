# Cauldron — Governance

What this document covers: the two independent governors, their full proposal
lifecycles with real numbers, the mandate/envelope model, both guardian seats, and
an explicit statement of what governance **cannot** do.

Every number below is read from the constant that defines it.

---

## 1. Two governors, two questions

| | `CauldronGovernor` | `TreasuryGovernor` |
|---|---|---|
| Decides | **What launches next** — the next brew's name, ticker, art, NFT supply, mint-out target and quote asset | **Whether and how far the treasury may rotate its LP** into another approved quote |
| File | `cauldron/CauldronGovernor.sol:28` | `cauldron/TreasuryGovernor.sol:84` |
| Electorate | MiFrens, `ERC721Votes` | the same MiFrens |
| Consumed by | `CauldronRegistry.relaunch()` → `winner()` / `markConsumed()` | `RedemptionExt.rotateSliceFrom` → `allowance()` / `consume()` |
| Output | one winning `BrewSpec` | one live `Envelope` |
| Cadence | stockpiled against the next death, which may be months away | at most one live envelope, with a cooldown |

They share no storage and neither can call the other.

---

## 2. `CauldronGovernor` — the next brew

### Constants

| Constant | Value | Cite |
|---|---|---|
| `VOTING_PERIOD` | 3 days | `CauldronGovernor.sol:61` |
| `MAX_NFT_SUPPLY` | 100,000 | `:55` |
| `MAX_NAME_BYTES` | 64 | `:97` |
| `MAX_SYMBOL_BYTES` | 16 | `:98` |
| `MAX_URI_BYTES` | 256 | `:99` |
| `MAX_LINK_BYTES` | 128 (each of `website`, `socials`) | `:100` |
| `BENCH_SLOTS` | 8 | `:200` |

Worst case those five strings sum to 592 bytes, about 49k gas to replay (`:94-96`).

### Lifecycle

**Propose** — `propose(name, symbol, mode, baseURI, renderer, website, socials,
nftSupply, volumePerNFT, quote)` (`:280`).

| Check | Rule | Cite |
|---|---|---|
| Eligibility | `mifrens.getVotes(msg.sender) != 0` — you must hold a MiFren. Auto-delegated on mint, so no separate delegate transaction. | `:294` |
| Name/symbol | non-empty | `:295` |
| Field sizes | the five byte caps above | `:300-305` |
| Metadata | `BaseURI` mode needs a non-empty URI; `Renderer` mode needs a contract with code | `:306-311` |
| NFT supply | `<= MAX_NFT_SUPPLY` | `:316` |
| Quote | native needs no lookup; anything else must be on the registry's `allowedQuote` | `:338-343` |

On success it stores `snapshot = block.number` and
`votingEndsAt = block.timestamp + VOTING_PERIOD` (`:359-360`).

**Vote** — `vote(proposalId)` (`:383`).

| Check | Rule | Cite |
|---|---|---|
| Exists, not consumed | | `:385-386` |
| Window | `block.timestamp <= votingEndsAt`, checked **before** the double-vote check so a closed window always reports as such | `:387-391` |
| One vote per address per proposal | | `:392` |
| Weight | `mifrens.getPastVotes(msg.sender, p.snapshot)` — checkpointed at the proposal's block, so transferring to a fresh wallet and voting again fails | `:394-399` |
| Snapshot readiness | `block.number > p.snapshot` | `:397` |

Voting is FOR-only; there is no against side. Ties keep the earlier leader (`:404`).

**Win** — `winner()` (`:451`) returns the best unconsumed proposal, or reverts
`NoProposals`. `hasProposals()` (`:470`) is the same test as a boolean.

A proposal is only eligible once its voting window has **closed**
(`_bestUnconsumed`, `:522-530`, specifically `:525`). This removes the
last-instant front-run: a whale cannot flip the result in the same block as the
permissionless `relaunch()`.

**Consume** — `markConsumed(proposalId)` (`:475`) is registry-only (`:476`) and
only ever removes an already-summoned proposal from contention (`:480`).

### How the leader is tracked, and why it is shaped that way

Three layers, added in response to three separate griefing shapes:

1. **A cached leader** (`_leaderId`/`_leaderVotes`, `:148-149`), maintained
   incrementally by `vote` (`:407-419`).
2. **A runner-up slot** (`_runnerId`/`_runnerVotes`, `:178-179`), promoted by
   `markConsumed` (`:488-496`). Without it, `markConsumed` fell back to a scan.
3. **An 8-slot bench** (`_bench`, `:233`), which is what `_recomputeLeader`
   actually scans (`:554-571`).

The reason the scan is over a fixed bench and not over the proposal list:
`propose()` is permissionless for the holder of a single MiFren with no cooldown
and no deposit, so **any window over a list anyone may grow is a window anyone may
flood**. Measured, pre-fix: three voted proposals plus 64 junk filings for 11.8M
gas erased the guild's surviving 90-vote mandate — `winner()` returned 0,
`hasProposals()` went false, and `relaunch()` reverted `NoProposal`
(`:204-232`).

Entry to the bench is by **votes**, which cost MiFrens, not by **position**, which
costs gas (`_benchRecord`, `:429-444`). A proposal nobody voted for can never
enter; displacing an incumbent means out-voting the weakest live mandate.
Consumed and nonexistent entries count as weight 0 and are reclaimed first, so the
bench self-cleans (`:438-439`).

The treasury governor solved the same shape by bounding its scan by **time**,
which works there because a treasury proposal must execute inside a 3-day window.
A brew mandate has no such window on purpose — it is stockpiled against the next
death — so time was not available here (`:219-224`).

### Known dead code

`MAX_LEADER_SCAN = 64` (`:550`) is still declared, and its NatSpec (`:532-549`)
describes a scan over the most recent 64 proposals. `_recomputeLeader` (`:554`)
does not reference it; it iterates `BENCH_SLOTS`. The constant is unused and the
doc block above it describes a design that was replaced.

---

## 3. `TreasuryGovernor` — the rotation envelope

### What is voted on

**An envelope, not a transaction**: "we may move up to N% of the LP into asset X,
before date D" (`TreasuryGovernor.sol:37-42`). Holders have opinions about whether
the treasury should hold USDG; they do not have opinions about whether slice
fourteen fills at 3pm. Execution is left mechanical and permissionless.

### Timing — immutable per deployment, not constant

The four durations are `immutable`, fixed at construction and unchangeable
afterwards by anyone including the guardian and the vote (`:274-280`,
`:394-397`). They were `constant`; hardcoding mainnet durations made the contract
untestable on a testnet where a full rotation would take 80+ days of real waiting
(`:261-273`).

| Parameter | Mainnet default | Floor (unless `testnet`) | Cite |
|---|---|---|---|
| `VOTING_PERIOD` | 3 days | 1 day | `:341`, `:349` |
| `ENVELOPE_LIFETIME` | 30 days | — (must be `>= EXECUTION_WINDOW`) | `:342`, `:392` |
| `COOLDOWN` | 7 days | 1 day | `:343`, `:350` |
| `EXECUTION_WINDOW` | 3 days | 1 day | `:344`, `:351` |

Passing zero for any of them selects the mainnet default (`:379-382`), so a caller
changing one duration does not have to restate the others correctly. The `testnet`
flag waives the floors and is a deploy-time argument; the mainnet script simply
never passes it (`:359-362`, `:384-388`). The `envelopeLifetime >= executionWindow`
check applies in **both** modes, because an envelope that expires before its own
execution window closes is an incoherence, not a policy choice (`:389-392`).

### Thresholds

| Constant | Value | Cite |
|---|---|---|
| `PROPOSAL_THRESHOLD` | 5 MiFrens to open a treasury proposal | `:331` |
| `QUORUM_BPS` | 1000 = **10% of total supply**, not of turnout | `:328` |
| `MAX_ENVELOPE_BPS` | 30,000 — the cumulative **slice budget** one envelope may spend | `:308` |
| `BPS_ONE` | 10,000 — one whole position | `:810` |
| `PoolOps.MAX_ROTATION_BPS` | 5,000 — hard ceiling on any single removal (50% of the live position) | `cauldron/PoolOps.sol:941` |

**`MAX_ENVELOPE_BPS` is a spend counter, not a position fraction.** `consume`
books the *nominal* `sliceBps` of each rotation, while `PoolOps.removePartial`
takes that share of the **current** position — so the position decays
geometrically and the nominal spend needed to convert most of it exceeds 100%.
Reaching 5% of the original costs about 27,500 bps of budget at a 25% slice, and
about 29,500 at a 5% slice. The old value of 4000 read as "40% of the LP" and was
neither: it bought 8 slices of 5%, moving `1 - 0.95^8 = 33.66%`, so a full
de-risking rotation needed roughly eight consecutive envelopes — about 80 days
with the vote and cooldown counted (`:281-307`).

Because the units are not the units a voter reasons in, the contract exposes
`conversionFor(spendBps, sliceBps)` (`:317-326`), which returns the share of the
position a budget actually converts. A UI showing the raw 30,000 would mislead.

### Lifecycle

**Propose** — `propose(quote, maxTotalBps)` (`:415`).

| Check | Rule | Cite |
|---|---|---|
| Threshold | `mifrens.getVotes(sender) >= PROPOSAL_THRESHOLD` | `:416` |
| Bounds | `0 < maxTotalBps <= MAX_ENVELOPE_BPS` | `:417` |
| Allowlist | `registry.allowedQuote(quote)` | `:420` |
| Priceable | the oracle must be able to value it | `:421`, `:926-931` |
| No live envelope | `!(envelope.active && now < envelope.expiry)` | `:437` |
| Cooldown | `now >= lastEnvelopeAt + COOLDOWN` | `:438` |

Snapshot is `block.number` at proposing (`:447`); `votingEndsAt = now +
VOTING_PERIOD` (`:444`).

**Proposals compete; they do not queue.** An earlier version allowed one open
proposal at a time, which read as a safety property and was an attack: anyone
holding the 5-MiFren threshold could file junk every three days and block treasury
governance permanently for the price of gas. Only the **envelope** is exclusive
(`:423-437`).

**Vote** — `vote(id, support)` (`:457`). Two-sided. Weight is
`getPastVotes(sender, snapshot)` (`:463`). One vote per address (`:461`), window
strictly before `votingEndsAt` (`:460`).

**Execute** — `execute(id)` (`:550`), **permissionless**: if the guild approved
it, no privileged account should be able to sit on the result (`:544-549`).

| Check | Rule | Cite |
|---|---|---|
| Window closed | `now >= p.votingEndsAt` | `:553` |
| Not already executed or cancelled | | `:554` |
| Passed | more FOR than AGAINST **and** FOR >= quorum | `:555`, `:868-881` |
| Is the leader | `id == winner()` — otherwise several proposals passing in the same window would turn a vote into a race | `:558-560` |
| Not stale | `now <= p.votingEndsAt + EXECUTION_WINDOW` | `:561-563` |
| Allowlist re-checked | the timelock may have de-listed the asset during the vote | `:584-586` |
| Priceable re-checked | a feed can be de-configured or go stale mid-vote | `:587-590` |

On success the envelope is installed with `movedBps = 0`, `movedPrimaryBps = 0`,
`expiry = now + ENVELOPE_LIFETIME`, `active = true` (`:592-601`), and
`lastEnvelopeAt` starts the cooldown (`:601`).

**Quorum is measured at the proposal's snapshot**, via `getPastTotalSupply`
(`:879`). Two reasons: reading a live supply would let anyone move the bar under a
vote in progress; and the contract actually wired is `MiFrensGenesis`, which is
`ERC721Votes` but **not** `ERC721Enumerable` — it has no `totalSupply()` and no
fallback, so a live-supply read reverted `unrecognized function selector` and
`execute` could never succeed (`:7-15`, `:871-880`).

### The winner scan is bounded by **time**, not position

`winner()` (`:659`) first tries a cached hint from `vote`, trusted only after the
same executability tests the scan applies (`:660-664`). On a miss it walks
**backwards** from `proposalCount` and **breaks** at the first proposal too old to
execute (`:693-704`). Because `votingEndsAt` is fixed at creation and ids are
chronological, it is monotonic — once one is stale, every older one is too.

The scan therefore spans only the last `VOTING_PERIOD + EXECUTION_WINDOW`
(6 days on mainnet defaults). The first fix attempted here was a positional window
of 64, copied from `CauldronGovernor`, and it reintroduced exactly the flooding
bug: a genuine proposal, voted and still inside its execution window, was pushed
out by 64 later filings and `winner()` returned 0 (`:667-692`).

The `_leadId` hint carries a stated invariant — *every proposal that is not
`_dead` holds at most `_leadVotes` FOR-votes* — and `vote` is its only writer
(`:152-162`, five branches at `:473-518`). The one branch that lowers `_leadVotes`
(`:493-512`) fires only when the leader is provably dead **and** every untracked
rival is provably dead too, dated by `_openVotedAt` (`:166-206`).

### Envelope accounting — the two counters

| Field | Counts | Cite |
|---|---|---|
| `movedBps` | **every** slice, including ones taken out of a secondary rotated leg by any permissionless caller | `TreasuryGovernor.sol:121`, written `:942` |
| `movedPrimaryBps` | only what left the **generation's own** position | `:125-128`, written `:850` |

`allowance()` (`:745`) reports `(quote, remainingBps)`. **`remainingBps` is the
liveness flag, not `quote`** — `address(0)` is a legitimate destination (native
ether), so it can never mean "nothing approved" (`:737-744`). A full-position
mandate (`maxTotalBps >= BPS_ONE`) meters against `movedPrimaryBps`; a partial one
meters against the shared `movedBps` (`:767`).

Why: `movedBps` counts every slice, so reporting `maxTotalBps - movedBps` let a
stranger spend a voted 10,000-bps migration envelope entirely out of a side pool.
The remainder reached 0, `consume` read that as "no envelope", the envelope
deactivated, and `movedPrimaryBps` was still zero — so the migration could never
complete, and the 7-day cooldown blocked the replacement (`:748-766`).

`migrationMandateSpent()` (`:803`) is true only when `maxTotalBps >= BPS_ONE`
**and** `movedPrimaryBps >= maxTotalBps`. It is the only signal allowed to
redenominate a generation. A mandate budgeting less than the whole position is
partial by construction: a fully-spent 2500-bps mandate left ~76% of the pair in
the old asset (`:772-802`).

`consume(bps, fromPrimary)` (`:819`) is **registry-only** (`:820`). A primary
slice is bounded by the primary's remaining budget; a secondary slice is bounded
by the shared total, so leg-to-leg rebalancing stays available and capped but can
no longer starve the migration (`:843-848`). A spent envelope deactivates itself
(`:862`) — without that, a mandate spent in its first hour locked out every new
treasury proposal for 30 days (`:851-861`).

---

## 4. The guardians

There are **two** guardian seats and they are unrelated.

### The registry guardian

| | |
|---|---|
| Set by | the emergency admin, or the owner (intended pre-handoff only) — `CauldronRegistry.sol:428-434` |
| Can do | exactly one thing: `vetoEmergency()`, which zeroes `emergencyReadyAt` — `:438-442` |
| Cannot do | propose anything, move any value, or unblock anything |

It is a pure-upside safety role: it turns the "watch and flee" window into "watch
and block" (`:436-437`).

### The treasury guardian

| | |
|---|---|
| Set by | itself only — `setGuardian(g)` is guardian-gated and refuses `address(0)` — `TreasuryGovernor.sol:623-627` |
| Can do | `cancel(id)` — marks a proposal cancelled and, if it had been executed, deactivates the live envelope (`:608-613`); and `setQuoteOracle(o)` (`:935-939`) |
| Cannot do | propose, vote, execute, redirect a rotation, or change any timing |

Zero is refused because the guardian is the sole caller of both `cancel` and
`setQuoteOracle`, and the setter is itself guardian-only — burning the seat would
dead-end both controls permanently with no way to appoint a replacement
(`:615-622`).

### The priceability check

`_requirePriceable(quote)` (`:926`) refuses a quote the oracle cannot value.
Two deliberate exemptions:

- **Native is exempt** (`:927`). `address(0)` is the fallback every generation can
  always launch against; refusing it because a feed lapsed would strand the
  treasury with nowhere to rotate **back** to, turning a price outage into a
  governance deadlock.
- **An unset oracle is exempt** (`:928-929`). A deployment that never wires one is
  measuring volume in raw quote units throughout, which is self-consistent.

What it prevents: the failure is not a revert. `CauldronHook._toUsd` returns 0 for
an unpriceable asset, and 0 means *cannot judge* — `_recordVolume` writes nothing,
no bucket, no cumulative total, no crystal credit. A generation rotated onto that
quote trades normally while recording **no** volume, and then reads as dying
(`:799-831`).

---

## 5. What governance cannot do

This section is the point of the whole design. Each item names the code that
enforces it.

### Neither governor can choose the asset

**The allowlist is not votable.** Only the registry's `onlyOwner` — the governance
timelock — may add a quote asset, via `setAllowedQuote(quote, allowed, scale)`
(`CauldronRegistry.sol:308`). A proposer picks *from* the set and can never add to
it. A proposer curating their own set is the obvious capture vector: they add a
token they control and drain the pool into it (`CauldronBase.sol:315-329`).

This is stated as the single most important guardrail in `TreasuryGovernor`'s own
header (`:46-52`): even a fully captured vote cannot route the treasury into an
attacker's token. Everything else limits damage; this removes the category.

Two further bounds on what the owner may allowlist:

- **Native ETH can never be removed** — `setAllowedQuote(address(0), false, …)`
  reverts `NativeQuoteRequired` (`CauldronRegistry.sol:309`). It is the fallback
  every generation can launch against and the sink a failed non-ETH payout rolls
  into.
- **Nothing at or above `QUOTE_WATERMARK`** may be allowlisted
  (`CauldronRegistry.sol:320`), which is what keeps "quote sorts below token" an
  invariant.

### A brew proposal cannot brick the machine

Every attacker-controllable field is either bounded at the boundary or clamped at
consumption, never allowed to revert inside `relaunch()`:

| Field | Bounded at propose | Clamped at relaunch |
|---|---|---|
| `name`/`symbol`/`baseURI`/`website`/`socials` | byte caps, `CauldronGovernor.sol:300-305` | — |
| `nftSupply` | `<= 100_000`, `:316` | clamped again, `CauldronRegistry.sol:925-927` |
| `quote` | allowlist, `:338-343` | re-checked, degraded to native, `CauldronRegistry.sol:915` |
| `renderer` | must have code, `:310` | — |

The byte caps cannot be moved to consumption: by the time `relaunch()` could
truncate anything, the cold SLOADs are already paid. Measured, an honest rebirth
costs 5,297,638 gas; one 24,007,131-gas `propose()` carrying 320KB in `baseURI`
pushed the next rebirth to 29,288,732 and out of gas
(`CauldronGovernor.sol:80-92`).

### Governance cannot pick the winner

There is no admin override in `CauldronGovernor`. The only privileged call is
`markConsumed`, restricted to the registry, and it can only ever **remove** a
proposal from contention (`:19-21`, `:475-480`). There is no pause.

### Governance cannot sit on a passed vote

`TreasuryGovernor.execute` is permissionless (`:550`). An owner who can refuse to
execute an approved rotation holds the same veto as one who can execute an
unapproved one (`cauldron/RedemptionExt.sol:295-299`).

### Governance cannot move more than the envelope, or faster than the caps

| Bound | Value | Cite |
|---|---|---|
| Any single removal | 50% of the live position | `PoolOps.sol:941` |
| Any single slice | `MAX_SLICE_BPS = 2500` (25%), well below the removal limit | `RedemptionExt.sol:598`, enforced `:326` |
| Cumulative per envelope | `MAX_ENVELOPE_BPS = 30_000` spend budget | `TreasuryGovernor.sol:308` |
| Envelopes in flight | one | `TreasuryGovernor.sol:437` |
| Gap between envelopes | `COOLDOWN`, 7 days on mainnet | `TreasuryGovernor.sol:438`, `:343` |
| Price per slice | caller-supplied `minOut` — a pumped price produces **no** fill, not a bad one | `TreasuryGovernor.sol:70-74`; `RedemptionExt.sol:269`, `:280` |

An envelope is permission to buy at a good price, never an obligation to buy at
any price (`TreasuryGovernor.sol:73-74`).

### Governance cannot weaken its own limits

`MAX_ENVELOPE_BPS`, `QUORUM_BPS` and `PROPOSAL_THRESHOLD` are `constant`
(`:308`, `:328`, `:331`). The four timings are `immutable` (`:274-280`). "A
governor that can vote to weaken its own limits does not have limits"
(`:259-260`).

### Governance cannot renounce control by accident

`CauldronBase.renounceOwnership()` reverts `RenounceDisabled`
(`CauldronBase.sol:446-451`). `MigrationVesting.renounceOwnership()` reverts
`OwnershipCannotBeRenounced` (`MigrationVesting.sol:358-360`). Ownership is
transferable — to a timelock — but the one-call version of the accident is closed.

### Governance cannot mint

No generation token has a mint function. The full supply is minted once in the
constructor, to the registry, and the only supply-changing call is registry-only
`burn` (`CauldronToken.sol:8-16`, `:46`, `:58`). Migration is conserved 1:1 by
transfer, never by minting (`CauldronRegistry.sol:1227-1232`).

### Governance cannot pause your exit

`setRedemptionPaused` is emergency-admin gated and deliberately **not** timelocked
— a live exploit needs a fast stop (`CauldronRegistry.sol:447-456`). But the pause
only holds while **nothing is armed**: `_redeemBlocked()` is
`redemptionPaused && emergencyReadyAt == 0` (`CauldronBase.sol:411-417`). The
instant a custody action is armed, the exit is forced open so holders can leave at
floor before anything moves. And arming is mandatory even at a zero delay
(`CauldronRegistry.sol:407`), so the guarantee cannot be configured away.

### What governance *can* do, stated honestly

The emergency admin is not a limited role. With an armed and elapsed timelock it
can withdraw a generation's entire LP to itself (`:469-478`), sweep the registry's
ETH or any ERC-20 (`:482-489`), and hand every position NFT plus all loose
balances to a successor contract (`:534-570`). The guardian can veto, the forced
exit opens during the window, and `emergencyDelay` is `immutable` so it cannot be
shortened after deployment (`:130`) — but the power itself is real and holders
should read it as such.

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
  - `cauldron/CauldronGovernor.sol:532-550` documents `MAX_LEADER_SCAN = 64` as
    the bound on the leader rescan. `_recomputeLeader` (`:554-571`) does not use
    it — it iterates `BENCH_SLOTS` (8). The constant is dead and its NatSpec
    describes a replaced design. The replacement *is* explained at `:555-559`, so
    the file contradicts itself in two places.
  - `cauldron/TreasuryGovernor.sol:637-655` documents a `MAX_WINNER_SCAN`
    positional bound at length, then states at `:656-657` that it was removed. The
    surviving block is a record of a rejected design, not of the code.
  - `cauldron/TreasuryGovernor.sol:933-934` calls `setQuoteOracle` "Timelock-set".
    The gate is `msg.sender != guardian` (`:936`), not the timelock.
  - `cauldron/TreasuryGovernor.sol:560` and `:611` carry inline line references
    (`:273`, `:409`, `:322`) that no longer point at the cited code. Cross-file and
    intra-file line references throughout this tree have drifted.
- **Unverified:** the gas measurements quoted inside the governors' comments
  (5,297,638 / 24,007,131 / 29,288,732 gas; 11.8M and 15.6M gas spam runs; 6,421
  vs 363,633 gas) were not re-measured in this pass. `RedemptionExt` is out of scope for this
  document; only its governor-facing gates were read (`:295-299`, `:326`, `:598`),
  not its rotation internals.
