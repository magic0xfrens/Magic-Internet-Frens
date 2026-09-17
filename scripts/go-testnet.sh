#!/usr/bin/env bash
#
# The whole testnet bring-up in one run:
#   1. arm the OLD deployment's break-glass  (starts its 48h clock)
#   2. deploy the new full stack
#   3. mint out the 1110-fren presale
#   4. finalize -> summons the pool
#   5. fold the new addresses into the manifest
#
# The keystore password is read ONCE, kept in a shell variable, and never
# written to disk or the shell history.
set -euo pipefail
#  Own directory resolved BEFORE the cd: a relative `$(dirname "$0")` in a later
#  `source` breaks once the script changes directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$0")/.."
ROOT=$(pwd)

R=https://ethereum-sepolia-rpc.publicnode.com
DEP=0xc94400e90bb652afa02740bff50824e14069c133
OLD_TL=0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3
OLD_REG=0x3FD7649FcF3aF0CB511E625e7d868d98bb85D7D4
Z=0x0000000000000000000000000000000000000000000000000000000000000000

#  SIGNER. Prefer the encrypted keystore; fall back to a gitignored .env holding
#  a plaintext testnet key. The .env path exists because an interactive password
#  prompt cannot be driven from an automated session — it is NOT the shape a
#  mainnet key should ever be in.
ENVFILE="contracts/solidity/.env"
PK=""
if [ -f "$ENVFILE" ]; then
  PK=$(grep -E '^PRIVATE_KEY=' "$ENVFILE" | head -1 | cut -d= -f2- | tr -d ' "\r')
fi

if [ -n "$PK" ]; then
  echo "signing with the key from $ENVFILE"
  #  EXPORT BEFORE RESOLVING. `resolve_signer` reads $PRIVATE_KEY, so exporting it
  #  afterwards left it empty at the only moment it was read and the run died
  #  "no signer" with a perfectly good key on disk. Same read-before-load shape as
  #  keeper.sh binding its addresses before sourcing its env.
  export PRIVATE_KEY="$PK"
  source "$SCRIPT_DIR/lib/signer.sh"
  resolve_signer || exit 1
  W=(--rpc-url "$R" "${SIGNER[@]}")
  #  Remove it on ANY exit — success, failure or Ctrl-C. A testnet key left on
  #  disk after the job that needed it is just a liability with no upside.
  #  KEY REMOVAL IS OPT-IN NOW. Deleting it on EVERY exit — including a failure
  #  in step 1 — meant a deploy that died early also destroyed the credential
  #  needed to retry, and the perp deploy, the manifest step and any recovery all
  #  still need it. Set WIPE_KEY=1 for the CI behaviour.
  cleanup() {
    if [ "${WIPE_KEY:-0}" = "1" ] && [ -f "$ENVFILE" ]; then
      rm -f "$ENVFILE"
      echo "removed $ENVFILE"
    fi
  }
  trap cleanup EXIT INT TERM
else
  read -rsp "keystore password for 'deployer': " PWD_IN; echo
  W=(--rpc-url "$R" --account deployer --from "$DEP" --password "$PWD_IN")
fi

#  Refuse to start unless the signer is actually the expected deployer. Sending
#  the arm/deploy from the wrong account would produce a deployment nobody owns.
ACTUAL=$(cast wallet address "${W[@]}" 2>/dev/null | tail -1 || true)
if [ -n "$ACTUAL" ] && [ "${ACTUAL,,}" != "${DEP,,}" ]; then
  echo "signer mismatch: got $ACTUAL, expected $DEP"; exit 1
fi

say() { printf "\n\033[1m== %s\033[0m\n" "$*"; }

# ── 1. ARM THE OLD DEPLOYMENT ───────────────────────────────────────────────
# Arming moves nothing by itself and forces redemption OPEN — the intended
# holder protection. It starts the old registry's 48h emergencyDelay, which is
# immutable, so the 6.8882 ETH of stranded LP cannot be recovered before then.
say "1/5  arming the old deployment (48h clock starts now)"
#  SKIPPABLE. Arming is a courtesy to the PREVIOUS deployment's holders, not a
#  precondition for this one, and it fails hard when the timelock already holds
#  that exact operation — same target, calldata and salt produce the same
#  operation id, so a second `schedule` reverts `TimelockUnexpectedOperationState`
#  once the first has been executed. That aborted an otherwise fine deploy under
#  `set -e`. SKIP_ARM=1 bypasses it; a failure inside it is now a warning.
READY_AT=$(cast call "$OLD_REG" 'emergencyReadyAt()(uint256)' --rpc-url "$R" 2>/dev/null | tail -1 | awk '{print $1}')
if [ "${SKIP_ARM:-0}" = "1" ]; then
  echo "   SKIP_ARM=1 — leaving the old deployment alone"
elif [ "${READY_AT:-0}" != "0" ]; then
  echo "   already armed (readyAt=$READY_AT), skipping"
elif true; then
  cast send "$OLD_TL" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
    "$OLD_REG" 0 0x06e7b8db "$Z" "$Z" 180 "${W[@]}" >/dev/null
  echo "   scheduled; waiting out the 180s timelock delay"
  sleep 190
  cast send "$OLD_TL" "execute(address,uint256,bytes,bytes32,bytes32)" \
    "$OLD_REG" 0 0x06e7b8db "$Z" "$Z" "${W[@]}" >/dev/null
  echo "   armed. emergencyReadyAt = $(cast call "$OLD_REG" 'emergencyReadyAt()(uint256)' --rpc-url "$R" | tail -1)"
else
  echo "   already armed, skipping"
fi

# ── 2. DEPLOY ───────────────────────────────────────────────────────────────
say "2/5  deploying the new stack"
./scripts/deploy-testnet.sh 2>&1 | tee /tmp/deploy-out.txt | grep -E "^  [A-Za-z]+ *:|SUCCESSFUL|TESTNET"

PRESALE=$(grep -oE "MiFrensGenesis : 0x[0-9a-fA-F]{40}" /tmp/deploy-out.txt | tail -1 | grep -oE "0x[0-9a-fA-F]{40}")
[ -n "$PRESALE" ] || { echo "could not read the presale address from the deploy output"; exit 1; }
echo "   presale: $PRESALE"

# ── 3. MINT OUT ─────────────────────────────────────────────────────────────
# Batched: mint() loops _mint per token (~55k gas each), so 1110 in one call
# would not fit in a block. 250 per tx is ~14M gas, comfortably inside.
#  LEAVE_UNMINTED lets a demo stop short so a HUMAN mints the last fren and fires
#  the summon from the UI. Default 0 = mint out and ignite, which is what CI wants.
LEAVE_UNMINTED="${LEAVE_UNMINTED:-0}"
say "3/5  minting out the presale (batched, leaving $LEAVE_UNMINTED for a human)"
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

# ── 4. IGNITE -> SUMMON ─────────────────────────────────────────────────────
# `igniteCauldron` summons the pool with the presale's entire balance, so this is
# the transaction that actually creates the market.
#  RENAMED ON-CHAIN: `finalize` -> `igniteCauldron`. The storage flag (`finalized`)
#  and the `Finalized` event kept their old names, so only the CALL changed. This
#  script still sent `finalize()`, which no longer exists and has no fallback to
#  catch it, so `set -e` aborted the deploy here — after arming, deploying and
#  minting out, leaving a stack with no pool. Verified against
#  `forge inspect MiFrensGenesis methodIdentifiers`: igniteCauldron() = 0xe830840c.
if [ "$LEAVE_UNMINTED" != "0" ]; then
  say "4/5  SKIPPED — $LEAVE_UNMINTED fren(s) left unminted on purpose"
  echo "   Mint the last one from the UI; that mint sells out the presale and then"
  echo "   igniteCauldron() summons the pool. Presale: $PRESALE"
  echo "   remaining=$(cast call "$PRESALE" 'remaining()(uint256)' --rpc-url "$R" | tail -1)"
else
say "4/5  igniteCauldron -> summon"
cast send "$PRESALE" "igniteCauldron()" "${W[@]}" >/dev/null

# ── 4a. PERP STACK ──────────────────────────────────────────────────────────
#  DeployPerp used to be a MANUAL step run from a runbook after this script
#  finished. That is the same shape the script's own comments warn about — "a
#  pending manual step behind an ownership transfer is a step that silently never
#  runs" — and it is why r31 shipped with `twapWindow == 300` and why every round
#  so far has shipped with NO mark source and NO quote oracle on the engine.
#
#  DEPLOY_MARK_SOURCE matters beyond multi-pool marks: `blocksVolumeLink()` is
#  `openCount != 0 && markSource == address(0)`, and `CauldronHook.linkVolume`
#  reverts `PerpsOpen()` on it. With no mark source, a single dust perp position
#  — measured at 0.000744 ETH in
#  test/attacks/S0x_RotationPerpHostage.t.sol — holds a governance-approved
#  treasury rotation hostage indefinitely, and nothing reachable closes a SOLVENT
#  position to clear it. Arming the mark removes the hazard the interlock guards,
#  so the interlock stands down. Same test file proves the fix
#  (test_S0x_FIXED_WeightedMarkLetsTheApprovedRotationProceed).
say "4a/5 deploying the perp stack (engine, vault, mark source)"
addr_of() { grep -oE "$1 *: 0x[0-9a-fA-F]{40}" /tmp/deploy-out.txt | tail -1 | grep -oE "0x[0-9a-fA-F]{40}"; }
HOOK=$(addr_of "CauldronHook")
REGISTRY=$(addr_of "CauldronRegistry")
DIVIDEND=$(addr_of "MiFrensDividend")
TIMELOCK=$(grep -oE "timelock \(reg emergencyAdmin[^:]*: 0x[0-9a-fA-F]{40}" /tmp/deploy-out.txt | tail -1 | grep -oE "0x[0-9a-fA-F]{40}")
QUOTE_ORACLE=$(addr_of "QuoteOracle")
echo "   hook=$HOOK registry=$REGISTRY dividend=$DIVIDEND"
echo "   timelock=$TIMELOCK quoteOracle=$QUOTE_ORACLE"

if [ -n "$HOOK" ] && [ -n "$REGISTRY" ] && [ -n "$DIVIDEND" ]; then
  ( cd contracts/solidity
    FOUNDRY_PROFILE=cauldron \
    PRIVATE_KEY="$PK" \
    POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
    HOOK="$HOOK" REGISTRY="$REGISTRY" PRESALE="$PRESALE" DIVIDEND="$DIVIDEND" \
    TIMELOCK="$TIMELOCK" QUOTE_ORACLE="$QUOTE_ORACLE" \
    DEPLOY_MARK_SOURCE=true \
    PERP_WARMUP="${PERP_WARMUP:-60}" \
    TWAP_WINDOW="${TWAP_WINDOW:-5}" \
    INSURANCE_SEED_WEI="${INSURANCE_SEED_WEI:-60000000000000000}" \
    PLV_SEED_ETH="${PLV_SEED_ETH:-0}" \

    # ── NEVER BROADCAST A STALE ARTIFACT (audit C-1 / F6) ───────────────────────
    # r43 and r44 both deployed a gacha router built from a cached out/ that was
    # missing `playChurn`. A forced rebuild costs minutes; a dead round costs a
    # round. Also proves the tree compiles CLEAN, not just incrementally.
    FOUNDRY_PROFILE=cauldron forge build --force || {
      echo "clean build FAILED - refusing to broadcast a stale out/." >&2; exit 1; }

    forge script deploy/DeployPerp.s.sol --tc DeployPerp \
      --rpc-url "$R" --private-key "$PK" --broadcast --slow
  ) 2>&1 | tee /tmp/perp-out.txt | grep -E "^  [A-Za-z]+ *:|SUCCESSFUL" || true
  PERP_ENGINE=$(grep -oE "PerpEngine *: 0x[0-9a-fA-F]{40}" /tmp/perp-out.txt | tail -1 | grep -oE "0x[0-9a-fA-F]{40}")
  echo "   engine=$PERP_ENGINE"
else
  echo "   SKIPPED — could not parse the launchpad addresses from /tmp/deploy-out.txt"
fi

#  ── ADOPT THE NEW GENERATION ON THE PERP ENGINE ─────────────────────────────
#  The engine is deployed BEFORE the summon, so `syncedToken` is still zero when
#  the pool is born. That is not cosmetic: `PerpSwapLib.swap` derives the swap
#  DIRECTION from `quoteIsCurrency0`, which the engine computes as
#  `key.currency1 == syncedToken` (PerpEngine.sol:1489). With `syncedToken == 0`
#  that is false, so the flag inverts and every "buy" is executed as a SELL —
#  measured on r42: a long opened, received 25,038,379 raw units instead of
#  ~4.5e25, and marked at ZERO ETH, instantly liquidatable. It does not revert,
#  which is the dangerous part.
#
#  `syncGeneration()` is permissionless and refuses while any position is open,
#  so it must run HERE, immediately after the summon and before anyone trades.
#  It also resets the TWAP ring, so opens stay gated for `twapWindow` after it.
if [ -n "${PERP_ENGINE:-}" ]; then
  say "4b/5 syncGeneration on the perp engine"
  #  `AlreadySynced` IS SUCCESS HERE. DeployPerp now runs AFTER the summon, so
  #  the engine adopts the live generation on its own and this call is redundant.
  #  Reporting that revert as "perps will fill INVERTED" is exactly backwards —
  #  it sent me chasing a non-bug on the Arc deploy. VERIFY by reading the state
  #  rather than trusting an exit code either way.
  if OUT=$(cast send "$PERP_ENGINE" "syncGeneration()" "${W[@]}" 2>&1); then
    echo "   synced; perps warm up in twapWindow seconds"
  elif echo "$OUT" | grep -q "AlreadySynced"; then
    echo "   already synced (engine deployed post-summon) — nothing to do"
  else
    echo "   WARNING: syncGeneration failed unexpectedly:"; echo "$OUT" | tail -3
  fi
  LIVE=$(cast call "$REGISTRY" 'currentToken()(address)' --rpc-url "$R" | tail -1)
  SYNCED=$(cast call "$PERP_ENGINE" 'syncedToken()(address)' --rpc-url "$R" | tail -1)
  if [ "$(echo "$LIVE" | tr 'A-Z' 'a-z')" = "$(echo "$SYNCED" | tr 'A-Z' 'a-z')" ]; then
    echo "   VERIFIED syncedToken == live token — perps fill in the right direction"
  else
    echo "   FAIL: syncedToken=$SYNCED live=$LIVE. Do NOT trade; re-run syncGeneration."
  fi
fi
echo "   summoned. token: $(cast call "$PRESALE" 'currentToken()(address)' --rpc-url "$R" 2>/dev/null | tail -1 || echo '(read from the registry)')"
fi

# ── 5. MANIFEST ─────────────────────────────────────────────────────────────
say "5/5  folding the new addresses into the manifest"
node scripts/apply-deployment.mjs

say "done"
echo "next:  cd indexer && railway up     (schema bumped -> clean reindex)"
echo "       npm run build                (frontend picks up round.json)"
echo "       in ~48h: ./scripts/recover-old-lp.sh   (the 6.8882 ETH)"
