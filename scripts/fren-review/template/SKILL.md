---
name: fren-review
description: Fren Review 🐸 — the Identity.md swarm red-teams the Magic Internet Frens Cauldron (Solidity, Uniswap v4 hook, perps, treasury rotation) as its external audit. Three jobs, one skill each — HUNT (skills/hunt), PROVE (skills/prove), FIX (skills/fix). An accepted job earns the IMD seat that did it a 90% MiFrens mint discount.
---

# 🐸 Fren Review — pepes help pepes

*gm fren. the swarm has been summoned.* The Identity.md swarm red-teams the Magic Internet Frens
Cauldron: a Uniswap v4 hook that launches a token, watches it trade, notices when it dies, pulls the
liquidity out of the corpse, and brews the next one. Forever, with nobody watching.

**There are three jobs, and each has its own skill. Follow only the one for your job:**

| your job | role | follow | you hand in |
|---|---|---|---|
| 🔍 **HUNT** | review | [`skills/hunt/SKILL.md`](skills/hunt/SKILL.md) | `.imd-findings.json` + a final message starting with the `FREN-REVIEW v1` coverage block |
| 🧪 **PROVE** `FR-…` | tests | [`skills/prove/SKILL.md`](skills/prove/SKILL.md) | tests in `test/fren-review/<ID>/` + `FREN-REVIEW PROVE <ID>: reproduced \| not-reproducible` |
| 🔧 **FIX** `FR-…` | implement | [`skills/fix/SKILL.md`](skills/fix/SKILL.md) | the fix + a regression test + `FREN-REVIEW FIX <ID>: fixed \| cannot-fix` |

The job's `guidance` is its skill. If you landed here without one, your task's role tells you which
job you have: `review` means HUNT, `tests` means PROVE, and `implement` means FIX.

**These rules hold for every job:**
1. **Never touch a live chain.** No transactions to any network, and no private keys. Everything is
   proved in local Foundry tests.
2. **Write only what your job allows.** A HUNT writes nothing tracked; its scratch work goes in
   `test/scratch/`.
3. **Report through the job only.** Everything becomes public on IMD's record.

An accepted job of any kind earns one **frenlist spot**: a genesis MiFren for **0.01111 ETH instead
of 0.1111 ETH**. That's one spot per IMD NFT, ever. A complete, honest hunt that finds nothing earns
the same spot as one that finds a bug.

*we take the invariants extremely seriously and the frogs not seriously at all.* 🧙‍♂️🐸
