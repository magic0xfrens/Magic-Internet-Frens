#!/usr/bin/env bash
#
# Loosen (or tighten) the perp engine's PER-POSITION NOTIONAL CAP through the
# timelock.
#
# ── WHY THIS SCRIPT EXISTS ───────────────────────────────────────────────────
# `PerpEngine._checkNotional` (:1471) refuses any position whose ETH notional
# exceeds `activeEthDepth() * maxNotionalBps / BPS`. It is a per-position
# slippage cap measured against the UNISWAP POOL's liquidity — NOT against the
# vault. Staking into PerpVault raises `plv` (how much the vault can lend) and
# does nothing whatsoever to this ceiling, which is the single most confusing
# thing about the perp panel: a fully funded vault still refuses every trade.
#
# Measured on Sepolia r40:
#
#     activeEthDepth()   0.2513 E     <- the pool
#     maxNotionalBps     500 = 5%
#     => notional cap    0.01257 E
#     maxLeverage()      2
#     => max collateral  0.00628 E    <- and minCollateral is 0.003 E
#
# So the entire openable window was 0.003 - 0.0063 E, while the UI's size presets
# were 0.01 / 0.05 / 0.1 / 0.25. Every preset was above the ceiling, so from the
# frontend perps were unusable. The presets are now derived from the real ceiling
# (PerpPanel `quickSizes`), which makes trading POSSIBLE — this script is how you
# make it PLEASANT, by giving one position more of a thin pool to work with.
#
# ── THE TRADE-OFF, STATED PLAINLY ────────────────────────────────────────────
# This cap is the only thing bounding how far a single open can move the pool.
# Opens execute as real swaps (`_swapExactIn`) but are marked against the 5-min
# TWAP, so a position large enough to move spot away from the mark can be born
# underwater and liquidated in its own block. Raising the cap raises that risk in
# exact proportion. 20% of depth is a reasonable launch setting for a pool this
# thin; 50%+ on a 0.25 E pool is asking to be self-liquidated.
#
# ── WHY ALL SIX PARAMETERS ARE PASSED ────────────────────────────────────────
# `setRisk` is a BUNDLE setter: it writes warmup, ceiling, maintenanceBps,
# maxNotionalBps, maxOiBps and fundingRateBpsPerDay in one call. Supplying a
# partial set would silently reset the rest to whatever the caller guessed, so
# every value is READ FROM CHAIN STORAGE first and passed back unchanged except
# the one being changed. `maxLeverageCeiling` and `maxOiBps` are `internal` with
# no getters (:133, :140), hence the storage-slot reads.
#
# USAGE
#   scripts/set-perp-risk.sh                 # dry run: print current + proposed
#   scripts/set-perp-risk.sh 2000            # set maxNotionalBps to 20%
#   MAX_LEV_CEILING=5 scripts/set-perp-risk.sh 2000   # also raise the lev ceiling
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/.."

R="${RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
Z=0x0000000000000000000000000000000000000000000000000000000000000000
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

ENG=$(python3 -c "import json;print(json.load(open('indexer/deployments/round.json'))['contracts']['perpEngine'])")
call() { cast call "$1" "$2" ${3:-} --rpc-url "$R" 2>/dev/null | tail -1 | awk '{print $1}'; }
slot() { cast to-dec "$(cast storage "$ENG" "$1" --rpc-url "$R" 2>/dev/null | tail -1)"; }

# Owner is read from the engine, never assumed: pointing a governance call at a
# stale timelock is the mistake that is easiest to make and hardest to notice.
TL=$(call "$ENG" "owner()(address)")

#  Storage slots from `forge inspect PerpEngine storage-layout`. Re-check them
#  after ANY change to the contract's state variable order — a shifted slot here
#  reads a neighbouring field and writes it back as a risk parameter.
WARMUP=$(slot 9)
CEILING=$(slot 10)
MAINT=$(slot 11)
MAXNOT=$(slot 12)
MAXOI=$(slot 13)
FUNDING=$(slot 22)

DEPTH=$(call "$ENG" "activeEthDepth()(uint256)")
MINCOLL=$(call "$ENG" "minCollateral()(uint256)")
LEV=$(call "$ENG" "maxLeverage()(uint8)")

NEW_MAXNOT="${1:-$MAXNOT}"
NEW_CEILING="${MAX_LEV_CEILING:-$CEILING}"

echo "engine   : $ENG"
echo "owner    : $TL   (timelock, read from the engine)"
echo
printf "pool depth          %s wei\n" "$DEPTH"
printf "minCollateral       %s wei\n" "$MINCOLL"
printf "maxLeverage()       %sx\n" "$LEV"
echo
echo "current risk params (all read from chain storage):"
printf "  warmup              %s s\n"   "$WARMUP"
printf "  maxLeverageCeiling  %s\n"     "$CEILING"
printf "  maintenanceBps      %s\n"     "$MAINT"
printf "  maxNotionalBps      %s\n"     "$MAXNOT"
printf "  maxOiBps            %s\n"     "$MAXOI"
printf "  fundingRateBpsPerDay %s\n"    "$FUNDING"
echo
python3 - "$DEPTH" "$MAXNOT" "$NEW_MAXNOT" "$LEV" "$MINCOLL" <<'PY'
import sys
depth, old, new, lev, mincoll = (int(x) for x in sys.argv[1:6])
def window(bps):
    cap = depth * bps // 10_000
    return cap, (cap // max(lev, 1))
for label, bps in (("now", old), ("proposed", new)):
    cap, coll = window(bps)
    ok = "" if coll > mincoll else "   <-- BELOW minCollateral: NOTHING can open"
    print(f"  {label:9s} {bps:5d} bps -> notional {cap/1e18:.5f} E, "
          f"max collateral {coll/1e18:.5f} E at {lev}x{ok}")
PY
echo

# `setRisk` validation (:2004): ceiling 1-10, maint <= 5000, and every bps field
# <= 10000. Checked here so a bad value fails in the shell rather than as an
# opaque BadParam() three minutes into a timelock delay.
if [ "$NEW_MAXNOT" -gt 10000 ] || [ "$NEW_CEILING" -lt 1 ] || [ "$NEW_CEILING" -gt 10 ]; then
  echo "refusing: setRisk would revert BadParam (maxNotionalBps <= 10000, ceiling 1-10)"; exit 1
fi

if [ "$NEW_MAXNOT" = "$MAXNOT" ] && [ "$NEW_CEILING" = "$CEILING" ]; then
  echo "dry run only — nothing to change. Pass a new maxNotionalBps to apply, e.g."
  echo "  scripts/set-perp-risk.sh 2000"
  exit 0
fi

DATA=$(cast calldata "setRisk(uint256,uint256,uint256,uint256,uint256,uint256)" \
  "$WARMUP" "$NEW_CEILING" "$MAINT" "$NEW_MAXNOT" "$MAXOI" "$FUNDING")
echo "calldata : $DATA"

ENVFILE="contracts/solidity/.env"
if [ -z "${PRIVATE_KEY:-}" ] && [ -f "$ENVFILE" ]; then
  PRIVATE_KEY=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi
source "$SCRIPT_DIR/lib/signer.sh"
resolve_signer || exit 1

#  CHECK THE SIGNER CAN ACTUALLY DO THIS, BEFORE SPENDING THE DELAY.
#  `schedule` is PROPOSER_ROLE-gated and `execute` is EXECUTOR_ROLE-gated, and
#  OpenZeppelin's AccessControl reverts with an unhelpful custom error. Without
#  this, signing with the wrong key fails on `schedule` with an opaque revert —
#  or worse, schedules fine and fails three minutes later on `execute`, leaving a
#  live queued operation nobody was expecting. Ask first.
WHO=$(cast wallet address "${SIGNER[@]}" 2>/dev/null | tail -1)
[ -n "$WHO" ] || { echo "could not derive an address from the signer — is PRIVATE_KEY set and valid?"; exit 1; }
#  Role ids are READ FROM THE TIMELOCK, not computed. keccak256 of OZ's
#  "TIMELOCK_PROPOSER_ROLE" / "TIMELOCK_EXECUTOR_ROLE" strings does NOT match
#  what this contract returns (checked: 0x678eead... vs the live 0xb09aa5a...),
#  so this timelock does not derive its ids from those literals. Asking the
#  contract is both shorter and immune to that being true of any future one.
#  `call` cannot pass two arguments, so these use cast directly.
has_role() { cast call "$TL" "hasRole(bytes32,address)(bool)" "$1" "$2" --rpc-url "$R" 2>/dev/null | tail -1 | awk '{print $1}'; }
PROPOSER=$(call "$TL" "PROPOSER_ROLE()(bytes32)")
EXECUTOR=$(call "$TL" "EXECUTOR_ROLE()(bytes32)")
HAS_P=$(has_role "$PROPOSER" "$WHO")
HAS_X=$(has_role "$EXECUTOR" "$WHO")
echo "signer   : $WHO   proposer=$HAS_P executor=$HAS_X"
if [ "$HAS_P" != "true" ] || [ "$HAS_X" != "true" ]; then
  echo
  echo "refusing: $WHO does not hold both timelock roles."
  echo "  This call must be signed by the address that does. Check you pasted the"
  echo "  DEPLOYER key, not another wallet's."
  exit 1
fi
GAS=$(cast balance "$WHO" --rpc-url "$R" --ether 2>/dev/null | tail -1)
echo "gas      : $GAS ETH"

D=$(call "$TL" "getMinDelay()(uint256)")
echo
read -rp "schedule + execute through the timelock (${D}s delay)? [y/N] " yn
[ "$yn" = "y" ] || { echo "aborted."; exit 0; }

echo "scheduling…"
cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  "$ENG" 0 "$DATA" "$Z" "$Z" "$D" --rpc-url "$R" "${SIGNER[@]}" >/dev/null
echo "waiting ${D}s + 12s…"
sleep $(( D + 12 ))
echo "executing…"
cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
  "$ENG" 0 "$DATA" "$Z" "$Z" --rpc-url "$R" "${SIGNER[@]}" >/dev/null

echo "done. maxNotionalBps is now $(slot 12), maxLeverageCeiling $(slot 10)."
