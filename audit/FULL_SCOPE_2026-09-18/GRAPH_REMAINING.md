# Remaining function-graph refresh

Date: 2026-09-18

Scope: `registry`, `pool`, `governance`, `seed`, `art`, and `deploy` only. Contract and test sources were not edited.

## Result

| cluster | nodes | files | edges | nodes with reads | nodes with writes | semantic fields present | validator |
|---|---:|---:|---:|---:|---:|---:|---|
| registry | 89 | 6 | 104 | 56 | 41 | 89/89 | 0 failures |
| pool | 77 | 2 | 110 | 8 | 0 | 77/77 | 0 failures |
| governance | 48 | 2 | 21 | 21 | 8 | 48/48 | 0 failures |
| seed | 69 | 5 | 70 | 25 | 10 | 69/69 | 0 failures |
| art | 61 | 6 | 15 | 14 | 9 | 61/61 | 0 failures |
| deploy | 66 | 14 | 148 | 0 | 0 | 66/66 | validator grammar limitation; details below |

All JSON outputs preserve every skeleton field and skeleton node. The accompanying Markdown files render every node and every semantic field from the canonical JSON, rather than retaining the stale 2026-09-12 prose and line references.

## Refresh method

- Prior semantics were reused only when the contract/name/body-hash tuple still matched the current skeleton and the current source body was confirmed.
- Added or changed declarations were re-read from current source. Mechanical diff totals were:
  - registry: 2 added, 1 changed;
  - pool: 8 added, 2 removed, 5 changed, 8 moved;
  - governance: 11 added, 1 removed, 7 changed;
  - seed: 4 added, 1 removed, 8 changed, 1 moved;
  - art: 61 new nodes;
  - deploy: 66 new nodes.
- Gate, reachability, value, storage, and edge citations were checked against current line numbers. In particular, the art storage map was verified against the `render` profile's real storage layouts for `LiquidatoorRenderer` and `TraitStorage`; immutable reads in `CauldronArtAdapter` and `FrenRenderer` were checked directly in source.
- Renderer selector checks used `FOUNDRY_PROFILE=render`; the cauldron profile intentionally excludes `render/**` and cannot supply those artifacts.

## Validation evidence

The following real validator summaries were produced against isolated cache directories so validation would not depend on stale tracked cache entries:

```text
COVERAGE registry: 89/89 nodes, 0 failures
COVERAGE pool: 77/77 nodes, 0 failures
COVERAGE governance: 48/48 nodes, 0 failures
COVERAGE seed: 69/69 nodes, 0 failures
COVERAGE art: 61/61 nodes, 0 failures
```

For `art`, real method identifiers and storage layouts came from `forge inspect` under the `render` profile. For the other four clusters, current artifacts were inspected under the `cauldron` profile. No test suite was run for this mapping task.

## Current deploy-validator gap

The deploy graph is fully populated (66/66 nodes). The validator now accepts
`.s.sol` filenames, so the remaining failures are current-source citation and
dynamic-target resolution issues rather than the former filename grammar issue.
The current run records 203 failures, primarily calls through script-local
address variables (`registry.set...`, `hook.set...`, `external...`) that cannot
be bound to a compiled contract identity, plus stale line citations in the
changed `DeployLaunchpad.s.sol` source:

| rule | count | mechanical cause |
|---|---:|---|
| R4 | current run | dynamic script-local target aliases are unresolved |
| R2 | current run | changed script line citations and dynamic call aliases |
| R3/R6 | current run | stale gate quotes and profile-specific artifact lookups |

These are explicit open validation failures, not coverage credited as complete.
The next reconciliation requires a target-identity map for script-local
addresses and fresh line citations; deleting edges or inventing aliases would
invalidate the audit evidence.

## Remaining review caveats

- `PoolOps` is a linked library executed in the caller's storage context. Its graph deliberately does not label library-local identifiers as contract storage writes when the validator cannot prove the delegatecall caller layout; the reachable state effects are instead represented through edges and prose.
- Deployment scripts have no persistent protocol storage of their own; their security-relevant behavior is represented by authority, configured-key reachability, value flow, and the 148 outbound wiring/deployment edges.
- A zero validator count proves schema consistency and cited-token presence. It is not, by itself, proof that every semantic interpretation is correct; the graph remains an audit input, not an audit conclusion.
