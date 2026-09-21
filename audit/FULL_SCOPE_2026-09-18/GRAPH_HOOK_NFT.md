# Hook and NFT graph refresh

Date: 2026-09-18

Scope was limited to `audit/graph/hook.{json,md}`, `audit/graph/nft.{json,md}`, and this report. No Solidity, test, deployment, cache, skeleton, tooling, or other cluster file was edited.

## Coverage

| cluster | old nodes | current skeleton | hash-confirmed reuse | re-read/annotated | validator |
|---|---:|---:|---:|---:|---|
| hook | 134 | 146 | 119 | 27 | 146/146, 0 failures |
| nft | 155 | 167 | 145 | 22 | 167/167, 0 failures |

Reuse required the same canonical contract/name/signature key and identical `body_sha1`. The graph was rebuilt from the current skeleton so removed declarations disappeared and every skeleton-owned field stayed byte-for-byte equal to the skeleton. Line-only movement was translated against the old pinned source, then every validator-rejected citation was re-read and corrected.

Newly covered files and surfaces include:

- `cauldron/SurtaxLib.sol`: policy wrapper and built-in block-decay/jitter curve.
- `cauldron/GachaLib.sol`: one-time re-anchor namespace, pinned seed namespace, bounded pin sweep, ticket resolution, mint-failure handling, and delegatecalled storage references.
- Hook pre/post-trade liquidation projection and gas interlock, symmetric volume sibling linking, absolute-hour volume expiry, extracted ticket resolution, ERC20 royalty sweep/adoption, and legacy-buy reference storage.
- NFT dead-end entitlement rejection, royalty balance adoption/accounting, final churn output floor, genesis cap correction, mutable placeholder URI, and genesis-only governance units.

## Validation

The repository's checked-in `audit/graph/cache/` predates these source changes, so validation was run against a fresh temporary compiler cache without changing the shared cache:

```text
python3 audit/graph/validate.py contracts/solidity /tmp/mifrens-graph-validation-20260918-a hook
COVERAGE hook: 146/146 nodes, 0 failures

python3 audit/graph/validate.py contracts/solidity /tmp/mifrens-graph-validation-20260918-a nft
COVERAGE nft: 167/167 nodes, 0 failures
```

The Markdown inventories are generated directly from the validated JSON and enumerate all nodes with declaration, body hash, authority, exact gate, reads, writes, value movement, edges, reachability, and observations.

## Unresolved review flags

These are graph observations or design/coverage flags, not newly confirmed severity findings:

1. `CauldronHook.linkVolume` has no unlink path. Distinct quote rotations permanently consume each pool's nine-sibling capacity; a later distinct link can make rotation fail.
2. The low-gas liquidation gate treats a reverting or malformed `openCount` response as an empty book. Correct deployment/wiring of the engine remains part of the safety boundary.
3. `SurtaxLib`'s current-block rate is observable before a transaction executes. The deterministic decay is the enforceable floor; the jitter is not an ungameable randomness guarantee.
4. `MiFrensDividend.fundToken` books the requested amount, not the measured balance delta. A fee-on-transfer or negatively rebasing basket asset can undercollateralize later claims.
5. Ticket seeds become deadline-independent only after some call pins the original blockhash. A completely untouched batch receives one re-anchor and is forfeited on a second expiry; this is an anti-reroll tradeoff with a liveness/UX cost on very fast chains.
6. Both NFT rarity reveal paths allow one re-anchor and commit the base tier on the second expiry. They are holder-only despite comments mentioning keepers.
7. `playChurn` now exposes `minTokenOut`, but callers may explicitly pass zero and accept no final-token slippage floor.
8. Transfer validators remain configurable external dependencies that can block mint, transfer, burn, and custody paths if they revert.
9. The checked-in compiler metadata under `audit/graph/cache/` is stale. A later graph-wide tooling pass should regenerate it; this refresh intentionally did not touch shared tooling/cache files.

No Solidity test suite was run for this bounded graph-only task.
