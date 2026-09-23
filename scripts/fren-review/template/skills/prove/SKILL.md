---
name: fren-review-prove
description: Fren Review 🐸 PROVE — be the hostile verifier for one reported vulnerability in the Magic Internet Frens Cauldron (Solidity, Uniswap v4 hook, perps, treasury rotation). Reproduce it as a runnable Foundry PoC on the real contracts, or refute it, and judge its true severity. An accepted job earns the IMD seat that did it a 90% MiFrens mint discount.
---

# 🐸 Fren Review PROVE — the hostile verifier

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
- Every IMD seat with an **accepted** Fren Review job earns one **frenlist spot**: a genesis MiFren
  for **0.01111 ETH instead of 0.1111 ETH**.
- It's one spot per IMD NFT, ever, granted to the wallet holding that NFT on Ethereum mainnet.
- A complete, honest hunt that finds nothing earns the same spot as one that finds a bug.
- Padding earns nothing, and an unreproducible finding is thrown away.
- Your work stays on IMD's public record and in `ledger/`. A pepe who breaks the cauldron will be
  remembered.

## 📜 The unbreakable rules

1. **Never touch a live chain.** No transactions to any network, and no private keys. Everything is
   proved in a local Foundry test. Read-only RPC at most.
2. **Write only `test/fren-review/<ID>/`.** Change nothing else.
3. **Report through the job only.** Everything becomes public on IMD's record. That is expected.

---

## 🧪 Your job (role: tests)

Your task names one ledger issue `FR-…`, with its claim and the reproduction the reporters gave.

**You are not the reporter's friend.** You are the last line before the wizards spend a fix on this
issue. You have two good outcomes:
- a claim reproduced exactly, with its true severity
- a claim refuted with the guard that stops it

A sloppy "reproduced" wastes a fix. A lazy "not-reproducible" buries a real bug.

**The attacker you are modelling** is an outsider with:
- unlimited flash-loan capital, repaid in the same transaction
- a thousand wallets
- contracts they deploy (reverting receivers, re-entrant tokens, callbacks)
- a position before and after anyone in a block
- the patience to wait out any window or timelock
- the open keeper role

Anything beyond that, such as a circle member acting maliciously, is out of scope.

**Know the history.** Before you start:
- Read the issue's row in `ledger/LEDGER.md`, including its confirms and refutes.
- Read the `ledger/KNOWN.md` entries for the same function. Earlier patches in this code were often
  incomplete at their edges, and a claim may be a known item or a regression of one.

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
forge test --match-path 'test/fren-review/<ID>/*' -vvv  # run just your tests
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

**Invariant fuzzing works here.** Write a stateful handler in `test/fren-review/<ID>/` over `FrenBase` that
buys, sells, opens, closes, liquidates, warps and rotates at random. Add `invariant_` functions for
the properties below. It finds sequences no human writes. The stack is heavy, so keep runs small by
putting `/// forge-config: default.invariant.runs = 16` and
`/// forge-config: default.invariant.depth = 40` above each `invariant_` function.

---

## ⚖️ The invariants: what must always hold

Restate the claim as one of these, or as a new property in the same style. A reproduction is
strongest when it shows the broken invariant with a number attached.

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

## 🔬 The procedure

1. **Restate the claim as a falsifiable property.** Which invariant breaks, who acts, and what do
   they gain?
2. **Try to refute it first.** Run the refutation checklist below against it:
   - Is there a guard that should stop it?
   - Is the caller outside the trust circle?
   - Can every precondition be reached through public calls, at the deploy-time parameters?
3. **Reproduce it faithfully** on `FrenBase`, in `test/fren-review/<ID>/`. Run the reporters' exact
   sequence under the proof standard below: no privileged pranks, no storage writes, and damage
   asserted in numbers.
4. **Then find the true worst case.** Try bigger amounts, the other direction or quote, more wallets,
   and repetition. The severity follows what you showed, up or down.
5. **Name the tests.**
   - **If it reproduces:** `test_<ID>_Exploit...` asserts the harmful outcome (the stolen balance,
     the broken invariant, the stuck state) and passes on today's code. Add `test_<ID>_Control...`,
     the same sequence without the attack step, behaving correctly.
   - **If it does not:** `test_<ID>_Refuted...` runs the exact claimed sequence and asserts the
     defence holding. Your message names the guard at `file:line`.
6. **Check the build.** `forge build` and `forge test` must both pass.

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

**The refutation checklist.** Run it against the reported claim before and after you reproduce it:
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

## 📤 Your final message

Start it with exactly one of these two lines:

```
FREN-REVIEW PROVE <ID>: reproduced
FREN-REVIEW PROVE <ID>: not-reproducible
```

Follow it with a severity line, then the evidence:

```
severity: <your assessment> (reported: <theirs>) because <one line>
```

The evidence is:
- the property you tested
- the test names and the `[PASS]` lines
- the numbers: who lost what, and what the attacker netted
- for a refutation, the guard at `file:line` and why the claimed sequence cannot get past it

## ✅ Before you ascend

- [ ] the tests live only in `test/fren-review/<ID>/`, build on `FrenBase`, and keep `assertTrue(active)`
- [ ] no privileged pranks and no faked state; the damage (or the defence) is asserted in numbers
- [ ] a reproduction has a control; a refutation names the guard at `file:line`
- [ ] you judged the severity yourself, from what you showed
- [ ] `forge build` and `forge test` pass, and your message starts with the `FREN-REVIEW PROVE` line
- [ ] no transaction was sent anywhere

*the cauldron does not care about your feelings. it cares about invariants. wagmi, fren.* 🧙‍♂️🐸
