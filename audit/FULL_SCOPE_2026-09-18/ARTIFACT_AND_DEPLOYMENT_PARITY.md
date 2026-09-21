# Artifact and deployment parity — evidence checkpoint

2026-09-18. **NO DEPLOY / parity gate open.** Local remediations have not been deployed.

## Read-only Sepolia observations

Fork execution follow-up: the original `LIQ02_PreemptiveProjection` suite ran
successfully using `FORK_RPC=https://sepolia.gateway.tenderly.co`, the Sepolia
PoolManager and PositionManager below, cauldron profile, serial offline compiler
mode. **5 passed / 0 failed / 0 skipped**, suite duration 9.73 seconds after
compilation. Buy/sell/exact-output projection assertions actually executed.
This harness forks the endpoint's latest state and deploys fresh local protocol
contracts inside the fork; it does not test the manifest's deployed protocol
runtime. The fixture does not pin a fork block, so do not attach the preceding
probe's block/hash to this run. No transaction was submitted or signer used.

Fork prerequisite follow-up: `probe-deployed.mjs --fork-prereqs` read the two
manifest managers at block `0xb2fd78`, hash
`0xfcb04200163649174311eda7c9a02306d781cf80f5835a8dffd3733b49d25e34`, observed
2026-09-18T11:07:58Z. PoolManager has 24,009 runtime bytes, code hash
`0x09930125a49f5b95caf8052991cc14d1240dca8b43f42b899115b86867e4bce1`;
PositionManager has 23,877, hash
`0xcffd746f78c2b50aafd19076bbe9c48f14446e5248fc5d76b9b4896610e51aab`.
This establishes present code at the public endpoint, not a successful full
historical fork or exact local dependency-bytecode parity.

`node scripts/verify-selectors.mjs` initially failed sandbox DNS. After explicit network permission it connected to chain 11155111 and exited 1: the manifest router lacks `playChurn(uint256,uint256,uint256,uint256)`, selector `0xdf70b5a4`. Its other listed checks found selector literals. Literal presence is not full dispatcher, authorization, behavior, or linked-library proof.

`node audit/FULL_SCOPE_2026-09-18/probe-deployed.mjs` pinned reads to block `0xb2fcad`, hash `0x055bafbe21cf63b0b863557a9b7f47a5a51061d1354a885a62401f14ab7fed70`, observed 2026-09-18T10:23:59Z. No signer, broadcast or transaction submission was used.

| Contract / manifest key | Deployed runtime bytes | Local runtime bytes | Deployed code hash |
|---|---:|---:|---|
| gachaRouter | 8,580 | 8,814 | `0xe7ab26ef71b90d202ddede7f088d936aeb51ad08324c1f013ed5f00e4716d158` |
| registry | 24,492 | 24,492 | `0x436cdf8d0853b243d5cc5b89e6b73a8fd54182b9ceef293f6844c27f485b9d4b` |
| hook | 24,530 | 23,762 | `0x9f7492d812d177f1567e516195ee523a9cfca678205689e2fb69c31066e3385a` |
| perpEngine | 24,460 | 23,243 | `0xd475375745ca09c651497155917ea41c027906d1c2d2c05b132bb7a8fa4f935c` |
| perpVault | 8,002 | 11,284 | `0x2bcd60fbe9145895fc38ea7a3411a13c102bce5df765c4c258c5862fd4b8ea4b` |

Equal lengths do not establish equal bytecode. These lengths/hashes are inventory, not metadata/immutable/library-normalized equivalence. Constructor, role, linked-library and complete deployment-transaction reconstruction remain open.

## Router ABI mismatch and safe compatibility

A second router-only read at block `0xb2fcca`, hash `0x15f471a44c77153689f6419105fb9923703c69accfbf8890eae74642bffc6763`, found:

| Signature | Selector literal in deployed code |
|---|---|
| `playChurn(uint256,uint256,uint256,uint256)` | Absent |
| `playChurn(uint256,uint256,uint256)` | Present (`0xc4ffce88`) |
| `play(uint256,uint256,uint256,uint256,uint256)` | Present |
| `playLiq(uint256,uint256,uint256,uint256,uint256,uint256[])` | Present |
| `openReady(uint256)` | Present |

The zero-value four-argument `eth_call` returned RPC execution error code 3 without supplied revert data. No live economic exploit or funded transaction was attempted.

Current source `CauldronGachaRouter.sol:379` adds a caller-specified final token minimum to churn. The legacy three-argument interface cannot encode that protection. Do not silently rewire the UI to it just to obtain looping behavior. `useCauldronSwap.ts:87-103,415-443` already detects the four-argument selector and falls back to protected `play`, which does one buy rather than the promised repeated churn. Thus the selector checker’s generic claim that every app spin must revert is too broad: the current app has a degraded fallback. UI loop/odds descriptions must match the actual selected mode.

The owner was asked whether to explicitly use protected single-buy mode now or retain multi-loop behavior pending an authorized updated-router deployment. No selection or deployment approval has been assumed.

## Local build constraints

Artifact freshness caveat: a later PERP-03 source edit left the bare
`out/PerpEngine.sol/PerpEngine.json` alias at an older source hash and 23,243
runtime bytes. The `.0.8.26.json` and `.0.8.30.json` variants matched the edited
primary source hash and measured 23,373 bytes (1,203 headroom). The measurements
below are the earlier checkpoint, not fresh size assertions. Verify metadata
source hashes when selecting multi-solc artifacts. PERP-04 requires another
measurement after its build completes; no local/deployed equivalence follows.

Current cauldron-profile runtimes: registry 24,492 (84 bytes EIP-170 headroom); hook 23,762 (814); engine 23,243 (1,333); vault 11,284 (13,292); redemption facet 13,744 (10,832). The registry/facet compiler storage layouts match across 60 entries. Fresh AST/typecheck graph resolves 1,035 declarations, 3,211 call expressions, 14 explicit sensitive sites and 162 contract surfaces with zero unresolved compiler declaration/selector references. That is structural parity, not completed security review.

The registry facet setter is one-shot. The new redemption source is not a drop-in upgrade for an already-wired deployment. A deployed-state migration plan requires separate review and explicit approval.

Still required: all consumer ABI/event tuple/indexed-field comparisons, all manifest contract/library identities, normalized runtime parity, deployment rehearsal, wiring/roles/feeds/quote configuration and a pinned fork integration lane. Public endpoint availability for these small reads does not attest reliable archival fork access or completion of those checks.
