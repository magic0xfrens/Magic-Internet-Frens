#!/usr/bin/env bash
#
# Recover the CURRENT round's liquidity, ready for a fresh deploy over the top.
#
# Generalised from recover-round35.sh, which hardcoded that round's registry and
# timelock. Every redeploy needs this step, so hardcoding guaranteed the script
# was wrong for the round you actually wanted to recover — and pointing a
# break-glass at a stale registry is exactly the kind of mistake that is easiest
# to make and hardest to notice. Everything below is read from the manifest and
# from the chain.
#
# WHAT IT TAKES OUT. `emergencyWithdrawLP(gen)` calls `_removeLiquidity(gen)`,
# which unwinds the registry's own positions AND, while the seeder is still
# flagged `seeding`, calls `ISeeder.withdrawAll` — so the streamed bands and any
# un-streamed ledger-A come back too, not just the reserve. Ledger C (an unspent
# prime-buy budget) rides along with the seeder's ETH balance.
#
# ── THIS KILLS THE CURRENT ROUND ─────────────────────────────────────────────
# Pulling the liquidity leaves whatever was bought this round with no market.
# That is the point when you are replacing it, but it is worth saying out loud.
#
# The ETH lands in the TIMELOCK (the registry's emergencyAdmin), not in the
# wallet, so the last step forwards it on.
set -euo pipefail
#  Own directory resolved BEFORE the cd: a relative `$(dirname "$0")` in a later
#  `source` breaks once the script changes directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/.."

R="${RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
DEP="${DEPLOYER:-0xc94400e90bb652afa02740bff50824e14069c133}"
Z=0x0000000000000000000000000000000000000000000000000000000000000000
ARM=0x06e7b8db   # armEmergency()
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

REG=$(python3 -c "import json;print(json.load(open('indexer/deployments/round.json'))['contracts']['registry'])")
call() { cast call "$1" "$2" ${3:-} --rpc-url "$R" 2>/dev/null | tail -1 | awk '{print $1}'; }

TL=$(call "$REG" "emergencyAdmin()(address)")
GEN=$(call "$REG" "currentGeneration()(uint256)")
DELAY=$(call "$REG" "emergencyDelay()(uint256)")

echo "registry : $REG"
echo "timelock : $TL   (emergencyAdmin, read from the registry)"
echo "gen      : $GEN   break-glass delay ${DELAY}s"
echo "deployer : $(cast balance "$DEP" --rpc-url "$R" --ether | tail -1) ETH"

if [ "$GEN" = "0" ]; then
  echo "nothing summoned on this round — there is no LP to recover."; exit 0
fi

ENVFILE="contracts/solidity/.env"
if [ -z "${PRIVATE_KEY:-}" ] && [ -f "$ENVFILE" ]; then
  PRIVATE_KEY=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi
if [ -n "${PRIVATE_KEY:-}" ]; then
source "$SCRIPT_DIR/lib/signer.sh"
resolve_signer || exit 1
  W=(--rpc-url "$R" "${SIGNER[@]}")
else
  read -rsp "keystore password for 'deployer': " PW; echo
  W=(--rpc-url "$R" --account deployer --from "$DEP" --password "$PW")
fi

bal() { cast balance "$1" --rpc-url "$R" | tail -1 | awk '{print $1}'; }
tl_do() {  # schedule + wait + execute one call through the timelock
  local target="$1" value="$2" data="$3" label="$4"
  local d; d=$(call "$TL" "getMinDelay()(uint256)")
  echo "    $label (schedule, ${d}s, execute)"
  cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
    "$target" "$value" "$data" "$Z" "$Z" "$d" "${W[@]}" >/dev/null
  sleep $(( d + 12 ))
  cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
    "$target" "$value" "$data" "$Z" "$Z" "${W[@]}" >/dev/null
}

READY=$(call "$REG" "emergencyReadyAt()(uint256)")
if [ "$READY" = "0" ]; then
  echo "1/4 arming the break-glass"
  tl_do "$REG" 0 "$ARM" "armEmergency()"
  READY=$(call "$REG" "emergencyReadyAt()(uint256)")
  echo "    armed; ready at $READY"
else
  echo "1/4 already armed; ready at $READY"
fi

NOW=$(date +%s)
if [ "$NOW" -lt "$READY" ]; then
  echo "2/4 waiting out the $(( READY - NOW ))s break-glass delay"
  sleep $(( READY - NOW + 10 ))
else
  echo "2/4 break-glass already elapsed"
fi

echo "3/4 withdrawing generation $GEN's liquidity"
tl_do "$REG" 0 "$(cast calldata 'emergencyWithdrawLP(uint256)' "$GEN")" "emergencyWithdrawLP($GEN)"

RECOVERED=$(bal "$TL")
echo "    timelock holds: $(cast from-wei "$RECOVERED") ETH"
[ "$RECOVERED" = "0" ] && { echo "    nothing recovered — stopping before the forward."; exit 1; }

echo "4/4 forwarding to the deployer"
tl_do "$DEP" "$RECOVERED" 0x "forward $(cast from-wei "$RECOVERED") ETH"

echo
echo "deployer: $(cast balance "$DEP" --rpc-url "$R" --ether | tail -1) ETH"
echo "next: ./scripts/deploy-testnet.sh"
