# Graph Tooling Hardening

## Outcome

The graph validator and cross-cluster joiner now fail closed for the cases covered by this review. Dotted Solidity script names such as `DeployLaunchpad.s.sol` are accepted in citations, and an edge no longer resolves merely because the same method name exists on some other first-party contract or somewhere under `lib/`.

`join.py` now resolves edges in every declared scope and returns a nonzero status for a missing cluster graph, invalid graph JSON, malformed edge, or unresolved edge. Previously, an `in-cluster` label bypassed target resolution entirely. The report's scope columns count labels, while both resolution columns count successful resolutions across all scopes. This makes it suitable for a CI gate instead of a report that always succeeds.

## Resolution rules

First-party calls require an exact `(contract, method)` match against graph skeleton nodes. The following intentional exceptions remain:

- low-level EVM call forms (`call`, `delegatecall`, `staticcall`, `transfer`, and `send`); this syntactic exception is not proof that a `transfer` target implements ERC-20 or has any particular asset semantics;
- compiler method-identifier entries keyed to the exact named contract, principally public state-variable getters that do not have skeleton function nodes;
- dependency functions found in `cache/libfns.json` only when the callee is an allowlisted dependency type. A `library` scope label alone is not treated as proof of identity.

These exceptions do not permit an arbitrary contract token to borrow a method name from another contract.

## Verification

The build-free regression suite covers:

- `.s.sol` filename parsing in prose, gate, and edge citations;
- acceptance of exact first-party targets;
- rejection of a wrong contract whose method name happens to exist on another contract;
- preservation of exact compiler-getter and explicit dependency resolution;
- nonzero join status for missing graphs, malformed edges, and unresolved wrong-contract edges;
- rejection of a bogus `in-cluster` target even when its method name exists on a different contract;
- rejection of `__error__` data in a failed compiler cache as a synthetic getter;
- zero join status for a complete minimal exact graph.

Run from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest audit/graph/test_validation.py
```

No Forge build or cache regeneration was performed for this tooling change.

Running the hardened joiner against the current inventory returns status `1`
with **343 unresolved edges and zero malformed edges**. The dependency
allowlist now includes the current PoolId/LiquidityAmounts, renderer, and
OpenZeppelin library targets; the remaining failures are primarily instance
aliases such as `registry`, `hook`, and `external`, plus stale `returns` prose
artifacts. This is not a reason to restore global-name matching. The inventory
must be normalized or a source-backed alias resolver added before this check
can become a passing repository-wide gate.

## Cache assessment and remaining limitations

- Existing `*.methodIdentifiers.json` cache files are keyed by contract name, not source path or source hash. They carry no compiler/profile/source freshness metadata. A duplicate contract name can collide, and a stale entry can make an obsolete exact method appear resolvable. The tooling preserves getter resolution for compatibility, but these caches should eventually use a path-qualified key plus source/compiler/settings fingerprint and be regenerated in a serialized build step.
- `cache/libfns.json` also has no source fingerprint and contains a method-global set rather than a `(dependency type, method)` map. For allowlisted dependency types, a method may therefore be accepted because it exists on a different dependency. The name allowlist reduces but does not eliminate this false-positive and stale-cache risk; a future cache format should key methods by declaring dependency type.
- Contract resolution is intentionally nominal. Edges written with an instance-variable alias instead of the declared contract/interface type will remain unresolved; the tool does not attempt unsafe global-name inference. Graph authors should name the declared target type or tooling should later add source-backed variable-type inference.
- The validator's contract-method index trusts the mechanically extracted skeletons. Missing or stale skeleton nodes can therefore produce false negatives; skeleton freshness is outside these scripts' current proof.
- Filename citations use basenames. Duplicate basenames remain potentially ambiguous because the validator's source index selects one path, with files in the current cluster taking precedence.
- Regex parsing does not provide an AST-level proof that a cited token is the actual call target, nor does it validate dynamic dispatch, inherited-method resolution, fallback/receive routing, or delegatecall implementation identity.
