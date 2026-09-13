#!/usr/bin/env bash
#
# Full-stack deploy to ARC TESTNET (chainId 5042002).
#
# This is deploy-testnet.sh's sibling. Read that one first: the TESTNET timing
# block is identical and documented there. THIS file documents only what is
# different about Arc, because that is the part nobody can reconstruct later.
#
# ── WHAT MAKES ARC DIFFERENT FROM SEPOLIA ───────────────────────────────────
#
#  1. THE GAS TOKEN IS A DOLLAR. Arc prices gas in USDC — but at EIGHTEEN
#     decimals, which was measured, not assumed: a 20 USDC faucet drop arrived
#     as 20000000000000000000 raw. That is the single most important fact here.
#     At 6 decimals every wei-denominated constant in this protocol would be
#     wrong by 1e12, and `PoolOps._sqrtPrice` cannot represent a quote below
#     TOTAL_SUPPLY/2^64 — on a 6-decimal native that is ~674 raw units, so a
#     normal seed would brick the launch behind `markConsumed` (audit Z-01).
#     At 18 decimals every seeding figure ports unchanged, and only the USD
#     MEANING of each number changes: 1 native is $1 here, not $2481.
#
#  2. THERE IS NO CHAINLINK. See NATIVE_PEGGED_USD below.
#
#  3. THERE WAS NO UNISWAP V4. It is deployed by deploy/DeployV4Core.s.sol; the
#     two addresses below are its output. A mock router was considered and
#     rejected: this protocol IS a v4 hook — the mint, the dividend split, the
#     perp mark and the keeper-free liquidation sweep all execute inside v4's
#     own swap lifecycle — so a mock would exercise none of the code that
#     matters and would prove nothing. Arc supports EIP-1153 transient storage
#     (probed with a raw TSTORE/TLOAD eth_call before committing to this), which
#     is the one thing v4 cannot be ported without.
#
#  4. NOTHING TO ARM. go-testnet.sh step 1 arms the PREVIOUS deployment's
#     break-glass so its LP can be recovered. Arc has no previous deployment, so
#     go-arc.sh has no such step.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/../contracts/solidity"

export FOUNDRY_PROFILE=cauldron

# ── UNISWAP V4, AS DEPLOYED BY US ───────────────────────────────────────────
# Output of: forge script deploy/DeployV4Core.s.sol --rpc-url $ARC_RPC --broadcast
# Verified after deploy: PositionManager.poolManager() points at this
# PoolManager, and PositionManager.permit2() is the canonical Permit2.
export POOL_MANAGER=0x6495341CF36fD399d74b58A5B125c07E15747d54
export POSITION_MANAGER=0x6EEA2bDee8c49168146f7015D717D9fe8fD252ae
DEPLOYER=0xc94400e90bb652afa02740bff50824e14069c133
ARC_RPC="${ARC_RPC:-https://rpc.testnet.arc.network}"

# ── ORACLE: THE NATIVE ASSET IS PEGGED, NOT FED ──────────────────────────────
# DeployLaunchpad's FEED_ETH_USD is a SEPOLIA Chainlink address. Left alone on
# Arc it is a codeless address, and `QuoteOracle.usdPerRawUnit` catches that
# revert and returns 0 — "cannot judge". The hook turns that into a ZERO volume
# contribution for every single trade, which quietly breaks two things at once:
# the mint ladder never advances, and `isDead` reads a busy generation as dying
# and pushes it toward a permissionless relaunch. The deploy would have looked
# completely successful.
#
# Pegging is the CORRECT model here rather than a shortcut: the gas token is
# USD-denominated, so there is no exchange rate to observe and a feed could only
# introduce a way to fail. Same reasoning already applied to USDG (PEG_STABLES).
export NATIVE_PEGGED_USD=true

# ── TESTNET ONLY — see deploy-testnet.sh for the full derivations ────────────
export TESTNET_GOV=true
export GOV_VOTING_PERIOD=120         # 2 min  (mainnet 3 days)
export GOV_COOLDOWN=60               # 1 min  (mainnet 7 days)
export GOV_EXECUTION_WINDOW=1800     # 30 min (mainnet 3 days)
export GOV_ENVELOPE_LIFETIME=7200    # 2 h    (mainnet 30 days)
export ROTATION_SLIP_BPS=2000        # 20%, the contract's own cap
export EMERGENCY_DELAY=600           # 10 min (mainnet 48 h)
export PERP_WARMUP=60                # 1 min  (mainnet 24 h)
export TWAP_WINDOW=5                 # 5 s    (mainnet 300 s)
export GENESIS_BONUS_BPS=1400
export SEED_WINDOW=300
export BADGE_ART=true
export PRESALE_MAXWALLET=1111

# ── THE BUDGET IS REAL MONEY HERE, SO IT IS WRITTEN DOWN ─────────────────────
# On Sepolia these numbers cost nothing. On Arc 1 native = $1, and the faucet
# gives 20. Measured: v4 core cost 0.175, and gas has been seen between 21.65
# and 41.65 gwei — so the gas line is budgeted at the HIGH end and then doubled,
# because running out of gas midway through a 14-contract deploy leaves a
# half-wired stack that has to be redeployed from scratch.
#
#   launchpad gas   ~114M @ 42 gwei      ~4.8
#   presale         1110 x 0.003         ~3.33   <- becomes the pool's depth
#   venue LP        VENUE_ETH             1.0
#   prime buy       PRIME_BUY_ETH         0.15
#   perp deploy     gas + insurance + PLV ~0.7
#   misc txs        ignite, sync, 5 mints ~0.5
#                                        -----
#                                        ~10.5 of 19.8 available
#
# PRESALE_PRICE 0.003, not Sepolia's 0.002: the presale balance IS the pool's
# seed liquidity, and the perp engine caps a position at `maxNotionalBps` (5%)
# of pool depth. 1110 x 0.003 = 3.33 native of depth -> ~0.166 max position.
export PRESALE_PRICE=3000000000000000  # 0.003 native
export VENUE_ETH=1000000000000000000    # 1.0

# ── PRIME_BUY_ETH IS DELIBERATELY 0 — IT WOULD BE STRANDED ───────────────────
# Ledger C (the seeder's tranche-by-tranche prime buy) is UNREACHABLE since
# seeding became full-range-always, and funding it parks money that can neither
# be spent nor recovered at relaunch:
#
#   * `SEED_BASE_WAD` is now 1e18, so in `PoolOps._seedActive` the base slice IS
#     the whole of ledger A and the function early-returns before
#     `ISeeder.startSeed` — correctly, since `startSeed` rejects
#     `baseWad > 0.5e18`. So `seeding` is never set on an atomic launch.
#   * `CauldronSeeder.primePending()` returns 0 unless `seeding` (:365), so the
#     prime tranche can never fire.
#   * BOTH registry paths to `withdrawAll` are gated on `ISeeder.seeding()`
#     (CauldronRegistry.sol:561 and :1636, "safe to skip … e.g. an atomic
#     generation" — an assumption that predates this change), so the unspent
#     budget is never swept back at relaunch either.
#
# `fundPrime` is a separate entry point from `startSeed`, which is why the money
# lands even though the campaign never begins. Measured: 0.15 parked on Arc and
# 0.1 ETH on Sepolia r43, both with `primeSpent == 0`.
#
# THIS COSTS NO FEATURE. The anti-snipe first-block market buy is `_greenCandle`,
# which `_seedActive` calls on BOTH branches (PoolOps.sol:398 and :465) and which
# does not touch ledger C at all.
#
# Recovery of what is already parked: `registry.rescueSeeder()` — onlyEmergency +
# timelocked, and notably NOT gated on `seeding`.
export PRIME_BUY_ETH=0

# MINT LADDER, RESCALED TO A DOLLAR NATIVE. This is the one figure that does NOT
# port across unchanged, because it is denominated in USD while everything else
# is denominated in native — and on Arc those two units are no longer 2481x
# apart. Sepolia used $8000 against a pool worth ~$5500 (a 1.45x ratio). The Arc
# pool is worth ~$3.33, so the same $8000 would need 2400x the pool's entire
# depth in volume and the mint counter would sit at zero forever, looking broken
# in exactly the way NATIVE_PEGGED_USD above exists to prevent.
#
# $30 keeps roughly the same "a few times pool depth" ratio, so the counter
# visibly advances on a few dollars of demo trading. `base` is derived inside the
# script as 8% of the mean, which preserves the ~25x first-to-last span at any
# target, so only this number needs changing.
export MINT_OUT_TARGET_USD=30000000000000000000  # $30 to mint out 3333

# HEARTBEAT_ETH / HEARTBEAT_USDC are deliberately NOT set: with both the native
# asset and USDG pegged, no aggregator is consulted and a heartbeat would be a
# value that nothing reads.
# ── end Arc block ───────────────────────────────────────────────────────────

ENVFILE=".env"
if [ -z "${PRIVATE_KEY:-}" ] && [ -f "$ENVFILE" ]; then
  PRIVATE_KEY=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi
[ -n "${PRIVATE_KEY:-}" ] || { echo "no PRIVATE_KEY (expected in contracts/solidity/.env)"; exit 1; }
export PRIVATE_KEY

#  REFUSE TO START IF THE BUDGET CANNOT COVER THE RUN. The failure mode this
#  prevents is the expensive one: a deploy that dies partway leaves orphaned
#  contracts and the whole thing starts over, having already burnt the gas.
BAL=$(cast balance "$DEPLOYER" --rpc-url "$ARC_RPC" 2>/dev/null | tail -1)
NEED=11000000000000000000  # 11 native, the table above rounded up
if [ -n "$BAL" ] && [ "$(python3 -c "print(1 if $BAL < $NEED else 0)")" = "1" ]; then
  echo "deployer has $(python3 -c "print($BAL/1e18)") native; this run needs ~$(python3 -c "print($NEED/1e18)")"
  echo "fund $DEPLOYER on Arc testnet first."
  exit 1
fi
echo "deployer balance: $(python3 -c "print($BAL/1e18)") native (\$$(python3 -c "print($BAL/1e18)"))"

forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
  --rpc-url "$ARC_RPC" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --slow
