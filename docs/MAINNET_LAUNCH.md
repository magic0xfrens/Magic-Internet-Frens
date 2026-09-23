# Robinhood Mainnet Launch — Runbook

The frontend targets **the chain the manifest itself declares**. `DEPLOYMENTS`
(`src/config/deployments.ts`) is keyed by each bundled manifest's own `chainId`,
so repointing `indexer/deployments/round.json` at chain 4663 is what makes the
app target 4663. `VITE_CHAIN_ID` is the authoritative override and **must** name
a chain a bundled manifest declares — anything else is a build failure
(`scripts/verify-manifest.mjs`) and a module-init throw, never a silent fallback.
A manifest whose `chainId` disagrees with the resolved chain throws in
`src/config/cauldron.ts` rather than logging: the old `console.error` let a user
sign Robinhood calldata with their wallet force-switched to Sepolia.

Cutover = deploy contracts + indexer, copy
`indexer/deployments/round.robinhood.template.json` over `round.json` and fill
it (including `quoteAssets`), set `VITE_CHAIN_ID=4663`, redeploy.

## Robinhood Chain params (VERIFIED on-chain 2026-09-15)
- chainId **4663** — confirmed three ways: live `cast chain-id`,
  `ArbSys.arbChainID()`, and `ethereum-lists/chains` `eip155-4663.json`.
- RPC **`https://rpc.mainnet.chain.robinhood.com`** (nitro v3.11.4-rc.3, ArbOS
  116, ~0.10 s blocks). ⚠️ The host this doc previously carried,
  `https://rpc.chain.robinhood.com`, **does not exist** — it refuses TLS
  (`handshake_failure`) from three independent TLS stacks. Do not use it.
- Explorer `https://robinhoodchain.blockscout.com` (Arbitrum-Orbit L2).
- Native currency: **real ETH, 18 decimals**.
- **Testnet is `46630`** (`https://rpc.testnet.chain.robinhood.com`). `46646`,
  which older revisions of these docs cited, is not a chain id at all.
- Overridable via `VITE_CHAIN_ID` / `VITE_RPC_URL` / `VITE_EXPLORER_URL` — the
  `VITE_ROBINHOOD_*` names this doc used to list are read by no code.

## Uniswap v4 on Robinhood (confirmed — Uniswap/contracts deployments/4663.md)
Uniswap v2/v3/v4 + UniswapX are LIVE on Robinhood. Canonical v4 addresses:
- **PoolManager**   `0x8366a39cc670b4001a1121b8f6a443a643e40951`
- **PositionManager** `0x58daec3116aae6d93017baaea7749052e8a04fa7`
- Permit2 `0x000000000022d473030f116ddee9f6b43ac78ba3`
- Universal Router `0x8876789976decbfcbbbe364623c63652db8c0904`
- StateView `0xf3334192d15450cdd385c8b70e03f9a6bd9e673b`
- V4Quoter `0x8dc178efb8111bb0973dd9d722ebeff267c98f94`

## Step-1 command (DeployLaunchpad) — infra filled in, YOU set the money/gov params
```bash
export PRIVATE_KEY=<deployer key, funded with real ETH on Robinhood>
export POOL_MANAGER=0x8366a39cc670b4001a1121b8f6a443a643e40951
export POSITION_MANAGER=0x58daec3116aae6d93017baaea7749052e8a04fa7

# ── DECIDE (real money) ──
export TIMELOCK_DELAY=172800        # 48h (audit rec up to 7d=604800). NOT 180.
export PRESALE_PRICE=111100000000000000  # 0.1111 ETH/fren public; the frenlist pays a tenth (0.01111).
#   Raise: 12.34321 ETH if all 1111 mint on the frenlist (the floor), plus
#   0.09999 ETH for every public mint, up to 123.4321 ETH all-public.
#   Frenlist (frenlist members + IMD workers who earned a spot):
#     node scripts/frenlist/add-imd-workers.mjs <our IMD job ids…>   # optional
#     node scripts/frenlist/build.mjs     # edits nothing; writes public/frenlist/<root>.json
#     deploy the site with that file, THEN presale.setDiscountRoot(root)
#   FRENLIST_ROOT / FRENLIST_SETTER set these at deploy (both optional).
#   Downstream, all forced by the RAISE (green-candle path, 80% active band).
#   These are the FLOOR case (12.34321 ETH, everyone on the frenlist); any
#   public mint moves every number up:
#     pool opens 12.709 gwei → settles 19.857 gwei (+56.25% candle) → FDV 15.429 ETH.
#   DEATH_THRESHOLD below is NOT auto-scaled — re-check it against the bigger pool.
export DEATH_THRESHOLD=1000000000000000000  # 1 ETH/24h vol floor to stay alive
export GUARDIAN=<gnosis safe>       # migration veto — a MULTISIG, not the EOA
export TREASURY=<treasury addr>     # defaults to deployer if unset
# (optional) GENESIS_BONUS_BPS=2000  LEGACY_BPS=4000  PRESALE_MAXWALLET=100

FOUNDRY_PROFILE=cauldron forge script deploy/DeployLaunchpad.s.sol:DeployLaunchpad \
  --rpc-url https://rpc.mainnet.chain.robinhood.com --broadcast --slow -vvv
```
After it mints out → anyone calls `finalize()` → gen-1 summons (token+pool+collection).
THEN run DeployPerp (§ below) and set `setTwapWindow(15)` + `warmup` via the timelock
(MIN_TWAP is now **1s**, so you can tune the mark as low as 1s live).

Post-mainnet governance handoff: grant the Timelock's proposer/executor/canceller
roles to the Gnosis Safe and REVOKE the deployer EOA (no redeploy needed).

## 1. Contracts → Robinhood mainnet
- [ ] Fund the deployer with real ETH on Robinhood.
- [ ] `DeployLaunchpad.s.sol` then `DeployPerp.s.sol` against `--rpc-url $ROBINHOOD_RPC`.
- [ ] Confirm the **V4 PoolManager** address on Robinhood (env `POOL_MANAGER`) —
      must be the canonical Uniswap v4 deployment on that chain, not the Sepolia one.
- [ ] Hand hook + engine ownership to the **Timelock** (script does this last).

## 2. Mainnet-safe parameters (DO NOT ship testnet values)
- [ ] **Timelock minDelay**: testnet 180s → **mainnet e.g. 7 days** (see audit r30 rec).
- [ ] **twapWindow**: testnet 30s → **mainnet 60–300s** (low-liq pool = more manipulation risk; 30s is a testnet-feel value).
- [ ] **Perp warmup** ≥ MIN_TWAP; set sane mainnet value.
- [ ] **Death threshold / relaunch** economics reviewed for real ETH.
- [ ] Remove/limit any **break-glass / emergency admin**; move to a **guardian multisig**.
- [ ] Confirm **SafeERC20** + genesis-fren ratify of `setSuccessor` (audit r30 mainnet recs).

## 3. Indexer → Robinhood mainnet (Ponder on Railway)
The indexer is fully manifest-driven (`indexer/deployments/round.json`): chainId,
addresses, blocks, poolIds AND the Postgres schema all come from it (`start.mjs`
reads `schema` → `ponder start --schema`). ponder.config.ts now **defaults the RPC
to Robinhood automatically when the manifest chainId is 4663** (chain-aware — an
unset PONDER_RPC_URL can't silently hit Sepolia nodes).
- [ ] Copy `deployments/round.robinhood.template.json` → `round.json`; fill every
      `<FILL>` from the DeployLaunchpad/DeployPerp broadcast logs + the summon tx
      (registry/hook/…/perpEngine/perpVault, blocks, gen-1 poolId, indexerUrl).
- [ ] Keep `schema` a NEW value (template uses `cauldron_rh1`) → forces a clean
      reindex on the new chain. (NEVER set schema/addresses as Railway env — env
      drift caused the r29-served-as-r31 incident.)
- [ ] Railway env: `DATABASE_URL` (Postgres), optionally a dedicated
      `PONDER_RPC_URL` (paid Robinhood RPC, comma-separate to rotate),
      `POLLING_INTERVAL_MS=1000` (sub-second L2 blocks).
- [ ] **Manually redeploy** the Railway indexer (it does not auto-redeploy on push).
- [ ] Verify `/health` cross-checks chain-vs-DB (staleness guard) and is on 4663.
- [ ] Put the public indexer URL in `round.json.indexerUrl` (frontend default) —
      `VITE_CAULDRON_INDEXER` is optional then.

## 4. round.json (single source of truth)
- [ ] Update `indexer/deployments/round.json`: `contracts.*` (registry/hook/gachaRouter/
      dividend/governor/presale/timelock/collectionLedger/poolManager), `blocks.deploy`,
      `genesisSupply`, `deathThresholdEth`, `indexerUrl`. Frontend + indexer both read this.

## 5. Vercel env (Production)
- [ ] `VITE_NETWORK=mainnet`  ← the flip
- [ ] `VITE_CAULDRON_INDEXER=<mainnet indexer URL>` (absolute https, NOT the site origin)
- [ ] `VITE_WALLETCONNECT_PROJECT_ID=<real id>` (currently placeholder → WC disabled)
- [ ] (optional) `VITE_ROBINHOOD_*` overrides if params differ from defaults.
- [ ] `VITE_DEX_URL` once a public DEX/pool page exists.

## 6. Ship + verify
- [ ] Redeploy Vercel; **Purge Cloudflare cache** (static assets cache 24h).
- [ ] Verify contracts on Blockscout.
- [ ] Smoke test: connect wallet → auto-add Robinhood Chain (WalletSelector map has it),
      genesis mint, swap, open/close a perp, open-guard (born-underwater) fires correctly.
- [ ] Confirm the perp open-guard + reasonable twapWindow so no self-rekt on open.

## Already done in code (frontend, shipped, testnet-safe)
- Single `VITE_NETWORK` switch → `ACTIVE_CHAIN` / `ACTIVE_CHAIN_ID` / `NETWORK_LABEL`.
- `CAULDRON` / `PRESALE` / `PERP` chainId, wallet switch, app store all follow it.
- Explorer/marketplace links network-aware (Blockscout on Robinhood, OpenSea on Sepolia).
- WalletSelector auto-adds Robinhood (chainId 4663) + Sepolia.
- Copy (chain-switch errors, guide/FrenHelper) network-aware.
