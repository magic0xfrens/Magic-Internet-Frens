# R45 Byte Ledger — CauldronHook / PerpEngine / EIP-170-adjacent contracts

| contract | runtime bytes at P0 | free at P0 | free now | claimed by |
|---|---|---|---|---|
| CauldronHook | 23,140 | 1,436 | 1,436 | — |
| Harness (test/attacks/K3d_DeathBandProtectsForcedClose.t.sol) | 24,548 | 28 | 28 | — |
| CauldronRegistry | 24,492 | 84 | 84 | — |
| X3iEngine | 24,299 | 277 | 277 | — |
| X9cEngine | 24,299 | 277 | 277 | — |
| PerpEngine (0.8.26 / 0.8.30) | 24,247 | 329 | 329 | — |
| PositionDescriptor | 24,110 | 466 | 466 | — |
| PoolOps | 24,006 | 570 | 570 | — |
| PerpSwapLib (0.8.26 / 0.8.30) | 8,978 / 8,968 | 15,598 / 15,608 | 15,598 / 15,608 | — |
| GachaLib | 1,466 | 23,110 | 23,110 | — |

Note: rows above are every production/test contract in the real-tree `forge build --sizes` table with < 2,000 B free at P0, plus PerpSwapLib and GachaLib (required by brief regardless of margin). Harness/X3iEngine/X9cEngine/PositionDescriptor/PoolOps are test-harness or vendored-library contracts, not deployed production contracts — included here only because they crossed the <2,000 B threshold; treat CauldronHook, CauldronRegistry, PerpEngine as the load-bearing production rows.

## Claims table

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|

Status legend:
- CLAIMED → DONE
- CLAIMED → RELEASED
- WAIT (note names the blocker)
- SPACE (note says bytes needed and from where)

## fixer-off claims (off-chain group)

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixer-off | F6 build hygiene | contracts/solidity/foundry.toml | [profile.cauldron] skip | DONE 763a84b | clean `forge build --force` now succeeds from an empty out/; ALL runtime sizes identical to sizes-real.txt (CauldronHook 23,140 / CauldronRegistry 24,492 / PerpEngine 24,247 / GachaRouter 8,814). No ABI change. |
| fixer-off | F1 R5A | src/components/cauldron/CrystalCauldronGame.tsx, src/components/cauldron/TheCauldron.tsx, audit/R45_READINESS_2026-09-15/hunt/h5-poc/r5a-spin-quote-unaware.mjs | spin, Props | DONE cf188a6 | the crystal spin now sends quoteIn + a bounded approval when the quote is ERC20 (value only when native) and sizes its floor in quote units; CrystalCauldronGame takes quote/quoteSymbol/quoteDecimals. |
| fixer-off | F2 R5B | src/components/cauldron/StakePanel.tsx, src/hooks/usePerpVault.ts, audit/R45_READINESS_2026-09-15/hunt/h5-poc/r5b-stakepanel-decimals.mjs | onAction, approveQuote, approveToken | DONE d53c26c | StakePanel parses with the live quote decimals and ERRORS on over-balance instead of substituting the balance; usePerpVault.approveQuote/approveToken now TAKE an amount (signature change for callers) and approve exactly it. |
| fixer-off | F3 R5C | indexer/ponder.config.ts | chains.cauldron.rpc | DONE 52e9c3c | default is ONE pinned provider (tenderly); PONDER_RPC_URL as a list is viem fallback(rank:false) ordered failover, never round-robin. railway.json untouched. |
| fixer-off | F4/F7 R5E,R5F | indexer/src/api/index.ts | evaluateHealth, watchdog, /candles, /recent | DONE a2c2e0b | /freshness now separates BEHIND (ok) from DIVERGED (not ok) and no longer masks divergence with everHealthy; watchdog fires on a fresh boot. Response shape kept + new `behind` field. /candles/:gen and /recent/:gen 400 on a non-integer param. |
| fixer-off | F5 C-1 | scripts/verify-selectors.mjs, scripts/apply-deployment.mjs, scripts/auto-deploy.sh, scripts/deploy-testnet.sh, scripts/go-testnet.sh, .github/workflows/deploy.yml | REQUIRED map, gate | DONE d9975af | selector parity now runs (and ABORTS) from apply-deployment.mjs, auto-deploy.sh and CI; REQUIRED covers 11 manifest keys / 43 signatures derived from the app's ABIs. Live run: ONLY playChurn missing on r44's router (0xdf70b5a4) — everything else present. deploy-round.mjs untouched (writes no manifest). Deploy scripts force a clean build before broadcast. |
| fixer-off | F7 R5H | src/hooks/useCauldronSwap.ts, src/components/cauldron/SwapWidget.tsx | approveToken | DONE 85a7a80 | useCauldronSwap.approveToken now TAKES an amount (signature change) and approves the sale size, not maxUint256. |
| fixer-off | F7 R5G | scripts/keeper.sh | materialize, sweep | DONE 7863119 | cast send failures log to stderr with the id; O(nextId) sweep logged-not-fixed in a comment. |

## fixer-vault claims (PerpVault group)

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixer-vault | R2B | contracts/solidity/cauldron/PerpVault.sol, contracts/solidity/test/attacks/R2B_TokenQueueLatch.t.sol, contracts/solidity/test/attacks/R2Mock.sol | claimPendingToken, depositToken, _bankTokWriteDown | DONE 8bcfe78 | claimPendingToken now BANKS the haircut on both owed==0 and paid==0 (no more revert-rollback), so pendingTok drains and hasStakers()/setVault unlatch; depositToken now reverts QueueInsolvent while pendingTok > engine.totalTokenAssets(). ABI CHANGED (see R2C row). |
| fixer-vault | R2C | contracts/solidity/cauldron/PerpVault.sol, contracts/solidity/test/attacks/R2C_DepositLatch.t.sol | claimPendingEth, _bankEthWriteDown, settlePendingEth, settlePendingToken | DONE 8bcfe78 | ANYONE can now call settlePendingEth(user)/settlePendingToken(user) to bank a queued address's pro-rata write-down; it pays the caller nothing, so a hostile receive() cannot re-latch. QueueInsolvent gate itself UNCHANGED and still refuses deposits while the queue is unbacked. ABI CHANGED: PerpVault gains settlePendingEth(address), settlePendingToken(address), event QueueWrittenDown(address indexed,bool,uint256) — indexer/abis + src/config may want the new event. |
| fixer-vault | R2A | (none) | _haircut | RELEASED | ACCEPTED-BY-DESIGN, no source change. A queued exit is a fixed nominal that has LEFT the share base (PerpVault.sol:336-344), so it stops earning yield as well as bearing loss; making it keep bearing loss after its shares are burned needs a second share class with its own index — i.e. the restructure of the queue's economics the brief forbids, and it would re-open the yield-attribution ambiguity the nominal-claim model settles. The transfer is LP-vs-LP, bounded by _haircut once claims exceed backing (PerpVault.sol:366-374), and no value leaves the protocol. A future change must FIRST prove (a) the race is orderable in practice — an LP observing an incoming death-settle/liquidation and landing withdrawEth ahead of it on the target chain's ordering, not a PoC that hard-codes the sequence — and (b) that the expected transfer exceeds the yield forgone by queueing early. Neither is established today. |
| fixer-vault | pre-existing/other-agent | contracts/solidity/test/attacks/S06_PerpVaultSolvency.t.sol | test_S06_POC_RealEngine_QueueingBeforeBadDebtShedsAllOfItOnLpB | WAIT | NOT MINE — FAILS at :600 `pending 344218925886143795 <= backing 459182015833333191`. ETH-only real-engine run; my diff changes no ETH-side arithmetic (claimPendingEth refactor is behaviour-identical, settlePending* is never called there, the depositToken guard is unreachable on this path). Blocker: fixer-liq's in-tree PerpEngine.sol/CauldronHook.sol edits change how much bad debt is realised, which is exactly the number this asserts. fixer-liq to re-check. |

## fixer-gacha claims

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixer-gacha | R3A uncapped gacha re-anchor | contracts/solidity/cauldron/GachaLib.sol, contracts/solidity/test/attacks/R3A_GachaReRollGrind.t.sol, contracts/solidity/test/attacks/R3C_SupplyConservation.t.sol, contracts/solidity/test/attacks/R3D_AgedQueueStall.t.sol | resolveTickets | CLAIMED | one re-anchor per batch via ERC-7201 namespaced slot; NO CauldronHook.sol edit, Batch struct + batches(uint256) getter ABI unchanged |

## fixer-liq claims (in-swap liquidation group)

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixer-liq | R1C caller-picked gas disables liquidation | contracts/solidity/CauldronHook.sol, contracts/solidity/test/attacks/R1C_GasFloorBypass.t.sol | _liqSweep, _beforeSwap, _afterSwap | CLAIMED | gas-starved swap must not trade with liquidation silently off |
| fixer-liq | R1B 12-slot window over 64-slot book | contracts/solidity/cauldron/PerpEngine.sol, contracts/solidity/test/attacks/R1B_SweepWindowStarvation.t.sol | _doSweep, sweepCursor, SWEEP_SCAN | CLAIMED | dust padding must not hide an insolvent position from its own trade's sweep |
| fixer-liq | R1A free-kill slack (LOG ONLY) | contracts/solidity/test/attacks/R1A_FreeKillSlack.t.sol | — | CLAIMED | characterization test only, accepted-with-rationale, no source change |

## fixer-pool claims (seed/relaunch group)

| agent | finding | files (comma-separated) | functions | status | note |
|---|---|---|---|---|---|
| fixer-pool | R4A seed reserve stranded by a short-returning branch | contracts/solidity/cauldron/PoolOps.sol, contracts/solidity/test/attacks/R4A_SeedFundingStrand.t.sol | seedFunding, _pullAsset, _pullEth | CLAIMED | peek hook reserve before pulling; CauldronHook.sol READ-ONLY (owned by fixer-liq), no edit planned |
| fixer-pool | R4A stub fidelity | contracts/solidity/test/audit/B13_SeedFundingDustPreference.t.sol | HookStub13 | CLAIMED | rename stub slots to relaunchAsset/relaunchETH to match the real hook's public getters; no assertion weakened |
