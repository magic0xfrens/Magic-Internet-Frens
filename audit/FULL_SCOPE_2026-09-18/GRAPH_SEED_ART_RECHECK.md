# SEED and ART graph source recheck

Date: 2026-09-18

## Method and result

All 69 SEED nodes and all 61 ART nodes were re-read from the current first-party source using comment-masked `body_lines`. Mechanical skeleton fields, including `body_lines` and `body_sha1`, were copied verbatim from the current skeleton. Semantic calls were rebuilt from executable bodies and resolved to declared types; casts, ABI/string helpers, array built-ins, constructors, and event emissions are not represented as graph edges.

The recheck removes generic `external.*` aliases and records concrete interfaces/libraries. It also restores omitted internal composition calls, PoolManager unlock/settlement calls, StateLibrary/PoolIdLibrary extensions, renderer helper calls, and TraitStorage/SSTORE2 calls. TRUSTED means first-party or pinned dependency code; caller/admin-selected addresses remain UNTRUSTED even when cast to a first-party interface.

## Exact dependency residuals

- `Vm.readFileBinary` in `BadgeArtLib.upload` is an exact Foundry cheatcode type used only by deployment scripts. The strict join allowlist does not model `Vm`; both executable calls remain explicit.
- `Base64.encode` and `Strings.toString` are exact OpenZeppelin library calls. If the strict join cache/allowlist lacks those library contract names, those edges remain exact dependency residuals rather than being relabeled.
- `BalanceDeltaLibrary.amount0/amount1` are global using-directive extensions on `BalanceDelta`; `StateLibrary.getSlot0/getPositionInfo` and `PoolIdLibrary.toId` are likewise typed v4 extensions. They are intentionally not represented as `poolManager.*`, `d.*`, or `_key.*` aliases.
- The strict join currently reports ten SEED residual edges: seven exact `PoolIdLibrary.toId` calls and three exact `LiquidityAmounts` calls. ART has eight: two `Vm.readFileBinary`, two `Base64.encode`, and four `Strings.toString` calls. These are dependency-name allowlist gaps, not unresolved source types.

## Source-grounded property gaps

### SEED

- **DERIVED — unchecked ERC20 returns:** `CauldronSeeder._teardown` (CauldronSeeder.sol:674), `_settle` (:731), and `rescue` (:891), plus `LaunchSniper.launch` (LaunchSniper.sol:96) and `sweep` (:107), do not check the boolean returned by `IERC20.transfer`. A false-returning token can leave accounting/events describing a transfer that did not occur. Production Cauldron tokens are expected to revert or return true, so exploitability depends on the configured token boundary.
- **DERIVED — bounded core teardown:** `CauldronSeeder._reserveRange` caps distinct tracked ranges at `MAX_RANGES = 64` (CauldronSeeder.sol:116,798-840), so `_teardown`'s loop (CauldronSeeder.sol:646-659) is bounded. `MigrationVesting._release` is independently bounded by the sole push site's `MAX_GRANTS` check (MigrationVesting.sol:217,264-298).
- **DERIVED — caller-sized keeper work:** `MigrationVesting.vestBatch` iterates the caller-supplied `holders` array (MigrationVesting.sol:191-203). This can exceed one transaction's gas, but the caller chooses the batch and no partial state survives a revert; individual holder exit remains bounded by `MAX_GRANTS`.
- **DERIVED — rescue preserves the lifecycle intentionally:** `CauldronSeeder.rescue` transfers only loose balances and does not clear `seeding` or tracked ranges (CauldronSeeder.sol:888-894). This keeps the registry's later `withdrawAll` route reachable, but an immediate subsequent placement can fail until funds are restored or the registry performs teardown.
- **HYPOTHESIS — range-cap eviction weakens the meaning of `placedWad`:** once `ranges.length >= MAX_RANGES`, `_reserveRange` removes a prior position and settles its assets into loose balances (CauldronSeeder.sol:815-835). `_placeStep` then sizes the replacement only from the new schedule delta (`tokenStep`/`ethStep`, CauldronSeeder.sol:569-572), without adding the evicted proceeds. Thus `placedWad` can reach 1e18 while a material fraction of ledger A is loose rather than deployed. The source explicitly chooses eviction as graceful degradation, so whether this violates the required depth invariant needs an end-to-end cap-reaching balance test rather than being labeled a defect from inspection alone.

### ART

- **DERIVED — malformed frozen traits can permanently break rendering:** `TraitStorage.storeTrait` accepts arbitrary blobs (TraitStorage.sol:64-68). `FrenRenderer._appendLayer` checks only `blob.length >= 8` before indexing the declared local palette and pixel body (FrenRenderer.sol:135-158), and `_nibble` indexes without an explicit payload-length check (:194-201). If the owner uploads a structurally short blob and then calls irreversible `freeze` (TraitStorage.sol:83-86), affected metadata calls can revert permanently.
- **DERIVED — fixed buffer has no capacity guard:** `FrenRenderer.renderSVG` allocates 200,000 bytes (FrenRenderer.sol:77), while `_append` performs raw `mcopy` and increments length without checking `start + n <= data.length` (:305-316). Uploaded dimensions are bytes and thus bounded per layer, but adversarially fragmented valid-looking pixels can produce output beyond the assumed realistic cap. Because the trait owner controls inputs, this is an administrative/configuration correctness risk rather than a permissionless write.
- **DERIVED — mutable/unbounded badge art:** `LiquidatoorRenderer.appendArt` lets the owner grow either pointer array without a cap (LiquidatoorRenderer.sol:80-92); `art` walks and repeatedly concatenates the entire array (:95-100). A sufficiently large owner-created array can make reads exceed RPC/block gas, and `setArt` must first pop the entire old array (:61-65), potentially making replacement impractical. There is no freeze operation for badge art.
- **DERIVED — renderer caller is intentionally untrusted:** `CauldronArtAdapter.tokenURI` and `LiquidatoorRenderer.tokenURI` derive collection data from `msg.sender` (CauldronArtAdapter.sol:91-94; LiquidatoorRenderer.sol:109). Any contract may invoke those views and supply its own interface responses; this does not move custody, but consumers must not treat a standalone renderer response as proof that the collection is canonical.
- **EIP-170 check:** `BadgeArtLib.CHUNK` is 24,000 bytes (BadgeArtLib.sol:24), below the 24,576-byte runtime code limit after SSTORE2's one-byte STOP prefix. The upload path splits both files before calling `SSTORE2.write` (BadgeArtLib.sol:27-37,64-73).

## Rejected concerns

- The SEED range and grant exit loops are not unbounded protocol state: their push paths enforce 64-entry ceilings.
- `CauldronSeeder.unlockCallback` is not publicly dispatchable by arbitrary callers; it requires the immutable PoolManager at CauldronSeeder.sol:541.
- `CauldronArtAdapter`'s `collection.code.length` check is not an authentication gate and is not represented as one; the function is correctly classified permissionless.

## Validation limits

The build-free source check confirms exact skeleton equality and that every edge method is present on its cited executable line. The legacy validator cannot complete cleanly without refreshed Forge artifacts: its cached storage layouts predate current private fields and the newly added ART contracts, and its exact dependency allowlist does not include the residuals listed above. No cache or validator rule was changed during this recheck.
