# Scope and Tree Baseline

## Counted first-party surfaces

| Surface | Count | Notes |
|---|---:|---|
| Solidity contracts, libraries, renderers, and deploy scripts | 66 | Every file is assigned to one graph cluster. Vendored `lib/` code is dependency context, not first-party implementation. |
| Solidity test files | 241 | Includes 164 adversarial/attack tests. |
| Frontend TypeScript/TSX files | 115 | UI, hooks, configuration, transaction construction, and display logic. |
| Indexer source TypeScript files | 3 | Event ingestion and derived-state assumptions. |
| API TypeScript/JavaScript files | 7 | Request validation, serialization, and trust-boundary checks. |

## Function-graph clusters

The graph scope is defined by `audit/graph/clusters.json` and covers all 66 unique first-party Solidity/deploy files exactly once.

| Cluster | Current skeleton nodes |
|---|---:|
| hook | 146 |
| registry | 89 |
| pool | 77 |
| perp | 216 |
| rotation | 93 |
| governance | 48 |
| nft | 167 |
| seed | 69 |
| art | 61 |
| deploy | 66 |
| **Total** | **1,032** |

The prior graph represented 801 nodes and was materially stale. Semantic review proceeds only after refreshed cluster files match the current skeleton and validator.

## Required node annotations

Each graph node must capture, where applicable: caller/privilege, payable/value behavior, state reads and writes, external calls and return handling, assets and unit domains, rounding direction, loop or gas bounds, event/indexer dependencies, lifecycle entry/exit paths, and directly relevant tests/assertions.

## Excluded/generated context

- `contracts/solidity/lib/**` is vendored dependency code. It remains in call-chain context but is not counted as first-party source.
- Build outputs and dependency caches are evidence inputs, not source-of-truth implementation.
- The dirty OpenZeppelin submodule and other pre-existing worktree changes are owner work and are not silently normalized or included.
