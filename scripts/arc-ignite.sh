#!/usr/bin/env bash
#
# ARC TESTNET, everything after deploy-arc.sh:
#   1. mint out the 1111-fren genesis presale (batched)
#   2. igniteCauldron  -> summons the pool with the presale's whole balance
#   3. DeployPerp      -> engine + vault, wired, insurance armed
#   4. syncGeneration  -> MANDATORY, see the note at step 4
#
# This is go-testnet.sh's Arc sibling, minus its step 1 (arming the PREVIOUS
# deployment's break-glass — Arc has no previous deployment) and minus its
# cleanup trap, which deletes contracts/solidity/.env on exit. That trap is
# correct for a one-shot Sepolia run and wrong here: the key is still needed for
# the perp deploy, the relaunch demo and any top-up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/.."

R="${ARC_RPC:-https://rpc.testnet.arc.network}"
DEP=0xc94400e90bb652afa02740bff50824e14069c133

# Addresses from the deploy-arc.sh run. Overridable so a redeploy needs no edit.
PRESALE="${PRESALE:-0x5ddCd156fc0ff37eC3dD20b53f070f7Ff8B4f48a}"
HOOK="${HOOK:-0x8864eE50a7fb9Ed8Dd8b78aA4BBfBaf3Aa9310cc}"
REGISTRY="${REGISTRY:-0x4e60D157E951898521A97dD5217e50D6187aB432}"
DIVIDEND="${DIVIDEND:-0x9D3BF0E3045e8a6642815bCE5F74564c4c033b40}"
TIMELOCK="${TIMELOCK:-0x95ab3D345e25A8B180Af3Ca6071ed3C595df8BcB}"
export POOL_MANAGER="${POOL_MANAGER:-0x6495341CF36fD399d74b58A5B125c07E15747d54}"

ENVFILE="contracts/solidity/.env"
PK=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "\r' || true)
[ -n "$PK" ] || { echo "no PRIVATE_KEY in $ENVFILE"; exit 1; }
W=(--rpc-url "$R" --private-key "$PK")

ACTUAL=$(cast wallet address --private-key "$PK")
[ "$(echo "$ACTUAL" | tr 'A-Z' 'a-z')" = "$(echo "$DEP" | tr 'A-Z' 'a-z')" ] \
  || { echo "signer mismatch: $ACTUAL != $DEP"; exit 1; }

say() { printf "\n\033[1m== %s\033[0m\n" "$*"; }
bal() { python3 -c "print(round($(cast balance "$DEP" --rpc-url "$R" | tail -1)/1e18, 4))"; }

say "balance before: $(bal) native"

# ── 1. MINT OUT ─────────────────────────────────────────────────────────────
# Batched because mint() loops _mint per token (~55k gas each) — 1111 in one
# call would not fit in a block. 250 per tx is ~14M gas.
LEAVE_UNMINTED="${LEAVE_UNMINTED:-0}"
say "1/4  minting out the presale (leaving $LEAVE_UNMINTED for a human)"
PRICE=$(cast call "$PRESALE" "PRICE()(uint256)" --rpc-url "$R" | tail -1 | awk '{print $1}')
REMAINING=$(cast call "$PRESALE" "remaining()(uint256)" --rpc-url "$R" | tail -1 | awk '{print $1}')
echo "   price=$PRICE wei  remaining=$REMAINING"
while [ "$REMAINING" -gt "$LEAVE_UNMINTED" ]; do
  TO_GO=$(( REMAINING - LEAVE_UNMINTED ))
  N=$(( TO_GO > 250 ? 250 : TO_GO ))
  VAL=$(python3 -c "print($PRICE*$N)")
  echo "   minting $N (value $VAL wei)"
  cast send "$PRESALE" "mint(uint256)" "$N" --value "$VAL" "${W[@]}" >/dev/null
  REMAINING=$(cast call "$PRESALE" "remaining()(uint256)" --rpc-url "$R" | tail -1 | awk '{print $1}')
  echo "   remaining=$REMAINING"
done

# ── 2. IGNITE ───────────────────────────────────────────────────────────────
if [ "$LEAVE_UNMINTED" != "0" ]; then
  say "2/4  SKIPPED — $LEAVE_UNMINTED fren(s) left for a human to mint from the UI"
else
  say "2/4  igniteCauldron -> summon"
  cast send "$PRESALE" "igniteCauldron()" "${W[@]}" >/dev/null
  echo "   summoned. token: $(cast call "$REGISTRY" 'currentToken()(address)' --rpc-url "$R" 2>/dev/null | tail -1 || echo '(read from the registry)')"
fi

# ── 3. PERP STACK ───────────────────────────────────────────────────────────
# POST-summon on purpose: the engine seeds its TWAP from the LIVE pool.
say "3/4  DeployPerp (engine + vault)"
( cd contracts/solidity
  FOUNDRY_PROFILE=cauldron \
  PRIVATE_KEY="$PK" \
  POOL_MANAGER="$POOL_MANAGER" \
  HOOK="$HOOK" REGISTRY="$REGISTRY" PRESALE="$PRESALE" DIVIDEND="$DIVIDEND" \
  TIMELOCK="$TIMELOCK" \
  PERP_WARMUP=60 \
  TWAP_WINDOW=5 \
  INSURANCE_SEED_WEI=60000000000000000 \
  PLV_SEED_ETH="${PLV_SEED_ETH:-300000000000000000}" \
  forge script deploy/DeployPerp.s.sol --tc DeployPerp \
    --rpc-url "$R" --private-key "$PK" --broadcast --slow
) 2>&1 | tee /tmp/arc-perp.txt | grep -E "^  [A-Za-z]+ *:|SUCCESSFUL" || true

PERP_ENGINE=$(grep -oE "PerpEngine *: 0x[0-9a-fA-F]{40}" /tmp/arc-perp.txt | tail -1 | grep -oE "0x[0-9a-fA-F]{40}" || true)

# ── 4. SYNC THE ENGINE TO THE LIVE GENERATION ───────────────────────────────
#  NOT OPTIONAL, AND IT FAILS SILENTLY IF SKIPPED. The engine is deployed with
#  `syncedToken == 0`, and `PerpSwapLib.swap` derives its swap DIRECTION from
#  `quoteIsCurrency0`, computed as `key.currency1 == syncedToken`
#  (PerpEngine.sol:1489). With a zero syncedToken that comparison inverts, so
#  every "long" executes as a SELL. Measured on Sepolia r42: a long received
#  25,038,379 raw units instead of ~4.5e25 and marked at ZERO — instantly
#  liquidatable. It does NOT revert, which is what makes it dangerous.
#
#  Permissionless, and refused while any position is open, so it must run HERE —
#  after the summon, before anyone trades. It also resets the TWAP ring, so opens
#  stay gated for twapWindow seconds afterwards.
#  `AlreadySynced` IS THE SUCCESS CASE HERE, not a failure. go-testnet.sh calls
#  syncGeneration because there the engine predates the summon; this script
#  deploys the engine AFTER it, so the engine adopts the live generation on its
#  own and the explicit call is redundant. Reporting that revert as "perps would
#  fill INVERTED" would be exactly backwards, so the state is VERIFIED by reading
#  `syncedToken` rather than inferred from the exit code either way.
if [ -n "$PERP_ENGINE" ]; then
  say "4/4  syncGeneration on $PERP_ENGINE"
  if OUT=$(cast send "$PERP_ENGINE" "syncGeneration()" "${W[@]}" 2>&1); then
    echo "   synced; perps warm up in twapWindow seconds"
  elif echo "$OUT" | grep -q "AlreadySynced"; then
    echo "   already synced (engine deployed post-summon) — nothing to do"
  else
    echo "   WARNING: syncGeneration failed for an unexpected reason:"
    echo "$OUT" | tail -3
  fi
  LIVE=$(cast call "$REGISTRY" 'currentToken()(address)' --rpc-url "$R" | tail -1)
  SYNCED=$(cast call "$PERP_ENGINE" 'syncedToken()(address)' --rpc-url "$R" | tail -1)
  if [ "$(echo "$LIVE" | tr 'A-Z' 'a-z')" = "$(echo "$SYNCED" | tr 'A-Z' 'a-z')" ]; then
    echo "   VERIFIED syncedToken == live token ($LIVE) — perps fill in the right direction"
  else
    echo "   FAIL: syncedToken=$SYNCED but live token=$LIVE. Do NOT trade; re-run syncGeneration."
    exit 1
  fi
else
  say "4/4  SKIPPED — could not read the PerpEngine address from /tmp/arc-perp.txt"
fi

say "balance after: $(bal) native"
echo
echo "Arc testnet deployment complete."
echo "  registry : $REGISTRY"
echo "  hook     : $HOOK"
echo "  engine   : ${PERP_ENGINE:-(unknown)}"
echo "  explorer : https://testnet.arcscan.app"
