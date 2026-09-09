# Deep Audit + Architecture Prompt

Paste everything below the line into a fresh session opened at the repo root.

---

You are a senior protocol security auditor and systems architect. Your engagement
covers **Magic Internet Frens / The Cauldron** — an autonomous, infinitely-relaunching
token protocol built as a Uniswap V4 hook, plus its indexer, serverless API, and
React frontend. Audit it end to end, then design the architecture of the whole flow.

Do not skim. This is a real protocol holding real value on a live testnet deployment
(round 34, Sepolia) with mainnet on Robinhood Chain as the target. Treat every finding
as something that will be acted on.

## Ground truth

- Repo root: `/Users/0x0010110/Documents/GitHub/Magic Internet Frens`
- Audit commit: `0a1830b` (`test: repoint the swap fork suite at a pool that still has liquidity`)
- Working tree is clean apart from a nested `forge-std` pointer inside the
  `openzeppelin-contracts` submodule — vendored noise, not project code. Confirm this
  yourself with `git status` before you begin; if anything else is dirty, audit the
  working tree and say so.
- Scale: ~32.8k lines of Solidity outside `lib/`, 63 Foundry test files, ~24.4k lines
  of TypeScript/TSX across 43 components.
- The last commit message claims **461 tests passing on a Sepolia fork, 443 locally**.
  Verify that number. If it does not reproduce, that is finding #1.

## Build and test

Solidity lives under `contracts/solidity/` and needs a dedicated Foundry profile —
V4's deps pin old solc (`permit2 =0.8.17`, `solmate =0.8.15`) and cannot share a
compilation unit with the `^0.8.26` protocol code:

```bash
cd contracts/solidity
FOUNDRY_PROFILE=cauldron forge build
FOUNDRY_PROFILE=cauldron forge test
FOUNDRY_PROFILE=cauldron forge test --match-contract <Name> -vvv
```

Fork tests (`RotatorSwapFork`, `QuoteOracleFork`, `CauldronSummonFork`) no-op unless
`FORK_RPC` / `POOL_MANAGER` / `POSITION_MANAGER` are exported. Run them — a suite that
silently skips is not a passing suite. Read `contracts/solidity/foundry.toml` for the
`render` and `cauldron` profiles and why each one exists; the constraints encoded there
(`via_ir = true`, `optimizer_runs = 1`) are load-bearing, not cosmetic.

Frontend: `npm run dev` (Vite, port 5173), `npm run type-check`, `npm run test:unit`.

## Scope — four layers and the trust boundaries between them

**1. Protocol (Solidity, `contracts/solidity/`)**

| Contract | Role |
|---|---|
| `CauldronRegistry.sol` (1551) | Orchestrator: `summon()`, permissionless `relaunch()`, `claimTokens(gen)`. At the EIP-170 limit. |
| `CauldronHook.sol` (2027) | V4 hook. 24h volume tracking → `isDead()`, tiered fee collection, fee reserve that self-funds relaunches, in-swap perp liquidation. |
| `cauldron/PerpEngine.sol` (1591) | Hook-native perp engine, auto-liquidated from `afterSwap`. |
| `cauldron/PoolOps.sol` (1069) | Pool lifecycle: liquidity add/remove, atomic rotation slices. |
| `cauldron/QuoteRotator.sol` (490) | Rotates the LP's backing asset between allowed quotes. |
| `cauldron/QuoteOracle.sol` | Chainlink-backed USD price per quote; returns 0 when untrusted. |
| `cauldron/MiFrensDividend.sol` (393) | Holder dividends, now over a multi-asset fee basket. |
| `cauldron/FeeRouteLib.sol` | Stateless primitive: `send` for transfers, `deliver` for recipients that must be told about a deposit. |
| `cauldron/PerpVault.sol`, `CauldronSeeder.sol`, `CauldronGovernor.sol`, `TreasuryGovernor.sol`, `CollectionLedger.sol`, `RedemptionExt.sol`, `ReserveLib.sol`, `SeedLib.sol`, `LaunchSniper.sol`, `MigrationVesting.sol`, `RoyaltyRouter.sol`, `CauldronFactory.sol`, `CauldronCollection.sol`, `MiFrensGenesis.sol` | Supporting system — all in scope. |

Also in scope: `CauldronToken.sol`, `MagicFrensPeg.sol`, `MagicFrensPresale.sol`,
`render/FrenRenderer.sol`, `render/LiquidatoorRenderer.sol`, `vendor/BaseHook.sol`
(vendored — verify it against upstream v4-core), and `deploy/*.s.sol`.

**2. Indexer (`indexer/`)** — Ponder. `ponder.config.ts`, `ponder.schema.ts`,
`src/index.ts`, `src/api/index.ts`. This is the frontend's *entire read layer*.

**3. API (`api/`)** — Vercel serverless: `fren-ask.ts`, `fren-teach.ts`, `x-token.ts`,
`brand.ts`, `cauldron/liquidatoor.ts`, `cauldron/unrevealed.ts`.

**4. Frontend (`src/`)** — React 19 + wagmi/viem + RainbowKit. 29 hooks in `src/hooks/`,
config in `src/config/`, on-chain access in `src/lib/cauldronOnchain.ts` and
`src/lib/cauldronIndexer.ts`.

**Deployment manifest:** `indexer/deployments/round.json` is the single source of truth,
read by *both* the frontend and the indexer. Understand why it lives inside `indexer/`
and what breaks if the two sides drift — the file's own comment explains it.

---

## Part 1 — Reconstruct the architecture

Do this before hunting bugs. You cannot audit a flow you cannot draw.

Read the code, not just the docs. `docs/PROTOCOL_SPEC.md`, `docs/FLYWHEEL_ECONOMICS.md`,
`docs/TOKENOMICS.md`, `docs/DEATH_SPIRAL_ANALYSIS.md`, `docs/TREASURY_FUND_PLAN.md`,
`docs/LAUNCH_LADDER_DESIGN.md` and `contracts/solidity/CAULDRON.md` state intent —
your job includes finding where the code disagrees with them.

Produce:

1. **The lifecycle**, as a sequence diagram with contract calls named:
   `summon()` → trading → fee accrual → volume decay → `isDead()` → `relaunch()` →
   LP recovery → next-gen deploy → seed → `claimTokens(gen)`. Mark every point where
   value moves and every point where an external actor can intervene.
2. **The value-flow map.** Every ETH/token path: swap fee → hook reserve → guild /
   floor / vault / dividend / perp splits, LP recovery, redemption, royalties.
   Where does value sit, who can move it, under what authority.
3. **The trust and permission model.** Timelock, `TreasuryGovernor`, `CauldronGovernor`,
   `emergencyAdmin`, hook owner, registry owner, keeper scripts (`scripts/keeper.sh`,
   `scripts/marketmaker.sh`). For each privileged function: who calls it, what stops
   them being malicious, and what happens if that key is lost or stolen.
4. **The invariant table.** Enumerate what must always hold — reserve floor, reserve
   ceiling, 1:1 claim guarantee across generations, supply conservation, perp
   solvency, dividend accounting ≤ funded amount. For each, name the test that
   enforces it (`test/invariants/`, `test/final/`, `test/attacks/`) or mark it
   **UNENFORCED**. The unenforced ones are where you look hardest.
5. **The four-layer data flow.** Chain → indexer → API → UI. Every place the frontend
   trusts indexer data, and what a compromised or stale indexer could make the UI show.

---

## Part 2 — Security audit

Threat classes that actually matter for this design. Go beyond the generic checklist.

- **V4 hook safety.** `beforeSwap`/`afterSwap`/`afterInitialize` return values and
  deltas, `BeforeSwapDelta` sign conventions, reentrancy through `PoolManager`'s
  unlock/settle pattern, `CurrencyNotSettled`, hook permission bits vs the CREATE2-mined
  address, and what a malicious pool initialized against this hook can do to it.
- **Death and relaunch.** Can `isDead()` be forced true or false? Volume is now
  normalized to USD via Chainlink — can a manipulated or stale oracle fake a death, or
  prevent a real one? What does a relaunch griefed at the wrong moment cost?
  What happens if `usdPerRawUnit` returns 0 mid-flow?
- **Perp engine.** Liquidation from inside `afterSwap` is the sharpest edge in this
  codebase. Self-liquidation, liquidation ordering, oracle/mark manipulation via the
  same swap that triggers liquidation, bad-debt socialization, `activeEthDepth()`
  bounding position size against a pool that may not be the one being traded.
- **Multi-quote (the newest and least-settled subsystem).** The last five commits
  introduced USD-denominated volume, the fee basket, quote-agnostic perps, and
  `FeeRouteLib`. Decimals handling across 6-decimal USDG and 18-decimal ETH/xNVDA,
  fee-on-transfer or rebasing quote assets, dust and rounding in the basket,
  `deliver` vs `send` correctness, and what a treasury-approved but hostile quote
  asset could do.
- **Accounting.** Rounding direction at every division. Does rounding ever favor the
  user over the protocol in a loop that can be repeated?
- **Griefing and MEV.** Sandwiching the seed, sniping the relaunch (`LaunchSniper.sol`
  exists — understand whether it defends or attacks), forcing the reserve past a
  ceiling or below a floor, gas-griefing the in-swap liquidation loop.
- **Upgrade and deploy.** CREATE2 address squatting (`test/attacks/A01_Create2Squat.t.sol`),
  deploy-script ordering, wiring gaps between `factory`/`registry`/`hook`/`engine`.
- **Off-chain.** Serverless functions: authz, injection, secret handling, rate limits.
  `api/fren-ask.ts` and `fren-teach.ts` are LLM-backed — check prompt injection and
  cost-amplification. `x-token.ts` handles OAuth. Frontend: `dompurify` usage,
  the `.env.local` / `.env.vercel-backup` files at repo root (are secrets committed?),
  and whether any private key or API key reaches the client bundle.

**Rules of engagement**

- Cite `file.sol:line` for every claim. No finding without a location.
- For every High or Critical, write a **failing Foundry test that demonstrates it**,
  placed in `contracts/solidity/test/audit/` alongside the existing `AuditPoC.t.sol`.
  A finding you cannot make fail is a hypothesis — label it as one.
- Read `audit/` and `contracts/solidity/audit/` first. Prior audits exist
  (`MagicFrens_Independent_Audit_2026-09`, `CauldronSecurityAudit`, the Uniswap hook
  allowlist brief). Do not re-report what was already found and fixed; *do* verify
  the fixes actually landed.
- Severity: Critical / High / Medium / Low / Informational, each with concrete impact
  and likelihood. Do not inflate. A Medium reported honestly is worth more than five
  padded Highs.
- Distinguish **bug** (code betrays intent) from **design risk** (code matches intent,
  intent is dangerous). Both are in scope; label which.

---

## Part 3 — The known frontier

`docs/TREASURY_FUND_PLAN.md` ends with three open problems the maintainer has already
reasoned about. Engage with these specifically — agree, disagree, or improve, but do
not ignore them:

1. **Dividend over a basket.** Three shapes were considered; option 3 (one
   USD-denominated accumulator, settled in a chosen asset) was judged almost certainly
   right. Pressure-test it. What breaks when the oracle is stale at claim time?
   What is the settlement-side solvency condition?
2. **EIP-170 on the hook.** Converting the five routing sites to `FeeRouteLib` was
   measured at **566 bytes over** against 30 bytes of headroom. The proposed fix is to
   move `_routeFee` and `_routePerpFee` wholesale into the library, passing config as
   arguments. Verify the measurement, then say whether the extraction actually reaches
   it — and what it costs in gas per swap.
3. **Which pool the perps trade.** `PerpEngine._key()` builds from
   `generationQuote[gen]`, so perps trade the *primary* pool, not the deepest. With
   several pools per generation the engine marks and liquidates against a pool that
   may be far thinner than a sibling. The maintainer calls this a correctness question,
   not a preference. Confirm or refute, and design the fix.

Then, as architect: given everything above, propose the target architecture for a
multi-pool, multi-quote generation. What must land before a generation runs more than
one pool with perps enabled, and in what order. Be specific about sequencing — this
protocol is deployed, so migration path matters as much as end state.

---

## Deliverables

Write to `audit/DEEP_AUDIT_<date>.md`:

1. **Executive summary** — 10 lines. Would you let this hold mainnet value today, and
   what are the three things standing between it and yes.
2. **Architecture** — the diagrams, value-flow map, trust model, and invariant table
   from Part 1.
3. **Findings** — severity-ordered, each with location, impact, a concrete exploit
   scenario, PoC test path, and a recommended fix.
4. **The frontier** — your answers to Part 3 plus the sequenced migration plan.
5. **Test-coverage gap analysis** — what the 63 suites do *not* cover, ranked by the
   value at risk behind each gap.
6. **What I could not verify** — be explicit. Fork tests you could not run, assumptions
   you had to make, code you did not reach. An audit that hides its blind spots is worse
   than one that names them.

Work through it systematically and report as you go. If you find something Critical,
surface it immediately rather than saving it for the report.
