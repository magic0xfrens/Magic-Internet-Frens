# Candidate artifact inventory — partial deployment verification

Reproduce from repository root:
`python3 audit/SOLIDITY_REAUDIT_2026-09-23/check_candidate_artifacts.py`.
Checks every metadata input keccak against the local source, records artifact
SHA256, compiler/settings and unlinked byte lengths. Does not accept stale
unversioned artifacts merely because a neighboring versioned artifact is fresh.

62/66 frozen source files have at least one artifact whose entire recorded
compiler input set matches. Missing standalone artifacts: DeployRenderer,
FrenRenderer, LiquidatoorRenderer, TraitStorage. Embedded creation code used by
passing tests does not fill this standalone artifact gate.

| Contract | Runtime | Runtime headroom | Initcode excluding constructor args |
|---|---:|---:|---:|
| CauldronRegistry |24568|8|25204|
| CauldronHook |24401|175|25497|
| PoolOps |24465|111|24497|
| PerpEngine (both0.8.26/0.8.30)|24207|369|26229|
| VenueSeeder |5294|19282|5353|

The above metadata input sets match. Runtime within EIP-170 is necessary, not
sufficient for deployability: constructor args, linking, CREATE2 salts and
supported wiring remain separate gates. No source-size headroom estimate.
Five oversize matching artifacts are deployment SCRIPT harnesses (DeployCauldron,
DeployLaunchpad, DeployPerp, DeployRotationStack, DeployV4Core); those numbers do
not establish that their deployed contracts exceed the runtime limit.
Interfaces/abstract artifacts may have zero code and are not counted as deployed
contracts. See JSON for complete per-artifact records and missing inputs.
No final semantic sign-off follows from this check.

## Renderer completion checkpoint

Prior62/66 inventory preserved as CANDIDATE_ARTIFACT_INVENTORY_PRE_RENDER.json.
Isolated explicit-path build renderer-standalone-artifacts succeeded with
solc0.8.30, cauldron viaIR/optimizer1 settings and empty skip list. Outputs/cache
are separate from the still-running full suite. All66 files now have at least
one whole-input-matching artifact. This does not repair or pass the broad render
profile that previously failed with mixed dependency compiler selection.

| Contract | Runtime | Initcode excluding args |
|---|---:|---:|
| DeployRenderer | 14493 | 14536 |
| IPegRenderer | 0 | 0 |
| FrenRenderer | 7266 | 7425 |
| LiquidatoorRenderer | 9336 | 9379 |
| TraitStorage | 2663 | 2781 |
