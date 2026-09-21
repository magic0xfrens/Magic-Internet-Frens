# System overlays — working audit map

This is a partial, source-derived overlay on `COMPILER_GRAPH.json`, not a claim
that every node/property is audited. Exact compiler inventory and explicit gaps
remain in `FUNCTION_COVERAGE.json`. Local source differs from deployed Sepolia.

## Perpetual position lifecycle and denomination

`PerpEngine.sol:980-1045,1713-1901`:

| Transition | Custody/accounting movement | Exit and protection |
|---|---|---|
| `openLong` | User supplies quote; fee reduces collateral C. Borrow C*(leverage-1) from quote PLV. Buy iteration tokens held by engine. Position principal is quote debt. | Minimum token output, notional/OI/utilization gates; transaction rollback on failure. |
| `openShort` | User supplies quote; borrow iteration tokens worth C*leverage, decrement token PLV and increment token OI. Sell tokens; engine holds C + quote proceeds as backing. | Minimum quote sale proceeds; notional/OI/utilization gates. `principal` here means held quote proceeds, unlike long principal. |
| Long settlement | Sell held position tokens; restore borrowed quote principal as available, insurance replenishes shortfall, residual goes through funding/payout tail. | Owner minimum compares gross sale proceeds; death sale is band-limited and unsold inventory is explicitly written off. |
| Complete short settlement | Buy token debt back; restore bought token inventory and reduce token OI. Spending above position backing charges insurance, then quote PLV. | Non-normal modes use mark band; owner minimum checks pre-funding residual. |
| Partial short settlement | Retire bought token debt; rebook unbought debt and remaining backing. No immediate user output. | PERP-01 preserves remaining collateral basis; PERP-03 rejects nonzero owner minimum before zero-output rebooking. Final acceptance pending. |
| Funding/penalty/payout | Funding payer is capped by residual; receiver draws insurance then PLV. Liquidation penalty is capped by residual, split to keeper and fee routing. | Not globally zero-sum; bad debt and funding can consume backing. Deferred payout behavior is a separate reviewed boundary, not proven by partial-close tests. |
| Death/relaunch | `forceCloseAllDead` drains a bounded book before generation sync; sync changes token/quote context. | Full transition matrix, token-yield write-off integration and all recovery paths still have gaps. |

The ABI suffix `Eth` does not mean native ETH for an ERC20-quoted generation.
Never sum quote and token units or compare price-normalized volume to raw quote
amounts merely because the fields have similar names.

## Treasury rotation trust and custody

1. Governance approves a destination and a finite allowance. Zero remaining
   allowance, not zero destination address, means idle: native currency uses
   address zero (`RedemptionExt.rotateSliceFrom`).
2. Permissionless execution selects a source leg and bounded slice, but cannot
   authorize a new quote/venue. Registry/facet validates governance allowance,
   destination allowlist and slice bounds before moving liquidity.
3. `QuoteRotator.swapOnce` is registry-only and requires an exact allowlisted
   PoolId, matching pair and an independent nonzero oracle floor. Caller minimum
   may tighten that floor; it cannot safely replace it. Failure reverts the whole
   transaction, including the source-position removal.
4. Destination LP identity is recorded separately from the launch pool and reserve.
   ROT-02 consolidates returns to the launch quote in the primary active position,
   so later primary mandate consumption tracks the actual returned treasury.
5. Historical pool identity persists after a PositionManager NFT is replaced or
   burned. Indexer discovery uses authenticated leg events plus persistent
   generation state; consumers select current denomination separately from
   launch-primary lifecycle identity. Same-block replacement is tested.

Evidence: four `RotationLifecycleLocalTest` cases, four real-V4 rotator cases,
treasury route helpers, seven indexer tests. Residuals: pre-existing duplicate
position migration, arbitrary hostile assets, deep reorg/service recovery,
deployed wiring and every open-perp rotation interlock are not certified.

## NFT floor separation

| Surface | Intended mode | Authority / failure behavior |
|---|---|---|
| `CauldronVault.redeem` | Explicit legacy ETH floor only | Holder + affirmative minter `vault()==this`; donations cannot enable mode. Burns NFT. |
| Registry `recycleCollectionNFT` / ledger `redeem` | Unified token floor | Holder/registry accounting path moves custody and debits entitlement; not the legacy burn endpoint. |
| Vault `close` | Relaunch teardown | Immutable registry only; sweeps actual ETH but reports only protocol-accounted amount, clamped to balance. |
| Ledger `crystallize` | Dead-generation accounting | Registry-only, once; frozen supply is derived from vault outstanding. Historical burnt-state recovery remains separate. |

NFT-01 changes no storage layout and does not restore already-burned NFTs.

## Explicit unfinished overlays

Complete role grant/revoke/renounce/dead-end matrix; every emergency/successor
custody path; event-to-consumer mapping outside reviewed rotation handlers;
all rounding/decimal/cast domains; every oracle outage/recovery transition;
all seeder, NFT validator, renderer, deployer and chain-specific liveness paths;
per-node assertions and a fully reconciled semantic graph.
