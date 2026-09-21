# Defensive correctness review — registry, pool, governance, seed, art, deploy

Date: 2026-09-18  
Baseline: `71443f2bac9275b54536046ead962b4a65f557c2` plus the preserved working-tree changes visible during review.

## Executive result

This pass confirmed **one high-severity deployment/configuration defect** and **one low-severity deployment-script defect**. It did not confirm a new permissionless on-chain asset-drain defect in the reviewed registry, pool, governance, seeder, or art contracts.

No production Solidity was modified. No new regression test was added: the confirmed defects are Foundry script/configuration failures whose minimal reproductions are direct source-level environment choices; an on-chain regression harness would not improve the evidence and a `BATCH=0` harness would intentionally enter a non-terminating loop.

The attempted targeted Forge run was stopped during a concurrent multi-solc rebuild that did not finish; it is not cited as pass evidence. The clean full-scope baseline already records `FOUNDRY_PROFILE=cauldron forge build --sizes` as passing and supplies the current runtime sizes.

## Verified defects

### CORE-01 — Raw launchpad deployment defaults to a freely mintable quote asset and a Sepolia-only native feed

Severity: **High (deployment/configuration)**  
Status: **remediated in the 2026-09-18 working tree; root verification pending**.

Evidence:

- `DeployLaunchpad.run()` enters the quote-stack path when `DEPLOY_QUOTES` is omitted because the default is `true` (`deploy/DeployLaunchpad.s.sol:531-535`).
- That path deploys `MockQuoteToken("Magic USD", "USDG", 6)` (`DeployLaunchpad.s.sol:651-658`).
- `MockQuoteToken.mint(address,uint256)` is callable by anyone and mints without a cap or role check (`cauldron/MockQuoteToken.sol:24-27`). The contract itself says it must never be deployed on mainnet (`MockQuoteToken.sol:6-15`).
- The same path configures native pricing with the hard-coded Sepolia ETH/USD feed `0x694A…0306` (`DeployLaunchpad.s.sol:600-604,690-698`). The source explicitly states that this address is codeless off Sepolia and makes `usdPerRawUnit` return zero (`DeployLaunchpad.s.sol:672-681`).
- The root mainnet wrapper sets `DEPLOY_QUOTES=false` and refuses any other value (`scripts/deploy-mainnet-rh.sh:329-343`), but the advertised Forge script itself has no chain-id assertion and remains unsafe when invoked directly or from a different wrapper.

Impact:

1. On a production chain, the raw default can allowlist and seed a quote token whose supply any address can inflate. A rotation venue holding real protocol inventory against that token can then be economically drained by arbitrary minting and trading.
2. On any non-Sepolia chain using the fed-native branch, the codeless feed makes volume pricing fail closed to zero. Mint progression and death/liveness judgments then operate on fictitious zero volume even though deployment succeeds.

Reproduction:

1. Invoke `DeployLaunchpad.run()` without `DEPLOY_QUOTES` on a non-Sepolia production chain.
2. Observe `_deployRotationStack` is entered and creates `MockQuoteToken`.
3. From an unrelated address, call `mint(attacker, amount)` successfully.
4. Observe the native feed configured at the Sepolia constant; on another chain it has no code and oracle reads return the failure value.

Remediation:

- Change the script default to `DEPLOY_QUOTES=false`.
- Require an explicit testnet chain allowlist before deploying `MockQuoteToken`; fail closed on every other chain.
- Make native feed addresses environment/config inputs and require `feed.code.length > 0` plus a successful, fresh probe before any broadcast that wires them.
- Put the chain assertion and mock-token prohibition inside `DeployLaunchpad.s.sol`, not only in a shell wrapper.
- Add a deployment test proving production chain IDs reject `DEPLOY_QUOTES=true` and reject a codeless feed.

Remediation applied:

- `DeployLaunchpad.run()` now defaults `DEPLOY_QUOTES` to false and performs quote-stack preflight before reading `PRIVATE_KEY`, required deployment addresses, calling `vm.startBroadcast`, or creating any contract.
- Opting into the mock quote stack now fails unless `block.chainid == 11155111`.
- Any configured non-pegged feed is checked before broadcast for code, successful `latestRoundData()` and `decimals()` responses, a positive answer, safe decimal normalization, a non-future timestamp, freshness under the configured non-zero `uint32` heartbeat, and configured price bounds.
- Feed addresses remain environment-overridable, while the existing Sepolia constants preserve the Sepolia deployment path.
- `test/audit_full_scope/DeployLaunchpadSafety.t.sol` now calls the real `run()` entry point and proves mainnet/mock, codeless-feed, and stale-feed configurations revert before missing signer or deployment environment variables can be read. The earlier helper-only test was removed.

### CORE-02 — `DeployRenderer` accepts `BATCH=0`, making its upload loop non-terminating

Severity: **Low (deployment availability / partial broadcast)**  
Status: **verified from executable source**.

Evidence:

- `batch` is read directly from `vm.envOr("BATCH", 12)` without a lower bound (`deploy/DeployRenderer.s.sol:38-43`).
- The manifest loop advances with `i += batch` (`DeployRenderer.s.sol:56-63`). With a non-empty manifest and `batch == 0`, `i` never changes.
- The script starts broadcasting and deploys `TraitStorage`, `FrenRenderer`, and the palette before entering that loop (`DeployRenderer.s.sol:44-62`). A broadcast run can therefore leave paid, partial infrastructure before eventually failing for gas or operator interruption.

Impact:

Operator error (`BATCH=0`) prevents renderer completion and can leave an incomplete deployment that has already consumed gas and produced addresses. If an incomplete address is wired manually, metadata reads can remain unavailable.

Reproduction:

Run the renderer script with a valid non-empty manifest and `BATCH=0`; the outer loop's post-expression adds zero forever.

Remediation:

Validate `batch > 0` before `vm.startBroadcast(pk)`. A practical upper bound should also be enforced to prevent a user-selected batch from exceeding transaction gas ceilings.

## Unconfirmed risks and design decisions

### RISK-01 — A one-basis-point secondary rotation disables the treasury `stalled()` escape hatch

`rotateSliceFrom` is permissionless and books every successful secondary-leg slice through `TreasuryGovernor.consume(sliceBps, false)` (`cauldron/RedemptionExt.sol:277-285,413-415,546-548`). `consume` increments `movedBps` but leaves `movedPrimaryBps` unchanged (`TreasuryGovernor.sol:935-966`). `stalled()` requires both counters to remain zero (`TreasuryGovernor.sol:926-932`). Consequently, one successful 1-bps secondary movement prevents the zero-progress escape until envelope expiry even though the voted primary allowance remains untouched. The existing `R2B_StalledDustImmunity.t.sol:129-170` encodes that state transition.

This is **not classified as a verified defect** in this pass because the contract's current policy explicitly treats any authorized treasury movement as envelope progress and explains that replacing a partially spent envelope could exceed the cooldown's aggregate movement budget (`TreasuryGovernor.sol:907-911`). It is a real liveness-versus-budget tradeoff requiring an owner/governance policy decision. If primary liveness should dominate, use a separate secondary budget/epoch or make `stalled()` primary-progress-aware without allowing two envelopes to exceed the intended aggregate cap.

### RISK-02 — Seeder deployer authority survives the registry ownership handoff

`CauldronSeeder` permanently stores its constructor caller as `deployer` (`CauldronSeeder.sol:223-227`). Both `fundPrime` and pre-campaign `refundPrime` authorize either that deployer or the current registry owner (`CauldronSeeder.sol:347-364,379-388`). `refundPrime` sends the entire native balance to an arbitrary recipient, not merely funds contributed by the caller. Therefore, if a later registry owner funds the seeder before its first campaign, the original deployer can still refund that balance to itself.

This is recorded as a **trust/centralization risk**, not an authorization bypass: the source intentionally grants the deployer that role, and the shipped configuration documents `PRIME_BUY_ETH=0` for this mechanism (`DeployLaunchpad.s.sol:395-415`). If post-handoff funding is expected, replace the permanent deployer privilege with the current registry owner or a one-way role-renunciation/handoff.

### RISK-03 — Mutable renderer inputs can make metadata unavailable

`TraitStorage` correctly offers an irreversible `freeze`, but `DeployRenderer` defaults `FREEZE` to false (`DeployRenderer.s.sol:38-42,83-87`). `LiquidatoorRenderer` has no freeze operation; its owner can clear/append arbitrary SSTORE2 chunks (`render/LiquidatoorRenderer.sol:35-40,61-99`), and `tokenURI` depends on the resulting array. Malformed trait blobs or very large badge chunk arrays can cause metadata calls to revert or exceed RPC gas limits.

This is not an asset-security defect and is admin-controlled. Production deployment should freeze validated trait storage, publish manifest hashes, and either transfer badge-renderer ownership to governance or add a deliberate freeze/finalization operation after upload.

## Rejected concerns / confirmed safeguards

### Authorization and callback safety

- `CauldronSeeder.unlockCallback` rejects every caller except the immutable PoolManager (`CauldronSeeder.sol:540-553`). External seeder state-changing entry points use the local reentrancy lock, and registry teardown/rescue paths are `onlyRegistry` (`CauldronSeeder.sol:203-205,850,888`). An arbitrary user cannot select an unlock action against the seeder.
- Direct calls to the deployed `PoolOps` library operate on the library's own context. Protocol asset movement occurs when registry wrappers invoke it in registry context; no evidence was found that an ungated direct library call reaches registry storage.

### Asset conservation and rounding

- Holder migration burns before reserve withdrawal, but a short withdrawal reverts the whole transaction, rolling the burn back (`PoolOps.sol:1412-1422`). The batch path recomputes reserve capacity for each holder and skips balances it cannot fully cover (`PoolOps.sol:1438-1453`).
- Collection recycling debits the ledger and transfers custody before reserve withdrawal, but explicitly reverts on a material shortfall, rolling all three effects back (`PoolOps.sol:1572-1616`).
- Pool launch price representability is handled in quote base units. `_minQuoteFor` computes the mathematical floor and `_sqrtPrice` clamps before 512-bit division (`PoolOps.sol:209-247`). Relaunch funding uses the more conservative `MIN_SEED_UNITS`, documented for both native and six-decimal quotes (`PoolOps.sol:217-225,1195-1212`). The apparent 6-vs-18-decimal asymmetry here is intentional raw-unit representability, not the separate legacy-hook threshold defect.
- Treasury conversion explicitly returns zero for `sliceBps == 0`, preventing division by zero, and otherwise uses a bounded 16-bit iteration count (`TreasuryGovernor.sol:310-325`).

### Bounded execution and lifecycle exits

- Both governors bound winner/bench scans to eight slots (`CauldronGovernor.sol:320,710,848`; `TreasuryGovernor.sol:209,558,743`). Proposal count no longer controls execution gas.
- Seeder teardown is bounded by `MAX_RANGES = 64`; when full, range replacement evicts within that fixed set (`CauldronSeeder.sol:116,798-840`). Teardown iterates only the bounded set (`CauldronSeeder.sol:643-658`).
- Pool CREATE2 mining is bounded by `SALT_TRIES = 1024` (`PoolOps.sol:691,772`).
- SSTORE2 reads guard `code.length <= 1` before subtracting the prefix (`render/SSTORE2.sol:48-58`), and badge deployment chunks are capped at 24,000 bytes, below EIP-170 (`deploy/BadgeArtLib.sol:17-35`).

### EIP-170 deployment constraint

The clean baseline reports:

| contract | runtime bytes | remaining |
|---|---:|---:|
| CauldronRegistry | 24,492 | **84** |
| PoolOps | 24,173 | **403** |

Both currently pass EIP-170, but neither has meaningful feature headroom. Any remediation touching them must rerun `FOUNDRY_PROFILE=cauldron forge build --sizes`; registry changes should preferentially use an existing facet/library path rather than remove checks or assume optimizer luck.

## Coverage conclusion

The pass reviewed authorization, asset conservation, unit/decimal domains, rounding, loop bounds, lifecycle exits, callback entry points, deploy wiring, renderer mutability, and current EIP-170 margins across the assigned clusters. The highest-priority action is to make the raw launchpad script fail closed on production chains; relying on one shell wrapper is not a sufficient deployment invariant.
