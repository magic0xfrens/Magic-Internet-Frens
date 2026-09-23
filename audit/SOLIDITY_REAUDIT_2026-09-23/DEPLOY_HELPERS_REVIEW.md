# Deployment helpers — full source traversals, execution verification pending

All functions, interfaces and run bodies read for the five scripts below.
No scripts broadcast or production transactions sent. Script source is not
proof of successful deployment, target-chain support or postconditions.

| File | Authority, lifecycle and remaining checks |
|---|---|
| DeployLaunchSniper.s.sol | Reads key/address configuration; checks hook.isOpener(gacha) before broadcasting. Deploys helper owned by broadcaster, sets exemption, sets presale finalizer. Actual hook requires owner/registry and presale requires original deployer. Multiple transactions are not atomic: later authority failure can leave a deployed helper or exemption without finalizer. Verify sold-out/ignition state, complete wiring and readback before launch. No identity/chain checks. |
| DeployMigrationVesting.s.sol | Derives vault from hook/engine unless explicitly supplied, deploys oracle and vesting, optionally sets gate for emergencyAdmin. VEST_WINDOW narrows uint256 to uint64 before constructor bound validation (oversized env value can wrap). Owner defaults timelock then deployer. Actual registry setClaimGate(nonzero) consumes emergency timelock, contrary to script's delay-irrelevant message; unset/unmatured emergency operation prevents enforcement. ENFORCE=false/nonadmin correctly report not enforced. Deployment sequence/readback needs local script integration. |
| DeployQuoteAssets.s.sol | Deploys two freely mintable test tokens and rotator, allowlists directly only if registry owner matches broadcaster; otherwise prints calls. Does NOT wire rotator into registry. No chain guard despite testnet-only documentation; no assumption that mocks are production assets is valid. Registry watermark rejection is possible for random mock address. Constant 1e18 scale for both assets requires unit/policy verification. No postcondition that rotation is ready. |
| DeployV4Core.s.sol | Requires code at constant Permit2 address, then creates real PoolManager and PositionManager with 300k unsubscribe cap and zero descriptor/WETH. Key optional; no-key msg.sender assumption for intended owner requires broadcaster simulation. Checks code presence, not Permit2 implementation. Commented transient/native-unit chain probes are historical claims, not executed checks in run. Zero optional dependencies require all downstream used action paths to avoid them. Ownership handoff remains manual. |
| FixFactoryWiring.s.sol | Always creates and configures a factory before either schedule or execute. New invocation creates a different address, therefore different encoded setFactory data and timelock operation hash. Documented rerun workflow cannot execute original scheduled operation. New factory ownership remains broadcaster; registry owner/timelock/proposer/executor roles not preflighted. Existing collections remain unchanged. No broadcast reproduction performed. |

Open final gates: local script simulations with real registry/timelock, operation
identity persistence, emergency gating, exact deployed source/compiler/library
hashes, sizes, chain/opcode dependencies, and interrupted multi-tx recovery.
No final sign-off.

## Final disposition (2026-09-23)

Final: DeployV4Core rehearsed on a local chain; FS-deployfactory-01 and FS-deployvesting-01 remain documented Lows. Signed off.
