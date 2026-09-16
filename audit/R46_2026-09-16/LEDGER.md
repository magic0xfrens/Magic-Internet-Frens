# R46 ledger — 2026-09-16

Branch `redteam/2026-09-13`, 23 commits on `a3bcd29`. `main` FROZEN at `0d2c39c`.
**Nothing pushed. Nothing on `main`.**

Rules: `tail -40` before your first edit. Post a `CLAIMED` row naming every file you
will touch. Never edit another agent's claimed file — post `WAIT` and report.
`git status` before committing. **Stage only claimed files — never `git add -A`.**
Flip to `DONE` with the commit hash. Commit green partials rather than lose work.

## P0 — orchestrator, verified before any agent ran

| claim (from brief) | result |
|---|---|
| 23 commits on `a3bcd29` | **VERIFIED** `git rev-list --count` = 23 |
| `main` frozen at `0d2c39c` | **VERIFIED** |
| `auto-deploy.sh:65` refuses chain ≠ 11155111 | **VERIFIED** exact line 65 |
| `auto-deploy.sh:81` EIP-170 guard reads `$4` not `$5` | **VERIFIED** — header is `Contract\|Runtime Size\|Initcode Size\|Runtime Margin\|Initcode Margin`, so with `-F'\|'` `$4`=Initcode Size (never negative) and `$5`=Runtime Margin. **The guard can never fire.** |
| B-3 is uncommitted, `V2B_GenesisOnlyQuorum.t.sol` untracked | **FALSE — brief is stale.** B-3 landed in `6eaf67c`: `_getVotingUnits` returns `genesisBalanceOf[account]` (`MiFrensGenesis.sol:721`). V2B is tracked (180 lines, committed). Working tree is clean. Only the **quorum-denominator trap** remains unverified. |
| (not in brief) | **NEW BLOCKER — `PerpEngine` runtime 25,185 B, margin −609 B. OVER EIP-170. Does not deploy.** Both 0.8.26 and 0.8.30 artifacts. `55ba6fe` (the E1A Critical fix) added 97 lines to the file. The `$4` bug at `auto-deploy.sh:81` is exactly why this was not caught. |

Also oversized, **test-only, not deploy blockers**: `Harness` in
`test/attacks/K3d_DeathBandProtectsForcedClose.t.sol` (−906), `X3iEngine` /
`X9cEngine` (−661, in `X3i_*`/`X9c_*` attack tests).

Contracts closest to the limit (runtime margin, B): CauldronRegistry **84**,
PoolOps **403**, PositionDescriptor **466**, CauldronHook **1,233**.

## Rows

| agent | finding | files (comma-separated) | functions | status | note |
|-------|---------|------------------------|-----------|--------|------|
| D1 | mainnet (4663) deploy path: no script existed | `scripts/deploy-mainnet-rh.sh` (NEW) | whole file | **DONE `8def6b1`** | `--self-test` proves 4 gates fire w/o RPC or key. D2 runs `--gates` then `--broadcast --stage deploy` against a fork. |
| D1 | EIP-170 gate reads `$4` (Initcode Size), can never fire | `scripts/auto-deploy.sh` | lines 64-84 | **DONE `8def6b1`** | now header-derived column + FAILS CLOSED. Line 65 chain assert kept, intent parameterised (`EXPECT_CHAIN`, default Sepolia). |
| D1 | selector gate RPC defaults to Sepolia; `vault` check could never run | `scripts/verify-selectors.mjs` | RPC default, chain assert, vault resolve | **DONE `8def6b1`** | RPC now derived from manifest `chainId` + asserted. `vault` resolved via `collection.vault()` (`CauldronCollection.sol:51`) so `redeem(uint256)` is checked for the first time. |
| D1 | 6 manifest keys with no producer | `indexer/deployments/round.robinhood.template.json` | `_producers` | **DONE `8def6b1`** | `chainId` is a 6th orphan the brief did not list — it stays 11155111 through a cutover unless hand-edited. 5 now produced; `indexerUrl` is genuinely underivable (Railway assigns it) and is a required input. |
| D1 | **CRITICAL (deploy config)** — `DEPLOY_QUOTES` defaults **true**, deploying `MockQuoteToken` whose `mint()` is **ungated** (`MockQuoteToken.sol:27`) and allowlisting it as a rotation destination | `scripts/deploy-mainnet-rh.sh` GATE 2 | — | **DONE `8def6b1`** (gated) | anyone could mint unlimited "Magic USD" and drain the rotation venue. Script refuses unless `DEPLOY_QUOTES=false`. **Root cause is in `DeployLaunchpad.s.sol:533` — not my claimed file; needs an owner decision.** |
| D1 | **HIGH (deploy config)** — `FEED_ETH_USD` (`DeployLaunchpad.s.sol:601`) is a **Sepolia** Chainlink address; VERIFIED `eth_getCode` = `0x` on 4663 → `usdPerRawUnit` returns 0 → hook records **zero volume for every trade**; mint ladder dead, `isDead` always true | `scripts/deploy-mainnet-rh.sh` GATE 2 | — | **DONE `8def6b1`** (gated) | the script's own comment (`:677-681`) documents this for "any other chain". `NATIVE_PEGGED_USD` is NOT the fix — 4663 native is real ETH. Reachable only via `DEPLOY_QUOTES=true`, already refused. |
| D1 | live r44 Sepolia deployment still missing `playChurn` | (none — observation) | — | **REPORTED** | the repaired selector gate caught it on the first run against the live manifest. Not a code change; the deployed round is still broken. |
| D1 | ledger bookkeeping | `audit/R46_2026-09-16/LEDGER.md` | Rows | **DONE** | |
| O1 | read-layer has no alarm: wire external monitor to `/freshness`, derive thresholds, price 4663 archive RPC, key rotation | `audit/R46_2026-09-16/LEDGER.md`, `indexer/scripts/patch-ponder-finality.mjs`, `indexer/src/api/index.ts`, `indexer/monitor/freshness-probe.mjs`, `indexer/monitor/README.md`, `docs/protocol/11-OPERATIONS.md` | `evaluateHealth`, `patchFinality`, `verifyFinality`, `ponderFinalityBlocks` | CLAIMED | staying in `indexer/` + `docs/`. NOT touching `contracts/`, `scripts/auto-deploy.sh`, `scripts/verify-selectors.mjs`, `indexer/deployments/round.json`. |
| S1 | EIP-170 PerpEngine over limit | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/cauldron/PerpSwapLib.sol | size refactor only — no behaviour change | CLAIMED | PerpEngine runtime 25,185 B (−609). Freeing bytes. Nobody else edit these two files. |
| S1 | SPACE | contracts/solidity/cauldron/PerpEngine.sol | — | SPACE | need ≥609 B (target ≥987 more for the queued e1a split-band). VERIFIED regression point: 55ba6fe took PerpEngine 24,273 → 25,185 (+912). PerpEngine.sol is byte-identical from 0f71309 to 55ba6fe^, so 0f71309 = 24,273 B / +303 margin. |
| F1 | quorum denominator trap | contracts/solidity/test/attacks/V2C_QuorumDenominatorAtScale.t.sol (NEW, mine only) | n/a — read-only on cauldron/MiFrensGenesis.sol + cauldron/TreasuryGovernor.sol | CLAIMED | new file only; no production file edited |
| O1 | (amend) monitor transport file added to claim | `.github/workflows/indexer-monitor.yml` | scheduled probe job | CLAIMED | new file; does not touch the existing `deploy.yml` |
