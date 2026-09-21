# Full-Scope Audit Baseline — 2026-09-18

## Current continuation rerun — 2026-09-19

The historical baseline below is retained. Against the current owner-modified
working tree, the required application/build checks were re-run:

| Check | Result | Evidence / limitation |
|---|---:|---|
| `npm run build` | PASS | Vite production build and five-route prerender completed; Sass/dependency deprecation and chunk-size warnings only. |
| `npm run verify:manifest` | PASS | Sepolia manifest validated; no hardcoded-address or env-override violations. |
| `npm --prefix indexer run codegen` | PASS WITH WARNING | Exit 0 and wrote `ponder-env.d.ts`; Ponder emitted `Failed to find Response internal state key`. |
| `npm --prefix indexer run typecheck` | PASS | Exit 0. |
| `npm test` | PASS | 19 Node, 2 API, 7 indexer, and 5 swap-gas tests passed. |
| `npm run type-check` | PASS | Exit 0. |
| Current full offline Forge run | PARTIAL | 803 passed / 35 failed; failures are retained and classified as fork/infrastructure coverage gaps in `OFFLINE_RERUN.md`. |

No deployment, broadcast, signing-key access, or live state mutation occurred.

Current isolated production compile/runtime size check (EIP-170 limit 24,576
bytes): `PerpEngine` 23,244 (1,332 headroom), `CauldronHook` 23,763 (813),
`CauldronRegistry` 24,493 (83), `PoolOps` 24,174 (402), `RedemptionExt`
13,745, and `QuoteRotator` 8,532. These are current source artifacts; no
deployed-bytecode parity is claimed.

## Authority and boundary

- First-party, owner-authorized defensive review of the local MiFrens repository.
- Baseline commit: `71443f2bac9275b54536046ead962b4a65f557c2` (`main`).
- Review is local and non-destructive. No live-chain transactions, credential access, or third-party targeting.
- Pre-existing worktree changes are excluded from audit-owned commits unless separately reviewed and approved.

## Toolchain

- Node.js: `v24.14.0`
- npm: `11.9.0`
- Foundry/Forge: `1.4.4-nightly`
- No RPC or fork variable names were present in the process environment at baseline. Values were never queried or printed.

## Build and verification results

| Check | Result | Evidence / limitation |
|---|---:|---|
| `FOUNDRY_PROFILE=cauldron forge clean` | PASS | Clean Solidity rebuild baseline. |
| `FOUNDRY_PROFILE=cauldron forge build --sizes` | PASS | Production contracts compile. |
| `FOUNDRY_PROFILE=cauldron forge test --offline --threads 2 -vv` | PARTIAL | 271 suites; 1,025 tests: 713 passed, 36 failed, 276 skipped. Most failures require an unavailable fork; each failure still requires classification. |
| Root `npm test` | PASS | 13/13 tests. |
| Root `npm run type-check` | PASS | No type errors. |
| Root `npm run verify:manifest` | PASS | Sepolia `11155111`, schema `cauldron_r44d`, one pool; no hardcoded-address or environment override detected by the verifier. |
| Root `npm run build` | PASS | Sass and chunk-size warnings only. Generated sitemap date churn was reverted. |
| Indexer `npm run typecheck` | PASS | No type errors. |
| Indexer `npm run codegen` | PASS WITH WARNING | Exit 0; Ponder warned: `Failed to find Response internal state key`. |

The first online Forge test attempt hit a Foundry system-proxy panic. Offline mode produced the stable result above and is the local source of truth until a fork RPC is explicitly supplied.

## EIP-170 production size headroom

| Contract | Runtime bytes | Remaining bytes |
|---|---:|---:|
| `CauldronRegistry` | 24,492 | 84 |
| `PoolOps` | 24,173 | 403 |
| `CauldronHook` | 23,343 | 1,233 |
| `PerpEngine` | 23,243 | 1,333 |
| `MiFrensGenesis` | 21,632 | 2,944 |
| `CauldronFactory` | 20,265 | 4,311 |

Any remediation touching `CauldronRegistry` or `PoolOps` must include a fresh size gate. Registry fixes should prefer an existing facet/library route because 84 bytes is not meaningful implementation headroom.

## Confirmed baseline regression requiring triage

`F2A_LegacyThresholdDecimals.test_F2A_sixDecimalQuoteNeverReachesTheWeiWrittenThreshold` fails without a fork and uses production `CauldronHook`/`LegacyBuyLib` behavior. Its 18-decimal control buys successfully; the 6-decimal quote buffers `9,900,000,000,000` raw units but cannot reach the default `0.02 ether` (`20,000,000,000,000,000`) raw-unit threshold. This is a unit-domain mismatch candidate, not a fork-infrastructure failure.

The finding is not yet assigned final severity. Required next evidence: trace the quote-rotation/configuration lifecycle, prove the affected value/liveness boundary, choose a scale-safe remediation, and add both 6- and 18-decimal regressions.

## Baseline interpretation

- PASS means the command completed and its own assertions passed.
- PARTIAL is not a waiver: fork-dependent failures remain open until reproduced with the pinned chain state or classified from direct evidence.
- Build success is not a security conclusion.
- No claim of “bulletproof” is made; the target is deploy-ready evidence with explicit residual risk.
