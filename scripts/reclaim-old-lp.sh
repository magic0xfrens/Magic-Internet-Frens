#!/usr/bin/env bash
# ============================================================================
# reclaim-old-lp.sh — recover value stranded in a SUPERSEDED Cauldron round.
#
# Why this exists: a retired round keeps real value in three places, and only
# one of them is obvious.
#   1. the generation's RESERVE position (a position NFT the registry owns)
#   2. on a PROGRESSIVE generation, the SEEDER's core band positions — there is
#      NO active position NFT (`generationPositionId == 0`), so anyone looking
#      only at position NFTs concludes the round is empty when it is not
#   3. loose ETH/token sitting on the seeder and on the registry
#
# `emergencyWithdrawLP(gen)` covers (1) and, on a progressive generation, also
# unwinds (2) — its `_removeLiquidity` calls `ISeeder.withdrawAll` while the
# seeder still reports `seeding()`. We then run `rescueSeeder` + `emergencySweep`
# to catch (3) and anything the first call left behind. Running all four is
# idempotent: each is a no-op when there is nothing left.
#
# DRY RUN BY DEFAULT. Nothing is broadcast unless you pass --execute.
#
#   ./scripts/reclaim-old-lp.sh                 # inspect only
#   PRIVATE_KEY=0x… ./scripts/reclaim-old-lp.sh --execute
#
# Env:
#   OLD_REGISTRY  registry to drain   (default: the round that follows r31)
#   GEN           generation to pull  (default: its currentGeneration)
#   RPC_URL       Sepolia RPC
#   PRIVATE_KEY   required only with --execute; must be the emergencyAdmin
# ============================================================================
set -euo pipefail
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

RPC_URL="${RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
OLD_REGISTRY="${OLD_REGISTRY:-0xF3d621392D8aaB7507E902cB2638d3bf934a4107}"
POSM="${POSM:-0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4}"
EXECUTE=0
[ "${1:-}" = "--execute" ] && EXECUTE=1

call() { cast call "$1" "$2" ${3:-} --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}'; }

echo "── superseded round ────────────────────────────────────────────"
echo "registry        : $OLD_REGISTRY"
GEN="${GEN:-$(call "$OLD_REGISTRY" 'currentGeneration()(uint256)')}"
ADMIN=$(call "$OLD_REGISTRY" 'emergencyAdmin()(address)')
DELAY=$(call "$OLD_REGISTRY" 'emergencyDelay()(uint256)')
SEEDER=$(call "$OLD_REGISTRY" 'seeder()(address)')
TOKEN=$(call "$OLD_REGISTRY" 'currentToken()(address)')
echo "generation      : $GEN"
echo "emergencyAdmin  : $ADMIN"
echo "emergencyDelay  : $DELAY s"
echo "seeder          : $SEEDER"
echo "live token      : $TOKEN"

echo
echo "── recoverable ─────────────────────────────────────────────────"
RES=$(call "$OLD_REGISTRY" 'generationReservePositionId(uint256)(uint256)' "$GEN")
ACT=$(call "$OLD_REGISTRY" 'generationPositionId(uint256)(uint256)' "$GEN")
echo "active posId    : $ACT $([ "$ACT" = "0" ] && echo '(progressive — liquidity is in the SEEDER, not an NFT)')"
if [ "$RES" != "0" ]; then
  echo "reserve posId   : $RES  liq=$(call "$POSM" 'getPositionLiquidity(uint256)(uint128)' "$RES")"
fi
if [ "$SEEDER" != "0x0000000000000000000000000000000000000000" ]; then
  echo "seeder seeding  : $(call "$SEEDER" 'seeding()(bool)')   ranges=$(call "$SEEDER" 'rangeCount()(uint256)')"
  echo "seeder ETH      : $(cast balance "$SEEDER" --ether --rpc-url "$RPC_URL") ETH"
fi
echo "registry ETH    : $(cast balance "$OLD_REGISTRY" --ether --rpc-url "$RPC_URL") ETH"

if [ "$EXECUTE" != "1" ]; then
  echo
  echo "DRY RUN — nothing broadcast. Re-run with --execute to recover."
  echo "You must send from the emergencyAdmin above ($ADMIN)."
  exit 0
fi

: "${PRIVATE_KEY:?PRIVATE_KEY required with --execute}"
SENDER=$(cast wallet address --private-key "$PRIVATE_KEY")
# NB: `${var,,}` is bash 4+; macOS ships bash 3.2, so lowercase via tr for portability.
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if [ "$(lc "$SENDER")" != "$(lc "$ADMIN")" ]; then
  echo "REFUSING: signer $SENDER is not the emergencyAdmin $ADMIN" >&2; exit 1
fi
BEFORE=$(cast balance "$SENDER" --rpc-url "$RPC_URL")

send() { echo "→ $*"; cast send "$@" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" >/dev/null || echo "   (no-op / reverted — continuing)"; }

# A non-zero delay means the action must be ARMED first and then waited out.
# (Post-audit builds require the arm at ANY delay — see finding F-19.)
if [ "$DELAY" != "0" ]; then
  echo "delay is ${DELAY}s → arming, then waiting"
  send "$OLD_REGISTRY" "armEmergency()"
  sleep $((DELAY + 5))
fi

send "$OLD_REGISTRY" "emergencyWithdrawLP(uint256)" "$GEN"   # reserve + seeder unwind
[ "$DELAY" != "0" ] && { send "$OLD_REGISTRY" "armEmergency()"; sleep $((DELAY + 5)); }
send "$OLD_REGISTRY" "rescueSeeder()"                        # loose seeder funds → registry
[ "$DELAY" != "0" ] && { send "$OLD_REGISTRY" "armEmergency()"; sleep $((DELAY + 5)); }
send "$OLD_REGISTRY" "emergencySweep(address)" "0x0000000000000000000000000000000000000000"
[ "$DELAY" != "0" ] && { send "$OLD_REGISTRY" "armEmergency()"; sleep $((DELAY + 5)); }
send "$OLD_REGISTRY" "emergencySweep(address)" "$TOKEN"

AFTER=$(cast balance "$SENDER" --rpc-url "$RPC_URL")
echo
echo "── done ────────────────────────────────────────────────────────"
echo "admin ETH before : $(cast from-wei "$BEFORE") ETH"
echo "admin ETH after  : $(cast from-wei "$AFTER") ETH"
echo "recovered token  : $(call "$TOKEN" 'balanceOf(address)(uint256)' "$SENDER")"
echo "(net of gas; the old token is only useful as a migration receipt)"
