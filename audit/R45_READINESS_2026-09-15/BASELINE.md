## STEP1a
redteam/2026-09-13
e4ea3dc
--status--
 m contracts/solidity/lib/openzeppelin-contracts
 M index.html
 M package.json
 M public/llms.txt
 M public/robots.txt
 M public/sitemap.xml
 M src/app/App.tsx
 M src/components/docs/Docs.tsx
 M src/components/layout/navItems.ts
 M src/components/presale/PresaleModal.tsx
 M src/components/preview/HomePreview.tsx
 M src/components/wizards/MyWizards.tsx
 M src/main.tsx
 M vercel.json
?? .agents/
?? audit/R45_READINESS_2026-09-15/
?? scripts/prerender-seo.mjs
?? skills-lock.json
?? src/app/RouteSeo.tsx
?? src/app/legacyHashUrl.ts
?? src/app/seo-routes.json
--diffstat--
 src/main.tsx                                  |  4 +++
 vercel.json                                   |  5 ++-
 14 files changed, 122 insertions(+), 37 deletions(-)

## STEP1b — forge build --sizes (real tree)
Full table saved to sizes-real.txt (1526 lines). Key contracts (Runtime B / Margin B):
- CauldronHook: 23,140 / 1,436
- PerpEngine (.0.8.26 and .0.8.30): 24,247 / 329
- CauldronRegistry: 24,492 / 84
- PerpSwapLib.0.8.26: 8,978 / 15,598 ; PerpSwapLib.0.8.30: 8,968 / 15,608
- GachaLib: 1,466 / 23,110
All match the brief's expected byte figures exactly.
Full margin-sorted extraction of every contract <1,000 B margin should be pulled from sizes-real.txt by grep.

## STEP1c — forge test --threads 2 (fork env, FOUNDRY_PROFILE=cauldron, tenderly FORK_RPC)
Ran 244 test suites in 851.35s: 969 passed, 2 failed, 1 skipped (972 total tests).

Failing tests:
1. test_CHURN1_playWorksButChurnReverts (test/attacks/CHURN1_LiveRevert.t.sol) — [FAIL: EvmError: Revert]
2. test_S06_POC_RealEngine_QueueingBeforeBadDebtShedsAllOfItOnLpB (test/attacks/S06_PerpVaultSolvency.t.sol) — [FAIL: expected the queue to outgrow the backing: 344218925886143795 <= 459182015833333191]

Re-run (--match-path, fork env, same tenderly RPC) on both failing files individually:
- CHURN1_LiveRevert.t.sol: still FAILED (1 test, deterministic EvmError: Revert — not a 429/520/db-error signature, so this is NOT infrastructure; genuine failure).
- S06_PerpVaultSolvency.t.sol: still FAILED on the same test, 16 other tests in that file passed — matches the brief's expected pre-existing failure.

## STEP1d — comparison to brief's expected numbers
- Expected: 969 passing, 1 failing (S06 POC), pre-existing. ACTUAL: 969 passing, 1 skipped, but 2 FAILING (S06 as expected, PLUS an additional CHURN1_LiveRevert failure not mentioned in the brief). DISAGREEMENT FLAGGED: CHURN1_playWorksButChurnReverts is a new/unexpected failure, confirmed non-infrastructure on re-run.
- Byte sizes: all 5 named contracts match expected exactly (see above). No disagreement.
- Skipped count: 1 (out of 972) — small fraction, fork env was present and correct (not a missing-fork-env signature).

## P0 step 1 — session check (orchestrator)
`ListAgents` at run start showed one peer session in this repo: `magic-internet-frens-71`, interactive, **idle** for ~3h, nothing queued. The brief says to stop if another session is *active*; an idle session was judged not active, so the run proceeded. No concurrent edits were observed at snapshot time (`git status` matched the pre-run snapshot). Flagged here and in the final recap.

## Orchestrator notes on the P0 result
- Second baseline failure `test_CHURN1_playWorksButChurnReverts` is not in the brief's expected set; it fails deterministically at HEAD e4ea3dc with no uncommitted contract changes, so it is a baseline failure, not a regression from this run. Classification delegated to P2.5 (artifact parity), since it concerns the live churn seam.
- PerpSwapLib measured 8,968 B (brief said 8,978); real and blind trees agree, so the brief's number is the stale one.
- Blind tree required `--skip 'lib/v4-periphery/lib/permit2/script/**'` for a clean build; the real tree only builds because a stale `out/` cache masks the broken vendored import. A clean-clone build of this tree currently fails. Referred to P2.5 as a deploy-pipeline hygiene item.
- `test/attacks/YBase.sol` is a shared helper, not an answer-key PoC; it was restored into the blind tree (3 comment tags hand-stripped).
