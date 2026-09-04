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
# SECURITY: sources .env.sepolia, uses $PRIVATE_KEY by name only.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."

PERP="${PERP_ENGINE:-0x26ae199E143d98be557Eaf89EF7764291bcc51e5}"
# Registry — for materializeLegacyReserve() (deposits the hook's held live-buyback
# tokens into the reserve + credits the collection floor; permissionless + cheap).
REGISTRY="${CAULDRON_REGISTRY:-0x6629a99fbb485c36ee63eb1190486660234611b8}"
set -a; source "contracts/solidity/.env.sepolia"; set +a
RPC="${SEPOLIA_RPC:?set SEPOLIA_RPC}"
KEEPER="$(cast wallet address --private-key "$PRIVATE_KEY")"

# Sweep the hook's buffered legacy buybacks into the reserve so the LIVE collection
# floor reflects recent volume. No-op (returns 0) when nothing is pending, so it's
# always safe to call. Run alongside the liquidation sweep.
materialize() {
  if cast send "$REGISTRY" 'materializeLegacyReserve()' --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1; then
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
      if cast send "$PERP" 'liquidate(uint256)' "$id" --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1; then
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
