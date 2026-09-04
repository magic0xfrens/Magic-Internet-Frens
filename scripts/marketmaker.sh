#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Cauldron market-maker / volume + pattern bot (Sepolia testnet)
#
# Generates real on-chain trading volume on the current iteration's V4 pool via
# the gacha router (buy = play with ETH, sell = play with token), so you can
# watch the candles move and test leverage trading against real price action.
#
# It can draw CLASSIC CHART PATTERNS by scripting buy/sell sequences:
#   uptrend  downtrend  pump  dump  chop  accumulate  distribute
#   head-shoulders  double-top  double-bottom  bull-div  rally  crash
#
# Usage (from repo root):
#   ./scripts/marketmaker.sh <pattern> [intensity] [step_delay_sec]
#   ./scripts/marketmaker.sh uptrend            # gentle uptrend
#   ./scripts/marketmaker.sh pump 3             # 3x size pump
#   ./scripts/marketmaker.sh head-shoulders     # draws an H&S top
#   ./scripts/marketmaker.sh loop chop          # run 'chop' forever
#   ./scripts/marketmaker.sh auto               # ★ CHAOS: random patterns +
#                                               #   perp seeding forever (leave
#                                               #   running while you test)
#   SEED_EVERY=0 ./scripts/marketmaker.sh auto  # chaos, volume only (no perps)
#
# SECURITY: sources .env.sepolia and uses $PRIVATE_KEY by name only (never printed).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."

# ── config (round-19) ──
GACHA="${GACHA:-0x13D8b35477A106882f43778E838704bdD137f885}"
TOKEN="${TOKEN:-0x125F6F988A681D0bA9288cce41D4d6b7478387df}"
PERP="${PERP_ENGINE:-0x26ae199E143d98be557Eaf89EF7764291bcc51e5}"
CONTRACTS_DIR="contracts/solidity"

# load key + rpc (never echo the key)
set -a; source "$CONTRACTS_DIR/.env.sepolia"; set +a
RPC="${SEPOLIA_RPC:?set SEPOLIA_RPC in .env.sepolia}"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"

BASE_ETH="${BASE_ETH:-0.03}"     # base buy size in ETH
INTENSITY="${2:-1}"              # size multiplier
DELAY="${3:-4}"                  # seconds between trades
APPROVED_FLAG="/tmp/.mm_approved_$TOKEN"

# ── helpers ──
_eth() { python3 -c "print(int(float($1)*1e18))"; }
POOL_MANAGER="${POOL_MANAGER:-0xE03A1074c86CFeDd5C142C4F04F1a1536e203543}"
POOL_ID="${POOL_ID:-0x8e367f8255a85bcf4b53d6fabe4da94b1f344766a94bd28e5e391504ad86f1d6}"
_gwei_price() {
  # REAL current spot (not the lagging TWAP): read slot0 from the PoolManager.
  local slot raw
  slot=$(cast keccak "$(cast abi-encode 'f(bytes32,uint256)' "$POOL_ID" 6)" 2>/dev/null)
  raw=$(cast call "$POOL_MANAGER" 'extsload(bytes32)(bytes32)' "$slot" --rpc-url "$RPC" 2>/dev/null)
  python3 -c "r=int('$raw',16); sp=r&((1<<160)-1); q=2**96; m=sp/q; print('%.1f gwei' % ((1/(m*m))*1e9))" 2>/dev/null || echo "?"
}

buy() {
  local eth; eth=$(python3 -c "print(round(float($BASE_ETH)*float($INTENSITY)*float($1),6))")
  echo "  🟢 BUY  ${eth} Ξ   (price ~$(_gwei_price))"
  cast send "$GACHA" 'play(uint256,uint256,uint256,uint256)' 0 0 0 0 \
    --value "$(_eth "$eth")" --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1 || echo "     (buy tx failed — likely RPC hiccup)"
}

_ensure_approved() {
  [ -f "$APPROVED_FLAG" ] && return 0
  echo "  … approving router to sell \$GNOME (one-time)"
  cast send "$TOKEN" 'approve(address,uint256)' "$GACHA" \
    "$(python3 -c 'print(2**256-1)')" --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1 && touch "$APPROVED_FLAG"
}

sell() {
  _ensure_approved
  # sell a fraction of the deployer's token balance (arg = fraction, e.g. 0.15)
  local bal; bal=$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  local amt; amt=$(python3 -c "print(int($bal*float($1)))")
  # bash can't compare 24-digit ints — use python for the >0 check
  python3 -c "import sys; sys.exit(0 if $amt>0 else 1)" || { echo "  (no token to sell)"; return 0; }
  echo "  🔴 SELL frac=$1  (price ~$(_gwei_price))"
  cast send "$GACHA" 'play(uint256,uint256,uint256,uint256)' "$amt" 0 0 0 \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1 || echo "     (sell tx failed)"
}

wait_step() { sleep "$DELAY"; }

# ── patterns (each is a sequence of buy/sell legs) ──
p_uptrend()     { for i in 1 1 1 1 1; do buy 1;    wait_step; sell 0.05; wait_step; done; }
p_downtrend()   { for i in 1 1 1 1 1; do sell 0.18; wait_step; buy 0.4;   wait_step; done; }
p_pump()        { for i in 1 2 3;     do buy "$i";  wait_step; done; }
p_dump()        { for i in 1 1 1;     do sell 0.3;  wait_step; done; }
p_chop()        { for i in 1 2 3 4 5 6; do if (( i % 2 )); then buy 0.8; else sell 0.12; fi; wait_step; done; }
p_accumulate()  { for i in 1 1 1 1 1 1; do buy 0.5; wait_step; done; }
p_distribute()  { for i in 1 1 1 1 1 1; do sell 0.1; wait_step; done; }
p_rally()       { buy 1; wait_step; buy 2; wait_step; buy 3; wait_step; buy 2; wait_step; }
p_crash()       { sell 0.25; wait_step; sell 0.3; wait_step; sell 0.4; wait_step; }

# left shoulder → head (higher) → right shoulder (lower) → break down
p_head_shoulders() {
  echo "▶ HEAD & SHOULDERS"
  buy 1.2; wait_step; sell 0.15; wait_step             # left shoulder up+down
  buy 2.2; wait_step; sell 0.22; wait_step             # head (higher high)
  buy 1.1; wait_step                                   # right shoulder (lower high)
  sell 0.35; wait_step; sell 0.35; wait_step           # neckline break → dump
}
p_double_top()  { buy 2; wait_step; sell 0.25; wait_step; buy 2; wait_step; sell 0.4; wait_step; }
p_double_bottom(){ sell 0.3; wait_step; buy 1.5; wait_step; sell 0.3; wait_step; buy 2.5; wait_step; }
# bullish divergence: price dips to a lower low, then strong reclaim
p_bull_div()    { sell 0.2; wait_step; buy 0.5; wait_step; sell 0.25; wait_step; buy 3; wait_step; buy 2; wait_step; }

# ── perp seeding: open small leveraged positions so there are always fresh
#    liquidatable targets for you to REKT (and earn a Liquidatoor badge). Random
#    side + leverage + a small collateral. These are meant to get liquidated as
#    the chaos loop swings price — that's the point. ─────────────────────────────
_rand() { python3 -c "import random;print(random.randint($1,$2))"; }
_randf() { python3 -c "import random;print(round(random.uniform($1,$2),4))"; }

seed_perp() {
  local side lev col
  side=$(_rand 0 1)                     # 0=long 1=short
  lev=$(_rand 2 3)                      # small leverage (depth-tier capped anyway)
  col=$(_randf 0.01 0.03)               # tiny collateral
  if [ "$side" = "0" ]; then
    echo "  🎪 SEED long  ${col}Ξ @ ${lev}x  (a fresh victim for liquidators)"
    cast send "$PERP" 'openLong(uint8,uint256)' "$lev" 0 \
      --value "$(_eth "$col")" --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1 || echo "     (open long failed — warmup/depth/dead?)"
  else
    echo "  🎪 SEED short ${col}Ξ @ ${lev}x  (a fresh victim for liquidators)"
    cast send "$PERP" 'openShort(uint8,uint256)' "$lev" 0 \
      --value "$(_eth "$col")" --private-key "$PRIVATE_KEY" --rpc-url "$RPC" >/dev/null 2>&1 || echo "     (open short failed)"
  fi
}

# ── AUTO / CHAOS: run forever, picking a random pattern each cycle with random
#    size + delay, occasionally seeding a perp position. This is the "leave it
#    running while I test the frontend" mode — organic volume, random up/down
#    swings, and a steady supply of liquidatable positions. ───────────────────
run_auto() {
  local seed_every="${SEED_EVERY:-4}"   # seed a perp roughly every N cycles (0=off)
  local cycle=0
  local pats=(uptrend downtrend pump dump chop rally crash head-shoulders double-top double-bottom bull-div accumulate distribute)
  echo "━━━ AUTO CHAOS mode · base=${BASE_ETH}Ξ · seed_every=${seed_every} · Ctrl+C to stop ━━━"
  while true; do
    cycle=$((cycle+1))
    INTENSITY="$(_randf 0.5 3)"         # random size each cycle
    DELAY="$(_rand 3 9)"                # random pacing
    local pat="${pats[$(_rand 0 $((${#pats[@]}-1)))]}"
    echo "▶ cycle #$cycle  pattern=$pat  intensity=${INTENSITY}x  delay=${DELAY}s"
    run_pattern "$pat"
    # occasionally seed a fresh leveraged position to be liquidated
    if [ "$seed_every" != "0" ] && [ "$(( cycle % seed_every ))" = "0" ]; then
      seed_perp
    fi
    sleep "$(_rand 2 6)"
  done
}

run_pattern() {
  local pat="$1"
  echo "━━━ pattern: $pat · base=${BASE_ETH}Ξ · intensity=${INTENSITY}x · delay=${DELAY}s ━━━"
  echo "    price before: $(_gwei_price)"
  case "$pat" in
    uptrend) p_uptrend ;; downtrend) p_downtrend ;;
    pump) p_pump ;; dump) p_dump ;; chop) p_chop ;;
    accumulate) p_accumulate ;; distribute) p_distribute ;;
    rally) p_rally ;; crash) p_crash ;;
    head-shoulders|hs) p_head_shoulders ;;
    double-top) p_double_top ;; double-bottom) p_double_bottom ;;
    bull-div) p_bull_div ;;
    *) echo "unknown pattern '$pat'"; echo "patterns: uptrend downtrend pump dump chop accumulate distribute rally crash head-shoulders double-top double-bottom bull-div"; exit 1 ;;
  esac
  echo "    price after:  $(_gwei_price)"
}

PATTERN="${1:-uptrend}"
if [ "$PATTERN" = "auto" ] || [ "$PATTERN" = "chaos" ]; then
  # ./scripts/marketmaker.sh auto        → random patterns + perp seeding forever
  # SEED_EVERY=0 ./scripts/marketmaker.sh auto   → volume only, no perp seeding
  run_auto
elif [ "$PATTERN" = "loop" ]; then
  LOOP_PAT="${2:-chop}"; INTENSITY="${3:-1}"; DELAY="${4:-4}"
  echo "looping '$LOOP_PAT' forever (Ctrl+C to stop)…"
  while true; do run_pattern "$LOOP_PAT"; done
else
  run_pattern "$PATTERN"
fi
echo "✅ done. Deployer: $DEPLOYER"
