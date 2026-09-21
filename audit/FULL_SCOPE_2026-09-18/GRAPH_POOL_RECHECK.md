# POOL Graph Recheck

## Result

All 77 skeleton nodes in `CauldronBase.sol` and `PoolOps.sol` were rechecked against current source. Mechanical fields are copied byte-for-byte from `skeleton/pool.json`; only semantic fields were rebuilt. Solidity comments were excluded when identifying executable calls.

The prior map contained comment/keyword false positives, notably `_sqrtPrice -> governor.markConsumed`, progressive seeding -> `governor.markConsumed`, and `seedFunding -> registry.call`. It also used non-type aliases such as `external.*`. Those entries are removed. Calls now use declared types where a Solidity cast or typed variable exists, including `IHookReserves`, `IVaultCloseOps`, `ICollectionOps`, `ILedgerOps`, `IColMinted`, `ISeeder`, and `IERC20`. Low-level dynamic calls retain the actual source expression (`q.call`, `asset.call`, `collection.staticcall`, or `hookAddr.staticcall`) because source does not prove a stronger runtime type.

Real omitted calls were added, including `_minQuoteFor` and `FullMath.mulDiv` in `_sqrtPrice`, both branches of progressive seeding, balance-delta accessors, hook reserve peeks/releases, the `GENESIS_SUPPLY()` probes, and the internal ledger/reserve orchestration. User-defined value-type `Currency.wrap`/`Currency.unwrap` conversions are casts rather than dispatching calls and are therefore excluded, consistently with the graph's built-in/cast convention.

## Trust and property review

- `IPoolManager`, PositionManager, pinned libraries, and exact first-party helpers are marked trusted. ERC-20 calls and raw low-level calls remain untrusted. `ISeeder.startSeed` is untrusted because the seeder address is governance-configurable even though its expected implementation is first-party.
- PoolOps is stateless; no function directly writes registry storage. Under delegatecall it moves registry-held native/ERC-20 value and position liquidity, which is recorded in each function's value field rather than misclassified as a storage write.
- Reserve exits measure actual balance deltas. Full-amount obligations (`migrateOne` and `recycleCollection`) revert on a short reserve beyond `CLAIM_DUST`; `migrateUpTo` deliberately reduces the burn to live capacity.
- `autoMigrateBatch` is caller-sized and therefore gas-bounded by the caller's transaction, but a very large list can still exhaust its own transaction. It skips unpayable holders instead of blocking later entries.
- ERC-20 compatibility remains a property assumption. `_approve` and the progressive handoff use typed `approve` without checking the returned boolean, while settlement, direct send, and buyer payment paths do check transfer success. Governance must not allowlist tokens with incompatible approval/transfer behavior.
- `executeBuy` derives its PoolManager from `msg.sender`; protocol safety therefore depends on the registry callback gate before delegatecalling this body. A direct call to deployed library code does not obtain registry storage or balances, but the body itself contains no sender assertion.
- `seedFunding` intentionally swallows old-vault and hook-release failures to protect rebirth liveness. This can omit optional value from the newborn seed, but cannot consume a below-threshold hook reserve because the code peeks before release.

## Exact dependency-resolution residual

The semantic map names exact dependency types. The strict joiner currently reports five POOL dependency edges unresolved: four `PoolIdLibrary.toId` sites and `LiquidityAmounts.getLiquidityForAmounts`. Those pinned dependency types are not in the joiner's explicit type allowlist. `ReserveLib` and `ISeeder` are first-party types and resolve through their own graph nodes. This report does not loosen validator policy, suppress those residuals, or replace exact names with aliases.

## Remaining graph limitations

Contract creation is described in `deployTokenAbove` value/reachability rather than represented as an edge, matching the graph convention. ABI encoding/decoding, hashing, casts, enum selection, and other Solidity built-ins are not call edges. Trust labels describe the expected protocol path; they do not prove deployed-address bytecode identity or configuration correctness.
