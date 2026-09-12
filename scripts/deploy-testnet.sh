#!/usr/bin/env bash
#
# Full-stack Sepolia deploy, tuned for TESTING.
#
# Every value below that differs from mainnet is here, in one place, so the
# mainnet deploy is this file with the TESTNET block deleted — not a diff you
# have to reconstruct later.
set -e
#  Resolve our own directory BEFORE the cd. `$(dirname "$0")` is relative, so any
#  later `source "$(dirname "$0")/..."` breaks once we have changed directory —
#  which is exactly how the shared signer helper came to be unfindable here.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/../contracts/solidity"

export FOUNDRY_PROFILE=cauldron
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
DEPLOYER=0xc94400e90bb652afa02740bff50824e14069c133

# ── TESTNET ONLY — delete this whole block for mainnet ──────────────────────
# Governance timing. Mainnet is a 3-day vote and a 7-day cooldown; that cannot
# be exercised on a testnet, so the whole path is driveable in ~2 minutes here.
# TESTNET_GOV waives the contract's own 1-day floors and is refused unless set,
# so a mainnet deploy that forgets to remove these still gets safe values.
#
# WHY 120s IS THE WHOLE WAIT, not a stage of it. The contract paces the VOTE and
# nothing after it: once `execute` opens the envelope, `rotateSlice` is
# permissionless with NO per-slice cooldown, so all 12 slices of an envelope can
# land in consecutive blocks. Propose -> vote -> execute -> 96.8% converted is
# therefore ~2 min plus twelve transactions. COOLDOWN only gates the SECOND
# envelope, so it stays at 60s — long enough to be visible as a real constraint,
# short enough to demo twice.
export TESTNET_GOV=true
export GOV_VOTING_PERIOD=120         # 2 min  (mainnet 3 days)
export GOV_COOLDOWN=60               # 1 min  (mainnet 7 days)
export GOV_EXECUTION_WINDOW=1800     # 30 min (mainnet 3 days)
export GOV_ENVELOPE_LIFETIME=7200    # 2 h    (mainnet 30 days)

# ROTATION PRICE FLOOR. `QuoteRotator.rotationSlipBps` defaults to 300 (3%) and
# nothing ever set it, which made the rotation undemonstrable for a reason that
# had nothing to do with governance: the floor is ORACLE-derived, so a slice only
# clears it if the venue absorbs the trade without moving price ~3%. Against a
# full-range venue that needs the venue to be ~65x the slice.
#
# 20% is the contract's own cap (`setRotationSlipBps` reverts above 2000), so
# this is the widest a testnet can be and still exercise the real code path. It
# buys a ~6x smaller venue. DO NOT ship this on mainnet — a 20% floor is a 20%
# haircut an unlucky slice is allowed to take.
export ROTATION_SLIP_BPS=2000        # 20% (mainnet: leave unset -> 3%)

# Break-glass delay. 48h on mainnet is the "holders can exit at floor before
# anything moves" guarantee; 10 minutes here so LP recovery is testable.
# Zero is refused at deploy, deliberately.
export EMERGENCY_DELAY=600           # 10 min (mainnet 48 h)

# Presale price, which is ALSO the pool's seed liquidity: `igniteCauldron()` summons
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
# 300s, tuned for a live demo rather than a realistic launch. With the keeper
# poking every 20s that is ~15 placements of ~6% each - a visible notification
# roughly every 20 seconds for five minutes, instead of the same 15 steps spread
# thin over a quarter of an hour. Raise to 900+ for anything real.
export SEED_WINDOW=300                  # 5 min stream

# Liquidatoor badge art: ~167KB across 8 SSTORE2 writes, about 33M of the
# deploy's ~114M gas (~0.064 ETH here). Affordable once round 35 is recovered;
# set false and run deploy/DeployBadgeRenderer.s.sol later if gas spikes.
export BADGE_ART=true

# MINT LADDER. The collection mints out after this much VOLUME (USD, because the
# oracle denominates it). $2M is a mainnet figure - on a testnet you would forge
# a dozen frens and the counter would look stuck, so this is sized so the mint
# counter visibly moves while trading during a demo. `base` is derived as 8% of
# the mean, which keeps the ~25x first-to-last span at any target.
export MINT_OUT_TARGET_USD=8000000000000000000000   # $8k to mint out 3333

# ORACLE HEARTBEATS. Sepolia's Chainlink feeds are maintained loosely - the
# USDC/USD pair was measured 23.7h stale against the 12h mainnet heartbeat, which
# made QuoteOracle report 0 ("cannot judge") for USDG and would have made a
# USDG-quoted generation record no volume at all. Widened here only; the script's
# own defaults stay at the mainnet values.
export HEARTBEAT_ETH=21600      # 6h  (mainnet 4h)
export HEARTBEAT_USDC=172800    # 48h (mainnet 12h)

# PERP GATES. Both are correct-for-mainnet defaults that make a testnet perp look
# broken, and both were found the hard way — a live `openLong` reverting with an
# empty message during a recording.
#
#   warmup           24h on mainnet: no leverage until the pool's TWAP has real
#                    history to resist manipulation. Every other testnet timing
#                    was cut to minutes; this one was never added to that list.
#   insurance floor  the bad-debt buffer fills from trading FEES, so a fresh
#                    engine has none and every open reverts `InsurancePaused`.
#                    SEEDED rather than lowered — lowering the floor would make
#                    opens work by deleting the protection instead of meeting it,
#                    and that protection is what stops a liquidation shortfall
#                    being written against the stakers' vault.
export PERP_WARMUP=60                         # 1 min  (mainnet 24 h)
# LIQUIDATION-MARK TWAP. 5 min on mainnet is what makes the mark expensive to
# push — a liquidation fires off the AVERAGE, so a flash move cannot trigger it.
# On a testnet it just means the mark lags every trade by minutes, the panel
# shows a large mark-vs-spot divergence, and opens are refused as
# "would be liquidated the instant it opens".
#
# 5s, not the contract's 1s floor: Sepolia blocks are ~12s, so a 1s window often
# spans a SINGLE block and the mark becomes whatever the last swap left behind —
# which is precisely the manipulation the TWAP exists to prevent, and it would
# make liquidations look random rather than fast. NEVER ship this on mainnet.
export TWAP_WINDOW=5                          # 5 s (mainnet 300 s)
export INSURANCE_SEED_WEI=60000000000000000   # 0.06 ETH, just over the 0.05 floor

# VENUE LP DEPTH for the ETH/USDG rotation route.
#
# This was 0.005 ETH, which is why "rotate ETH into USDG" had never actually been
# watchable: the generation's LP holds ~0.4 ETH on the quote side, so one 25%
# slice is ~0.1 ETH swapping into a 0.005 ETH book — a ~95% haircut, rejected by
# the floor long before it could fill.
#
# `_seedActive` places FULL RANGE (PoolOps.sol:734-740 spans MIN_TICK..MAX_TICK),
# so this behaves like a constant-product pool: price impact is ~2x/X. For the
# 20% floor above, the largest slice needs x/X < ~10%, i.e. X > ~1 ETH. 1.5 ETH
# leaves headroom for the cumulative drift across all twelve slices, which is the
# part that bites — by slice 12 the venue has already been bought up eleven times.
#
# VENUE_USDG is deliberately UNSET: the deploy derives the USDG leg from the
# oracle so the pool opens AT the floor's own reference price. Hardcoding it
# encoded an ETH/USD guess that silently expired.
export VENUE_ETH=1500000000000000000 # 1.5 ETH  (recoverable: VenueSeeder.recover)
# export VENUE_USDG=                 # leave unset -> priced from the oracle
# ── end TESTNET block ───────────────────────────────────────────────────────

#  PRIVATE_KEY (exported by go-testnet.sh from the gitignored .env) wins when
#  set; otherwise fall back to the encrypted keystore, which is what a mainnet
#  deploy should always use.
#  A keystore PASSWORD FILE is preferred over a plaintext PRIVATE_KEY: the key
#  stays encrypted at rest and never exists in the clear on disk. --password is
#  not used because a flag value shows up in `ps` for every process on the box.
#  READ THE .env DIRECTLY. This used to rely on go-testnet.sh exporting
#  PRIVATE_KEY, so running THIS script on its own silently fell through to the
#  keystore branch and died on `Device not configured (os error 6)` — forge
#  asking for a password with no TTY to ask on. Loading it here means the script
#  works standalone, which is how it actually gets run.
PASSFILE="${KEYSTORE_PASSWORD_FILE:-/tmp/mif-keystore-pass}"
#  Relative to contracts/solidity, which this script cd'd into at the top.
ENVFILE=".env"
if [ -z "${PRIVATE_KEY:-}" ] && [ -f "$ENVFILE" ]; then
  PRIVATE_KEY=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi
if [ -s "$PASSFILE" ]; then
  SIGNER=(--account deployer --sender "$DEPLOYER" --password-file "$PASSFILE")
elif [ -n "${PRIVATE_KEY:-}" ]; then
  export PRIVATE_KEY
  source "$SCRIPT_DIR/lib/signer.sh"
  resolve_signer || exit 1
else
  SIGNER=(--account deployer --sender "$DEPLOYER")
fi

forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  "${SIGNER[@]}" \
  --broadcast
