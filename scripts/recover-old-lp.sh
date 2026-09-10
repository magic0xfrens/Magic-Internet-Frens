#!/usr/bin/env bash
#
# Recover the OLD deployment's stranded LP (~6.8882 ETH).
#
# Run this once the 48h break-glass delay armed by go-testnet.sh has expired.
# The delay is `immutable` on the old registry, so there is no way to shorten it
# — it is the "holders can always exit at floor before anything moves"
# guarantee, and the old deployment was built with 48h.
#
# The ETH lands in the TIMELOCK (it is the registry's emergencyAdmin), not in
# your wallet, so the last step forwards it on.
set -euo pipefail
cd "$(dirname "$0")/.."

R=https://ethereum-sepolia-rpc.publicnode.com
DEP=0xc94400e90bb652afa02740bff50824e14069c133
TL=0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3
REG=0x3FD7649FcF3aF0CB511E625e7d868d98bb85D7D4
Z=0x0000000000000000000000000000000000000000000000000000000000000000

READY=$(cast call "$REG" "emergencyReadyAt()(uint256)" --rpc-url "$R" | tail -1 | awk '{print $1}')
NOW=$(date +%s)
if [ "$READY" = "0" ]; then
  echo "not armed. run ./scripts/go-testnet.sh (or arm-old-emergency.sh) first."; exit 1
fi
if [ "$NOW" -lt "$READY" ]; then
  echo "break-glass not ready yet."
  echo "  ready at : $READY  ($(date -r "$READY" 2>/dev/null || date -d "@$READY"))"
  echo "  remaining: $(( (READY - NOW) / 3600 ))h $(( ((READY - NOW) % 3600) / 60 ))m"
  exit 1
fi

read -rsp "keystore password for 'deployer': " PW; echo
W=(--rpc-url "$R" --account deployer --from "$DEP" --password "$PW")

# emergencyWithdrawLP(1) — removes generation 1's liquidity and sends the ETH
# and tokens to emergencyAdmin (the timelock).
CD=$(cast calldata "emergencyWithdrawLP(uint256)" 1)

echo "scheduling emergencyWithdrawLP(1)..."
cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  "$REG" 0 "$CD" "$Z" "$Z" 180 "${W[@]}" >/dev/null
echo "waiting out the 180s timelock delay..."
sleep 190
cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
  "$REG" 0 "$CD" "$Z" "$Z" "${W[@]}" >/dev/null

RECOVERED=$(cast balance "$TL" --rpc-url "$R")
echo "timelock now holds: $(cast from-wei "$RECOVERED") ETH"

# Forward it out of the timelock to the deployer. The timelock can call any
# target, so this is a plain value transfer scheduled through it.
echo "forwarding to the deployer..."
cast send "$TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  "$DEP" "$RECOVERED" 0x "$Z" "$Z" 180 "${W[@]}" >/dev/null
sleep 190
cast send "$TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
  "$DEP" "$RECOVERED" 0x "$Z" "$Z" "${W[@]}" >/dev/null

echo "deployer balance: $(cast balance "$DEP" --rpc-url "$R" --ether | tail -1) ETH"
