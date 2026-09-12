#!/usr/bin/env bash
#
# Mint the genesis MiFrens presale — STOPPING ONE SHORT OF SOLD OUT.
#
# THE LAST MINT IS NOT OURS TO MAKE. Minting the final fren is what arms
# ignition, and igniting is what summons generation 1: the token, the pool, the
# green candle and the streaming schedule all land in that one transaction. That
# moment belongs to whoever is running the launch, so this script mints
# GENESIS_SUPPLY - 1 and stops. `TARGET` overrides it if a round genuinely wants
# something else.
#
# Batched because MAX_PER_WALLET is the only per-tx limit that matters here, and
# a batch of 250 is comfortably inside the block gas limit while keeping the
# number of transactions (and therefore the number of chances to fail halfway)
# small.
#
# Usage:  ./scripts/mint-presale.sh [PRESALE_ADDRESS]
#         TARGET=1110 ./scripts/mint-presale.sh
set -euo pipefail
#  Own directory resolved BEFORE the cd: a relative `$(dirname "$0")` in a later
#  `source` breaks once the script changes directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/.."

R="${RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

PRESALE="${1:-$(python3 -c "import json;print(json.load(open('indexer/deployments/round.json'))['contracts']['presale'])")}"

ENVFILE="contracts/solidity/.env"
if [ -z "${PRIVATE_KEY:-}" ] && [ -f "$ENVFILE" ]; then
  PRIVATE_KEY=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi
[ -n "${PRIVATE_KEY:-}" ] || { echo "no PRIVATE_KEY (env or $ENVFILE)"; exit 1; }
source "$SCRIPT_DIR/lib/signer.sh"
resolve_signer || exit 1
W=(--rpc-url "$R" "${SIGNER[@]}")

num() { cast call "$PRESALE" "$1" --rpc-url "$R" | tail -1 | awk '{print $1}'; }

SUPPLY=$(num "GENESIS_SUPPLY()(uint256)")
PRICE=$(num "PRICE()(uint256)")
MINTED=$(num "minted()(uint256)")
TARGET="${TARGET:-$(( SUPPLY - 1 ))}"

echo "presale : $PRESALE"
echo "supply  : $SUPPLY   price: $(cast from-wei "$PRICE") ETH"
echo "minted  : $MINTED   target: $TARGET"

if [ "$MINTED" -ge "$TARGET" ]; then
  echo "already at or past the target - nothing to do."; exit 0
fi

NEED=$(( TARGET - MINTED ))
COST=$(python3 -c "print($NEED * $PRICE)")
echo "to mint : $NEED   cost: $(cast from-wei "$COST") ETH"
echo

BATCH="${BATCH:-250}"
while [ "$MINTED" -lt "$TARGET" ]; do
  N=$(( TARGET - MINTED ))
  [ "$N" -gt "$BATCH" ] && N=$BATCH
  VAL=$(python3 -c "print($N * $PRICE)")
  echo "  minting $N (have $MINTED / $TARGET)..."
  cast send "$PRESALE" "mint(uint256)" "$N" --value "$VAL" "${W[@]}" >/dev/null
  MINTED=$(num "minted()(uint256)")
done

echo
echo "minted  : $MINTED / $SUPPLY"
echo "remaining for YOU to mint: $(( SUPPLY - MINTED ))"
echo "then: igniteCauldron() from the frontend"
