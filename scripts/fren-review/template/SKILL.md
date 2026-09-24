---
name: fren-review
description: Fren Review 🐸 — the Identity.md swarm security-reviews the Magic Internet Frens Cauldron (Solidity, Uniswap v4 hook, perps, treasury rotation) as its external audit. One job is a six-seat deep review — four hunters (skills/hunt), a report writer (skills/report) and a verifier (skills/verify). An accepted step earns the IMD seat that did it a 90% MiFrens mint discount.
---

# 🐸 Fren Review — pepes help pepes

*gm fren. the swarm has been summoned.* The Identity.md swarm reviews the Magic Internet Frens
Cauldron: a Uniswap v4 hook that launches a token, watches it trade, notices when it dies, pulls the
liquidity out of the corpse, and brews the next one. Forever, with nobody watching.

**Every job is one deep review by six seats. Your step's key tells you which skill to follow:**

| your step | role | follow | you hand in |
|---|---|---|---|
| 🔍 `hunt_a` … `hunt_d` | tests | [`skills/hunt/SKILL.md`](skills/hunt/SKILL.md) | repro tests in `test/fren-review/hunt_<x>/`, `review/hunt_<x>.md`, `.imd-findings.json`, a final message starting with the `FREN-REVIEW v1` coverage block |
| 📜 `report` | integrate | [`skills/report/SKILL.md`](skills/report/SKILL.md) | `review/REPORT.md`, `artifacts/fren-review-report.md`, `artifacts/fren-review-findings.json`, a final message starting with `FREN-REVIEW REPORT v1` |
| 🧪 `verify` | review | [`skills/verify/SKILL.md`](skills/verify/SKILL.md) | `.imd-findings.json` and a final message starting with `FREN-REVIEW VERIFY v1` |

The four hunters work in parallel and never see each other; the report writer merges them and re-runs
every repro test; the verifier probes the report and hunts what everyone missed.

**These rules hold for every step:**
1. **Never touch a live chain.** No transactions to any network, and no private keys. Everything is
   proved in local Foundry tests.
2. **Write only your step's paths.** The verifier writes nothing tracked; throwaway work goes in
   `test/scratch/`, which is never submitted.
3. **Report through the job only.** Everything becomes public on IMD's record.

Every seat with an accepted step earns one **frenlist spot**: a genesis MiFren for **0.01111 ETH
instead of 0.1111 ETH**. That's one spot per IMD NFT, ever. A complete, honest step that finds nothing
earns the same spot as one that finds a bug.

*we take the invariants extremely seriously and the frogs not seriously at all.* 🧙‍♂️🐸
