#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Cauldron perp KEEPER bot (Sepolia testnet)
#
# Scans every open perp position and liquidates any that are underwater (at the
# TWAP mark). Keepers earn the keeper share of the liquidation penalty, so in
# production anyone runs this; here it lets you TEST the full liquidation flow:
#   1. open a leveraged position on the site
#   2. crash the price:  ./scripts/marketmaker.sh crash   (repeat / loop)
#   3. run this keeper   → it liquidates you → the site pops a RIP PnL card
#
# Usage:
#   ./scripts/keeper.sh          # one sweep
#   ./scripts/keeper.sh watch    # sweep every ~8s forever
#
# SECURITY: loads contracts/solidity/.env.sepolia FIRST, then resolves a signer
# through scripts/lib/signer.sh. With KEYSTORE_ACCOUNT set, no key touches argv;
# the raw-PRIVATE_KEY fallback says out loud that it does.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."

#  CONFIGURATION LOADS BEFORE ANYTHING READS IT.
#  PERP and REGISTRY used to be bound ABOVE this `source`, so the hardcoded
#  defaults won even when the env file named different addresses — and both
#  defaults pointed at a dead round. The keeper swept an engine that no longer
#  existed and reported "0 open" forever, which looks exactly like "nothing to
#  liquidate".
ENVFILE="contracts/solidity/.env.sepolia"
[ -r "$ENVFILE" ] || { echo "missing $ENVFILE — refusing to run on defaults"; exit 1; }
set -a; source "$ENVFILE"; set +a
RPC="${SEPOLIA_RPC:?set SEPOLIA_RPC}"

#  ADDRESSES COME FROM THE SHIPPED MANIFEST, and the env may only AGREE with it.
#  A stale address is not a degraded mode, it is a different deployment: fail.
manifest() { node -e "process.stdout.write(require('./indexer/deployments/round.json').contracts.$1 || '')"; }
PERP_MANIFEST="$(manifest perpEngine)"
REGISTRY_MANIFEST="$(manifest registry)"
PERP="${PERP_ENGINE:-$PERP_MANIFEST}"
# Registry — for materializeLegacyReserve() (deposits the hook's held live-buyback
# tokens into the reserve + credits the collection floor; permissionless + cheap).
REGISTRY="${CAULDRON_REGISTRY:-$REGISTRY_MANIFEST}"
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
[ -n "$PERP" ] && [ -n "$REGISTRY" ] || { echo "no perpEngine/registry in indexer/deployments/round.json"; exit 1; }
if [ "$(lc "$PERP")" != "$(lc "$PERP_MANIFEST")" ]; then
  echo "STALE PERP_ENGINE: env says $PERP, the manifest says $PERP_MANIFEST"; exit 1; fi
if [ "$(lc "$REGISTRY")" != "$(lc "$REGISTRY_MANIFEST")" ]; then
  echo "STALE CAULDRON_REGISTRY: env says $REGISTRY, the manifest says $REGISTRY_MANIFEST"; exit 1; fi

# shellcheck source=lib/signer.sh
source "scripts/lib/signer.sh"
resolve_signer || exit 1
KEEPER="$(cast wallet address "${SIGNER[@]}")"

# Sweep the hook's buffered legacy buybacks into the reserve so the LIVE collection
# floor reflects recent volume. No-op (returns 0) when nothing is pending, so it's
# always safe to call. Run alongside the liquidation sweep.
materialize() {
  if cast send "$REGISTRY" 'materializeLegacyReserve()' "${SIGNER[@]}" --rpc-url "$RPC" >/dev/null 2>&1; then
    echo "  ◆ materialized legacy buybacks → reserve/floor"
  fi
}

sweep() {
  local next; next=$(cast call "$PERP" 'nextId()(uint256)' --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  [ -n "$next" ] || { echo "  (engine unreachable)"; return; }
  local liquidated=0 scanned=0
  for (( id=1; id<next; id++ )); do
    # skip closed (trader == 0)
    local trader; trader=$(cast call "$PERP" 'positions(uint256)(address,bool,uint128,uint256,uint256,uint64,uint8,int256)' "$id" --rpc-url "$RPC" 2>/dev/null | head -1)
    [[ "$trader" =~ ^0x0000 ]] && continue
    scanned=$((scanned+1))
    local liq; liq=$(cast call "$PERP" 'isLiquidatable(uint256)(bool)' "$id" --rpc-url "$RPC" 2>/dev/null)
    if [ "$liq" = "true" ]; then
      echo "  ⚡ position #$id is UNDERWATER → liquidating…"
      if cast send "$PERP" 'liquidate(uint256)' "$id" "${SIGNER[@]}" --rpc-url "$RPC" >/dev/null 2>&1; then
        echo "     ✅ liquidated #$id (keeper reward → $KEEPER)"
        liquidated=$((liquidated+1))
      else
        echo "     ✗ liquidate #$id reverted (healthy at TWAP mark, or per-block cap)"
      fi
    fi
  done
  echo "  swept $scanned open · liquidated $liquidated  ($(date +%H:%M:%S))"
}

if [ "${1:-}" = "watch" ]; then
  echo "keeper watching (every ~8s, Ctrl+C to stop)… engine $PERP"
  n=0
  while true; do sweep; n=$((n+1)); [ $((n % 8)) -eq 0 ] && materialize; sleep 8; done
else
  echo "keeper single sweep · engine $PERP"
  sweep
  materialize
fi
