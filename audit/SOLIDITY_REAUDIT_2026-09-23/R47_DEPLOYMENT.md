# r47 on Sepolia — the fixed tree, deployed (2026-09-23, owner-authorized)

Source: contracts at `6961bb4` (all High/Medium/Low fixes); graph at `afb5642`.
Deployer `0xc94400e90bb652afa02740bff50824e14069c133`. Chain 11155111.
Run: `SKIP_ARM=1 ./scripts/go-testnet.sh` (r46 was already retired, R46_RETIREMENT.md).

## What ran

| Step | Result |
|---|---|
| First attempt | Stopped in simulation, nothing broadcast (balance unchanged): the launchpad refused a rotator with no oracle because `DEPLOY_QUOTES` is opt-in since the 2026-09-18 audit and the testnet wrapper never set it. Fixed in `deploy-testnet.sh` (with `VENUE_BAND_BPS=500`, which that file's own comments assumed). A full no-broadcast simulation then passed before the real run. |
| DeployLaunchpad | 78 transactions, blocks 11767649–11767663, 93.19M gas, 0 failed |
| Presale mint-out | 1111 frens at 0.002 ETH in five batches; `finalized = true` |
| `igniteCauldron()` | generation 1 summoned; token `0xf7e9F718238B7402b9DC7dba5308F84A6a17ECdb`, collection `0x1cbb1b1cd99c53a97251eb8d9aa539c5089eedb5`, vault `0x727e879349e23d3cc98dc38450ee55cc5cd30e01` |
| DeployPerp | 15 transactions, blocks 11767753–11767770, 10.44M gas, 0 failed; insurance seeded 0.06 ETH; engine already synced to generation 1 |
| Treasury oracle (the launchpad prints this as a timelock step) | `timelock.schedule(treasuryGov.setQuoteOracle(0xB085…925A))` `0x9486928f24cb3b9664fae0da54ccd72f95b88cfd7a000aa42e110c253bfcb451`; after the 180 s delay `execute` `0x480e12ef757de3cd10f24b9bf93f56034c2c4341b062cfc967c3b773b594afc0`; `quoteOracle()` reads back `0xB085…925A` |
| Manifest | `indexer/deployments/round.json` round 47, schema `cauldron_r47`, start block 11767639; `verify-manifest.mjs` OK; selector parity 11/11 contracts |

Deployer balance 9.3741 → 6.6078 ETH (2.222 ETH presale into the pool, 0.3 ETH venue, 0.06 ETH insurance, gas).

## Manifest fix found on the way

Foundry recorded five of the launchpad's CREATEs with `contractName: null`
(QuoteOracle, QuoteRotator, MockQuoteToken, CauldronSeeder, LiquidatoorRenderer).
`apply-deployment.mjs` matched by name only, so it silently kept r46's rotator,
oracle, USDG and perp vault in the manifest while everything else moved.
It now identifies an unnamed CREATE by comparing its init code with the compiled
artifacts (link placeholders matching any address). Re-applied from the r46
manifest, every address resolves from this deployment.

## Bytecode parity (verify_deployed_bytecode.py)

Every deployed runtime compared with the artifact of the same name from the
force-rebuilt `contracts/solidity/out` (renderer: the explicit-path build under
`remediation/renderer-artifacts`). Immutable and library-link slots masked;
everything else, including the CBOR metadata hash, byte-identical.

| Contract | Address | Runtime bytes | Result |
|---|---|---:|---|
| TimelockController | 0xc61f0d8f33372fb4a4f4076aa7808023f6c2e601 | 5,375 | MATCH |
| MiFrensGenesis | 0x3962433f1d58f4e550775b90a2850ff6ef992814 | 22,858 | MATCH |
| CauldronHook | 0xdbf776a73c6e4e27b69edce4aca9e211c1d610cc | 24,338 | MATCH |
| CauldronRegistry | 0x4117cc0a60c1d511050cb4dd2db7095c1e359311 | 24,342 | MATCH |
| RedemptionExt | 0xde2cae8c0f4cf263e46feb901f20475cb4a125f1 | 17,250 | MATCH |
| CauldronGovernor | 0x2612a7433389684d4f063e2bc642970b4d280e98 | 9,341 | MATCH |
| CauldronFactory | 0x23eeb347076b282a38ff26870eca52e20634bd08 | 20,520 | MATCH |
| MiFrensDividend | 0xc1083d30793ae14825e6d01ef173e1dd7bc2cd80 | 8,194 | MATCH |
| CauldronGachaRouter | 0xb910c76ec63a8f389cdd159eed2f672c973a9da8 | 8,828 | MATCH |
| CollectionLedger | 0x5061861516a4667305cc11342abc533c903a38c4 | 2,092 | MATCH |
| LiquidatoorRenderer | 0x01ddf0016f8f56c7d202cb2e0365fea7968effe0 | 9,336 | MATCH |
| QuoteOracle | 0xb085330e412f206d11ac80840172c9f026d7925a | 3,970 | MATCH |
| MintCurvePolicy | 0xb68266e2532e2f70a4819786573847af30bfed9b | 871 | MATCH |
| CauldronSeeder | 0xcca638871b94e5fde82ab122791d972def1cbea0 | 15,453 | MATCH |
| QuoteRotator | 0x0ff411a7b64e6aea1f2b4abb522b6088b8f4852d | 9,874 | MATCH |
| TreasuryGovernor | 0x85989d34e0970ab86286368341ed8777908ec683 | 6,938 | MATCH |
| MockQuoteToken (USDG) | 0xe00e34c4f7fe2ffc9b52adf59502989e57386a6f | 1,725 | MATCH |
| VenueSeeder (full range) | 0x3eeb3a910e0ccf91dff883405031df211c873976 | 5,295 | MATCH |
| VenueSeeder (±5% band) | 0xef7a2ccf6007d10ac871275f3a200f1354f3f580 | 5,295 | MATCH |
| NativeQuoteZap | 0x54880777a3d3e769a76787edb221718009a77123 | 2,326 | MATCH |
| FeeRouteLib | 0xa4096093f6922d8244cCA9a9622F4e33d92a39fD | 2,083 | MATCH |
| GachaLib | 0xf60E4196115B3904bad1b86E27d748A9D8D81dAd | 1,958 | MATCH |
| LegacyBuyLib | 0x29726E945A7b85562F631575b989C7E5D5B199eB | 3,331 | MATCH |
| PoolOps | 0xfBD376d8694B9F7675916f49fc5E45ace798c763 | 24,465 | MATCH |
| SurtaxLib | 0x526820e435d27a88b608e8fEFEa67f88d5bd5406 | 687 | MATCH |
| PerpEngine | 0x07279f9503dab494d2bba929d674bde3c6cf9017 | 24,207 | MATCH |
| PerpVault | 0x01110799de1bac598426704d8ecee95c6b4c5c08 | 12,608 | MATCH |
| PerpMarkSource | 0x84734fca6DD21Ef21c0C94768490683D9F1408b8 | 3,603 | MATCH |
| CauldronCollection (gen 1) | 0x1cbb1b1cd99c53a97251eb8d9aa539c5089eedb5 | 11,952 | MATCH |
| CauldronVault (gen 1) | 0x727e879349e23d3cc98dc38450ee55cc5cd30e01 | 2,495 | MATCH |
| CauldronToken (gen 1) | 0xf7e9F718238B7402b9DC7dba5308F84A6a17ECdb | 2,033 | MATCH |

32/32 match. FeeRouteLib and LegacyBuyLib were not re-created: their CREATE2
addresses already held this exact code from an earlier round, and the match
above confirms it.

## Live state read back

presale `finalized = true`, `minted = 1111`; registry `summoned = true`,
generation 1; engine `insuranceEth = 0.06 ETH`, `syncedGeneration = 1`; registry,
hook and engine owned by the r47 timelock, which is also the emergency admin
(`emergencyDelay = 300 s`); `hook.perpEngine()` is the r47 engine.

## Not done here

- Indexer: `cd indexer && railway up` (schema bumped, clean reindex) needs the
  owner's Railway login.
- Site: deploys from `main` via deploy.yml once this branch is merged.
