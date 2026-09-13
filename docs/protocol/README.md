# Protocol documentation

The authoritative description of Cauldron / Magic Internet Frens: a Uniswap V4
hook protocol with an on-chain lifecycle, a perpetuals engine, an NFT gacha, and
an off-chain indexer, API and operator toolchain.

Documents are numbered. On-chain mechanics come first, off-chain systems last.

---

## Index

| # | Document | What it covers |
|---|---|---|
| 01 | [`01-OVERVIEW.md`](01-OVERVIEW.md) | What the protocol is, and the contract-by-contract map of the deployment |
| 02 | [`02-LIFECYCLE.md`](02-LIFECYCLE.md) | The live–die–reborn cycle: summon, trade, death, relaunch |
| 03 | [`03-GENESIS-AND-SEEDING.md`](03-GENESIS-AND-SEEDING.md) | The genesis presale, ignition, and how launch liquidity is streamed |
| 04 | `04-*.md` | *Reserved — not yet written.* |
| 05 | `05-ARCHITECTURE.md` | Contract layout, the delegatecall facet, and the registry's forwarders |
| 06 | [`06-HOOK.md`](06-HOOK.md) | `CauldronHook`: what runs in `beforeSwap` / `afterSwap` and why |
| 07 | `07-FEES.md` | Where every basis point of a trade's fee goes |
| 08 | `08-*.md` | *Reserved — not yet written.* |
| 09 | [`09-FRONTEND.md`](09-FRONTEND.md) | Every write path (function, selector, asset, slippage, approvals), the read paths, and what the UI shows when data is stale |
| 10 | [`10-INDEXER-AND-API.md`](10-INDEXER-AND-API.md) | What the Ponder indexer ingests and serves, the freshness beacon, and every serverless route with its authentication, rate limiting and cost |
| 11 | [`11-OPERATIONS.md`](11-OPERATIONS.md) | Environment variables, the two keeper loops, the market maker, the recovery scripts, and a health checklist |
| 12 | [`12-DEPLOYMENT.md`](12-DEPLOYMENT.md) | A fresh deployment from the deploy scripts: contract order, constructor arguments, every wiring call and its ordering constraint, then verification |
| 13 | [`13-PERPS.md`](13-PERPS.md) | The perp engine: opening and closing, collateral and leverage, the vault and who bears loss, the full liquidation path, every mark source and its fallback order, solvency accounting, funding and fees |
| 14 | [`14-QUOTE-ROTATION.md`](14-QUOTE-ROTATION.md) | Why a generation can hold more than one quote asset: the rotation state machine, the envelope lifecycle, the oracle's fail-safe/fail-open split, slice and leg mechanics, and what every stored quantity does across a rotation |

Documents 04, 05, 07 and 08 are referenced by their siblings but were not
present when this index was written. Their titles above are taken from those
references (`06-HOOK.md:19`, `01-OVERVIEW.md:147`); the 04 and 08 slots are
**unverified** — no document in this directory names them.

---

## Start here

**If you are a user** — someone who wants to trade, mint, stake or vote:

1. [`01-OVERVIEW.md`](01-OVERVIEW.md) — what the thing is.
2. [`02-LIFECYCLE.md`](02-LIFECYCLE.md) — why the token you hold can be
   replaced, and what happens to it when it is.
3. `07-FEES.md` — what a trade actually costs you.

**If you are an integrating engineer** — calling the contracts or reading the
data:

1. [`09-FRONTEND.md`](09-FRONTEND.md) §2 — the write-path table. Every
   entrypoint, its selector, whether it takes native ETH or an ERC20, and where
   the slippage floor comes from. This is the shortest complete list of what the
   protocol accepts.
2. [`10-INDEXER-AND-API.md`](10-INDEXER-AND-API.md) §1.3 — the read API, and
   §1.4 for how to tell whether the data you just read is current.
3. `05-ARCHITECTURE.md` — which calls land on the registry and which are
   forwarded into the facet. The registry has **no catch-all fallback**, so an
   unlisted selector reverts.

**If you are an operator** — running the deployment:

1. [`12-DEPLOYMENT.md`](12-DEPLOYMENT.md) — the deploy sequence and its ordering
   constraints. Read §5 before §4; the constraints explain the order.
2. [`11-OPERATIONS.md`](11-OPERATIONS.md) §1 — the environment, then §5 for the
   health checklist and §6 for what to do when a check fails.
3. [`12-DEPLOYMENT.md`](12-DEPLOYMENT.md) §7 — the deployment records disagree
   with each other. Know which file is real before you touch anything.

---

## What is generated, and what is not

None of these documents are generated. Every one was written by reading source
and citing `path/file:line`.

Some of them lean on a machine-checked artefact. `audit/graph/*.md` and
`audit/graph/*.json` are a function-reachability graph validated against the
compiler's own output (`audit/graph/validate.py`, `audit/graph/make_readme.py`).
Where a document states that a function exists, that a selector is or is not
implemented, or that a call path is unreachable, that claim can be checked
against the graph rather than against a comment. The contract-side documents
(01–08) use it most; the off-chain documents (09–12) cite application source
and computed selectors directly.

Selectors quoted in 09 and 12 were computed with `cast sig` against the
signatures the code actually encodes, not copied from a table.

---

## The rule these documents follow

Every claim carries a file and line that was read. If a comment, a header or an
older document says a feature exists and the code does not implement it, the
code is described and the disagreement is recorded in that document's
**Verification** footer. Aspirations are not written as behaviour.

Each document ends with the commit it was verified against.

---

## Related material outside this directory

| Path | What it is |
|---|---|
| `audit/` | Audit and red-team reports, the deploy runbook, and the verified function graph |
| `audit/prompts/` | The prompts used to drive audit passes (moved here from `docs/`) |
| `archive/superseded-docs/` | Documents kept for history; not current |
| `indexer/deployments/round.json` | The canonical deployment manifest — the single file the frontend, the indexer and the operator scripts all read |

---

## Verification

- `git rev-parse --short HEAD` → `20d6de2`
- Disagreements found: documents 04, 05, 07 and 08 are cited by their siblings
  but were not present in this directory when the index was written; the 04 and
  08 titles are unknown and are marked reserved rather than guessed.
