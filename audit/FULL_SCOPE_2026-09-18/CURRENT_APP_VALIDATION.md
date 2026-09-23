# Application validation — 2026-09-21 continuation

Observed HEAD: `83ef97bdf3da3ed8520b1eb6f7e3b50a46b4735c`, dirty shared tree.
These commands verify their selected local lanes, not all application behavior.

| Command | Result | Evidence |
|---|---|---|
| `npm run test` | exit 0 | Session 16319: 19 quote/rotation helpers + 2 API + 7 indexer + 5 swap-gas tests; 33 pass, no reported skips |
| `npm run type-check` | exit 0 | Session 19049: application TypeScript check |
| `npm run verify:manifest` | exit 0 | Local chain 11155111, schema cauldron_r44d, one pool; configuration and hardcoded-address checks |
| `npm --prefix indexer run codegen && npm --prefix indexer run typecheck` | exit 0 | Session 68792: generated ponder-env.d.ts, then TypeScript check |
| `npm run build-only` | exit 0 | Session 45623: Vite transformed 6,999 modules and built in 14.48s |

Warnings retained: codegen printed `Failed to find Response internal state key`
before reporting successful shutdown; Vite reported Sass deprecations, removed
misplaced dependency PURE annotations and warned about chunks above 500 kB.
No remediation of these Low/Informational observations was attempted.

`build-only` deliberately omits the package's pre/postbuild lifecycle. Manifest
validation was executed separately. LLM document synchronization and SEO
prerender acceptance are NOT established. In particular, postbuild writes
`public/sitemap.xml`, which already has owner edits; those were preserved.
No claim of successful Cypress/browser, live API/indexer, RPC, deployed-code,
wallet-signing or complete frontend function coverage follows from these runs.

Indexer codegen left no tracked diff in ponder-env.d.ts. `git diff --check`
passed after the commands. Solidity traversal validation remains a separate
running session (25490); application success does not close its finding.
