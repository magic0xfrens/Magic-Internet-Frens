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
# Hook — for resolveTickets() (permissionless; settles committed crystals before
# their commit blockhash ages out of the EVM's 256-block window). Same
# manifest-is-truth rule as the two above.
HOOK_MANIFEST="$(manifest hook)"
HOOK="${CAULDRON_HOOK:-$HOOK_MANIFEST}"
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
[ -n "$PERP" ] && [ -n "$REGISTRY" ] || { echo "no perpEngine/registry in indexer/deployments/round.json"; exit 1; }
if [ "$(lc "$PERP")" != "$(lc "$PERP_MANIFEST")" ]; then
  echo "STALE PERP_ENGINE: env says $PERP, the manifest says $PERP_MANIFEST"; exit 1; fi
if [ "$(lc "$REGISTRY")" != "$(lc "$REGISTRY_MANIFEST")" ]; then
  echo "STALE CAULDRON_REGISTRY: env says $REGISTRY, the manifest says $REGISTRY_MANIFEST"; exit 1; fi
if [ -n "$HOOK" ] && [ "$(lc "$HOOK")" != "$(lc "$HOOK_MANIFEST")" ]; then
  echo "STALE CAULDRON_HOOK: env says $HOOK, the manifest says $HOOK_MANIFEST"; exit 1; fi

# shellcheck source=lib/signer.sh
source "scripts/lib/signer.sh"
resolve_signer || exit 1
KEEPER="$(cast wallet address "${SIGNER[@]}")"

# Sweep the hook's buffered legacy buybacks into the reserve so the LIVE collection
# floor reflects recent volume. No-op (returns 0) when nothing is pending, so it's
# always safe to call. Run alongside the liquidation sweep.
materialize() {
  #  DO NOT SWALLOW THE ERROR. `>/dev/null 2>&1` made a keeper that had been
  #  failing every call for days look exactly like a keeper with nothing to do.
  local out
  if out=$(cast send "$REGISTRY" 'materializeLegacyReserve()' "${SIGNER[@]}" --rpc-url "$RPC" 2>&1); then
    echo "  ◆ materialized legacy buybacks → reserve/floor"
  else
    echo "  ✗ materializeLegacyReserve FAILED: $(echo "$out" | tr '\n' ' ' | cut -c1-300)" >&2
  fi
}

# NOTE (logged, not fixed): this sweep is O(nextId) in `cast call`s per pass —
# every closed position is re-read forever. Fine at r45 volumes; it wants a
# cursor or an indexer-driven candidate list before it is left running unattended
# on a busy round.
#  ── RESOLVE COMMITTED CRYSTALS (audit B-1) ─────────────────────────────────
#  `resolveTickets` is PERMISSIONLESS (CauldronHook.sol:2482). Resolution reads
#  the commit block's hash, which the EVM keeps for only 256 blocks; a crystal
#  that ages out past that window is settled at its base outcome with NO pity
#  credit (GachaLib.sol:135,150,182), and it emits the same TicketLost a fair
#  loss does, so the player is never told why. The keeper did not call this at
#  all, which made honest crystals forfeit to nothing but inactivity. Bounded
#  per pass so one call can never run out of gas.
resolve() {
  local out
  [ -n "$HOOK" ] || { echo "  ✗ no hook in the manifest — cannot resolve crystals" >&2; return; }
  if out=$(cast send "$HOOK" 'resolveTickets(uint256)' 64 "${SIGNER[@]}" --rpc-url "$RPC" 2>&1); then
    echo "  ◆ resolved up to 64 committed crystals"
  else
    echo "  ✗ resolveTickets FAILED: $(echo "$out" | tr '\n' ' ' | cut -c1-300)" >&2
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
      #  Log the reason with the ID. A silent failure here is a position that
      #  stays underwater while the keeper reports a clean sweep.
      local lout
      if lout=$(cast send "$PERP" 'liquidate(uint256)' "$id" "${SIGNER[@]}" --rpc-url "$RPC" 2>&1); then
        echo "     ✅ liquidated #$id (keeper reward → $KEEPER)"
        liquidated=$((liquidated+1))
      else
        echo "     ✗ liquidate #$id FAILED (healthy at TWAP mark, per-block cap, or a real fault): $(echo "$lout" | tr '\n' ' ' | cut -c1-300)" >&2
      fi
    fi
  done
  echo "  swept $scanned open · liquidated $liquidated  ($(date +%H:%M:%S))"
}

# ── ROYALTY SWEEP (audit FG-2) ───────────────────────────────────────────────
# `RoyaltyRouter.sweep(address)` is permissionless BY DESIGN — "a royalty must
# not wait on a keeper" — but nothing anywhere called it, and the per-brew router
# address is published in no config, so an ERC20 royalty sat at an address nobody
# could find without reading the factory's deploy trace.
#
# The router IS discoverable: it is the live collection's EIP-2981 receiver. So
# resolve it from the chain rather than adding a manifest key that would go stale
# the moment a brew is redeployed. address(0) sweeps held ether (which is what a
# stipend-paying marketplace leaves behind); each quote asset sweeps its ERC20
# leg to the genesis dividend. Both are no-ops that revert "nothing" when there
# is nothing to move, so failures are silent by design.
COLLECTION="$(manifest collection)"
QUOTE_ASSETS="$(node -e "const r=require('./indexer/deployments/round.json');process.stdout.write((r.quoteAssets||[]).map(q=>q.address).filter(a=>a&&!/^0x0{40}$/i.test(a)).join(' '))")"

royalty_sweep() {
  [ -n "$COLLECTION" ] || return 0
  ROUTER="$(cast call "$COLLECTION" 'royaltyInfo(uint256,uint256)(address,uint256)' 1 1000000000000000000 --rpc-url "$RPC" 2>/dev/null | head -1)"
  case "$ROUTER" in 0x*) ;; *) return 0 ;; esac
  [ "$(lc "$ROUTER")" != "0x0000000000000000000000000000000000000000" ] || return 0
  for ASSET in 0x0000000000000000000000000000000000000000 $QUOTE_ASSETS; do
    if cast send "$ROUTER" 'sweep(address)' "$ASSET" "${SIGNER[@]}" --rpc-url "$RPC" >/dev/null 2>&1; then
      echo "  ◆ swept royalty $ASSET → dividend/legacy buffer (router $ROUTER)"
    fi
  done
}

if [ "${1:-}" = "watch" ]; then
  # ── THE GACHA WINDOW IS 256 BLOCKS, WHICH IS A TIME ONLY ONCE YOU KNOW THE
  #    CHAIN ────────────────────────────────────────────────────────────────
  #  A crystal's commit blockhash survives 256 blocks. That is ~51 min on
  #  Sepolia (12s blocks) but only ~25.6 SECONDS on Robinhood Chain 4663, whose
  #  blocks land about every 0.10s (measured — CHAIN_PROFILE.md §1). The old
  #  fixed "resolve every ~64s" cadence was justified in a comment by the
  #  Sepolia number and was 2.5x OUTSIDE the window on 4663: quiet-pool crystals
  #  aged past their blockhash and fell to GachaLib's deterministic fallback.
  #  (Ordinary traffic immunises the queue — any resolve landing while the hash
  #  is live pins the batch's seed — but a quiet pool is exactly the case with
  #  no traffic, which is when this keeper is the only thing running.)
  #
  #  So derive the cadence from the chain instead of asserting it. Aim to resolve
  #  at least 4x inside the window; never slower than the old 64s, never faster
  #  than 2s of pointless RPC.
  CHAIN_ID="$(cast chain-id --rpc-url "$RPC" 2>/dev/null || echo 0)"
  case "$CHAIN_ID" in
    4663|46630) BLOCK_MS=100 ;;   # Robinhood Chain — measured ~0.10s
    5042002)    BLOCK_MS=1000 ;;  # Arc testnet
    11155111)   BLOCK_MS=12000 ;; # Sepolia
    *)          BLOCK_MS=12000 ;; # unknown: assume the SLOW case, which is the
                                  # conservative one — it resolves too often, not
                                  # too rarely. Guessing fast would forfeit draws.
  esac
  WINDOW_S=$(( 256 * BLOCK_MS / 1000 ))
  SLEEP_S=$(( WINDOW_S / 4 )); [ "$SLEEP_S" -lt 2 ] && SLEEP_S=2; [ "$SLEEP_S" -gt 8 ] && SLEEP_S=8
  #  Target period: a quarter of the window, but never SLOWER than the 64s this
  #  script has always used on Sepolia — that cadence is fine there and players
  #  notice a crystal that sits unresolved. The cap only ever makes it faster.
  RESOLVE_S=$(( WINDOW_S / 4 )); [ "$RESOLVE_S" -gt 64 ] && RESOLVE_S=64
  RESOLVE_EVERY=$(( RESOLVE_S / SLEEP_S )); [ "$RESOLVE_EVERY" -lt 1 ] && RESOLVE_EVERY=1
  ROYALTY_EVERY=$(( 480 / SLEEP_S )); [ "$ROYALTY_EVERY" -lt 1 ] && ROYALTY_EVERY=1
  echo "keeper watching (chain $CHAIN_ID · ~${BLOCK_MS}ms blocks · gacha window ${WINDOW_S}s)"
  echo "  sweep every ${SLEEP_S}s · resolve every $((SLEEP_S * RESOLVE_EVERY))s · engine $PERP"
  n=0
  while true; do
    sweep; n=$((n+1))
    [ $((n % RESOLVE_EVERY)) -eq 0 ] && resolve
    [ $((n % RESOLVE_EVERY)) -eq 0 ] && materialize
    # Royalties trickle in from marketplace sales, so a slower cadence is plenty.
    [ $((n % ROYALTY_EVERY)) -eq 0 ] && royalty_sweep
    sleep "$SLEEP_S"
  done
else
  echo "keeper single sweep · engine $PERP"
  sweep
  resolve
  materialize
  royalty_sweep
fi
