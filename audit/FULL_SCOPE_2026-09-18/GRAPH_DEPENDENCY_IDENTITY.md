# Dependency identity validation correction — 2026-09-21

The old resolver required an allowlisted dependency type but looked up its
method in a GLOBAL name set. Therefore `TickMath.safeTransfer` could resolve
because SafeTransferLib declares `safeTransfer`. The scope annotation did not
remedy this mismatch. This was false-positive audit tooling, not a Solidity
runtime vulnerability.

Both `audit/graph/join.py` and `validate.py` now require dependency methods keyed
by the named contract. Legacy flat `cache/libfns.json` is ignored for resolution,
not automatically upgraded by guessing ownership. The validator no longer
generates a global method-name list with recursive grep. Malformed string-valued
method collections are rejected instead of performing substring membership.

Validation: `python3 -m unittest discover -s audit/graph -p 'test_*.py'`
passed **15/15**. New regression tests reject wrong dependency ownership, the
legacy flat set and malformed mapping values while accepting the explicit
correct type/method pair. `git diff --check` passed.

Current join execution returned **exit 1, 537 unresolved, 0 malformed edges**.
This supersedes the earlier 343 count. The increase is expected: previously
accepted dependency edges lacked identity proof. Per-cluster unresolved counts:
hook 22, registry 8, pool 40, perp 173, rotation 67, governance 2, nft 22,
seed 57, art 8, deploy 138.

This is conservative hardening, not completed graph reconciliation. No fresh
compiler-derived dependency map was fabricated. Remaining issues include
unqualified names, overloaded signatures, cache provenance, arbitrary low-level
method-name recognition, stale source citations, and instance alias resolution.
Existing node/getter resolution is unchanged and still requires those checks.
Historical cluster validator zero-failure claims do not establish current
success under these stricter dependency rules; they must be rerun/reconciled.

## Low-level-name shortcut removed

Follow-up: neither validator now accepts an arbitrary target solely because its
method is named `call`, `delegatecall`, `staticcall`, `transfer`, or `send`.
The source-file existence check no longer exempts those names either. A
declared `Token.transfer` still resolves normally to its exact graph node.
Regression suite now passes **16/16**. Join returns **exit 1, 632 unresolved,
zero malformed**, superseding 537. Counts are hook 53, registry 18, pool 46,
perp 185, rotation 75, governance 7, nft 32, seed 67, art 8, deploy 141.

Real address operations remain unresolved in this prose join until compiler
receiver/type evidence is connected; they are not asserted invalid Solidity.
This prevents untyped target text from masquerading as successful resolution.
The compiler graph remains available for that next reconciliation step.

## Receiver evidence added to compiler graph

`compiler_graph.mjs` now emits memberName and receiver text, Solidity type and
referenced declaration for each member call, including calls with gas/value
options. Regeneration succeeded with Solidity 0.8.30 and 0.8.26: 1,038
declarations, 3,230 call expressions, 14 sensitive sites, 163 surfaces, zero
unresolved compiler references/selectors. All recorded first-party SHA-256
source hashes were checked against the current files: zero stale sources.

There are 1,533 member calls. Among call/staticcall/delegatecall/transfer/send
names, 90 receivers are compiler-typed address/address payable and 14 have
other types. This directly demonstrates why method-name-only classification
was insufficient. Example: CauldronHook `o.call` has address receiver `o` tied
to declaration `0.8.30:824`; that is distinct from resolving the dynamic call's
runtime destination or selector, which remains a separate audit obligation.

`node --check` and `git diff --check` passed. No prose edges were newly credited
by this data addition. Exact source/caller/expression matching and artifact
freshness must gate the future join; do not infer resolution from aggregate
counts. Source may evolve independently; use this regenerated inventory rather
than assuming the older 3,227-call total is current.

## Exact compiler address-operation join

Added `compiler_edges.py` and optional compiler/source arguments to `join.py`.
Recognition requires current file SHA-256, exact caller contract/signature,
expression, source line and byte span, compiler address receiver type, no static
target declaration, and exactly one candidate. Stale files, wrong callers,
wrong types, forged text and ambiguous matches are rejected by regression tests.
Tooling suite: **17/17 passed**.

Command:
`python3 audit/graph/join.py audit/graph audit/FULL_SCOPE_2026-09-18/COMPILER_GRAPH.json contracts/solidity`

Result: exit 1, **566 unresolved, zero malformed**, and **66 typed address
operations** shown in a SEPARATE column marked runtime target unverified.
These 66 replace untyped prose gaps, not security/property acceptance. Without
the optional compiler evidence the conservative unresolved count remains 632.
This matcher does not establish runtime destination, selector, authority, return
handling or call safety, and does not change the property coverage gate.

## Source-pinned declaration matching

The exact-call matcher now also recognizes compiler-referenced
function/getter declarations, requiring both caller and target source hashes
to match current files. It uses compiler declaration IDs rather than a global
method name. Interface targets are labeled **implementation unverified** in a
separate column; no runtime wiring or overload guess is substituted for them.
Dependency files outside the source-hashed inventory remain uncredited.

Correction: the inventory hashes ALL compiler source inputs, including imports
(223 files), not only the 66 first-party scope files. The 106 newly classified
declarations therefore include dependencies. Across all edges with an exact
compiler declaration match (including edges already counted by the legacy
resolver), 52 point into `lib/` and 105 point outside it; these totals must not
be added to the 106 newly classified count. Examples include exact TickMath and
FullMath targets in the nested V4 dependency tree.

Freshness now requires the entire compiler source snapshot to match disk, not
merely the caller and directly named target. A changed inherited/interface
dependency can alter resolution without editing caller text. The existing
regression test now mutates an otherwise unreferenced import and confirms that
all compiler matches fail closed. The suite still passes 18/18; no production
Solidity changes. Legacy name/getter fallback is not made source-pinned by this
change and remains an explicit limitation.

Tests pass **18/18**, including target-source invalidation. The same explicit
compiler-backed join now returns exit 1 with **460 unresolved, zero malformed**,
**106 compiler declaration matches** and the existing **66 typed address
operations**. No property-coverage credit or production safety conclusion
follows from these structural matches. Static legacy node/getter matches still
need provenance and source-location reconciliation.

## Strict compiler mode replaces legacy fallback

Explicit compiler mode now requires exact compiler evidence for EVERY edge;
it no longer falls back to legacy node/getter name caches. Bare internal source
calls (`run()`) can match prose `Contract.run` only when the compiler identifies
that exact declaring contract and method. Wrong-contract matches are rejected.

Regression suite passes **20/20**, including a join whose valid-looking named
target has no compiler/source evidence and therefore must fail. Current strict
join returns **exit 1, 1,092 unresolved, zero malformed**, with **565 pinned
declarations and 66 typed address operations**, totaling 1,723 prose edges.
The older 460 count used mixed compiler/name-only evidence and is superseded
for audit acceptance. This increase exposes stale/incomplete evidence rather
than establishing 1,092 Solidity vulnerabilities. Runtime implementation and
economic-property review remain separate from all structural classifications.

## Five perp view nodes reconciled against source and AST

Inspected `_quoteIsNative`, `totalEth`, `freeEth`, `totalTokenAssets`, and
`freeToken` directly in current PerpEngine source. Compiler edges confirm zero
calls in each. Removed ten fabricated declaration/`returns` edges from
`perp.json`, updated the Markdown counts, and corrected `_quoteIsNative` from
a supposed quote write to a read: `==` is comparison, not assignment. The four
asset views return the documented counters (two checked sums, two direct
returns); they neither transfer value nor call other functions.

This is source/semantic reconciliation of five nodes, not a new economic test
or global coverage closure. Other nodes may share the extraction defect and
remain subject to source-backed review; none were auto-whitelisted or deleted
based solely on their names.
