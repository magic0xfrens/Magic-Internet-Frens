# Graph validation checkpoint

2026-09-19. **Gate OPEN — do not claim all nodes audited.**

## Current-source inventory

`python3 audit/graph/coverage.py contracts/solidity audit/graph audit/FULL_SCOPE_2026-09-18 --check` returns exit 1, deliberately:

- 66 in-scope source files; 1,038 current declarations.
- 2,305 inventory entries when explicit assembly/delegatecall sites and compiler selectors are included separately.
- 260 declaration annotations stale or absent after source changes.
- Focused source/test/consumer evidence is recorded for a subset; 2,282 entries still need explicit mapping. This is bookkeeping coverage, not a claim that earlier source review or tests did not occur.
- Fresh source-hashed compiler extraction includes renderer-script surfaces. There are 163 surfaces, 3,227 call expressions and zero unresolved compiler references/selectors. Scope issues: zero at extraction.
- Compiler binding resolves structural getter/inheritance identity; it does not establish runtime dependency trust or property coverage.

The current Solidity SHA-256 inventory is `TREE_SHA256_CURRENT.txt`. It does not replace or claim to reconstruct the initial pre-edit baseline.

## Tooling checks

Current rerun: the governance cluster validates **48/48 with 0 failures**, the
renderer/art cluster validates **61/61 with 0 failures** under the `render`
profile, and the seed cluster validates **69/69 with 0 failures**. The pool
cluster validates all 77 nodes but reports 43 stale-citation or
interface-artifact failures; the NFT cluster validates all 167 nodes but reports
305 stale semantic/citation failures, and the hook cluster validates all 146
nodes but reports 597 stale semantic/citation failures. The prior zero-failure table below is historical
and must not be treated as current evidence. The remaining clusters likewise
remain open until their current-source semantic citations are reconciled.

The previous joiner always exited zero and accepted unrelated contracts merely sharing a function name. The hardened tools reject that shortcut; the legacy annotations now expose unresolved aliases rather than being silently accepted. See `GRAPH_TOOLING.md` for exact boundaries and remaining cache/dependency limitations.

The coverage-ledger tests pass 5/5: getter/sensitive-site retention, inherited getter binding without review claims, unclustered-file detection, incomplete-evidence rejection and source-edit invalidation. These test the audit tooling, not smart-contract security.

Root independently ran the combined build-free tooling suite: 14/14 passed (`PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s audit/graph -p 'test_*.py' -v`). A historical hardened semantic join returned exit 1 with **412 unresolved edges, zero malformed edges**; that historical result is saved in `GRAPH_JOIN_CHECKPOINT.txt`, not asserted as a fresh current count. Both in-cluster and other-scope edges are checked.
The current rerun returns exit 1 with **343 unresolved edges and zero malformed
edges** after verified dependency allowlist refreshes. Both in-cluster and
other-scope edges are checked; these remain graph-resolution gaps, not protocol
vulnerabilities.

Do not close this gate until source/semantic freshness, target identity, dependency/cache provenance, exact selectors, independent samples, and the per-node property/evidence gaps have been reconciled. Resolving a written edge also does not prove that no edge was omitted.
