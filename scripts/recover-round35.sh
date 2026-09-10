#!/usr/bin/env bash
#
# Recover ROUND 35's liquidity (~0.95 ETH) before redeploying over it.
#
# WHY THIS ONE IS FAST AND THE OTHER IS NOT. The old deployment was built with a
# 48h break-glass delay and that value is `immutable`, so recover-old-lp.sh
# genuinely cannot run before 2026-09-12 09:05. Round 35 was deployed with the
# testnet EMERGENCY_DELAY of 600s, so the same guarantee costs ten minutes here.
#
# WHAT IT TAKES OUT. `emergencyWithdrawLP(1)` calls `_removeLiquidity(1)`, which
# unwinds the registry's own positions AND, because the seeder is still flagged
# `seeding`, calls `ISeeder.withdrawAll` — so the seeder's five streamed bands
# come back too, not just the reserve. The stream already completed (placedWad
# 1e18) after the pool was traded, so effectively all of the 0.8888 ETH seed plus
# the ETH side of the ~0.097 ETH that traded through it is in those positions.
#
# ── THIS KILLS ROUND 35 ──────────────────────────────────────────────────────
# Pulling the liquidity leaves the GNOME bought on round 35 with no market. That
# is the intended trade here — round 35 is being replaced — but it is worth
# saying out loud rather than discovering afterwards.
#
# The ETH lands in the TIMELOCK (the registry's emergencyAdmin), not in the
# wallet, so the last step forwards it on.
#
# Roughly 20 minutes end to end, almost all of it waiting out delays:
#   arm (180s timelock) -> break-glass (600s) -> withdraw (180s) -> forward (180s)
set -euo pipefail
cd "$(dirname "$0")/.."

R=https://ethereum-sepolia-rpc.publicnode.com
DEP=0xc94400e90bb652afa02740bff50824e14069c133
TL=0x69ab4554FCAfa1473E6F0eaF586e566f17883Eb3   # round-35 timelock (emergencyAdmin)
REG=0x94b16dc3b31fe2849f62d5b9a152dce4b480a2b9  # round-35 registry
Z=0x0000000000000000000000000000000000000000000000000000000000000000
ARM=0x06e7b8db                                   # armEmergency()

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

bal() { cast balance "$1" --rpc-url "$R" | tail -1 | awk '{print $1}'; }

echo "deployer before: $(cast from-wei "$(bal "$DEP")") ETH"

#  SIGNER, in order of preference. The whole sequence is ~20 minutes of sleeps,
#  so it has to run unattended — an interactive password prompt needs a TTY that
#  an agent session does not have.
#
#    1. A keystore PASSWORD FILE. Best option: the key stays encrypted at rest in
#       ~/.foundry/keystores/deployer and never exists on disk in the clear,
#       which a pasted PRIVATE_KEY does. `--password-file` rather than
#       `--password` on purpose — a flag VALUE is visible in `ps` to every
#       process on the box, a file path is not.
#    2. A gitignored plaintext testnet key, for when the passphrase is not to
#       hand. Delete it when the run finishes.
#    3. An interactive prompt, for a human at a terminal.
PASSFILE="${KEYSTORE_PASSWORD_FILE:-/tmp/mif-keystore-pass}"
ENVFILE="contracts/solidity/.env"
if [ -z "${PRIVATE_KEY:-}" ] && [ -f "$ENVFILE" ]; then
  PRIVATE_KEY=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi
if [ -s "$PASSFILE" ]; then
  W=(--rpc-url "$R" --account deployer --from "$DEP" --password-file "$PASSFILE")
elif [ -n "${PRIVATE_KEY:-}" ]; then
  W=(--rpc-url "$R" --private-key "$PRIVATE_KEY")
else
  read -rsp "keystore password for 'deployer': " PW; echo
  W=(--rpc-url "$R" --account deployer --from "$DEP" --password "$PW")
fi

READY=$(cast call "$REG" "emergencyReadyAt()(uint256)" --rpc-url "$R" | tail -1 | awk '{print $1}')

if [ "$READY" = "0" ]; then
  echo "1/4 arming the break-glass (180s timelock)..."
  cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
    "$REG" 0 "$ARM" "$Z" "$Z" 180 "${W[@]}" >/dev/null
  sleep 190
  cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
    "$REG" 0 "$ARM" "$Z" "$Z" "${W[@]}" >/dev/null
  READY=$(cast call "$REG" "emergencyReadyAt()(uint256)" --rpc-url "$R" | tail -1 | awk '{print $1}')
  echo "    armed; ready at $READY"
else
  echo "1/4 already armed; ready at $READY"
fi

NOW=$(date +%s)
if [ "$NOW" -lt "$READY" ]; then
  WAIT=$(( READY - NOW + 10 ))
  echo "2/4 waiting out the ${WAIT}s break-glass delay..."
  sleep "$WAIT"
else
  echo "2/4 break-glass already elapsed"
fi

echo "3/4 withdrawing generation 1's liquidity (180s timelock)..."
CD=$(cast calldata "emergencyWithdrawLP(uint256)" 1)
cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  "$REG" 0 "$CD" "$Z" "$Z" 180 "${W[@]}" >/dev/null
sleep 190
cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
  "$REG" 0 "$CD" "$Z" "$Z" "${W[@]}" >/dev/null

RECOVERED=$(bal "$TL")
echo "    timelock now holds: $(cast from-wei "$RECOVERED") ETH"
if [ "$RECOVERED" = "0" ]; then
  echo "    nothing recovered - stopping before the forward step."; exit 1
fi

echo "4/4 forwarding to the deployer (180s timelock)..."
cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  "$DEP" "$RECOVERED" 0x "$Z" "$Z" 180 "${W[@]}" >/dev/null
sleep 190
cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
  "$DEP" "$RECOVERED" 0x "$Z" "$Z" "${W[@]}" >/dev/null

echo
echo "deployer after: $(cast balance "$DEP" --rpc-url "$R" --ether | tail -1) ETH"
echo "next: ./scripts/deploy-testnet.sh"
