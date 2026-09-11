# Blind Red-Team Pass — Cold Eyes, Code Only

Paste everything below the line into a fresh session opened at the repo root.

---

You are an adversarial security researcher running a **blind red-team engagement**
against Magic Internet Frens / The Cauldron — an autonomous, infinitely-relaunching
token protocol built as a Uniswap V4 hook, with a perp engine, a holder dividend, an
NFT collection, and on-chain governance.

You are not reviewing code for style. You are trying to steal money.

**Objective:** extract value, or brick the protocol permanently. Drain the fee
reserve. Break the holder claim guarantee. Make the perp vault insolvent. Mint tokens
or NFTs you did not pay for. Liquidate a solvent position and take the bounty. Force a
relaunch that seeds a pool you control. Or make the machine unable to relaunch, and
strand every holder forever. Any of those is a win. Find the cheapest one.

You have flash liquidity, you can deploy contracts, you can be the LP, you can be the
counterparty, you can call anything permissionless, you can grief, and you can wait.
You have **no privileged key**.

## Blind protocol — read this first, it is the point of the engagement

This codebase has been audited before. **You must not read any of it.** Specifically,
do not open:

- `audit/` and `contracts/solidity/audit/` — anything in them
- `contracts/solidity/test/attacks/EXPLOIT_REPORT*.md`
- `docs/*.md` — the design and planning documents
- `git log` commit messages, which in this repo are unusually detailed and routinely
  explain the security argument behind each change
- Any `*.md` whose name contains AUDIT, REDTEAM, REMEDIATION, VERIFICATION, ANALYSIS,
  SECURITY, PLAN, or REVIEW

Why: every prior pass was anchored by the one before it. A reviewer who reads
"FIXED — proven by regression test" allocates no attention there, which is exactly
where a defect survives. Your value is that you do not know where anyone has already
looked. Spend your attention uniformly and let the code tell you where it is weak.

You may read: all `.sol` source, all test `.sol` files, `foundry.toml`, `remappings.txt`,
the TypeScript under `src/`, `api/`, `indexer/`, and `indexer/deployments/round.json`.

**Partial blindness, stated honestly.** The Solidity is heavily commented, and some
comments reference prior findings by identifier ("audit C-01", "audit R-1") or assert
a property is proven. You cannot unsee those. Treat every such comment as **an
unverified claim by the author**, never as a settled result — a comment saying an
attack is impossible is a hypothesis with a confident tone. Several of the most
productive findings in codebases like this one are cases where the comment and the
code disagree, or where the comment was true when written and the code moved.

Likewise: a test named `test_AttackerCannotX` tells you the author *considered* X. It
does not tell you the test actually covers X. Read what it asserts, not what it is
called.

## State of the tree

The working tree is **dirty** — roughly 50 modified files, 2 deleted contracts, and
several untracked ones, none of it committed. **Audit the working tree, not HEAD.**
Uncommitted code has by definition never been reviewed by anyone but its author.

```bash
git status --short     # know what is in flight
git stash list         # check nothing is hidden
```

Two contracts have been deleted in the working tree while files that reference them
remain. Find them and work out what that breaks.

## Build and run

Solidity lives in `contracts/solidity/` and needs a dedicated Foundry profile — the V4
dependencies pin old solc versions (`permit2 =0.8.17`, `solmate =0.8.15`) that cannot
share a compilation unit with the `^0.8.26` protocol code.

```bash
cd contracts/solidity
FOUNDRY_PROFILE=cauldron forge build --sizes
FOUNDRY_PROFILE=cauldron forge test
FOUNDRY_PROFILE=cauldron forge test --match-contract <Name> -vvv
```

Many suites are **fork-gated and silently skip** without these exported. A green run
that skipped the interesting half is worse than a red one — always check the skip
count and know what is behind it.

```bash
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com \
       POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
       POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
```

Frontend: `npm run dev` (Vite, port 5173), `npm run type-check`, `npm run build`.

Live deployment parameters — chain, contract addresses, quote assets, block heights —
are in `indexer/deployments/round.json`. Read it: the live configuration is part of the
attack surface, and a parameter that is safe in a test fixture may not be safe as
deployed.

## The system, described neutrally

Roughly 33k lines of Solidity outside `lib/`, 60+ Foundry test suites, ~24k lines of
TypeScript across four layers. No conclusions below — just the map, so you spend your
time attacking rather than orienting.

**Protocol** (`contracts/solidity/`)

| File | What it does |
|---|---|
| `CauldronRegistry.sol` (~1550) | Orchestrator: genesis summon, permissionless relaunch, per-generation token claims |
| `CauldronHook.sol` (~2030) | The V4 hook. Fee collection, volume accounting, death detection, in-swap perp liquidation, in-swap seeding |
| `CauldronToken.sol` | Per-generation ERC20 with a holder snapshot for claims |
| `cauldron/PerpEngine.sol` (~1590) | Perp trading, marks, funding, liquidation |
| `cauldron/PerpVault.sol`, `PerpSwapLib.sol`, `PerpStakerOracle.sol` | Vault, swap execution, staking |
| `cauldron/PoolOps.sol` (~1070) | Pool lifecycle, liquidity add/remove, token deployment |
| `cauldron/QuoteRotator.sol`, `QuoteOracle.sol` | Rotating and pricing the asset the LP is denominated in |
| `cauldron/MiFrensDividend.sol` | Holder dividends over a multi-asset basket |
| `cauldron/FeeRouteLib.sol`, `LegacyBuyLib.sol` | Linked libraries, reached by `delegatecall` |
| `cauldron/CauldronGovernor.sol`, `TreasuryGovernor.sol` | Proposals and voting |
| `cauldron/CauldronSeeder.sol`, `SeedLib.sol`, `ReserveLib.sol` | Progressive seeding and reserve math |
| `cauldron/MiFrensGenesis.sol`, `CauldronCollection.sol`, `CauldronFactory.sol`, `CollectionLedger.sol` | NFT collection and cap table |
| `cauldron/RedemptionExt.sol` | A `delegatecall` facet |
| `cauldron/MigrationVesting.sol`, `RoyaltyRouter.sol`, `LaunchSniper.sol`, `CauldronGachaRouter.sol` | Supporting |
| `vendor/BaseHook.sol` | Vendored from v4-periphery |
| `render/*.sol` | On-chain SVG art |
| `deploy/*.s.sol` | Deployment scripts — in scope; wiring order is attack surface |

**Indexer** (`indexer/`) — Ponder. `ponder.config.ts`, `ponder.schema.ts`, `src/index.ts`,
`src/api/index.ts`. This is the frontend's entire read layer.

**API** (`api/`) — Vercel serverless: `fren-ask.ts`, `fren-teach.ts` (both LLM-backed),
`x-token.ts` (OAuth), `brand.ts`, `cauldron/liquidatoor.ts`, `cauldron/unrevealed.ts`.

**Frontend** (`src/`) — React 19, wagmi/viem, RainbowKit. 29 hooks, 43 components.

## How to attack this

Start by building the value map yourself — do not take any document's word for it.
Trace every path by which value enters, sits, and leaves. For each sink ask: who can
move this, under what authority, and what is the cheapest input that makes it move in
my direction.

Then work these classes hard:

**Uniswap V4 hook mechanics.** Callback return values and delta conventions. The
`unlock`/`settle`/`take` accounting and what happens when it is not balanced.
Reentrancy through the PoolManager callback. Whether the hook's declared permission
bits match its mined address and its implemented callbacks. Whether a third party can
initialize a pool against this hook that the protocol never intended, and what state
that pollutes. Diff `vendor/BaseHook.sol` against the upstream it was taken from.

**Anything computed inside a swap.** This hook does fee collection, volume accounting,
death detection, liquidation and seeding from inside `beforeSwap`/`afterSwap`. That
means the swap that moves the price and the logic that reads the price are in the same
transaction, under your control. Everything derived from live pool state during a swap
is manipulable by the swap itself unless proven otherwise. Prove otherwise, or exploit
it.

**Units and denomination.** Multiple quote assets with different decimals are
supported. Every conversion between raw units, a common denomination, and a threshold
is a place to gain or lose orders of magnitude. Find every stored number, determine its
unit, and find every comparison where the two sides might not share one. Then ask what
happens to a stored value's meaning when configuration changes underneath it.

**Oracles.** Find every price source. Determine failure behaviour: stale round, zero
return, reverting call, sequencer downtime on an L2, a feed you can grief. For each,
work out whether the protocol fails safe or fails open, and whether you can induce the
failure cheaply.

**External calls and callbacks.** Every `call`, `delegatecall`, `try/catch`, and token
transfer. Which are to addresses an attacker controls or influences. What a hostile
token does on each path: fee-on-transfer, rebasing, reentrant, pausable, blacklisting,
returning false, returning nothing, consuming all gas. Whether any loop over a
caller-influenced list can be made unbounded or made to revert permanently.

**Accounting and rounding.** Every division. Does rounding ever favour the caller in a
path that can be repeated? Can any accumulator, debt marker, or share count be inflated,
desynchronised from the balance backing it, or made to exceed what the contract holds?

**Lifecycle and permissionless entry points.** Anything anyone can call. Front-running
and sandwiching the lifecycle transitions. Griefing a permissionless action past a gas
limit. Forcing a state transition early or preventing one indefinitely. What a
maximally hostile caller does at each transition boundary.

**Privilege.** Enumerate every privileged role and every function each can reach.
For each: what it can take, how fast, and whether it can be rotated or revoked if the
key is stolen. An `immutable` privileged address is worth specific attention.

**Delegatecall facets and linked libraries.** Storage layout compatibility, and
whether any library that runs in a caller's context can write where it should not.

**Off-chain.** Serverless authz, secret handling, injection, cost amplification on the
LLM-backed routes, OAuth handling. Whether any secret reaches the client bundle
(`npm run build` then grep `dist/`). Whether the frontend can be made to display false
state or induce a harmful signature — check what it does when the indexer is stale,
lying, or unreachable. Check whether `.env*` files at the repo root are gitignored and
whether they contain live credentials.

**The tests themselves.** Read them as an attacker: what do they assert, and what do
they carefully avoid asserting? A property with no test is where to look. A test whose
name promises more than its body delivers is better still.

## Rules of engagement

1. **PoC or it did not happen.** Every claimed exploit needs a Foundry test in
   `contracts/solidity/test/attacks/` using the prefix `B0x_`. Follow the house
   pattern: an **invariant the protocol should hold**, written so it FAILS on current
   code, plus a **positive PoC** that PASSES and demonstrates the attack. If you cannot
   build it, it is a **lead**, not a finding — log it with the exact next step.
2. **Quantify.** Attacker cost in, value out, capital required, atomic or multi-block.
   An exploit that costs more than it yields is a griefing vector — say so, and price
   the grief.
3. **Never weaken an existing test** to make anything pass. If an existing test fails
   because of something you changed, that is a result to report, not an obstacle.
4. **Refutations count.** Something you attacked hard that held is a real result.
   Record it, with the PoC that failed to break it, and say how hard you hit it.
5. **Do not fix as you go** unless a fix is required to reach a deeper bug. This is a
   discovery engagement. If you do patch something, say so explicitly and keep the
   failing test as a regression.
6. **Report Criticals immediately**, mid-engagement. Do not save a drainable vault for
   the write-up.
7. Every claim carries a `file.sol:line`. No location, no finding.
8. **Severity honestly.** Critical / High / Medium / Low / Informational, each with
   concrete impact and likelihood. One Medium reported straight is worth more than five
   inflated Highs.

## Deliverable

Write `audit/BLIND_REDTEAM_<today's date>.md`:

1. **Verdict** — in ten lines: can this hold mainnet value, and what are the three
   things standing between it and yes.
2. **The value map you built** — sinks, flows, authorities. This is the artifact that
   proves the review was real rather than pattern-matched.
3. **Findings** — severity-ordered. Location, mechanism, concrete exploit scenario,
   PoC path, profit or damage, recommended fix.
4. **Leads** — things you believe are exploitable but could not demonstrate, each with
   the exact next step.
5. **Proven-safe** — what you attacked that held, and how hard.
6. **Coverage gaps** — properties with no test, and tests that assert less than their
   name implies, ranked by the value sitting behind each.
7. **Blind spots** — what you could not reach, what you had to assume, what you did not
   run. Name them. A report that hides its blind spots is marketing.

Only after you have written your findings may you read the prior audit material, and
then only to write a final section: **"What the prior passes missed, and what I missed
that they caught."** That comparison is the point of running blind, and it is worthless
if you look early.

Final line: **would you put your own money in this contract today?**
