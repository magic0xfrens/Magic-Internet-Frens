# Local-chain lane and production-script rehearsal (2026-09-23)

Local anvil only (chain 31337, `--hardfork cancun`, 100M block gas, EIP-170
enforced). No public network, no production key: every transaction was signed
with anvil's published test key or with throwaway keys `keccak("mifrens-rehearsal-wallet-N")`
funded by `anvil_setBalance`. Foundry broadcast output was redirected here with
FOUNDRY_BROADCAST; the owner's `contracts/solidity/broadcast/` is untouched.

Setup: Permit2 runtime placed at its canonical address from the compiled artifact
(`anvil_setCode`, zeroed immutables -> domain separator rebuilt per chain);
100 blocks mined; PoolManager given 10,000 ETH ambient inventory for the fork lane
(same explicit model as test/audit_full_scope/LocalLifecycleAdapters.t.sol).
A MockAggregator (ETH/USD $3,000, 8 dp) and a QuoteOracle owned by the deployer
were created with `cast` and passed as QUOTE_ORACLE.

## Production scripts executed (all ONCHAIN EXECUTION COMPLETE & SUCCESSFUL)

| Script | Log | Result |
|---|---|---|
| deploy/DeployV4Core.s.sol | deploy-v4core.log | PoolManager 0x5FbD…0aa3, PositionManager 0xe7f1…0512 |
| deploy/DeployLaunchpad.s.sol (defaults + QUOTE_ORACLE) | deploy-launchpad.log | full stack, ~121.3M gas estimated |
| deploy/DeployPerp.s.sol (PLV_SEED_ETH=20, DEPLOY_MARK_SOURCE=true) | deploy-perp.log | engine/vault/mark source, ownership to timelock |

Readback: registry.hook/hook.registry, owner=emergencyAdmin=timelock, 48h
emergency delay, factory, governor, igniter=presale, finalizer=deployer, hook
opener, internal pointers collectionLedger (slot 16) and redemptionExt (slot 44)
all correct. Deployed runtime lengths equal the audited artifacts: registry
24,553, hook 24,401, facet 16,334, Genesis 22,858.

## Lifecycle exercised (lifecycle.log)

1. Presale sell-out: 12 wallets, 1,111 minted, 123.4321 ETH held (5.6M gas per 100).
2. Finalizer ignition: summon gen 1, native quote, active/reserve NFTs 1/2, collection wired.
3. Router buy 0.5 ETH (dapp path): 2.43M tokens, 30 crystals committed.
4. Third-party resolveTickets(30): 28 NFTs minted to buyer, opened == 28.
5. DeployPerp; opens refused first with TokenDead (test fast-forward starved volume)
   then InsurancePaused (default DeployPerp seeds no insurance) — both intended guards;
   after volume + fundInsurance(2 ETH): 2x long opened and closed (0.426 ETH back of 0.5).
   Shorts refuse PlvInsufficient until token-side PLV exists (default deploy seeds ETH PLV only).
6. Governance: Genesis holders propose and vote; 3-day period; generation dies.
7. FS-relaunch-01 on deployed bytecode, open long in the book: relaunch at 6.0M /
   7.5M / 8.0M tx gas REVERTS at 72,961 gas with Panic(0x11) (the fix's checked
   reserve subtraction); relaunch with the eth_estimateGas limit (8,378,972, the
   dapp path) SUCCEEDS: gen 2, engine openCount 0, syncedGeneration 2, Genesis
   continued as iteration 2 with hook as minter.
8. Gen-2 router buy 1 ETH + resolve: Genesis 1,111 -> 1,139 (28 volume-tranche art).

Operator notes (Informational, configuration not code): default DeployPerp leaves
opens paused until insurance is funded and shorts unavailable until token PLV is
deposited; relaunch now needs >= ~8.4M tx gas even though it uses ~3.4M.
