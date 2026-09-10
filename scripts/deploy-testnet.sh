#!/usr/bin/env bash
#
# Full-stack Sepolia deploy, tuned for TESTING.
#
# Every value below that differs from mainnet is here, in one place, so the
# mainnet deploy is this file with the TESTNET block deleted — not a diff you
# have to reconstruct later.
set -e
cd "$(dirname "$0")/../contracts/solidity"

export FOUNDRY_PROFILE=cauldron
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
DEPLOYER=0xc94400e90bb652afa02740bff50824e14069c133

# ── TESTNET ONLY — delete this whole block for mainnet ──────────────────────
# Governance timing. Mainnet is a 3-day vote and a 7-day cooldown; that cannot
# be exercised on a testnet, so a full rotation is driveable in ~6 minutes here.
# TESTNET_GOV waives the contract's own 1-day floors and is refused unless set,
# so a mainnet deploy that forgets to remove these still gets safe values.
export TESTNET_GOV=true
export GOV_VOTING_PERIOD=300         # 5 min  (mainnet 3 days)
export GOV_COOLDOWN=60               # 1 min  (mainnet 7 days)
export GOV_EXECUTION_WINDOW=1800     # 30 min (mainnet 3 days)
export GOV_ENVELOPE_LIFETIME=7200    # 2 h    (mainnet 30 days)

# Break-glass delay. 48h on mainnet is the "holders can exit at floor before
# anything moves" guarantee; 10 minutes here so LP recovery is testable.
# Zero is refused at deploy, deliberately.
export EMERGENCY_DELAY=600           # 10 min (mainnet 48 h)

# Presale price, which is ALSO the pool's seed liquidity: `finalize()` summons
# with the presale's whole balance (MiFrensGenesis.sol:576). Pricing this too
# cheaply is not a saving — it launches a pool too thin to open a perp against or
# rotate, and the test then measures nothing.
#
# 1110 x 0.0008 = 0.888 ETH of seed, ~0.52 ETH left over for actually trading.
export PRESALE_PRICE=800000000000000 # 0.0008 ETH (mainnet 0.0062)
export PRESALE_MAXWALLET=1111        # (mainnet 100)

# Venue LP depth for the ETH/USDG rotation route.
export VENUE_ETH=5000000000000000    # 0.005 ETH
export VENUE_USDG=15000000           # 15 USDG (6dp)
# ── end TESTNET block ───────────────────────────────────────────────────────

forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account deployer --sender $DEPLOYER \
  --broadcast
