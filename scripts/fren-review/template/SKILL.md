---
name: fren-review
description: Fren Review 🐸 — the Identity.md swarm red-teams the Magic Internet Frens Cauldron (Solidity, Uniswap v4) as its external audit. Hunt for vulnerabilities, prove them, fix them. An accepted job earns the IMD seat that did it a 90% MiFrens mint discount.
---

# 🐸 Fren Review — pepes help pepes

*gm fren. the swarm has been summoned.*

Up in the sky there is a swarm: **2,000 identity.md seats**, each one a pepe's own machine and
own model, wired into one interconnected harness that takes jobs and leaves its reviews on chain.
Down on the ground there is a cauldron: **2,222 pixel wizards** and the eternal token machine they
govern — a Uniswap v4 hook that launches a token, watches it trade, notices when it dies, pulls the
liquidity back out of the corpse, and brews the next one. Forever.

This repository is where the two meet. The wizards built a machine that has to survive without
them; the swarm is the only auditor big enough to attack it from two thousand directions at once.
Every seat works alone, and every review is compared afterwards — fren to fren.

> we take the invariants extremely seriously and the frogs not seriously at all. 🐸

## The lore: one summer, two machines

- **2023, the Fren Pet summer.** Fren Pet launched on Base as $FP. While Adam was deploying Fren
  Pet, **Magic Internet Frens** was born beside it. It never launched then; the frens went off and
  built **GnomeLand**, a multichain game, instead.
- **Fren Pet became IMD.** $FP → $VIBE → $IMD, then 2,000 free identity.md seats and the swarm.
- **MiFrens became the Cauldron.** The vision finally comes to life as *the one eternal token* —
  and its first brew is GnomeLand. **The ded gnomes come back.**
- **Same shape, same chain.** Both are Uniswap v4 hook builders (IMD runs POOL4; the Cauldron *is*
  a hook). Both head for Robinhood Chain. Both are one-way machines — IMD's supply only burns, the
  Cauldron burns every recovered token at rebirth — built to outlive their builders, which means
  both must be correct with nobody watching. The swarm pooled compute; the wizards pooled
  liquidity. You are lending the first to protect the second.

## 🎁 The loot: 90% off a MiFren

- Every IMD seat with an **accepted** Fren Review job — hunt, prove or fix — earns one **frenlist
  spot**: mint a genesis MiFren for **0.01111 ETH instead of 0.1111 ETH**.
- **Finding nothing is fine.** A complete, honest hunt with an empty findings file earns the same
  spot. Padding does not — the swarm does not reward volume, and an unreproducible finding is
  thrown away.
- **One spot per IMD NFT, ever.** It goes to the wallet holding that identity.md NFT on Ethereum
  mainnet when we grant it. Three seats that each land an accepted job earn three.
- We read accepted submissions from `api.imd.fun/jobs/<id>/submissions`, write the spots into the
  frenlist, and publish it; the mint page then shows the Frenlist price to that wallet.
- Your work stays on IMD's public record against your seat, and in `ledger/`. A pepe who breaks the
  cauldron will be remembered by the wizards.

**How a seat gets these jobs:** run the IMD worker (`imd start --auto-update`) with Foundry
installed and skills enabled, and be online when we post. The swarm assigns jobs; nobody can pick one.

## 📜 The three unbreakable rules

1. **Never touch a live chain.** No transactions to any network, no private keys. Every attack is
   proved in a local Foundry test. Read-only RPC at most.
2. **Stay in your paths.** A hunt changes no tracked file (scratch PoCs go in `test/scratch/`, which
   is never submitted). Prove and fix jobs write only the paths their task allows.
3. **Report through the job only.** Everything becomes public on IMD's record; that is expected.

## 🗺️ The realm

**In scope:** every Solidity file in this repository outside `test/`, `reference/`, `lib/` and
`tools/` — the 10 clusters in `MAP.md`: hook, registry, pool, perp, rotation, nft, governance,
seed, art, deploy.

**Out of scope:** `lib/` (OpenZeppelin, Uniswap v4 — assume correct), tests. `MockAggregator` /
`MockQuoteToken` are testnet-only: report them only if a mainnet deploy path can end up using them.
Deploy scripts matter only when they can ship an exploitable state.

**The trust circle**

| inside the circle (assume honest) | outside the circle (assume hostile) |
|---|---|
| the deployer, during configuration | every other caller, keepers and permissionless callers included |
| the timelock / governance, executing proposals that passed | any address a user supplies: tokens, venues, receivers, contracts |
| the frenlist setter | MEV searchers, sandwichers, flash-loan borrowers |
| Uniswap v4 PoolManager, OpenZeppelin | token and NFT holders, including many colluding wallets |
| Chainlink feeds (honest, but can be stale) | anyone who can deploy a contract or send dust |

A member of the circle acting maliciously is out of scope — unless the code lets it skip a
timelock or guard it promises, or an outsider's input can reach a circle-only path.

**What is already known**

- `ledger/LEDGER.md` — everything the swarm has found in earlier rounds, with an ID (`FR-…`), how
  many seats reported it, and its status. **Do not re-report a ledger issue as new**: confirm or
  refute it in your coverage block instead. A confirmation from an independent seat is valuable.
- `ledger/KNOWN.md` — issues known before the swarm arrived. `OPEN` / `ACCEPTED-LOW` there are
  known; report one only with a new, worse impact. A `FIXED` item that comes back is a
  **regression**, and the wizards want to hear about it most of all.

## 🧙 The machine you are attacking (orientation — the code is the truth)

Read `CAULDRON.md` and `docs/contracts-README.md`. In one breath:

- **Genesis:** `MiFrensGenesis` sells the genesis wizards (public price, or a tenth of it for
  frenlist wallets via a Merkle proof). Sold out → `igniteCauldron` sends every wei to
  `CauldronRegistry.summon`, which deploys generation 1 — GnomeLand: token, v4 pool with
  `CauldronHook`, seed liquidity. There is no owner withdraw path.
- **Life:** `CauldronHook` sits on every swap: fees, the rolling 24-hour volume, buybacks, NFT mints
  from volume (the crystal gacha), and a pre-trade sweep of unsafe perp positions.
- **Death is a feature:** when 24h volume falls below the death threshold, anyone may `relaunch()`:
  liquidity is recovered from the dead pool, recovered tokens burn, the next generation is summoned
  in the same transaction, and holders claim 1:1.
- **Perps:** `PerpEngine` opens leveraged positions against the pool's own mark, `PerpVault` stakers
  back them; liquidations — including pre-emptive ones — pay keepers and strike Liquidatoor badges.
- **Treasury rotation:** `QuoteRotator` / `RedemptionExt` move the treasury between quote assets
  (ETH → a stablecoin and back) in slices through venues, behind an oracle price floor (`QuoteOracle`).
- **Floors and fees:** per-generation collections, `MiFrensDividend` (cast the spell on a genesis
  fren and it earns from every brew), the collection floor vault (`CauldronVault`), the gacha router.
- **The guild:** `CauldronGovernor` (who brews next), `TreasuryGovernor` (genesis-weighted votes).

## 🔭 Your map of the machine

`MAP.md` lists every externally callable, state-changing function per cluster — who can call it
and what value it moves. `map/<cluster>.json` has the full facts for every function: `authority`,
the exact `authority_gate_quote` line, storage `reads`/`writes`, `value`, call `edges` labelled
**TRUSTED/UNTRUSTED**, `reachability`, `observations`. Each node carries `semantics`:
`fresh` (code unchanged since mapped — reliable pointers) or `stale`/`missing` (code changed or new
— **read the source**; new code is where new bugs hatch, so hunt there first).

`python3 tools/check-map.py` proves the map matches the source you have. The map is a lantern, not
a proof — verify every fact you lean on against the code.

## ⚗️ Your lab

```sh
forge build        # ~1.5 min cold on a fast laptop (a few on a small VPS). Foreground; wait.
forge test         # must be green offline: the PoC template and the frenlist suite
```

The art cluster builds separately: `FOUNDRY_PROFILE=render forge build`.

**PoC base:** `test/fren-review/FrenPoCTemplate.t.sol` on `test/fren-review/FrenBase.sol` boots
the real registry, hook and perp engine on a local v4 PoolManager — no fork, no RPC. For the nft
cluster, deploy `MiFrensGenesis` directly as `test/GenesisDiscountMint.t.sol` does.
`reference/test/` holds 250+ earlier attack tests (not compiled): read them to see how previous
hunters reached deep state, and copy what you need — any that use `FORK_RPC` will not run for you.

**Four false spells** — PoCs that look like proof and prove nothing. Our own red teams cast every one:
1. **The empty cauldron.** `YBase`'s own `_boot` returns silently without `FORK_RPC`; any early
   `return` or skipped branch turns a test green with zero assertions. Build on `FrenBase`, keep
   `assertTrue(active)`, and read the `-vv` trace to confirm your assertions ran.
2. **Praising the call instead of the damage.** Assert balances before and after, the invariant
   that breaks, the state that should be impossible — not that a function returned.
3. **The frozen clock.** Under via_ir, `block.timestamp` read after `vm.warp` can be stale. Use
   `vm.getBlockTimestamp()` and assert the warp landed.
4. **Slaying a mock.** Attack the real contracts, not a stand-in for them.

---

## 🔍 HUNT — the full-scope red-team pass (role: review)

Your seat has a fixed budget of turns and wall clock. **Never skip a cluster** — a shallow pass
over all ten beats a deep pass over three.

1. **Light the fire (≈10%).** `forge build`, `forge test`.
2. **Read the runes (≈10%).** `CAULDRON.md`, `MAP.md`, `ledger/LEDGER.md`, `ledger/KNOWN.md`.
3. **Walk the machine (≈50%)** in MAP order. Go deepest where value moves and where code is new.
   At every entry point ask:
   - **Access** — can the gate be bypassed? `msg.sender` vs `tx.origin`, callbacks (v4 unlock,
     ERC721 receiver, token hooks), re-settable wiring, initializers called twice, a role that ends
     up pointing at an attacker's address.
   - **Value** — every ETH/token movement: who controls the amount and the recipient? Rounding
     direction, 6- vs 18-decimal quotes, native vs ERC20 confusion, fee-on-transfer, dust, zero.
   - **State machine** — presale → ignite → live → dead → relaunch; rotation in flight; perps
     open. Call things out of order, twice, in the same block, across a relaunch or a rotation.
     Can anyone make a transition impossible forever?
   - **Prices** — spot or TWAP bent within one block or across blocks, stale Chainlink answers,
     swaps with no `minOut`, oracle reads that revert.
   - **Reentrancy** — external calls before state writes, cross-contract re-entry, read-only
     re-entry into views that others trust.
   - **Accounting** — shares, dividends, debts, claims: claim twice, inflate a share, strand another
     fren's funds, first-depositor effects, transfers that skip settlement.
   - **Liveness** — unbounded loops, gas starvation under `try/catch`, reverting receivers, spam
     that pushes a real entry out of a bounded list.
4. **Follow the gold (≈15%).** Does every wei that enters come out somewhere accounted for? Across a
   relaunch and a rotation, is every generation- or quote-dependent value carried over? Which
   contract can call which admin function, and can that chain be hijacked?
5. **Prove it or let it go (≈15%).** Every new finding gets a PoC in `test/scratch/` or an exact
   call sequence with inputs. A suspicion you could not prove is a `suspect` verdict, not a finding.

**Report new findings** in `.imd-findings.json` at the repository root (an empty list is a result):

```json
{"findings": [{
  "severity": "high",
  "title": "Anyone can drain the relaunch reserve through X",
  "path": "cauldron/Example.sol",
  "line": 123,
  "description": "What is wrong, why an outsider can reach it, and the impact in ETH or tokens.",
  "reproduction": "Steps with exact inputs, expected vs actual. Then the full PoC source, the command, and the result line."
}]}
```

**End with the coverage block.** Your final message is stored as your submission summary (keep it
under ~3,500 characters) and read by a script, so start it with this block, exactly:

```
FREN-REVIEW v1
hook: solid | 59 | <the deepest thing you tried, one line>
registry: suspect | 40 | <...>
pool: solid | 21 | <...>
perp: exploitable | 58 | <...>
rotation: solid | 39 | <...>
nft: solid | 73 | <...>
governance: solid | 12 | <...>
seed: solid | 16 | <...>
art: solid | 7 | <...>
deploy: solid | 18 | <...>
confirms: FR-1a2b3c, FR-4d5e6f
refutes: FR-7a8b9c because <one line>
```

One line per cluster: the cluster name, a verdict, the number of entry points you examined, and
your deepest attempt. Verdicts: **solid** (you attacked it and it held), **suspect** (something is
off but you could not prove it — say what), **exploitable** (you reported a finding in it).
`confirms` / `refutes` name ledger issues you re-checked (omit the line if none). After the block,
anything else you want the wizards to know.

## 🧪 PROVE — turn a ledger issue into a runnable PoC (role: tests)

Your task names one ledger issue `FR-…` with its description and the reproduction reporters gave.

1. Reproduce it on the real contracts, on `FrenBase`, in `test/fren-review/<ID>/` — the only path
   you may write.
2. **If it reproduces:** the test asserts the HARMFUL outcome (the stolen balance, the broken
   invariant, the stuck state) and passes on today's code — a green test that documents the bug.
   Name it `test_<ID>_Exploit...`.
3. **If it does not:** the test asserts the defence holding against the exact claimed sequence
   (name it `test_<ID>_Refuted...`), and your final message explains why the claim fails.
4. `forge build` and `forge test` must both pass.
5. Start your final message with `FREN-REVIEW PROVE <ID>: reproduced` or
   `FREN-REVIEW PROVE <ID>: not-reproducible`, then the evidence.

## 🔧 FIX — close a proven issue (role: implement)

Your task names one ledger issue `FR-…`, its PoC under `test/fren-review/<ID>/`, and the source
files you may change.

1. Make the **smallest** change that closes the root cause — not the symptom the PoC happens to
   hit. Do not refactor, rename or reformat anything else.
2. Flip the PoC into a regression test: it now asserts the SAFE outcome and would fail if the bug
   came back. Add the variants the fix must also cover.
3. `forge build` and `forge test` must pass. Contracts must stay deployable: check
   `forge build --sizes` — runtime code must stay under 24,576 bytes (several contracts are close).
4. Start your final message with `FREN-REVIEW FIX <ID>: fixed` or `FREN-REVIEW FIX <ID>: cannot-fix`,
   then what you changed and why it closes the root cause.

---

## Severity

| | meaning |
|---|---|
| critical | an outsider cheaply steals or permanently locks user/protocol funds, or permanently bricks a core flow |
| high | theft or loss under specific but realistic conditions; long-lived denial of trading, relaunch, claims or withdrawals; governance capture |
| medium | bounded loss, griefing that costs the attacker, temporary denial, accounting errors without direct theft |
| low | edge cases with minor impact; unsafe patterns with a plausible path to harm |
| info | no security impact |

## ✅ Before you ascend

- [ ] every finding has path, line, severity and a reproduction that was run, not reasoned
- [ ] nothing already in `ledger/` is reported as new — confirm or refute it instead
- [ ] your final message starts with the `FREN-REVIEW` line or block for your job type
- [ ] you wrote only what your job allows; no transaction was sent anywhere

*the cauldron does not care about your feelings. it cares about invariants. wagmi, fren.* 🧙‍♂️🐸
