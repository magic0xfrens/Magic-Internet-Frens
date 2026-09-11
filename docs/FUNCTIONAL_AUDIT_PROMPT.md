# Functional Audit — Orchestrated

## AUTHORIZATION & CONTEXT

- This is **my own protocol.** I am the author (git author `0x0010110`, repo `Magic-Internet-Frens`).
- This is a **functional correctness / behavioral conformance audit** of my own smart
  contracts before mainnet — verifying that every feature does what it is designed to
  do, end to end, including correct handling of ordinary edge cases.
- This is QA and verification work, not exploitation. Findings are functional defects
  (a feature does not behave as specified) and are fixed in-repo.

You are the **orchestrator** of this functional audit. You reuse the function graph
already built at `audit/graph/` (nodes, edges, authority, reads/writes, value flow).
If that graph is absent or stale, rebuild the parts you need — do not re-derive what is
already there.

The protocol is Magic Internet Frens / The Cauldron: an autonomous, infinitely-
relaunching token protocol on Uniswap V4, with an NFT collection, a perp engine, holder
dividends, a rotating LP quote asset, and on-chain governance. ~33k lines of Solidity
outside `lib/`, 486 external/public entrypoints, 87 Foundry suites.

Four phases: **specify → verify conformance → exercise end-to-end → fix.** You delegate
to subagents; you own correctness.

---

## Prime directive: describe only what the code does

A functional audit is worthless if the spec it checks against is fiction.

1. **Every behavioral claim carries `path/File.sol:line`, verified by reading it.**
2. **Never name a function, event, or state variable without grepping it first.**
3. **Separate three things and never merge them:** what the code is **designed** to do
   (intent — from NatSpec, function names, tests, `docs/`), what it **actually** does
   (traced execution), and the **delta**. The delta is the finding.
4. **Tag conformance** per feature: `CONFORMS` (matches intent, tested),
   `CONFORMS-UNTESTED` (matches intent, no test proves it), `DEVIATES` (does something
   other than intent), `UNDERSPECIFIED` (intent itself is ambiguous or self-
   contradictory), `MISSING` (intent exists, implementation does not),
   `DESIGN-ONLY` (documented and perhaps branched, but not in this tree),
   `DEPRECATED-PRESENT` (superseded by newer intent but still live in code).
5. A comment stating intent is **evidence of intent, not of behavior.** When comment
   and code disagree, that is a finding — determine which is wrong.
6. Discard any subagent claim you cannot locate in the code. Record the discard.

---

## Environment

```bash
cd contracts/solidity
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com \
       POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
       POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
FOUNDRY_PROFILE=cauldron forge build --sizes
FOUNDRY_PROFILE=cauldron forge test
```

`cauldron` profile is mandatory (V4 deps pin old solc). Many suites are fork-gated and
silently skip without those env vars — report skip counts. Review the **working tree**,
not HEAD (~50 files modified, uncommitted). Note the current branch (`git branch
--show-current`): design docs may describe work living on *other* branches, which is
exactly the `DESIGN-ONLY` case. Frontend: `npm run dev` (5173), `type-check`, `build`.

Intent sources to read (unlike a blind security pass): `docs/PROTOCOL_SPEC.md`,
`FLYWHEEL_ECONOMICS.md`, `TOKENOMICS.md`, `LAUNCH_LADDER_DESIGN.md`,
`TREASURY_FUND_PLAN.md`, `AI_REBIRTH_SYSTEM.md`, `PHOENIX_*`,
`contracts/solidity/CAULDRON.md`, and any `*_DESIGN.md` / `*_UNIFY.md` under
`contracts/solidity/` (e.g. `COLLECTION_FLOOR_UNIFY.md`). They state intent; find where
code diverges from them and where they contradict each other.

---

## Phase 1 — Write the specification

Produce `audit/spec/FUNCTIONAL_SPEC.md`: the complete written description of what this
protocol is supposed to do, feature by feature. This is what the audit checks against,
and it does not currently exist in one place. **Nothing is too small to write down.**

Per feature: **Purpose** (one sentence) · **Entrypoints** (`Contract.fn`, with
authority) · **Preconditions** · **Behavior** (state transition step by step, value
moved and in what denomination) · **Postconditions & invariants** · **Edge cases**
(the boundary behaviors that are part of *correct* operation) · **Events**.

Feature areas — each maps to real, grounded functions:

**A. Genesis & NFT collection** — presale summon (`MiFrensGenesis.summon`), mint
(`MiFrensGenesis.mint`, `CauldronCollection.mint`), reveal in batches (`reveal`,
`revealBatch` — the sealed-crystal flow), gacha (`CauldronGachaRouter.openReady`),
Liquidatoor badges (`mintLiquidator`, `mintLiquidatorWithStats`, `LIQUIDATOR_ID_BASE`,
`LiquidatoorRenderer`).

**B. Iteration lifecycle** — first iteration (`CauldronRegistry.summon`), permissionless
relaunch (`relaunch`), the creature cycle (MIT→SPIRIT→WRAITH→BEAST→ASTRAL→STORM→repeat),
cross-generation claims (`claimByBurn`, `claimByBurnUpTo`, `MigrationVesting.claimByBurn`
/ `startVest` / `vestBatch` / `claim`), the 1:1-forever guarantee.

**C. Volume, credit & death** — NFTs and swaps generate volume/mint-credit (hook volume
accounting, `_commitCrystals`, `nftCredit`), USD denomination across quotes
(`QuoteOracle.usdPerRawUnit` / `cachedUsdPerRawUnit`), death detection (`isDead()`, the
death threshold, the 24h window).

**D. Perps** — vault staking of both base and iteration token (`PerpVault.depositEth` /
`depositToken` / `withdrawEth` / `withdrawToken`, PLV, insurance, `fundFromVault` /
`fundTokenFromVault`), open/close (`openLong`, `openShort`, `close`), liquidation
(`liquidate`, in-swap `liquidateInSwap` from `afterSwap`), funding and marks
(`fundingDelta`, TWAP, `poke`), accounting edge cases (bad debt, insurance-then-PLV
ordering, queued exits), Liquidatoor badge minting on liquidation.

**E. Community LP & quote management** — treasury-curated quote allowlist
(`setAllowedQuote`), a governance proposal naming its quote (`CauldronGovernor` /
`TreasuryGovernor` `propose` / `vote` / `execute`), switching an iteration's LP quote
asset **while live** (`rotateSlice`, `QuoteRotator.rotateStep`, rotation-as-a-flow in
atomic slices), relaunching against a different quote, gradual/progressive LP seeding
(`CauldronSeeder`, in-swap `pokeInSwap`, seed window).

**F. Dividends** — the multi-asset fee basket (`fundToken`, `claimTokens`, `claim`,
`claimMany`, `withdrawOwed` / `withdrawOwedToken`), dividend settlement on transfer
(`onMiFrenTransfer`), enchant/re-enchant of a moved fren (`castSpell`, `enchantFee` =
`enchantFeeMultBps × floorPerFren`).

**G. Floors, redemption & the 2× treasury ratchet — BOTH genesis AND creatures.**
This area is **mid-migration across three overlapping mechanisms**; the audit must
establish, per collection type, which path is actually live, whether they conflict, and
whether the safety invariant is enforced. Do not describe only the genesis path.

  **G1 — Genesis (OG) floor, LIVE and built.** `redeemOgFren` recycles an OG genesis
  fren for its live floor share of the current iteration token — NFT moves to the
  **treasury, not burned**. `buyTreasuryOgFren` buys a recycled OG back for **2× the
  live floor**, paid in the current token → added to the reserve, so the floor
  **ratchets up** for every remaining holder. `donateToReserve` grows it
  permissionlessly. (`CauldronRegistry` forwards to `RedemptionExt`.)

  **G2 — Creature / iteration-collection floor, THREE mechanisms in the tree at once:**
  - **ETH vault** (`CauldronVault.redeem` — burn NFT → ETH slice, live). Still present;
    `CauldronFactory` still deploys it. `COLLECTION_FLOOR_UNIFY.md` says delete it.
    Classify: `DEPRECATED-PRESENT` or live?
  - **Ledger crystallization** (`CollectionLedger.credit` / `redeem` / `buyback`, with
    the same 2× ratchet as G1). `buyback` is wired from `PoolOps.sol:1286`; determine
    whether `redeem` has any production caller and whether it is death-only or live.
  - **Unified live model** `redeemCreature(gen,tokenId)` / `buyTreasuryCreature(gen,
    tokenId)` — the target design that mirrors G1 for creatures (NFT→treasury, live
    redeem from the reserve LP, 2× ratchet). **Grep confirms these do not exist in the
    tree** — classify `DESIGN-ONLY` and cite `COLLECTION_FLOOR_UNIFY.md` + its branch.

  **G3 — INVARIANT R (the safety core).** The unified design shares ONE reserve LP
  across genesis + every creature collection + migration, sound only iff, on **every**
  credit and redeem:
  `Σ(genesisReserveOutstanding + Σ_gen entitledTokens[gen] + migrationOutstanding) ≤
  reserve LP token balance`. The doc calls for an on-chain assert. **Determine whether
  that assert exists on every path today**, or only holds by construction. If it is
  absent, that is a headline finding regardless of exploitability, because it is the one
  thing standing between a ledger bug and bricking the last redeemers.

  **G4 — Fold-forward.** On relaunch, does each collection's entitlement re-express
  correctly in the new iteration token (and the new quote, if rotated)? Genesis uses the
  `genesisPending` / `claimByBurn` path — verify creatures do too, or note the gap.

Delegate spec-writing in parallel, one subagent per feature area, each handed the
relevant subgraph. Brief: *"Document what the code does and what it appears designed to
do, with line numbers. Where the two differ, flag it — do not resolve it. Do not judge
security; describe function."* You reconcile — especially cross-feature interactions (a
relaunch that also rotates the quote, re-seeds, pays dividends and folds forward the
floors touches D, E, F, G at once).

---

## Phase 2 — Verify conformance

For every feature, trace the actual execution path and classify with the Phase-1 tags.
`DEVIATES`, `MISSING`, `DESIGN-ONLY` (where a user would reasonably expect it live), and
`DEPRECATED-PRESENT` (two mechanisms for one thing) are all findings; each needs the
exact location and the correct behavior it fails to deliver.

Interaction seams to check hardest:

- A relaunch that changes the quote asset — new pool seeds, volume stays consistent,
  dividends and **all floors** fold forward, perp engine follows.
- Rotating an LP quote in a live iteration — reserve, death detection, perp mark stay
  coherent across a partial (sliced) rotation.
- Cross-generation claims after multiple relaunches on different quotes — 1:1 honored in
  every asset.
- **The 2× ratchet, for BOTH genesis and creatures** — reserve grows monotonically,
  ledgers stay consistent with what is actually held, INVARIANT R holds on every path.
- Liquidatoor badge minting — fires on every liquidation path, including in-swap.

Finding schema:

```
FEATURE:      area + name
INTENT:       what it is supposed to do (spec ref + code comment/doc)
ACTUAL:       what it does (path/File.sol:line, traced)
DELTA:        the difference
CLASS:        CONFORMS | CONFORMS-UNTESTED | DEVIATES | UNDERSPECIFIED | MISSING | DESIGN-ONLY | DEPRECATED-PRESENT
IMPACT:       what a user experiences when this is hit
REPRO:        test path, or exact steps
```

---

## Phase 3 — Exercise the full journeys end to end

Foundry tests in `contracts/solidity/test/functional/` (prefix `FN_`) driving complete
flows as a user would:

1. **Genesis → first iteration:** presale summon → mint → reveal → first `summon()` →
   pool live and trading.
2. **Volume → death → relaunch:** volume → USD pricing → 24h decay → `isDead()` →
   permissionless `relaunch()` → LP recovered → next creature → seeded → holders
   `claimByBurn` 1:1.
3. **Perp full cycle:** stake base + iteration token → fund PLV → `openLong` → funding
   accrues → `close` with correct PnL; separately a position crosses maintenance →
   `liquidateInSwap` from a swap → Liquidatoor badge mints → insurance/PLV balances.
4. **Live quote rotation:** iteration on ETH → proposal names USDG → `rotateSlice`
   streams it → mid-rotation state coherent → completes on USDG.
5. **Relaunch on a new quote:** proposal names a non-ETH quote → `relaunch()` against it
   → seeding, dividends, floors, perps all follow the new denomination.
6. **Floors & redemption, genesis AND creature:** fees accrue as a basket → holder
   `claim`s → a fren is transferred (dividends settle) → moved fren re-enchants → OG
   `redeemOgFren` for floor → `buyTreasuryOgFren` at 2× ratchets the reserve; then the
   creature path — a creature holder redeems for the live token floor and someone buys
   the treasury creature at 2× — using whichever of G2's three mechanisms is actually
   live, and asserting INVARIANT R throughout.

Record pass / fail / could-not-construct (a journey you cannot even set up is itself a
finding about testability, and for journey 6 tells you directly which floor mechanism is
real).

---

## Phase 4 — Fix

For each `DEVIATES` / `MISSING` / `DEPRECATED-PRESENT`, fix it to match intent — unless
the *intent* is wrong or a design decision is genuinely open (the three-way floor state
is exactly this: closing it may be a design call, not a bug fix — surface it, recommend,
do not silently pick). Before each patch use the graph for blast radius. Per fix: root
cause; chosen shape and rejected alternatives; contract size before/after (`forge build
--sizes` — several contracts sit near the 24,576-byte EIP-170 limit); storage-layout
safety; regression test kept; full suite re-run (pass/fail/skip). Never weaken an
existing test to make a fix pass. Re-audit your own fixes — this repo's last remediation
introduced two of its own three findings.

---

## Deliverables

1. `audit/spec/FUNCTIONAL_SPEC.md` — the complete written specification (Phase 1). This
   alone is worth the audit: it turns intent scattered across code, six design docs and
   three prior audits into one conformance-checkable document.
2. `audit/CauldronFunctionalAudit.tex` → `.pdf` — match house style
   (`contracts/solidity/audit/MagicFrens_Independent_Audit_2026-09.tex` for the
   preamble; build `pdflatex` ×3 or `tectonic`). Contents:
   - **Abstract** — scope, method, headline conformance result.
   - **Methodology** — the four phases, the intent/actual/delta protocol, subagent
     discard counts.
   - **The specification** — the full feature spec, rendered, with a `longtable`
     **conformance matrix**: every feature × tag × test.
   - **Feature architecture** — TikZ diagrams for the six journeys; a dedicated diagram
     for the three-mechanism floor state and its intended unified end state.
   - **Findings** — one `tcolorbox` per deviation: intent, actual with a `listings`
     excerpt, delta, user impact, repro, class.
   - **Remediation** — per fix, as above.
   - **Coverage** — features tagged `CONFORMS-UNTESTED`, ranked by centrality to the
     flywheel.
   - **Threats to validity** — journeys not constructable, intent inferred, fork tests
     not run.
   - **Appendix** — reproduction commands, full suite output, the feature→function map.

Every number measured, every excerpt copied not retyped, every claim located. Report
progress as you go; surface any feature that is outright broken the moment you confirm
it.
