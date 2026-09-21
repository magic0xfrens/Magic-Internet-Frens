# Indexer lifecycle and recovery review

Date: 2026-09-18  
Scope: `indexer/ponder.config.ts`; `registerPool`, summon/reborn handlers, `ensurePool`, PoolManager swap handler, rotation handlers, and position-transfer handlers in `indexer/src/index.ts`; installed Ponder 0.11.44 indexing client, realtime reorg reconciliation, and database revert implementation; installed viem fallback transport. No service, network, build, or provider was run.

## Result

One executable source-level lifecycle defect was confirmed: pools opened by treasury rotation are rejected by discovery and their swaps are not indexed. Ordinary Ponder reorg rollback is present for database and framework factory state, but application module state and multi-provider consistency have named recovery gaps below. No claim is made about a live provider disagreement or deployed `STRICT_POOL_FILTER` setting.

## IDX-01 — Rotation destination pools were permanently rejected by discovery (Medium, remediated)

**Evidence and reachable path.** A rotation opens/adds the destination quote/token pair, derives its distinct pool id, links that id into generation volume, and records it as a treasury leg (`RedemptionExt.sol:508-560`). It deliberately does not replace the singular launch `generationPoolId`; even after denomination changes, `generationPoolKey`/the launch pair remain distinct (`RedemptionExt.sol:605-632`).

The indexer has only two pool registration paths:

1. `CauldronSummoned` and `CauldronReborn` call `registerPool` with the launch/relaunch event's pool id (`indexer/src/index.ts:49-101`). Rotation events only insert a `rotationSlice`; they do not register a pool (`indexer/src/index.ts:911-928`).
2. A swap for an unknown pool calls `ensurePool`, which accepts the id only when it equals `generationPoolId[currentGeneration]`. Every other id is added to `foreignPools` and rejected (`indexer/src/index.ts:315-355`).

Therefore the first swap on a newly opened rotation destination pool has no database row, fails the singular-primary comparison, is cached as foreign, and returns before swap/candle insertion (`indexer/src/index.ts:358-405`). Subsequent swaps return at the negative-cache check. This is independent of log order or end-of-block call pinning: the registry's primary id intentionally remains the launch id.

**Impact/severity.** The official index omits trading history, candles, volume, and quote metadata for every non-launch rotation leg, including the pool holding the newly adopted denomination after a completed migration. The old launch pool remains the only generation pool row. This is Medium off-chain data integrity/availability because downstream UI/API consumers can present the wrong active market or no market data after a core lifecycle action. It does not alter on-chain custody or execution.

**Required remediation.** Discover every on-chain generation pool, not only `generationPoolId`. The implemented ABI-compatible path consumes the authenticated `RotationExec:LegOpened(gen, quote, positionId)` event, reads the immutable registry `generationToken(gen)` and launch `generationPoolKey(gen)`, validates the token against the launch key, and derives the destination PoolKey from the event quote plus the launch key's fee, tick spacing, and hook. Those are the exact parameters `RedemptionExt` passes to `PoolOps.openOrAddPair`. It does not infer ownership from an arbitrary PoolManager swap.

**Exact regression.** Process summon for primary pool A, then a successful rotation that opens pool B without changing `generationPoolId`, then a PoolManager swap for B. Assert B is registered with the destination quote and correct decimals, its swap/candle rows exist, A remains historical, and an unrelated pool C is still rejected. Repeat after `GenerationRequoted` and after a later `CauldronReborn` to ensure B history remains attributed to its original generation while the new generation's primary is discovered.

**Executable pre/post evidence.** The isolated test imports the actual `indexer/src/index.ts` and captures its real registered handlers through mocked Ponder registry/schema/client/database boundaries. The initial pre-fix failed at `missing registered handler RotationExec:LegOpened`. A first remedy read the event's PositionManager NFT at the event block, but `PositionManager._burn` clears `positionInfo[tokenId]`; an NFT opened and replaced later in the same block is therefore already empty at Ponder's end-of-block read. The strengthened pre-fix suite was 2 failed / 2 passed: the cleared first position caused a quote/key mismatch, and a transient `currentGeneration` error was swallowed as a successful no-op. The corrected handler uses only authenticated event data and persistent registry generation state, derives the v4 PoolId, and records immutable quote/decimal identity. `ensurePool` now returns `null` only for a verified foreign id; identity-critical RPC failures reject the handler so Ponder can retry it.

## Recovery behavior verified from installed framework source

- Handler `readContract` calls are pinned to the event block number by Ponder's installed indexing client (`node_modules/ponder/src/indexing/client.ts:545-554`), supporting the same-block summon/rebirth lookup assumption in `ensurePool`.
- Ponder realtime reconciliation walks to a common ancestor, reports reorged blocks, and removes factory child addresses learned in those blocks (`node_modules/ponder/src/sync-realtime/index.ts:715-791`). Reorgs beyond its finalized boundary throw as unrecoverable (`:741-753`).
- Ponder records inverse database operations and reverts inserts/updates/deletes after the ancestor checkpoint (`node_modules/ponder/src/database/index.ts:1091-1177`). Thus ordinary database writes in these handlers are framework-revertible; transaction-hash ids and conflict handlers are not the sole reorg defense.
- Viem `fallback(..., {rank:false})` preserves provider order, but fallback selection is made independently for every RPC request: provider zero is tried, and on a qualifying error that request is retried against the next transport (`node_modules/viem/_cjs/clients/transports/fallback.js:10-88`). It is ordered failover, not request-session pinning or consensus.

## Named gaps / unproven risks

### GAP-01 — `foreignPools` is not reorg-transactional

The process-global `foreignPools` Set was outside Ponder rollback. It has been removed: an unknown swap is revalidated rather than becoming process-lifetime state. The regression makes the first event-block registry read fail transiently and asserts the actual handler rejects (rather than committing a successful no-op), then proves a replay registers/indexes the primary pool; it separately proves an unrelated pool is rejected.

This trades an RPC read on each unknown pool swap for reorg safety. If negative caching becomes operationally necessary, it should be database-backed/reorg-aware or bounded by block/expiry rather than permanent module memory.

### GAP-02 — Ordered fallback does not guarantee one provider's view for a sync

The config commentary says secondary providers are only failover, which is true per request, but concludes that two providers cannot answer the same height in one sync (`ponder.config.ts:75-109,144-151`). Installed viem provides no such session affinity: separate log, block, and `eth_call` requests can be answered by different providers when the primary fails selectively. Ponder validates block ancestry and rolls back ordinary forks, but an event-pinned `eth_call` is identified by block number here, not block hash (`indexing/client.ts:396-408,545-554`); the reviewed code has no quorum or response-hash check around registry discovery. No live disagreement was induced, so operational severity is unconfirmed.

**Regression needed:** deterministic mock transports where the primary succeeds for logs/block but fails an event-block registry call and the fallback returns sibling-fork state. Assert startup either fails explicitly or retries canonical state without populating `foreignPools`.

### GAP-03 — Strict mode deliberately loses automatic relaunch discovery

When `STRICT_POOL_FILTER=true`, PoolManager logs are filtered to manifest `round.poolIds` (`ponder.config.ts:185-212`). A future relaunch pool cannot be observed until the manifest/container is updated. This is source-certain conditional behavior, but the deployed environment value was not inspected, so it is not classified as a live finding. Add a configuration-startup assertion or deployment test that forbids strict mode for autonomous lifecycle deployments unless the manifest update is part of the relaunch procedure.

### GAP-04 — Deep reorg/provider recovery is operational, not automatic

Installed Ponder throws when it cannot reconcile before the finalized boundary. The repository provides provider ordering and comments describing manual redeployment, but no reviewed health check, automatic provider quarantine, canonical checkpoint comparison, or tested rebuild procedure. No deep-reorg service test was run. Document and rehearse the exact database/checkpoint recovery procedure; alert on fatal sync and block-hash disagreement rather than allowing APIs to serve stale readiness indefinitely.

## Functions and paths covered

- Full `ponder.config.ts` chain/RPC construction, PoolManager subscription, registry/rotation/position subscriptions, and collection factory configuration.
- `registerPool`, `CauldronSummoned`, `CauldronReborn`, `ensurePool`, complete PoolManager `Swap`, complete treasury proposal/vote/execute/cancel/slice handlers, and position in/out handlers.
- Downstream `/cauldron`, `/candles/:generation`, and `/recent/:generation` market selection, selected-pool volume scope, launch-primary death identity, and the shared selector regression boundary.
- On-chain destination-pool creation/recording and denomination-flip lines necessary to establish that `generationPoolId` remains singular.
- Installed Ponder event-block client pinning, realtime common-ancestor/factory rollback, database operation reversal, and installed viem ordered fallback.

Not covered: unrelated NFT, gacha, dividend, perp, floor, or seeder handler correctness; live environment variables; provider behavior; database migration/rebuild tooling; browser or running Ponder/Postgres integration; or end-to-end service recovery.

## Downstream consumer compatibility (remediated)

Historically, `/cauldron`, `/candles/:generation`, and `/recent/:generation` selected `.where(generation=gen).limit(1)`. Once rotation added multiple pool rows per generation, database row order could therefore choose either the launch pool or a sibling with no relationship to the generation's current denomination.

The API now queries the generation's bounded pool set and uses the shared `selectGenerationMarket` helper to select the row whose immutable PoolKey quote matches the registry's authoritative `generationQuote(gen)`. Missing launch rows, missing matching markets, and quote-RPC failure produce explicit unavailable responses rather than falling back to an arbitrary row. Historical sibling rows remain indexed. `/cauldron` scopes 24-hour volume to the selected pool instead of summing native and ERC20 quote units, and all three responses include quote/decimal and launch-pool metadata. The canonical launch primary remains separate and is used for `CauldronHook.isDead`, because hook volume linkage is directed from the primary to its siblings.

The regression exercises the exact shared selector used by the routes across reversed database order, a single generation moving native → 6-decimal ERC20 → native, an independent historical generation, a missing quote market, and quote-RPC failure. It is a deterministic helper/handler-boundary test, not a running Ponder/Postgres service or browser integration test.

**Named semantic gap, not a verified finding:** `/cauldron` still derives `phase === "dying"` by comparing the selected market's normalized 24-hour quote volume (`vol24hEth`, whose legacy name is retained) with `deathThresholdEth`. After a denomination change those values may not share the intended economic unit semantics even though the selected volume itself is decimal-normalized. This review did not establish the hook's precise cross-quote threshold semantics or reproduce a wrong phase, so no defect or severity is claimed.

## Regression execution

- Pre-fix: 1 failed / 1 passed; failure was the missing actual `RotationExec:LegOpened` handler.
- Strengthened pre-fix suite against the first remedy: 2 failed / 2 passed, proving both the same-block burned-position fault and swallowed transient RPC fault.
- Post-fix lifecycle suite: 4/4 passed, covering rotated swap/candle insertion plus relaunch history, unrelated-pool rejection plus rejecting transient RPC retry, fail-closed ERC20 decimals, and repeated same-block leg replacement followed by relaunch without loss or reassignment of history.
- Post-fix consumer-selection suite: 3/3 passed, covering reversed row order, native → 6-decimal ERC20 → native selection, independent generation history, missing matching market, and quote-RPC failure. Combined indexer result: 7/7.
- Root independently reran the repository test command: 19 Node tests, 2 API tests, and 7 indexer tests passed.
- `indexer` TypeScript check: passed.
- No service, network, build, Forge test, or live provider was run.
