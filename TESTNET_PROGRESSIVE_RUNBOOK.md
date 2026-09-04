# Testnet runbook — progressive-seed launch + full lifecycle (Sepolia)

Deploys the launchpad with the **in-swap progressive seeder** + facet-split registry
and drives the whole lifecycle: mintout → progressive summon → snipe probes →
perp stake/long/short/liquidate → death → relaunch (rounds 2/3) → vesting claim.

> Broadcasting sends real (testnet) transactions from **your** funded key — run each
> `--broadcast` yourself. Everything here is fork-verified; the multi-round gaps need
> real elapsed time (the death clock is on-chain), so it's phased.

All commands run from `contracts/solidity/` with `FOUNDRY_PROFILE=cauldron`.

## 0. Env

```bash
export PRIVATE_KEY=0x...                 # funded Sepolia deployer
export SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
export SEED_WINDOW=900                    # 15-min progressive window (0 = atomic)
# testnet convenience: short timelock + short brew lifetime
export TIMELOCK_DELAY=180
```

## 1. Deploy the launchpad (progressive) + perp

```bash
# Launchpad: hook, registry (+ RedemptionExt facet), governor, factory, dividend,
# gacha, ledger, and the CauldronSeeder (wired to hook via registry.setSeeder).
FOUNDRY_PROFILE=cauldron forge script deploy/DeployLaunchpad.s.sol \
  --rpc-url $SEPOLIA_RPC --broadcast -vvv
# Record from the logs: Timelock, MiFrensGenesis(=PRESALE), CauldronHook,
# CauldronRegistry, RedemptionExt, CauldronGovernor, MiFrensDividend,
# CauldronSeeder, seed window.

export HOOK=0x...  REGISTRY=0x...  PRESALE=0x...  DIVIDEND=0x...
export SEEDER=0x...  TIMELOCK=0x...

# Perp engine + vault (enables staking, longs/shorts, in-swap liquidation).
PLV_SEED_ETH=1000000000000000000 \
FOUNDRY_PROFILE=cauldron forge script deploy/DeployPerp.s.sol \
  --rpc-url $SEPOLIA_RPC --broadcast -vvv
# Record: PerpEngine, PerpVault. (This also hands hook+engine to the TIMELOCK.)
export ENGINE=0x...  VAULT=0x...
```

## 2. Mint out the presale → summon gen-1 (progressive)

The registry is owned by the presale; `finalize()` is what calls `summon()`. Mint the
whole MiFrens supply, then finalize. (Use the frontend, or `cast`:)

```bash
# price/among from DeployLaunchpad logs (default 0.0062 ETH each, 1111 supply).
cast send $PRESALE 'mint(uint256)' 100 --value <100*price> \
  --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY     # repeat/other wallets to sell out
cast send $PRESALE 'finalize()' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY
# → gen-1 summoned. Grab the token + poolId:
export TOKEN=$(cast call $REGISTRY 'currentToken()(address)' --rpc-url $SEPOLIA_RPC)
```

At this point the pool is live with only the **10% seed floor**; the rest of the
active tranche streams in over `SEED_WINDOW` as people trade (the hook pokes the
seeder in `afterSwap`). The 69× redemption reserve is fully placed from block 0.

## 3. Snipe / early-buyer probes (watch the anti-snipe)

Run `SnipeBuy` from a few wallets at different times across the window and compare
the logged **tokens-per-ETH** + **tick impact**. Early = thin book = brutal impact;
late = fully streamed = smooth.

```bash
# t≈0 (block-0 snipe, only the 10% floor live):
BUY_ETH=1000000000000000000 SEEDER=$SEEDER TOKEN=$TOKEN HOOK=$HOOK \
FOUNDRY_PROFILE=cauldron forge script deploy/SnipeBuy.s.sol \
  --rpc-url $SEPOLIA_RPC --broadcast -vvv   # use a DIFFERENT PRIVATE_KEY per sniper

# ...wait ~window/2, run again from another wallet (POKE=1 to nudge the stream)...
POKE=1 BUY_ETH=1000000000000000000 SEEDER=$SEEDER TOKEN=$TOKEN HOOK=$HOOK \
FOUNDRY_PROFILE=cauldron forge script deploy/SnipeBuy.s.sol --rpc-url $SEPOLIA_RPC --broadcast -vvv

# ...after the full window, run once more: much better fill, tiny impact.
```

Expected shape (matches `test/LaunchSnipe.t.sol` on the fork): a 1 ETH block-0 buy
gets ~8× fewer tokens and ~23× more tick impact than the same buy once fully seeded.
`SnipeBuy` buyers are NOT fee-exempt, so they also eat the anti-sniper surtax on top.

## 3b. FAST ROUNDS on live Sepolia (crank the death detector)

Rounds are gated by the on-chain death check (24h rolling volume) + `minLifetime`.
To cycle rounds in **minutes** instead of days on real Sepolia, lower both. These
are gov/emergency-admin params (the deploy sets `emergencyAdmin = timelock`, testnet
delay short). Via the timelock:

```bash
# minLifetime -> 60s (registry.setMinLifetime is onlyEmergency = timelock):
cast send $TIMELOCK 'schedule(address,uint256,bytes,bytes32,bytes32,uint256)' \
  $REGISTRY 0 $(cast calldata 'setMinLifetime(uint256)' 60) $(cast hz) $(cast hz) $TIMELOCK_DELAY \
  --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY
# ...wait TIMELOCK_DELAY seconds...
cast send $TIMELOCK 'execute(address,uint256,bytes,bytes32,bytes32)' \
  $REGISTRY 0 $(cast calldata 'setMinLifetime(uint256)' 60) $(cast hz) $(cast hz) \
  --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY

# death threshold -> tiny (hook.setDeathThreshold is onlyOwner = timelock after DeployPerp):
#   schedule/execute hook.setDeathThreshold(1) the same way.
```

A pool then reads "dead" almost as soon as its rolling 24h-volume bucket empties +
`minLifetime` elapses → `relaunch()` succeeds quickly. (Simplest of all: pass
`EMERGENCY_DELAY=0` + a low `DEATH_THRESHOLD` at deploy and keep the deployer as
`emergencyAdmin` on testnet, so you call `registry.setMinLifetime` / `hook.setDeathThreshold`
directly with no timelock dance.)

## 4. Perp — stake, long/short, liquidate

Perps need a **spot-straddling (two-sided)** book — which every progressive gen now
has **automatically**: the seeder lays a small two-sided full-range **BASE** at summon
(`SEED_BASE_WAD`, default 15%) alongside the single-sided streaming bands. So
`activeEthDepth()` is non-zero from block 0 — perps just work, no extra step, no
liquidity ever removed mid-life. (An atomic gen, `SEED_WINDOW=0`, also works and is
deeper.) Note the base is thin by design (anti-snipe priority) → a progressive gen
supports smaller perps; raise `SEED_BASE_WAD` for deeper perp capacity. Then:

- **Stake PLV**: `PerpEngine.fundPlv{value:}()` (ETH side) + `fundPlvToken(amt)` (token
  side, after approve) — or the community `PerpVault.depositEth{value:}()` / `depositToken`.
- **Open long / short**: `PerpEngine.openLong{value:col}(leverage, minOut)` /
  `openShort{value:col}(leverage, minEthOut, liqHint)`.
- **Liquidate**: `PerpEngine.liquidate(id)` once underwater at the TWAP mark, or pass a
  liquidation hint in a normal swap's `hookData` → the hook's `afterSwap` auto-liquidates
  it and mints the swapper a Liquidatoor badge. (Warmup + TWAP window are engine params;
  lower them on testnet for fast liquidations.)

## 5. Death → relaunch (round 2) + vesting

```bash
# Age the pool: no volume for the death window + past minLifetime. On testnet you can
# lower minLifetime via the timelock (registry.setMinLifetime is emergencyAdmin=TIMELOCK):
#   timelock.schedule(registry.setMinLifetime(60)) → wait TIMELOCK_DELAY → execute
# Then, once dead + a governance proposal exists:
cast send $REGISTRY 'relaunch()' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY
# → gen-2 born. The gen-1 seeder is torn down (withdrawAll) and its funds fold into
#   the reseed; gen-2 re-arms progressive (SEED_WINDOW still set) OR set SEED_WINDOW=0
#   via the registry to make gen-2 atomic.
```

**Vesting claim** (anti-dump): if `registry.setClaimGate(MigrationVesting)` is on (deploy
it via `deploy/DeployMigrationVesting.s.sol`), a gen-1 holder migrates by approving the
escrow + `startVest(1, amount)`, then `claim()` drips over the window (stakers instant).
Otherwise `registry.claimByBurn(1, amount)` migrates 1:1 instantly.

## 6. Round 3

Repeat step 5 (buy gen-2 into circulation → let it die → `relaunch()` → gen-3), and
re-run the snipe probes on gen-3's window to confirm the anti-snipe holds each round.

---

### What's already proven on the fork (run any time, no broadcast)

```bash
FORK_RPC=$SEPOLIA_RPC POOL_MANAGER=$POOL_MANAGER POSITION_MANAGER=$POSITION_MANAGER \
FOUNDRY_PROFILE=cauldron forge test --match-path \
  'test/{CauldronSummon,PerpEngine,CauldronSeeder,ProgressiveSeed,MigrationVestingGate,LaunchSnipe}.t.sol' -vv
```
- `ProgressiveSeed` — summon→stream→teardown→relaunch, partial-fill recovery, in-swap
  auto-stream, toggle-off + permissionless fallback, atomic opt-out.
- `LaunchSnipe` — the block-0 vs late impact numbers.
- `PerpEngine` — stake/long/short/liquidate/relaunch-migration.
- `MigrationVestingGate` — vesting drip + instant staker tier + gate enforcement.
