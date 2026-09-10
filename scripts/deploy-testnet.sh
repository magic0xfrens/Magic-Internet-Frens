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
# 1110 x 0.0005 = 0.555 ETH of seed, leaving ~0.5 ETH to actually trade with.
# ASSUMES ./scripts/recover-round35.sh HAS RUN (~0.95 ETH back, taking the
# deployer to ~1.46). Without it there is only 0.507 and this will not fit —
# recover first. The OG allocation ratio is price-independent (bonusBps x
# TOTAL/ACTIVE), so the mint price is purely a depth/budget decision.
export PRESALE_PRICE=500000000000000 # 0.0005 ETH (mainnet 0.0062)
export PRESALE_MAXWALLET=1111        # (mainnet 100)

# OG allocation = 17.5% of the mint price. bonusBps = target x 8000; see the
# derivation in DeployLaunchpad.s.sol and the live-fork assertion in F12.
export GENESIS_BONUS_BPS=1400

# LEDGER C — the treasury's prime buy, spent by poke() in tranches across the
# seed window. Impact is (1 + e/E)^2 against deployed depth, so 0.05 into a
# 0.2222 ETH book lands at ~1.50x by completion. A lump sum at t0 would instead
# meet the thinnest book of the whole launch.
export PRIME_BUY_ETH=100000000000000000 # 0.10 ETH -> ~1.39x at full depth
export SEED_WINDOW=900                  # 15 min stream

# Liquidatoor badge art: ~167KB across 8 SSTORE2 writes, about 33M of the
# deploy's ~114M gas (~0.064 ETH here). Affordable once round 35 is recovered;
# set false and run deploy/DeployBadgeRenderer.s.sol later if gas spikes.
export BADGE_ART=true

# Venue LP depth for the ETH/USDG rotation route.
export VENUE_ETH=5000000000000000    # 0.005 ETH
export VENUE_USDG=15000000           # 15 USDG (6dp)
# ── end TESTNET block ───────────────────────────────────────────────────────

#  PRIVATE_KEY (exported by go-testnet.sh from the gitignored .env) wins when
#  set; otherwise fall back to the encrypted keystore, which is what a mainnet
#  deploy should always use.
if [ -n "${PRIVATE_KEY:-}" ]; then
  SIGNER=(--private-key "$PRIVATE_KEY")
else
  SIGNER=(--account deployer --sender "$DEPLOYER")
fi

forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  "${SIGNER[@]}" \
  --broadcast
