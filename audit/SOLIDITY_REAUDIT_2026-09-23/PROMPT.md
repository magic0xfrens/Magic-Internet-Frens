# MiFrens / Cauldron owner-authorized security review and remediation brief

> Revision: 2026-09-23. Fresh Solidity audit; previous reports are historical leads.
> Frozen baseline: `31b753546c0e39efb7ae3c28efe9ee4d7fa67df5` plus dependency state
> recorded in `audit/SOLIDITY_REAUDIT_2026-09-23/BASELINE.json`.
> The working tree may contain owner work that is not part of that commit. Record it; do not
> overwrite, stage, move, or commit it without an explicit claim.

## 0. Mission and authorization

Use the installed `solidity-auditor` skill and its applicable references. This
brief is derived from the owner's Desktop audit-r45-sepolia-2026-09-15.md; that
original is unchanged. SCOPE.md defines this pass: complete Solidity review and
its deployment/ABI/call/event consumers, not unrelated application features.
All relative report paths below refer to `audit/SOLIDITY_REAUDIT_2026-09-23/`.
Use snapshot/contracts/solidity for baseline execution, not the moving root tree.
Do not import old findings, fixed labels, graph annotations or coverage claims.

The requester states that they own and built this MiFrens / Cauldron repository and authorize
source review, local security testing, and remediation of its contracts and supporting application.
This authorization covers the supplied project, not third-party systems or other users' assets.
Reproduce vulnerabilities in isolated tests, remediate confirmed defects, and prove the fixes
without weakening intended behavior. Preserve the full adversarial review described below.

### Execution boundaries

- Perform source analysis, function mapping, compilation, fuzzing, invariant testing, and regression
  testing against the identified local review tree.
- Reproduce suspected security failures only on a local EVM or isolated local fork with test accounts and
  simulated balances. A fork is a local simulation, not permission to transact on its source chain.
- Use approved RPC endpoints only for bounded read-only state, bytecode, and log checks or fork
  initialization. Mock outages, hostile callbacks, reorgs, malformed responses, and resource
  exhaustion locally; do not induce them in public infrastructure or production services.
- Do not broadcast transactions, deploy, move real funds, submit governance actions, alter live
  services, probe unrelated targets, or use production signing keys under this audit authorization.
  Any live operation requires a separate explicit scope and approval.
- Keep secrets out of prompts, logs, reports, and test fixtures. Use synthetic credentials and
  redact any accidentally encountered secrets.
- Produce repository-scoped diagnostic reproductions and regression tests, not
  tools for use against live systems. Adversarial actors below are simulated
  test accounts used to evaluate authorization, accounting and recovery properties;
  they do not expand these execution boundaries.

### Continuity and honest status

Work through the authorized scope without unnecessary reconfirmation, subject to actual tool,
permission, resource, and platform limits. This prompt does not override those limits or grant
model/product access. Do not disguise requests or attempt to bypass a restriction.

Do not auto-resubmit, rephrase to evade detection, or self-ping in response to a
platform warning. Identify any specific unavailable action, preserve results,
and continue independent permitted review. Authorization clarifies scope; it is
not a guarantee that a product will execute or display every request.

If a specific action cannot proceed, record the action, reason, evidence already collected, and
the next permitted step in `STATUS.md`. Continue independent permitted work where possible; ask
for direction when progress requires new authority. Never mark blocked or unexecuted work as
passed. A UI notice alone is not evidence that a command ran, completed, or remains active.
Report actual commands, exit status, active job identifiers when available, and deliverable paths.
At a session boundary, save a resumable checkpoint; do not promise unobserved background work.

The scope remains every in-scope function and lifecycle, including perps, liquidation, liquidity
rotation, and new-pair transitions. Fix every confirmed Critical, High, and Medium finding and
retain meaningful regression assertions; document Low and Informational findings without fixing
them unless separately requested. Do not lower severity or omit a property to make the review
appear complete.

The outcome is not a claim that the system is “bulletproof.” The outcome is a reproducible,
commit-pinned body of evidence answering:

1. What can an unprivileged attacker, malicious integrator, compromised role, or failing
   dependency extract, corrupt, censor, strand, or permanently stop?
2. Does every documented lifecycle complete under realistic ordering, denomination, timing,
   gas, callback, reorg, and hostile-token conditions?
3. Do the source, compiled artifacts, deployment scripts, manifests, ABIs, frontend, indexer,
   and deployed bytecode describe the same system?
4. After remediation, which properties were executed and held, and what residual risk remains?

The orchestrator owns correctness. It MUST inspect source, tests, artifacts, and commands itself;
agent summaries are leads, not ground truth. Delegation may improve coverage, but never replaces
independent source review and reproduction.

## 1. Credit discipline and stopping rules

Default to one reviewer and deterministic tooling. Do not launch a swarm. Delegate
only when explicitly authorized and when bounded non-overlapping work saves cost.

- Establish baseline identity and complete mechanical inventory before vulnerability assessment.
  Call-edge/property annotations develop during review; do not create a circular
  requirement that every semantic finding be resolved before review can begin.
- Prefer one agent per non-overlapping subsystem. Resume an agent that already has context rather
  than starting a replacement.
- Give each task a bounded deliverable and command budget. Stop an agent after two consecutive
  reports that add no new executable evidence.
- Mechanical inventory, builds, formatting, selector extraction, and test counting belong to
  scripts, not reasoning agents.
- Read source selectively with `rg` and ranged views, but every in-scope function body must be
  covered by at least one reviewer. Large files are not exempt.
- Full reports go under `audit/SOLIDITY_REAUDIT_2026-09-23/`; agent summaries stay under 15 lines.
- Batch related regressions. Reuse an unchanged, hash-verified compiled snapshot;
  do not clean/recompile repeatedly or rerun passing tests merely for status prose.
- Do not repeat a test solely to generate prose. Record the exact command and result once.
- Parallelize read-only work only when file scopes do not overlap. Serialize fixes to shared
  contracts, storage layouts, manifests, ABIs, and deployment scripts.

## 2. Evidence rules

These rules apply to every phase and every agent.

1. Pin every claim to `path:line` and quote the relevant code before characterizing it.
2. Grep every cited symbol. An invented or stale symbol invalidates the claim.
3. Tag claims `VERIFIED`, `DERIVED`, or `HYPOTHESIS`:
   - `VERIFIED`: executed against the pinned tree and observed.
   - `DERIVED`: established from cited code, but not executed.
   - `HYPOTHESIS`: plausible and still needs a named next step.
4. A confirmed Critical/High/Medium requires a minimal executable PoC or a documented reason an
   executable PoC is impossible. Static-tool output alone is a lead.
5. A passing test proves only its assertions. The top-level `test_*` function may not use
   `return;`, `vm.skip`, catch-and-ignore, or an assertion-free success path. Run with `-vv` and
   show that the intended assertions execute.
6. When using `vm.warp` under `via_ir`, read time with `vm.getBlockTimestamp()` and assert the warp
   landed before depending on it.
7. Comments, NatSpec, test names, old reports, and this prompt are not implementation evidence.
8. Solidity 0.8.x checks ordinary arithmetic. Overflow claims must identify `unchecked`, casts,
   signed edge cases, assembly, or a different mechanism.
9. Deployed bytecode outranks local source for claims about what users can call. Current source
   outranks old audit prose for claims about intended fixes.
10. Never weaken a gate, invariant, slippage bound, event, or existing test to make a fix pass.
11. Execute every feature from a reachable state. Code that looks correct but cannot be entered is
    broken.
12. Quantify attacker input, attacker output, victim loss, value locked, duration, gas, required
    privilege, and repeatability. Price griefing on both sides.
13. Separate mechanism, impact, and remedy. A correct finding can have an unsafe proposed fix.
14. Re-run a result before blaming code when the failure is an RPC 429/5xx, timeout, or fork-data
    inconsistency. Report infrastructure failures separately; never silently discard them.

## 3. Scope: derive it from the tree

The frozen input inventory contains 66 first-party Solidity files and 273
Solidity test/helper files. The tokenizer found 1,093 declaration nodes; this is
not compiler-selector coverage or a security verdict. Reconcile compiler AST,
generated getters, inheritance and assembly before declaring the universe complete.

### In scope

- All first-party Solidity below `contracts/solidity/`, excluding dependency implementation code
  under `lib/` but including every way first-party code calls or assumes those dependencies.
- Constructors, modifiers, receive/fallback handlers, libraries, interfaces, facets/forwarders,
  `delegatecall`, assembly, storage layouts, deploy scripts, renderers, and mocks used by production
  scripts.
- Every unit, functional, invariant, fork, and attack test. Prior PoCs are regression seeds, not
  proof that the current tree is safe.
- Contract-facing portions of `scripts/`, `deployments/`, `indexer/`, `api/`,
  `contracts/abis/`, `src/`, build configuration, environment templates and CI.
  General unrelated UI/product features are outside this Solidity-focused pass.
- Current deployment manifests and on-chain contracts they identify, when RPC access is available.
- Documentation only as a source of promised behavior to compare against code.

### Dependency treatment

Do not re-audit all vendored OpenZeppelin or Uniswap source. Do audit pinned versions, local
submodule state, compiler/EVM compatibility, overrides, unsafe assumptions, callback surfaces,
Permit2/V4 integration, and every boundary where first-party code relies on dependency behavior.

### Out of scope

- Attacks against third-party services or live users.
- Changes to dependency code solely for style or gas.
- Claims based only on old audit IDs. Old reports are opened only after the fresh review for
  reconciliation.

## 4. Workspace safety and reproducibility

Phase 0 begins with read-only inspection.

1. Record branch, `HEAD`, submodule commits, `git status --short`, and a SHA-256 manifest of every
   in-scope file. Save `TREE_BASELINE.md` and `TREE_SHA256.txt`.
2. Distinguish committed baseline files from pre-existing modified/untracked owner work. Do not run
   `git add -A`, `git stash`, reset, checkout-overwrite, clean, or mass-format.
3. If isolation is needed, create a dedicated worktree/branch from the recorded baseline and copy
   only explicitly authorized owner changes. Never silently snapshot unrelated dirty files.
4. Stage exact paths only. Before every commit, print the staged name list and `git diff --cached
   --check`.
5. Do not commit audit fixes directly to `main` and do not push without explicit owner approval.
6. Never print `.env`, private keys, provider secrets, or full signed transactions. Check for leaks
   by key name/pattern and report only the path and redacted context.
7. A submodule with a dirty marker is an independent input. Record its commit and diff summary;
   do not reset it.

## 5. Phase 0 — executable baseline

Create `audit/SOLIDITY_REAUDIT_2026-09-23/BASELINE.md` containing commands, versions, exit codes, elapsed
time, pass/fail/skip counts, and reproducibility notes.

Run, from a cleanly identified tree:

```bash
git status --short
git submodule status
node --version
npm --version
forge --version

cd contracts/solidity
# Run inside the captured snapshot, whose out/cache started empty.
FOUNDRY_PROFILE=cauldron forge build --offline --sizes --threads 1
FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 -vv

cd ../..
npm run test
npm run type-check
npm run build
npm run verify:manifest
npm --prefix indexer run codegen
npm --prefix indexer run typecheck
```

Fork-dependent tests are a separate mandatory lane. Discover the repository's supported RPC env
names without exposing values. Run the fork lane only when a valid endpoint is available, and
report exactly which tests skipped otherwise. A green local suite with skipped fork tests is not a
green full baseline.

Record for every deployable contract: creation size, runtime size, EIP-170 headroom, compiler
version, optimizer settings, `via_ir`, linked libraries, and EVM target. A build that relies on
stale `out/` artifacts is invalid. The isolated baseline starts with empty output
and cache; preserve the completed build and logs. Do not clean the owner's build.
Record profile-excluded first-party contracts and validate them in separate lanes.

Do not label pre-existing failing tests “known” until they are reproduced from the recorded
baseline. Open failures remain findings or coverage gaps.

## 6. Phase 1 — complete function-node and system graph

The graph is part of this audit, not a separate future run. Reuse and improve `audit/graph/`
instead of discarding working tooling.

### 6.1 Mechanical universe

Generate a skeleton from every in-scope first-party Solidity file. It must include:

- contract/interface/library name, file, declaration line, kind (`function`, `constructor`,
  `modifier`, `receive`, `fallback`), canonical signature, selector where applicable, visibility,
  mutability, modifiers, inheritance origin, and body hash;
- all public state-variable getters in compiler method identifiers;
- assembly blocks and `delegatecall` sites as explicit nodes;
- a raw declaration count per file and compiler method-identifier count per deployable contract.

The skeleton and annotated graph must be bijective. No reviewer may invent, delete, rename, or move
a skeleton node. All selectors must match `forge inspect <Contract> methodIdentifiers` or have an
explicit compiler-backed explanation.

### 6.2 Required annotations per node

For every node, record:

```text
authority: caller classes and exact gate location
reachability: realistic roots and state prerequisites
reads: storage, immutable, constant, balances, oracle/environment inputs
writes: storage and balance/custody effects
assets: native/ERC20/ERC721 in/out, denomination, payer, recipient
calls: internal edge, external edge, callback, delegatecall, create/create2
trust: trusted code, configurable dependency, attacker-controlled target
ordering: checks/effects/interactions and rollback assumptions
loops: bound and who can grow it
math: units, decimals, normalization, rounding direction, casts, unchecked
events/errors: emitted/expected and off-chain consumers
liveness: next states and all exits from the current state
tests: exact test/assertion covering the property, or GAP
frontend/indexer/deployer consumers: selector/event/config references
```

Every annotation cites source. Reads/writes must validate against compiler storage layout plus
immutables/constants. Every out-of-cluster edge resolves to another graph node or a named external
allowlist entry. Unknown edges fail validation.

### 6.3 System overlays

Build these from the node graph, not from memory:

1. Authority matrix: role holder, grant/revoke/renounce/rotate path, timelock/multisig assumption,
   emergency power, and dead-end state.
2. Asset-conservation ledger: every custody location and every increment/decrement/transfer for each
   denomination; distinguish accounting counters from actual balances.
3. Lifecycle state machines: summon, launch/seed, trade, death, liquidation, redemption, relaunch,
   quote rotation, migration, governance/treasury execution, gacha, mint/reveal/churn/dividend.
4. Denomination matrix: native and ERC20 quote assets, token decimals, normalized units, thresholds,
   stored meanings, and behavior when the quote changes.
5. Trust/callback map: V4 hook phases, token/NFT callbacks, configurable contracts, oracles,
   routers, Permit2, low-level calls, linked libraries, and delegatecalled facets.
6. Deployment/dataflow map: deploy script -> artifact/library links -> broadcast -> manifest -> ABI
   -> frontend/indexer/API/keeper consumer -> on-chain address.
7. Event map: producer, topic/signature, decoder, indexed fields, reorg/finality behavior, and user
   display/action driven by the event.

### 6.4 Coverage clusters

Cover all first-party files, including at least these domains:

- Hook, fee routing, reserves, royalties, legacy buys, surtax, V4 permission bits and swap deltas.
- Registry/token, forwarders/facets, shared storage, generation adoption and lifecycle.
- Pool, seeding, launch sniper, migration vesting, CREATE2/address derivation.
- Perp engine/vault/swap/mark/staker oracle, solvency, funding, liquidation and PLV waterfall.
- Quote oracle/rotator, redemption, vault, native-quote zap and denomination transitions.
- Genesis/collection/factory/ledger/gacha/mint curve/dividend and supply conservation.
- Governor/treasury, proposal lifecycle, quorum, scans, execution and mandate preservation.
- Art adapters/renderers/trait storage/SSTORE2 and production metadata/render reachability.
- Solidity deployment and operational scripts, library linking, broadcast parsing and wiring order.
- Frontend/API/indexer/keeper/deployer call and event consumers.

### 6.5 Graph validation gate

`audit/graph/validate.py` (or its replacement) must exit zero. Produce a table per file/contract:
declarations, graph nodes, external selectors, resolved edges, unresolved edges, storage references,
nodes with tests, and GAP nodes. Independently re-derive a risk-weighted sample from source. Any
cluster with two semantic mismatches is re-reviewed before using its graph as evidence.

Deliver `FUNCTION_GRAPH.md`, machine-readable graph files, `SYSTEM_MAPS.md`, and
`GRAPH_VALIDATION.md`. Systematic assessment starts after the node inventory is complete.

## 7. Phase 2 — full-scope adversarial review

If delegation is authorized, assign non-overlapping clusters. Each reviewer receives the relevant
validated graph, source paths, and no old conclusions. The orchestrator independently reviews
cross-cluster edges and the highest-value paths.

For every cluster, evaluate both classes of security failure in isolated tests:

- Asset safety: unauthorized value extraction, repeatable accounting imbalances,
  or losses imposed on other simulated participants.
- Availability: permanent or material interruption of a legitimate lifecycle,
  including failure conditions that do not benefit the initiating test account.

### Security property and failure-condition matrix

Apply every relevant category to every reachable node:

- Access control, role escalation, confused deputy, unsafe renounce/rotation, constructor/wiring
  windows, signature replay, chain-id/domain/nonce mistakes.
- Reentrancy: same-function, cross-function, cross-contract, read-only, ERC721 receiver, hostile
  ERC20, V4 callback, delegatecall/shared-storage reentrancy.
- Accounting: reserve floors/ceilings, counter-versus-balance drift, donation, fee splitting,
  rounding accumulation, duplicate credit/claim, stale liabilities, insolvency waterfalls.
- Units: native/ERC20 confusion, decimals 0/6/8/18/extreme, raw versus normalized values, quote
  rotation, threshold reinterpretation, signed/unsigned casts and rounding direction.
- Oracle/price: stale, zero, revert, inversion, manipulation, same-transaction pool state, TWAP
  warm-up/reset/ring behavior, depth assumptions and fail-open/fail-closed behavior.
- V4/MEV: exact-in/out asymmetry, hook delta signs, permission bits, sandwiching, JIT liquidity,
  flash liquidity, swap-internal gas floors and attacker-sized projected prices.
- Perps: funding booking/settlement order, pnl and collateral conservation, liquidation ordering,
  close availability, queue seniority, bad-debt socialization, mark manipulation and quote changes.
- Lifecycle/liveness: partial completion, retry, idempotency, stale flags, stranded envelopes/legs,
  dust dominance, list growth, gas exhaustion, relaunch/rotation/migration totality.
- NFT/gacha/randomness: supply conservation, payment/refund conservation, reroll/grind, miner/caller
  influence, reanchor, callback failures, churn unlocks, reveal/render availability and claim rights.
- Governance/treasury: flash/vote farming, quorum denominator, proposal spam, scan windows, mandate
  erasure, payload gas, execution replay, stale configuration and privileged theft/griefing.
- Deployment/artifacts: CREATE2 squatting, library-address mismatch, stale artifact/broadcast,
  manifest fallback, selector/ABI mismatch, wrong network/chain id, orientation and wiring order.
- Off-chain: RPC 429/5xx/stale/reorg disagreement, indexer crash loops/finality, retry idempotency,
  wrong-address cache, spoofable `minOut`, auth/rate-limit headers, injection, secret leakage,
  malicious API payloads, unsafe shell quoting and key handling.
- EVM/compiler: `unchecked`, assembly, transient/storage assumptions, Cancun compatibility,
  multi-solc dependency builds, viaIR semantic/test quirks, EIP-170 and init-code limits.
- DoS/gas: attacker-growable arrays, bounded scans that starve important entries, revert bombs,
  return-data bombs, storage expansion, conditional work below measured gas floors.

For every public/external function, record either a security property with a local reproduction, a validated
existing assertion, or an explicit coverage gap. “Reviewed” without a property is not coverage.

## 8. PoC and invariant standard

New PoCs go in uniquely named files under `contracts/solidity/test/attacks/` and must:

- start from a reachable fresh deployment or faithful fork state;
- prove the precondition rather than force-writing the target state, unless the forced state is
  explicitly used only to isolate a mechanism;
- show the vulnerable path succeeds and the control path behaves differently;
- assert asset/state deltas for attacker, victim, protocol, and relevant accounting counters;
- fuzz meaningful boundaries and repeated execution when accumulation matters;
- identify whether a fork is required and pin the block when it is;
- contain no silent skip, early-return success, or swallowed revert;
- preserve a minimized regression form after remediation.

Add stateful invariants for asset conservation, supply conservation, solvency, reserve floors,
role safety, and lifecycle totality. Bound handlers realistically but include adversarial ordering.
Use differential/model tests for fee math, quote normalization, funding/PnL, voting/quorum,
mint curves, gacha odds, and rotation accounting.

## 9. Finding schema and severity

```text
id: FS-<cluster>-<nn>
title: one sentence describing attacker capability
severity: Critical | High | Medium | Low | Informational
confidence: VERIFIED | DERIVED | HYPOTHESIS
status: Open | Confirmed | Refuted | Fixed | Accepted
location: path:line with quoted code
graph_nodes: affected node IDs and cross-cluster edges
property: invariant or lifecycle promise violated
preconditions: privilege, capital, timing, state and reachability proof
sequence: numbered calls with caller/value/order
attacker_cost: capital, fees, gas and opportunity cost
impact: value lost/locked, corruption, outage duration and blast radius
repeatability: once | bounded | repeatable | permanent
poc: path, test name, exact command and assertion
counterargument: cheapest attempted refutation and result
root_cause: mechanism, not symptom
recommendation: minimal safe change and compatibility constraints
fix: commit/diff reference
regression: exact test and result
artifact_effect: ABI/selector/event/storage/bytecode/deployment changes
residual: what remains after the fix
```

Severity follows realized impact and reachability:

- Critical: permissionless material loss, protocol-wide insolvency, arbitrary privileged control, or
  permanent protocol-wide lock/brick.
- High: material loss/lock with meaningful capital, timing, partial scope, or privileged access.
- Medium: bounded loss/corruption/outage, or griefing whose cost exceeds damage but violates a
  promised property.
- Low: limited edge-case impact or defense-in-depth defect.
- Informational: maintainability, gas, documentation, or test weakness without a demonstrated
  security impact.

Centralization is described factually; it is not automatically a vulnerability. Gas optimization
must never precede correctness and must include measured before/after gas and bytecode.

## 10. Independent verification and reconciliation

Every Medium+ receives a separate adversarial verification pass. A second model
agreeing is not execution; if the same reviewer performs both passes, disclose
that limitation rather than claim reviewer independence:

1. reproduce from the pinned tree with `-vv`;
2. prove assertions executed and state was reachable;
3. attempt the strongest cheap refutation: missed gate, rollback, wrong units, impossible state,
   uneconomic sequence, stale artifact, or severity mismatch;
4. return `CONFIRMED`, `REFUTED`, or `DOWNGRADED` with one evidence sentence;
5. treat the proposed remedy as a new hypothesis and test for broken routing/lifecycle behavior.

Only after blind verification, reconcile with all prior audit reports and attack tests. Classify
each current result: new, regression/fix-induced, rediscovered-open, confirmed-fixed, previously
refuted, or missed-by-current-pass. A prior “fixed” label is not evidence; re-run its regression.

## 11. Artifact, deployment and on-chain parity

For every address used by a current manifest or production configuration:

1. identify network, chain id, deployment transaction, code hash and contract/library identity;
2. compare deployed runtime length/hash/metadata-normalized bytecode with the source build;
3. verify every selector callable by frontend/indexer/API/keepers exists in deployed bytecode;
4. regenerate ABIs from the pinned source and diff every consumer ABI, including tuple layouts,
   errors and event indexed fields;
5. cross-check broadcasts against manifests without fallback-to-previous-round behavior;
6. verify library links, constructor args, ownership/roles, V4 permission bits, pool orientation,
   quote asset/decimals, oracle/mark arming, generation synchronization and volume links;
7. execute one realistic happy-path transaction per contract-facing feature on
   a local EVM or local fork. No public-testnet or mainnet broadcasts are authorized.

Any source-versus-shipping mismatch blocks deployment until resolved. Deliver
`ARTIFACT_AND_DEPLOYMENT_PARITY.md` with exact evidence and unavailable-RPC gaps.

## 12. Remediation protocol

Fix confirmed Critical, High, and Medium findings. Leave Low and Informational
findings documented and unfixed unless the owner separately requests them.
Before editing, claim exact files/functions in `LEDGER.md`. Shared files are
serialized.

For each fix:

1. capture the failing invariant and observable security impact before editing;
2. identify the root cause and constraints from all incoming/outgoing graph edges;
3. make the smallest change that closes the mechanism without narrowing legitimate routing;
4. invert the PoC into a regression asserting the attack is impossible; never delete it;
5. run targeted tests, neighboring regressions, graph validation, ABI/event/selector checks, size
   checks, then the full applicable suites;
6. update frontend/indexer/deploy scripts in the same logical fix when compatibility changes;
7. stage exact claimed paths and keep behavior-neutral size refactors separate from security fixes;
8. review the changed neighborhood again without assuming the proposed fix is correct.

If EIP-170 is exceeded, do not remove security checks. Measure every refactor. Prefer reducing
duplication, custom errors, safe storage-reference library extraction, or moving coherent large
logic into an already-audited facet with headroom. Revalidate delegatecall storage, gates, events,
ABI consumers and bytecode after any extraction.

## 13. Off-chain resilience and recovery drills

Test, do not merely read:

- depth-1 reorg and removed-log handling;
- two RPCs disagreeing on a block/log hash;
- 429, 5xx, timeout, stale tip and delayed receipt;
- indexer restart/backoff/freshness/alert behavior and crash-loop recovery;
- keeper/deployer idempotency after a reorged-out or ambiguously submitted transaction;
- frontend degraded mode when indexer or one RPC is unavailable;
- manifest/ABI cache invalidation after a deployment;
- API input limits, authorization, injection resistance and redacted errors;
- build output and repository history checks for secrets.

Deliver `OFFCHAIN_RESILIENCE.md` and a tested operator runbook. Clearly distinguish “behind,”
“provider inconsistent,” “indexer dead,” and “deployment mismatch.”

## 14. Final validation gate

Run from source-matched artifacts and report all exits, failures and skips.
The initial build must be clean-input; subsequent batches may reuse unchanged
artifacts after checking source and dependency hashes:

- graph validators and unresolved-edge join;
- targeted PoCs/regressions and all stateful invariants;
- full local Foundry suite and separately the pinned fork suite;
- contract sizes, storage layouts, selectors and ABI parity;
- frontend unit tests, type-check, production build, manifest verification and E2E where feasible;
- indexer codegen/type-check and resilience drills;
- deploy rehearsal on a local fork using production scripts and generated manifests;
- secret scan with redacted reporting;
- `git diff --check`, staged-path review, and a final tree hash.

No result may be described as fully green while skips, unavailable fork tests, unresolved graph
edges, mismatched deployed code, or open Medium+ findings remain.

## 15. Deliverables

Under `audit/SOLIDITY_REAUDIT_2026-09-23/` produce:

- `BASELINE.md`, `TREE_BASELINE.md`, `TREE_SHA256.txt`
- `FUNCTION_GRAPH.md`, machine-readable graph outputs, `GRAPH_VALIDATION.md`
- `SYSTEM_MAPS.md` containing authority, asset, lifecycle, denomination, trust, deployment and event
  overlays
- subsystem security-review reports and executable local reproductions
- `FINDINGS.md` and `VERIFICATION.md`
- `ARTIFACT_AND_DEPLOYMENT_PARITY.md`
- `OFFCHAIN_RESILIENCE.md`
- `LEDGER.md` with claims, commits, ABI/event/storage changes and bytecode headroom
- `FINAL_REPORT.md`

`FINAL_REPORT.md` must lead with a deploy/no-deploy verdict and list:

1. exact commit/tree/submodule scope and limitations;
2. risk counts by verified severity/status;
3. value and authority model;
4. findings with PoCs, fixes and regressions;
5. attacks attempted that held;
6. function/property coverage and every explicit gap;
7. source/artifact/manifest/on-chain parity;
8. off-chain resilience and recovery readiness;
9. test/build/skip/size results before and after;
10. residual risk, accepted assumptions, unavailable evidence and concrete launch blockers.

Final question: **Would you deploy this exact tree and artifact set today? If not, name the minimum
evidence or fixes still required.**

## 16. Definition of done

- The mechanical function universe covers every first-party declaration and compiler-visible
  selector; validation has zero unresolved in-repo edges.
- Every public/external node has a tested security property, a meaningful executed assertion, or a named
  gap.
- Every custody counter and asset transition appears in the conservation ledger.
- Every lifecycle has success, retry, cancellation/failure and terminal-state analysis.
- Every confirmed Medium+ is fixed and verified with a passing regression.
  An accepted unresolved finding remains explicit and does not satisfy the
  owner's fix-all-Medium+ requirement unless the owner changes that requirement.
- All fix-induced ABI, selector, event, storage, bytecode, manifest and consumer changes match.
- Fresh local and fork suites report pass/fail/skip counts; unavailable infrastructure is explicit.
- Every deployable contract fits chain limits with measured headroom.
- A production-script deployment rehearsal creates a manifest whose addresses, wiring, ABIs and
  selectors verify against the deployed bytecode.
- No open ledger claims, no hidden skipped tests, no weakened assertions, no secrets in output, and
  no unapproved changes pushed.
