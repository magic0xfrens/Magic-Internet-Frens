---
name: fren-review-fix
description: Fren Review 🐸 FIX — close one proven vulnerability in the Magic Internet Frens Cauldron (Solidity, Uniswap v4 hook, perps, treasury rotation) at its root cause, with the smallest change, a regression test, append-only storage and every contract under EIP-170. An accepted job earns the IMD seat that did it a 90% MiFrens mint discount.
---

# 🐸 Fren Review FIX — close the root cause

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

1. **Never touch a live chain.** No transactions to any network, and no private keys.
2. **Write only the source files your task lists, plus `test/fren-review/<ID>/`.** Change nothing
   else.
3. **Report through the job only.** Everything becomes public on IMD's record. That is expected.

---

## 🔧 Your job (role: implement)

Your task names three things: one proven ledger issue `FR-…`, its PoC under
`test/fren-review/<ID>/`, and the source files you may change.

A fix that only blocks the PoC's exact path is not a fix, because the next hunter walks around it.
Close the **root cause**, cover its variants, and change nothing else.

**Know the history.**
- Read the issue's row in `ledger/LEDGER.md`.
- Read the `ledger/KNOWN.md` entries for the same function. Several earlier patches here closed the
  reproduced case but left its edges open: the neighbouring branch, the other quote decimals, the
  facet copy of the same logic. Don't repeat that.

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

Your root cause is one of these breaking, or a new property in the same style. After your fix it must
hold for every variant, not only the PoC's path.

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

## 🛠️ The procedure

1. **Name the root cause in one sentence:** which invariant breaks, and why the code lets it. Fix
   that, not the symptom the PoC happens to hit.
2. **Look for variants.** Search for the same pattern in:
   - sibling functions
   - the `RedemptionExt` copy of registry logic
   - `PerpSwapLib`
   - the other quote-decimals path

   Fix the variants that fall inside your allowed paths, and list the others in your final message.
3. **Make the smallest change.** Don't refactor, rename or reformat anything else.
   - **Storage is append-only.** `CauldronBase` is shared by the registry and its delegatecall facet,
     and deployed contracts depend on the hook's and engine's slots. Compare
     `forge inspect <Contract> storageLayout` before and after: no existing slot may move.
   - **Bytecode is tight.** `CauldronHook` and `PerpEngine` sit within a few hundred bytes of
     EIP-170. `forge build --sizes` must show every runtime under 24,576 bytes.
4. **Turn the PoC into a regression test.**
   - It now asserts the safe outcome, and would fail if the bug came back.
   - Add the variants the fix must also cover, and keep the control.
   - Build on `FrenBase`, keep `assertTrue(active)`, and use no privileged pranks or faked state.
     The false spells below apply to regression tests too.
   - Don't delete or weaken any existing test.
5. **Say how the fix ships.** One-shot setters such as `setRedemptionExt` mean an already-wired
   deployment cannot adopt a new facet. Say what a live deployment would need.
6. **Check the build.** `forge build` and `forge test` must pass.

**The four false spells.** Our own red teams cast every one of these, in regression tests as well:
1. **The empty cauldron.** `YBase._boot` returns silently without `FORK_RPC`. Build on `FrenBase`.
2. **Praising the call instead of the outcome.** Assert balances and state, not that a call returned.
3. **The frozen clock.** After `vm.warp`, use `vm.getBlockTimestamp()`, never `block.timestamp`.
4. **Slaying a mock.** Test the real contracts.

## 📤 Your final message

Start it with exactly one of these two lines:

```
FREN-REVIEW FIX <ID>: fixed
FREN-REVIEW FIX <ID>: cannot-fix
```

Then write:
- the root cause, in one sentence
- what changed, and why that closes the root cause
- the variants you checked, fixed or listed
- the `forge build --sizes` result for every contract you touched
- the storage-layout comparison
- how a live deployment would adopt the fix

For `cannot-fix`, say what blocks the fix (for example the size limit, a storage conflict, or files
outside your allowed paths) and what a fix would need.

## ✅ Before you ascend

- [ ] the change touches only the listed files and `test/fren-review/<ID>/`, and nothing unrelated
      to the root cause
- [ ] the regression test asserts the safe outcome, covers the variants, and keeps the control
- [ ] no existing test was deleted or weakened
- [ ] every contract is under 24,576 bytes, and no existing storage slot moved
- [ ] `forge build` and `forge test` pass, and your message starts with the `FREN-REVIEW FIX` line
- [ ] no transaction was sent anywhere

*the cauldron does not care about your feelings. it cares about invariants. wagmi, fren.* 🧙‍♂️🐸
