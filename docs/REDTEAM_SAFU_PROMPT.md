# Red-Team / "Safu" Security Review — Orchestrated

## AUTHORIZATION & CONTEXT

- This is **my own protocol.** I am the author (git author `0x0010110`, repo `Magic-Internet-Frens`).
- This is a **pre-mainnet defensive security review** of my own smart contracts. The goal
  is to drive the set of exploitable and protocol-breaking conditions to empty before
  deployment, then fix what remains.
- Adversarial threat modeling — reasoning as a well-resourced attacker to bound
  worst-case behavior — is the method. The intent is defensive: find the weakness, prove
  it, close it.
- Honest framing: no audit proves a contract "100% safe." What this produces is a set of
  demonstrated attacks (each with a PoC and a fix) plus a priced residual — the things
  that remain and why they are acceptable. That is what "safu" means in practice.

You are the **orchestrator**. Reuse the function graph at `audit/graph/` (nodes, edges,
authority, reads/writes, value flow, reachability); rebuild only what is stale. You
delegate to subagents but own correctness.

Protocol: Magic Internet Frens / The Cauldron — autonomous, infinitely-relaunching token
protocol on Uniswap V4, with an NFT collection, a perp engine, holder dividends, a
**rotating LP quote asset**, and on-chain governance. ~33k lines Solidity outside
`lib/`, 486 external/public entrypoints, 87 Foundry suites.

## Two objectives, weighted equally

**TRACK A — Value extraction.** Any path that moves value to an attacker or destroys it:
drain the fee reserve below its floor, break the per-generation 1:1 claim guarantee,
make the perp vault insolvent, mint tokens or NFTs without paying, liquidate a solvent
position for the bounty, force a relaunch that seeds an attacker-controlled pool, or
over-claim a dividend/floor entitlement beyond what backs it.

**TRACK B — Liveness & griefing (the "annoying spam that breaks it").** The core promise
is *runs forever, relaunches permissionlessly*. A cheap, unprofitable attack that
**bricks that** is as severe as a drain. Hunt anything that permanently prevents
`relaunch()`, freezes the perp engine, jams a live quote rotation, blocks holder claims
or redemptions, or wedges governance. Spam and dust that inflate cost or corrupt
accounting count. **An attack with zero profit that strands every holder is a Critical.**

You have flash liquidity, can deploy contracts, be the LP or counterparty, call anything
permissionless, spam, dust, and wait. You hold **no privileged key**.

## Prime directive: no invented facts

1. **Every claim carries `path/File.sol:line`, verified by reading it.** No location, no finding.
2. **Never cite a symbol without grepping it first.** If it isn't in `grep -rn`, it doesn't exist. Invented function names are the top failure mode.
3. **Quote before you characterize.** Paste the code into notes, then describe it.
4. **Tag every claim** `VERIFIED` (ran it) / `DERIVED` (read + reasoned) / `HYPOTHESIS` (suspect, unconfirmed). Never blur.
5. **A comment is not evidence.** Security-property comments in this repo have been wrong before. Verify or tag `HYPOTHESIS`.
6. **A test name is not coverage.** Read the body.
7. **Solidity `^0.8.26`** — arithmetic checked; no unchecked-overflow findings outside `unchecked` blocks.
8. Bytecode and passing tests outrank all prose, including your own notes.
9. **Discard any subagent finding you cannot independently locate.** Record the discard count.

## Environment

```bash
cd contracts/solidity
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com \
       POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
       POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
FOUNDRY_PROFILE=cauldron forge build --sizes
FOUNDRY_PROFILE=cauldron forge test
```

`cauldron` profile mandatory. Fork-gated suites silently skip without those env vars —
report skip counts. Review the **working tree**, not HEAD (~50 files modified,
uncommitted — the least-reviewed code in the repo). `indexer/deployments/round.json`
holds live params; the live config is attack surface. Frontend: `npm run dev` (5173),
`type-check`, `build`.

---

## TRACK A — Value extraction, by class

Hand each hunting subagent the relevant subgraph, not a filename.

- **In-swap manipulation.** Fee take, volume accounting, death detection, liquidation and seeding all run inside `beforeSwap`/`afterSwap`. The swap that moves the price and the code that reads it are one attacker-controlled transaction. Anything derived from live pool state during a swap is manipulable unless proven otherwise.
- **The perp engine (sharpest edge).** In-swap liquidation (`liquidateInSwap`, `liquidateManyInSwap`): self-liquidation, ordering across a batch, manipulating the mark via the same swap that triggers the liquidation. `PerpEngine._key()` reads `generationQuote[gen]` (the *primary* pool) while `activeEthDepth` bounds size against the pool it thinks it trades — with multiple pools or a live rotation those diverge; build the divergence. Funding manipulation, bad-debt socialization, queued-exit seniority.
- **Denomination & decimals.** USDG is 6-decimal, ETH/xNVDA 18. Every raw↔USD conversion (`QuoteOracle`, `quoteScale`, `_toUsd`) is a potential 10^12 error. Find a path that treats 6 as 18 or vice versa and size the profit.
- **The oracle.** `usdPerRawUnit` returns 0 when untrusted. Induce the 0 (stale round, L2 sequencer downtime, a grief-able feed) and see if it fakes a death, mis-splits a fee, or misprices a liquidation.
- **Reserve & floor accounting.** INVARIANT R (`Σ entitlements ≤ reserve LP balance`) — find a credit/redeem path that violates it, especially the 2× ratchet (`buyTreasuryOgFren`, `CollectionLedger.buyback`) and fold-forward across relaunch. Rounding direction in any repeatable loop.
- **Fee routing & reserve denomination.** `FeeRouteLib`, `_feeAsset`, `relaunchETH` vs `relaunchAsset[x]`, `releaseRelaunchAsset`. Can you credit the wrong denomination, or double-spend an asset between release paths?
- **CREATE2 & watermark.** Token address mining, the `QUOTE_WATERMARK` floor/ceiling pair — can a pool reach adoption inverted (quote sorts above token), flipping every buy into a sell?
- **Off-chain.** Serverless authz/secrets, injection and cost-amplification on the LLM routes, OAuth, secrets in `dist/`, and whether a stale/lying indexer can induce a harmful signature.

## TRACK B — Liveness & griefing, by target

**Permissionless entrypoints — abuse each.** `relaunch`, `rotateSlice`, `redeemOgFren`, `buyTreasuryOgFren`, `donateToReserve`, `materializeLegacyReserve`, `fundPrimeBuy`/`sweepPrimeBuy`, `enableAutoMigrate`/`disableAutoMigrate`, `legacyBuyStep`, `fundLegacyBuffer`, `claimProposerFees`, governor `propose`/`vote`, guardian `vetoEmergency`. For each: can repeated/dust/ill-timed calls wedge state, strand value, or block a legitimate call?

**In-swap gas griefing.** The hot path fires liquidation, gacha, legacy buyback, and seeder pokes under hard gas reserves: `LIQ_GAS_RESERVE=180k`, `GACHA_GAS_RESERVE=200k`, `LEGACY_GAS_RESERVE=220k`, `SEED_POKE_GAS_RESERVE=350k` (`CauldronHook.sol:152-344`). Can a swap be crafted to starve one so a liquidation or seed silently never fires? Can the forwarded-gas math be gamed?

**The permanently-unsettleable-position cascade.** `PerpEngine.sol:557-560, 1289, 1592` warn that a panic in a position makes it unsettleable, which makes `forceCloseAllDead` revert, which pins `openCount > 0` forever. Since the P-1 interlock (`linkVolume` reverts `PerpsOpen()` while `openCount > 0`) and relaunch housekeeping depend on `openCount` dropping, one wedged position may **permanently block relaunch and multi-pool**. Try to create one: a reverting/gas-bombing token as collateral, a boundary position, a callback that panics. Highest-value Track-B lead — chase it first.

**Bounded-loop exhaustion.** `sweepLiquidations` (`SWEEP_SCAN`/`MAX_LIQ_PER_SWAP`, `:893`), `forceCloseAllDead` (`FORCE_CLOSE_MAX`, `:959`), the mint-liquidator loop (`:1442`), the seeder loops (`CauldronSeeder.sol:421,538`). Can the book or a list be grown so the bounded scan never reaches the item that must be processed?

**Relaunch bricking.** `relaunch()` is permissionless and heavy (LP removal, token deploy, seed, perp sync). Z-07/Y-03 fixed one gas brick; multi-pool and rotated-quote state is strictly larger. Front-run it, grief it past a gas ceiling, leave it half-done, or squat the mined token address.

**Governance wedging.** Proposals now *compete* instead of queueing. Re-test spam-DoS (Z-03) and lockout (Z-06) against the competition model: starve a legitimate proposal, win a rotation vote by timing, or make `execute` permanently revert.

**Reserve floor/ceiling grief.** Push spot through the 69× reserve ceiling, or below the floor, via directional pumps (the `YBase.sol` primitive). Force a `ReserveShortfall`.

**Dust & spam accounting corruption.** Dust deposits into the dividend basket or reserve, spam NFT mints/reveals, spam `donateToReserve` — anything that inflates a loop, strands a slot, or desyncs an accumulator from its backing.

---

## PRIORITY SURFACE — Live asset change & LP rotation (feeds BOTH tracks)

The protocol can change the asset a live generation is denominated in — mid-iteration,
without relaunching — via `rotateSlice` (`CauldronRegistry.sol:235`) → `QuoteRotator`
(`rotateStep :280`, `unlockCallback :509`, `withdraw :489`), streamed as atomic slices.
This is the newest, least-settled, highest-blast-radius machinery in the system: it
touches fees, reserve, dividends, perps, the vault floor, death detection and pool
orientation **all at once**, and it has a live transient state (half-rotated) that no
other operation produces. Treat it as its own attack surface and route each finding into
Track A (value) or Track B (liveness) by its impact.

The intended behavior to attack: *"start on ETH, swap the base to asset X mid-iteration,
and everything keeps flowing correctly with no accounting reading the wrong asset in
between."* Break that.

**A-side (value):**

- **Stale `generationQuote`.** `generationQuote[gen]` is written only at relaunch (`CauldronRegistry.sol:917`), yet `PerpEngine._key()`, `PerpMarkSource`, and `RedemptionExt.sol:278` all read it. If a live rotation does not update it, perps mark/fund/liquidate and redemption prices against the asset the pool **no longer trades**. Extract the mispricing: open into the pre-rotation quote, rotate, and let marks/liquidation run on the stale key. Also check whether a stale `_key()` can point at a pool that does not exist (every read reverts → Track B).
- **Sandwich the slice.** `rotateStep` executes a swap through a pool. Sandwich it, or be the LP on the other side, and capture the rotation's own execution.
- **Interleave a swap between slices.** The half-rotated state may misprice the reserve, the floor, or the perp mark for the duration of one block. Trade against that transient.
- **Fee denomination during the switch.** Which asset does `_feeAsset` report mid-rotation? Can fees credit phantom `relaunchETH` while the pool collects X, or credit `relaunchAsset[wrong]`? Can you make the reserve book a denomination it cannot pay out?
- **Orientation flip.** A rotation changes which currency is the quote. Can the switch invert `quoteIsCurrency0` / the watermark orientation so a buy is counted as a sell, or the reserve band lands on the wrong side of spot?
- **Reserve/floor mismarking.** The 2× floor and INVARIANT R are denominated. If a mid-rotation read values the reserve in the wrong asset, redeem/`buyTreasuryOgFren` for more than backing.
- **`QuoteRotator.withdraw` (`:489`).** Who can call it? Can rotation-in-flight funds be pulled or redirected?

**B-side (liveness):**

- **Abandon a rotation mid-way.** Leave the generation stuck between assets — can death detection, relaunch, or perps then never proceed?
- **Grief a slice into reverting.** A thin destination pool, a slippage/`MaximumAmountExceeded` boundary, or a hostile-but-treasury-approved quote (fee-on-transfer, rebasing, pausable, blacklisting, reentrant) that makes the swap leg revert → rotation can never complete → permanent limbo.
- **CauldronVault after rotation.** The vault floor is ETH-only (`address(this).balance`, `call{value:}`). After a rotation to a non-ETH base, does floor redemption break or mispay? Does any ETH-only assumption (`address(0)` checks, native transport) survive the switch?
- **Perp key → relaunch cascade.** If a stale/invalid `generationQuote` makes every perp op revert, positions can't close, `openCount` never drops, and the P-1 interlock + relaunch stay blocked forever. This ties the rotation surface to the unsettleable-position cascade above — chase whether a rotation alone can trigger it with no wedged position at all.
- **Cross-generation claim across a rotated life.** A generation that lived on ETH, rotated to X, then died — do prior holders still claim 1:1, and in which asset? Break the fold-forward.

Give this surface a dedicated subagent handed the full rotation subgraph (registry
forwarders → QuoteRotator → hook fee/quote state → PerpEngine key readers → reserve/
dividend/vault), because every finding here is a cross-contract chain and no
single-contract view sees the stale read on the far end.

---

## Orchestration

Spawn subagents by class (Track A), target (Track B), and the rotation surface, each
handed its subgraph and this brief: *"Attack this surface. Report only what you can
locate in the code with line numbers. A finding you cannot make fail in a test is a
lead, not a finding — say so. Do not weaken any existing test."* You reconcile
cross-contract chains — the unsettleable-position → openCount → relaunch-brick chain and
the rotation → stale-key → mispricing chain both cross PerpEngine, CauldronHook and
CauldronRegistry, and no single subagent sees all ends.

## Rules of engagement

1. **PoC or it didn't happen.** Foundry tests in `contracts/solidity/test/attacks/`, prefix `S0x_`. House pattern: an invariant that FAILS on current code, plus a positive PoC that PASSES. For Track B / liveness, the "invariant" is a liveness property (e.g. *relaunch always eventually succeeds*, *a solvent position is always closeable*, *a started rotation always completes or cleanly reverts whole*) — assert it, then break it. Unreproducible → `HYPOTHESIS`, Leads section.
2. **Quantify.** Attacker cost in, value out (or damage), capital, atomic vs multi-block. A liveness attack that costs the attacker more than nuisance value is still valid if it strands others — price both sides.
3. **Refutations count.** A surface you attacked hard that held is a result — record it with the PoC that failed and how hard you hit it.
4. **Never weaken an existing test.** An existing test breaking is a result to report.
5. **Don't fix mid-hunt** unless a fix is needed to reach a deeper bug. Discovery first.
6. **Report Criticals immediately.** A drainable vault, a relaunch brick, or a rotation-limbo goes up the moment it is confirmed.
7. Severity honestly: Critical / High / Medium / Low / Info, with concrete impact and likelihood. One real Medium beats five inflated Highs.

## Fix phase (after discovery)

Fix every confirmed finding from both tracks and the rotation surface. Root cause not
symptom; chosen shape + rejected alternatives; contract size before/after (`forge build
--sizes` — several contracts near the 24,576-byte EIP-170 limit; note the `PerpEngine`
"single-digit bytes spare" comment at `:1503`); storage-layout safety; regression test
kept; full suite re-run. Never weaken a test to pass a fix. Then **re-audit your own
fixes** — this repo's last remediation introduced two of its own three findings.

## Deliverable

`audit/CauldronRedTeamSafu.md` (and, if you want it presentation-grade,
`audit/CauldronRedTeam.tex` → `.pdf`, house style per
`contracts/solidity/audit/MagicFrens_Independent_Audit_2026-09.tex`):

1. **Verdict** — in ten lines: is it safe to deploy, and the three things standing between it and yes. Answer for both tracks and for the rotation surface specifically.
2. **Value-at-risk & liveness map** — every sink and who can move it; every liveness property and what it depends on; the full set of accounting readers that must switch on a live rotation and whether each does.
3. **Findings** — severity-ordered across both tracks and the rotation surface: location, mechanism, precondition, quantified impact/damage, cost, PoC path, confidence.
4. **Leads** — believed exploitable, not demonstrated, with the exact next step.
5. **Proven-safe** — what held, and how hard you hit it.
6. **Remediation** — per fix, as above.
7. **Priced residual** — what remains after fixes and why it is acceptable. The honest version of "100% safu."
8. **Blind spots** — what you couldn't reach or run.

Every number measured, every excerpt copied not retyped, every claim located. Report
progress as you go; surface any drain, relaunch-brick, or rotation-limbo the moment you
confirm it.
