# Fresh Solidity audit — 2026-09-23

## Objective

Audit a frozen snapshot using solidity-auditor. Review every first-party
Solidity function and cross-contract lifecycle, reproduce current defects,
fix confirmed Critical/High/Medium findings, and independently verify fixes.
Document Low/Informational findings without implementing optional changes.
No push, deployment, production transaction, or secret disclosure is authorized.

Earlier audits and swarm findings are historical leads, not current verdicts.
Do not carry forward their FIXED labels, coverage percentages, or test counts.

## Scope and priority

All first-party Solidity, including libraries, interfaces, constructors,
modifiers, receive/fallback, assembly, renderers, deployment scripts and mocks
used by deployment. Audit first-party dependency interactions and any local
dependency modifications; do not imply a fresh audit of all vendored code.
Tests are evidence inputs, not production function coverage by themselves.

Prioritize perp solvency, funding/fees, partial closes, liquidation completeness
and gas, vault withdrawals/queues, liquidity rotation, denomination changes,
oracle behavior, governance, and successor-generation transitions. Review the
remaining token, NFT, dividend, mint, seeding and rendering functions too.
Configuration, ABI and deployment consumers are included where they affect
these contracts. General unrelated frontend feature review is not this pass.

## Gates and deliverables

1. BASELINE.json pins HEAD, source hashes, submodule commits and current dirty
   state; snapshot/ contains isolated inputs without old compiler artifacts.
2. Build once per required profile into that snapshot; save exact commands,
   exits, versions, skips, failures, runtime sizes and explicit compiler gaps.
3. Generate fresh declaration/call inventory from snapshot sources. Every node
   starts unreviewed. Track body review, authority, assets, callbacks, invariants,
   executed assertions and consumer dependencies separately.
4. Review current implementation before reconciling old findings. Confirmed
   severity requires a reachable local reproduction or documented limitation.
5. Batch fixes and regression execution. Preserve owner changes and original
   acceptance properties. Source drift invalidates affected evidence.
6. Produce FINDINGS.md, COVERAGE.md, VALIDATION.md and FINAL_REPORT.md with
   source identities, remaining gaps and old-finding reconciliation. No claim
   of completion until all required work is actually verified.

Use local EVM simulations. Fork results require an authorized, available read-only
endpoint and separate reporting; unavailable forks never count as passed.
Generic skill examples are prompts for review, not proof of a defect or a reason
to change protocol design. Measure gas/storage claims against actual artifacts.
