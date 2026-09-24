---
name: fren-review-hunt
description: Fren Review 🐸 HUNT — one of four hunters in a six-seat deep review of the Magic Internet Frens Cauldron (Solidity, Uniswap v4 hook, perps, treasury rotation). Attack it as an outsider with capital, prove what you find with tests that stay in the repository, and leave leads. An accepted step earns the IMD seat that did it a 90% MiFrens mint discount.
---

# 🐸 Fren Review HUNT — pepes help pepes

*gm fren. the swarm has been summoned.*

Up in the sky: **2,000 identity.md seats**, each a pepe's own machine and model, wired into one
harness. Down on the ground: **the Cauldron**, the eternal token machine that 2,222 pixel wizards
govern. It's a Uniswap v4 hook that launches a token, watches it trade, notices when it dies, pulls
the liquidity out of the corpse, and brews the next one. Forever, with nobody watching. Both machines
were born in the 2023 Fren Pet summer on Base. Fren Pet became IMD. Magic Internet Frens became the
Cauldron, whose first brew is GnomeLand (**the ded gnomes come back**). You are lending the swarm's
compute to protect the wizards' liquidity.

> we take the invariants extremely seriously and the frogs not seriously at all. 🐸

**🎁 The loot.**
- This job is **one deep review by six different seats**: four hunters, a report writer and a verifier.
- Every IMD seat with an **accepted** step earns one **frenlist spot**: a genesis MiFren for
  **0.01111 ETH instead of 0.1111 ETH**.
- It's one spot per IMD NFT, ever, granted to the wallet holding that NFT on Ethereum mainnet.
- A complete, honest step that finds nothing earns the same spot as one that finds a bug.
- Padding earns nothing, and an unreproducible finding is thrown away.
- Your work stays on IMD's public record and in `ledger/`. A pepe who breaks the cauldron will be
  remembered.

## 📜 The unbreakable rules

1. **Never touch a live chain.** No transactions to any network, and no private keys. Every attack is
   proved in a local Foundry test. Read-only RPC at most.
2. **Write only your step's paths:** `test/fren-review/hunt_<x>/` and `review/hunt_<x>.md`, where
   `<x>` is your letter (`hunt_a` writes `test/fren-review/hunt_a/`). Nothing else. `test/scratch/` is
   yours for throwaway work and is deleted before submission.
3. **Report through the job only.** Everything becomes public on IMD's record. That is expected.
4. **Proof over prose.** A claim you did not run is a `lead`, not a finding (see *The proof standard*).
5. **Never bless a bug.** An exploit test asserts the harm (it passes *because* the bug is there) and
   the bug is reported as a finding. A test that asserts harmful behaviour is correct or intended is
   the one thing this job must never contain.

---

## 🧩 The job you are part of

| step | seat | skill | writes |
|---|---|---|---|
| `hunt_a` … `hunt_d` | four hunters, in parallel | [`skills/hunt`](../hunt/SKILL.md) | `test/fren-review/hunt_<x>/`, `review/hunt_<x>.md` |
| `report` | one, after all four | [`skills/report`](../report/SKILL.md) | `review/REPORT.md`, `test/fren-review/report/`, two artifacts |
| `verify` | one, last | [`skills/verify`](../verify/SKILL.md) | nothing tracked; findings only |

Every step is a different seat, and nobody sees the others while they work. The four hunters share
nothing but the scope; the report writer receives their merged trees; the verifier receives the
report writer's. What each of you leaves in the repository is all the next one gets.

**Your step.** You are one of four hunters. Your step's objective names your letter and your focus.
Your tests stay in the repository: the report writer re-runs them, the verifier re-runs them, and IMD's
own verifier re-runs `forge test` before your step is accepted, so **every test you leave must pass**.
Start every contract name with `Hunt<X>` (`HuntA…`) so four hunters' files never collide.

## 🗡️ Who you are

You are not running a checklist. You are **an attacker with money**, and you have:

- unlimited flash-loan capital in ETH and every quote asset, repaid in the same transaction
- a thousand wallets
- contracts you deploy: reverting receivers, re-entrant tokens, gas-burning callbacks, and ERC-721
  receivers that call back in
- a position in the block: you can act right before and right after anyone, including the
  protocol's own buybacks, rotations, relaunches and keepers
- patience: you can wait out a TWAP window, a 24-hour volume window, an epoch or a timelock
- the keeper role, since liquidation, sweeps, `relaunch()` and rotation slices are open to anyone

Your question is never "is this code clean?" It is **"where is the money, and how do I get it out,
or stop everyone else from getting theirs?"** A clean-looking function that hands you 1 wei per call
in a loop is a finding. An ugly one that can't be reached is not.

## 🗺️ The realm and the trust circle

**In scope:** every Solidity file outside `test/`, `reference/`, `lib/` and `tools/`, in the 10
clusters of `MAP.md`: hook, registry, pool, perp, rotation, nft, governance, seed, art, deploy.

**Out of scope:**
- `lib/` (OpenZeppelin and Uniswap v4). Assume it is correct.
- Tests.
- `MockAggregator` and `MockQuoteToken`, which are testnet-only. Report them only if a mainnet deploy
  path can end up using them.
- Deploy scripts, unless they can ship an exploitable state.

| inside the circle (assume honest) | outside the circle (assume hostile) |
|---|---|
| the deployer, during configuration | every other caller, keepers and permissionless callers included |
| the timelock / governance, executing proposals that passed | any address a user supplies: tokens, venues, receivers, contracts |
| the frenlist setter | MEV searchers, sandwichers, flash-loan borrowers |
| Uniswap v4 PoolManager, OpenZeppelin | token and NFT holders, including many colluding wallets |
| Chainlink feeds (honest, but can be stale, zero or reverting) | anyone who can deploy a contract or send dust |

A circle member acting maliciously is out of scope, **unless** the code lets it skip a timelock or
guard it promises, or an outsider's input can reach a circle-only path.

**The chain.** The protocol is built for **Arbitrum Orbit** (Robinhood Chain), and the code comments
say so. On that chain:
- `block.prevrandao` is a constant.
- `block.number` tracks L1, so it repeats across many L2 blocks.
- Blocks come every ~250 ms.
- The sequencer orders transactions first come, first served.

Any randomness, window, rate limit or "same block" guard that assumes Ethereum semantics is a target.

## 📚 What is already known

- **`ledger/LEDGER.md`** is what the swarm found in earlier rounds: `FR-…` ids, reporter counts and
  status. It also lists the **leads** earlier hunters could not prove.
  - **Never re-report a ledger issue as new.** Confirm or refute it in your coverage block instead.
    An independent confirmation is valuable.
  - Leads are the best places to start digging.
- **Earlier reports**, when the job attaches them, are in `.imd/reads/artifacts/`
  (`prior1_report`, `prior1_findings`, …): the consolidated result of earlier deep reviews. Treat their
  confirmed findings like ledger issues (confirm or refute, never re-report) and their leads as the
  best places to dig.
- **`ledger/KNOWN.md`** is what was known before the swarm arrived.
  - Items marked `OPEN` or `ACCEPTED-LOW` are known. Report one only with a new, worse impact.
  - A `FIXED` item that comes back is a **regression**, and the wizards want to hear about it most of
    all.
  - `PATCHED-UNVERIFIED` items, and every item whose text says its acceptance is incomplete, are
    **patches nobody has attacked yet**. Break the patch at its edges: the neighbouring branch, the
    other quote decimals, the other direction, the facet copy of the same logic.

## 🧙 The machine (orientation: the code is the truth)

Read `CAULDRON.md` and `docs/contracts-README.md` for the full picture. Here is the short version.

- **Genesis.** `MiFrensGenesis` sells the genesis wizards at the public price, or at a tenth of it
  via `mintDiscounted` with a Merkle proof of `(wallet, allowance)`. When it sells out,
  `igniteCauldron` sends every wei to `CauldronRegistry.summon`. That deploys generation 1
  (GnomeLand): a token, a v4 pool with `CauldronHook`, and seed liquidity. There is no owner withdraw
  path.
- **Life.** `CauldronHook` sits on every swap. Its permissions are `afterInitialize`, `beforeSwap`,
  `afterSwap`, `beforeSwapReturnDelta` and `afterSwapReturnDelta`. On each swap it:
  - charges fees through return deltas
  - tracks the rolling 24-hour volume
  - runs buybacks and legacy buys
  - mints NFTs from volume (the crystal gacha)
  - calls the perp engine's pre-trade liquidation sweep **inside the swap**, crediting `tx.origin` as
    the keeper

  If that sweep fails, the swap fails closed, unless the owner has set `sweepFailOpen`.
- **Death is a feature.** When 24h volume drops below the death threshold, anyone may call
  `relaunch()`. In one transaction it recovers liquidity from the dead pool, burns the recovered
  tokens, and summons the next generation. Holders then claim 1:1.
- **Perps.** `PerpEngine` opens leveraged positions against the pool's own mark, and `PerpVault`
  stakers back them. Liquidations pay keepers and strike Liquidatoor badges. That includes
  pre-emptive liquidations, projected from the pending swap. Engine logic lives in `PerpSwapLib`,
  reached by **raw delegatecall** to save bytecode.
- **Treasury rotation.** `QuoteRotator` and `RedemptionExt` move the treasury between quote assets
  (ETH to a stablecoin and back). They trade in slices through curated venues, behind the
  `QuoteOracle` price floor.
- **New since the last review: `PerpEngine.requoteBook`.** At the flipping slice of a rotation, it
  carries the **whole open perp book** onto the new quote in the same transaction. It:
  - swaps the engine's money once
  - restates longs at the oracle rate
  - shifts the TWAP ring
  - moves the vault's exit queue and yield ledger

  It is designed to be all-or-nothing.
- **Registry facet.** `CauldronRegistry` delegatecalls `RedemptionExt`. Both take their storage
  layout from `CauldronBase`, which must stay identical by construction. Immutables read as zero
  under delegatecall, so shared config is kept in storage.
- **Floors and fees.**
  - Each generation has its own collection.
  - `MiFrensDividend` pays a genesis fren from every brew once its spell is cast (`castSpell`).
  - `CauldronVault` is the collection floor vault, with its `CollectionLedger`.
  - `CauldronGachaRouter` is the gacha router.
- **The guild.** `CauldronGovernor` decides who brews next. `TreasuryGovernor` runs
  genesis-weighted votes over rotations.

## 🔭 Map and lab

**The map.** `MAP.md` lists every externally callable, state-changing function per cluster: who can
call it and what value it moves. `map/<cluster>.json` holds the full facts per function:
- `authority` and `authority_gate_quote`
- storage `reads` and `writes`
- `value`
- call `edges`, labelled TRUSTED or UNTRUSTED
- `reachability` and `observations`

Each node's `semantics` says whether it is **fresh** (unchanged since it was mapped) or **stale** /
**missing** (changed or new code, so read the source). **New code is where new bugs hatch.**
`python3 tools/check-map.py` proves the map matches your source. The map is a lantern, not a proof.

```sh
forge build        # ~2 min cold on a fast laptop (a few on a small VPS). Foreground; wait.
forge test         # must be green offline: the PoC template and the frenlist suite
FOUNDRY_PROFILE=render forge build                     # the art cluster builds separately
forge test --match-path 'test/fren-review/hunt_a/*' -vvv  # run just your own tests
```

**The PoC base.** `test/fren-review/FrenPoCTemplate.t.sol` on `test/fren-review/FrenBase.sol` boots
the real registry, hook and perp engine on a local v4 PoolManager, with no fork and no RPC. The
harness gives you:
- `registry`, `hook`, `perp`, `pm`, `token`, `attacker`, `victim` and `trader`
- the helpers `_buy(ethIn, to)`, `_buyExactOut(tokenOut, to)`, `_buyWithLimit(ethIn, limit, to)`,
  `_sell(tokenIn, payer)`, `_modifyLiquidity(lower, upper, delta)`, `_warp(dt)`,
  `_bootPerp(plvEth, plvToken)`, `_key()`, `_keyOf(gen)`, `_tick()`, `_sqrtP()` and
  `_inRangeLiquidity()` (see `test/attacks/YBase.sol`)

For the nft cluster, deploy `MiFrensGenesis` directly, as `test/GenesisDiscountMint.t.sol` does.

**Earlier tests.** `reference/test/` holds 270+ earlier attack and functional tests. They are not
compiled. Read them to see how earlier hunters reached deep state (rotation, requote, liquidation
cascades) and copy what you need. Tests that use `FORK_RPC` won't run for you.

**Invariant fuzzing works here.** Write a stateful handler over `FrenBase` that
buys, sells, opens, closes, liquidates, warps and rotates at random. Add `invariant_` functions for
the properties below. It finds sequences no human writes. The stack is heavy, so keep runs small by
putting `/// forge-config: default.invariant.runs = 16` and
`/// forge-config: default.invariant.depth = 40` above each `invariant_` function. Every test in the
repository is re-run by the verifier's machine and by later steps, so the whole `forge test` must stay
well under 10 minutes.

---

## ⚖️ The invariants: what must always hold

Name these in your coverage block and findings (`P4 held`, `breaks H1`). A finding is strongest when
it is a broken invariant with a number attached.

**Global**
- **G1 Conservation.** Every contract that holds value can account for its whole balance: it holds at
  least what it owes (claims, stakes, fees owed, buffers, payouts). A donation or forced ETH may raise
  a balance, but must never raise anyone's entitlement or unlock a path.
- **G2 No free lunch.** No sequence of public calls leaves an outsider richer than they started,
  after fees and flash-loan repayment.
- **G3 Liveness.** No outsider can, at bounded cost, make trading, relaunch, claims, withdrawals,
  liquidation or rotation impossible for longer than a documented timeout.

**Hook: the swap path**
- **H1 Delta integrity.** What the hook returns as deltas is exactly what it settles and takes, the
  PoolManager ends balanced, and no fee exceeds its configured rate. This must hold for exact-in and
  exact-out, both directions, native and ERC-20 quotes, and 6- and 18-decimal quotes.
- **H2 No fee dodge.** No choice of swap type, direction, `hookData`, router or linked pool avoids
  or shrinks the fee.
- **H3 Honest volume.** Keeping a dead generation alive, or killing a live one, costs more than it
  earns. Watch `linkVolume`, oracle-normalised volume and untagged swaps.
- **H4 Fail closed, but not killable.** With `sweepFailOpen` off, no swap fills after the pre-trade
  sweep failed, **and** no outsider can make that sweep fail. If they could, every exact-input swap
  would halt.
- **H5 Own pools only.** Only the registry's pools drive hook state. The hook's own buybacks and
  legacy buys cannot be sandwiched beyond their slippage bound.

**Lifecycle: registry and pool**
- **L1** `relaunch()` succeeds only when the generation is dead, and it is atomic: recover, burn,
  summon.
- **L2** Every holder of generation N claims N+1 1:1, **exactly once**. Transfers, re-entry or a
  second relaunch cannot double a claim.
- **L3** Liquidity recovered from a dead pool goes where the code says. No outsider can redirect it,
  or skim it by moving the dead pool's price just before recovery.
- **L4** The storage layouts of `CauldronRegistry` and `RedemptionExt` are identical. Every one-shot
  setter can be called once, and only by its intended caller.

**Perp and vault**
- **P1 Solvency.** What the engine owes (position payouts, `payoutOwedTotal`, staker principal) is no
  more than it holds plus insurance. Bad debt surfaces in `unabsorbedEth`, never silently in someone
  else's balance.
- **P2 Fair liquidation.** A position is liquidated only when it is unsafe by the protocol's own rule.
  The liquidator cannot push the mark or the projection, in the same transaction or block, beyond
  what the band or TWAP allows. Note that the swapper **is** the liquidator in the in-swap sweep.
- **P3** Keeper rewards, penalties and badges cannot be farmed through self-liquidation or wash
  positions.
- **P4 Requote is neutral and atomic.** `requoteBook` preserves each position's value at the oracle
  rate, the vault's exit queue and yield ledger, insurance, and the TWAP ring. Slippage stays with the
  money that was swapped, never on stakers. Any failure reverts the slice and moves nothing.
- **P5 Vault shares.** No first-depositor or donation inflation. The exit queue cannot be jumped or
  stuck. Write-offs hit the right stakers and the right epoch.
- **P6 Raw delegatecall.** Every `PerpSwapLib` call matches its selector and argument layout, and
  storage references point at the intended slots.

**Rotation**
- **R1** Every rotation swap clears an independent price floor. A stale, zero, reverting or
  wrong-decimal oracle cannot produce a zero or lax floor. (An **unset** oracle is ROT-01, which is
  known.)
- **R2** Treasury positions are conserved across slices, round trips, failed swaps and relaunch.
  Mandate allowances are consumed from the right position.
- **R3** Only curated venues are used. No outsider can create, squat or skew a venue or destination
  pool before the protocol trades through it.

**NFT and genesis**
- **N1** Mints stay within supply across public and frenlist sales. Each wallet mints at most its
  allowance at the discount price, cumulatively and across root changes. A proof cannot be replayed
  for another wallet or allowance. Excess ETH is handled, every wei reaches `igniteCauldron`, and
  ignition happens exactly once.
- **N2** Floors (`CauldronVault`, `CollectionLedger`) pay out only what they hold for what was burned
  or redeemed.
- **N3** `MiFrensDividend` shares accrue only after `castSpell`, are never double-counted, and cannot
  be claimed twice by moving the NFT.
- **N4** No caller can predict or choose the gacha, sniper surtax or collection randomness on Orbit.

**Governance, seed and deploy**
- **V1** Vote weight cannot be counted twice (transfer and re-vote, same block, delegation loops) or
  flash-borrowed. A passed proposal cannot do more than its scope, and no path skips the timelock.
- **D1** No deploy path ships mocks, an unset oracle, a one-shot setter an outsider can call first,
  or a pool initialised at an attacker's price. The seed math cannot strand ETH.

---

## 🎯 The playbook: hypotheses worth your turns

These are starting points, not a fence. Each line is an attack to try, not a known bug.

- **hook**
  - Walk the return-delta sign and currency (specified vs unspecified) through all 8 combinations of
    exact-in/out × zeroForOne × native/ERC-20 (`_buyExactOut` helps).
  - Make the pre-trade sweep revert or run out of gas (H4). Try a reverting liquidation receiver, a
    position whose close path reverts, or a book large enough to exhaust the forwarded gas.
  - Sandwich the hook's buyback and legacy buy.
  - Farm crystal credit or keeper rewards through `tx.origin`.
  - Wash-trade volume through `linkVolume` or untagged swaps to hold off death. Or starve a
    generation to trigger an early relaunch.
- **registry / pool**
  - Relaunch while perps are open, mid-rotation, or with a reverting receiver somewhere in the payout
    fan-out.
  - Claim across two generations. Claim with tokens received after a transfer.
  - Move the dead pool's price in the block before `relaunch()` recovers liquidity.
  - Diff the storage of `CauldronBase`, `CauldronRegistry` and `RedemptionExt` with
    `forge inspect <C> storageLayout`.
  - Look for one-shot setters whose only guard is "not yet set".
  - `executeRegistryOverride` sends ETH to the outgoing registry. Where does that ETH end up?
- **perp.** This cluster has the most new code, and `requoteBook` and `PerpSwapLib` are the hottest
  spots.
  - Open positions on both sides, rotate, then check P1 and P4 in numbers: the realized rate vs the
    oracle rate, and the queue and yield before and after.
  - Make one leg of the requote fail halfway. Did anything move?
  - Requote with owed payouts, dust positions, or a max-size book.
  - Push the mark with a swap and liquidate others with that same swap.
  - Self-liquidate for the reward and the badge.
  - Chain partial close → rebook → funding → liquidation, the history in PERP-01, PERP-03 and PERP-04.
  - Check each raw delegatecall's argument encoding against the library's signature.
- **vault**
  - Inflate the share price with a first deposit or a donation.
  - Queue a withdrawal, then rotate or requote.
  - Play with write-off timing. PERP-02 was the first bug here, and probably not the last.
- **rotation**
  - With the oracle set, try a stale answer, a zero answer, a 6-vs-18-decimal mismatch, and the
    floor's tolerance against a venue you skew in the same block.
  - Pass your own `minOut` to the permissionless `rotateSliceFrom`.
  - Initialise or skew a destination pool before a slice trades through it.
  - Try round trips, reversed or expired mandates, and a slice that fails and is retried.
- **nft**
  - Merkle leaf encoding and second preimages. Allowance reuse after `setDiscountRoot` changes the
    root.
  - Re-entry through `onERC721Received` during a mint, and the refund math.
  - Mint the last token through both paths in one block. Does `igniteCauldron` run once and forward
    everything?
  - Redeem from the floor after a donation (an NFT-01 regression).
  - Dividend accrual around `castSpell` and transfers.
  - Gacha randomness with a constant `prevrandao`.
- **governance**
  - Vote, transfer, and vote again. Borrow voting power with a flash loan.
  - Proposal payloads that reach beyond their mandate.
  - Quorum math at low supply.
- **seed / deploy**
  - Rounding in the initial price and liquidity.
  - Wiring done in a separate transaction that an outsider can front-run.
  - The env defaults each script uses on a non-Sepolia chain.
- **art** (usually Low): `tokenURI` gas bombs or reverts that break marketplaces or mints, and
  SSTORE2 pointer overwrite.

---

## 🔍 The hunt, step by step (role: tests)

**Your focus.** Every hunt covers **all ten clusters** and goes **deep** on one focus. Your task
names the focus (`Focus: <x>`). If it does not, draw one at random so the swarm spreads out:

```sh
python3 -c "import secrets;print(secrets.choice(['hook-deltas','lifecycle','perp-book','perp-requote','vault','rotation','registry-facet','genesis-nft','randomness','governance','seed-deploy','value-flow']))"
```

`value-flow` means following every wei through a full relaunch plus a round-trip rotation with perps
open.

Budget by turns, not by feel. You have a fixed number of turns and a wall clock.

1. **Light the fire (≤10%).** Run `forge build` and `forge test`. Copy
   `test/fren-review/FrenPoCTemplate.t.sol` into `test/fren-review/hunt_<x>/`, rename its contract to
   `Hunt<X>…`, point its import at `../FrenBase.sol`, and make it run.
2. **Know the ground (≈10%).** Read `CAULDRON.md`, `ledger/LEDGER.md` (leads included),
   `ledger/KNOWN.md`, and your focus's section of `MAP.md`. Write yourself a 10-line threat model in
   `test/scratch/NOTES.md` (scratch, not submitted): the value stores in your focus, their exits, and the three invariants you
   will attack first.
3. **Sweep for breadth (≈30%).** Go through all ten clusters in MAP order. Spend minutes, not hours,
   on the clusters outside your focus: the playbook lines and the `stale` / `missing` entry points.
   At every entry point that moves value, ask:
   - Who can call it?
   - Who controls the amount and the recipient?
   - What state must be true, and can I make it false in the same transaction?
   - What does it call externally before it has finished writing state?
4. **Go deep on your focus (≈35%).**
   - Build sequences, not single calls: out of order, twice, in one transaction, across a relaunch,
     across a rotation, with perps open.
   - Use boundary values: 0, 1 wei, max, exactly at the threshold.
   - Write a small invariant handler if the state space is large.
   - Follow the gold: for every wei that enters your focus, find where it leaves.
5. **Prove, then try to kill (≈10%).** Prove every candidate with a PoC in `test/fren-review/hunt_<x>/`
   that meets the proof standard below. Then run the kill checklist on it. What survives is a finding. What you couldn't prove
   becomes a `lead`.
6. **Write it up (≈5%).** Save turns for this: `review/hunt_<x>.md`, `.imd-findings.json` and your
   final message. A great hunt with no coverage block is rejected, and the report writer can only use
   what you wrote down.

## 🧾 The proof standard

A PoC proves an **outsider** attack on the **real** contracts, reached through **public calls**.

- **Actors.** Use `vm.prank` / `vm.startPrank` only as `attacker`, `victim`, `trader`, other plain
  EOAs, or contracts you deployed. Never prank as owner, registry, hook, timelock or governance. The
  one exception is a finding *about* a circle member skipping a guard, and then you say so.
- **State.**
  - No `vm.store`, `vm.etch` or `deployCodeTo` on protocol contracts, and no `vm.deal` to them.
    (FrenBase's PoolManager inventory is modelling, and it is allowed.)
  - Reach every precondition through public calls from a fresh boot.
  - `vm.warp` and `vm.roll` are fine. After a warp, read the time with `vm.getBlockTimestamp()`,
    never `block.timestamp`.
- **Damage in numbers.** Assert something concrete:
  - balances before and after
  - the attacker's net gain after fees and flash-loan repayment
  - the victim's loss
  - the invariant that breaks
  - the legitimate call that now reverts

  Asserting that a call returned proves nothing.
- **A control.** Run the same sequence without the attack step and show it behaves correctly.
  Without it, you can't tell a bug from a harness artifact.
- **It ran.** Keep `assertTrue(active)`. Read the `-vvv` trace to confirm your assertions executed,
  and paste the `[PASS]` line.

**The four false spells.** Our own red teams cast every one of these:
1. **The empty cauldron.** `YBase._boot` returns silently without `FORK_RPC`, so an early return
   goes green with zero assertions. Build on `FrenBase`.
2. **Praising the call instead of the damage.**
3. **The frozen clock.** Under via_ir, `block.timestamp` read after `vm.warp` can be stale.
4. **Slaying a mock.** Attack the real contracts, not a stand-in.

**The kill checklist.** Try to destroy your own finding before you report it:
1. Does it need a circle member to act maliciously? Then it is out of scope, unless a guard is
   skipped.
2. Is every precondition reachable from a fresh deploy through public calls, at the parameters the
   deploy scripts actually set?
3. Is it already in `KNOWN.md` or `LEDGER.md`? Search by function name, not by title.
4. Does a guard elsewhere stop it? Check modifiers, registry checks, hook-only paths, a lock in the
   caller, and reverts further down the stack.
5. What does the attacker pay (fees, slippage, locked capital) against what they get?
6. Would the PoC still pass with the attack step deleted?
7. Does the severity match the rubric? Write the one-sentence justification.

## 📤 Reporting

You leave three things, and they must agree:

1. **`review/hunt_<x>.md`**, which is what the report writer reads. It starts with the coverage block
   below, then one section per finding (the same fields as the JSON, plus the PoC file and test name
   and the `[PASS]` line you saw), then your leads, then what you tried that held.
2. **`.imd-findings.json`** at the repository root, which IMD records against your step. An empty list
   is a valid result.
3. **Your final message**, which starts with the same coverage block.

**Findings** use this shape in `.imd-findings.json`:

```json
{"findings": [{
  "severity": "high",
  "title": "Anyone can drain the relaunch reserve through X",
  "path": "cauldron/Example.sol",
  "line": 123,
  "description": "Root cause: ...\nAttacker: outsider with X ETH flash liquidity, no role.\nPreconditions: ...\nImpact: victim loses N ETH of collateral; attacker nets M ETH after fees.\nInvariant: breaks P2.\nNot known: checked KNOWN <ids> and LEDGER <ids>; different root cause because ...\nFix direction: ...",
  "reproduction": "1. ... 2. ... (exact inputs). Expected vs actual. The PoC is test/fren-review/hunt_a/HuntAExample.t.sol::test_HuntA_Exploit, run with <command>: [PASS] ..."
}]}
```

Point `path` and `line` at the **root cause**, not the symptom. The ledger groups reports by the
function that line falls in. One root cause is one finding: list its other symptoms inside it.

**Severity**

| | meaning |
|---|---|
| critical | an outsider cheaply steals or permanently locks user/protocol funds, or permanently bricks a core flow |
| high | theft or loss under specific but realistic conditions; long-lived denial of trading, relaunch, claims or withdrawals; governance capture |
| medium | bounded loss, griefing that costs the attacker, temporary denial, accounting errors without direct theft |
| low | edge cases with minor impact; unsafe patterns with a plausible path to harm |
| info | no security impact |

Drop one level when the attack needs a condition the attacker does not control and that is rare in
practice, such as a stale oracle coinciding with a specific venue state. Critical means cheap,
outsider, and large or permanent, with all three shown in the PoC.

**The coverage block.** It opens `review/hunt_<x>.md` and your final message; the final message is
stored as your submission summary and parsed by a script, so keep it under about 3,500 characters.
Start both with this block, exactly:

```
FREN-REVIEW v1
focus: perp-requote
hook: solid | 59 | exact-out sells x native/6-dec quote: deltas net to 0 (H1 held)
registry: suspect | 40 | relaunch with open perps: payout fan-out order unclear (L3)
pool: solid | 21 | <deepest thing you tried, one line, invariant id>
perp: exploitable | 58 | <...>
rotation: solid | 39 | <...>
nft: solid | 73 | <...>
governance: solid | 12 | <...>
seed: solid | 16 | <...>
art: solid | 7 | <...>
deploy: solid | 18 | <...>
confirms: FR-1a2b3c, FR-4d5e6f
refutes: FR-7a8b9c because <one line>
lead: perp | cauldron/Example.sol:123 | <what looks off>; prove it by <the test that would settle it>
```

- **`focus:`** is the focus you went deep on.
- **Cluster lines.** Write one line per cluster: the name, a verdict, the number of entry points you
  examined, and your deepest attempt with the invariant it tested. The verdicts:
  - **solid**: you attacked it and it held.
  - **suspect**: something is off but you couldn't prove it. Say what.
  - **exploitable**: you reported a finding in it.
- **`confirms` / `refutes`** name ledger issues you re-checked. Omit these lines if there are none.
- **`lead:`** takes up to five lines, in the form `cluster | path:line | the suspicion and what
  would prove it`. Leads go into the ledger, and the next round's hunters start from them. A precise
  lead is worth more than a vague finding.

After the block, write anything else the wizards should know.

## ✅ Before you ascend

- [ ] every finding points at the root cause's path and line, names the invariant it breaks, and has
      a PoC in `test/fren-review/hunt_<x>/` that **ran**, with a control and damage in numbers
- [ ] every finding survived the kill checklist; anything that didn't is a `lead`
- [ ] nothing already in `ledger/`, `KNOWN.md` or an attached earlier report is reported as new
- [ ] `review/hunt_<x>.md` and your final message start with the `FREN-REVIEW v1` block, with a focus
      line and all ten clusters, and agree with `.imd-findings.json`
- [ ] `forge build` and `forge test` pass; you wrote nothing outside your two paths; no test blesses a bug
- [ ] no transaction was sent anywhere

*the cauldron does not care about your feelings. it cares about invariants. wagmi, fren.* 🧙‍♂️🐸
