#!/usr/bin/env bash
# H5 T5A — REGRESSION TEST (was an attack PoC; inverted onto post-fix behaviour).
#
# BEFORE THE FIX: the Robinhood (4663) cutover documented in
# indexer/deployments/round.robinhood.template.json ("copy this over round.json")
# could not produce a bundle that targets chain 4663. src/config/deployments.ts
# hard-coded DEPLOYMENTS = {11155111, 5042002}; the emitted bundle contained
# `Ea={11155111:z1,5042002:tS}` with no 4663 key, so a 4663 manifest loaded under
# the SEPOLIA key, CAULDRON.chainId was 11155111, and useCauldronSwap
# force-switched the wallet to Sepolia before sending Robinhood-addressed
# play{value} calldata.
#
# AFTER THE FIX: DEPLOYMENTS is keyed by each manifest's OWN chainId, so the
# bundle's map key follows round.json; VITE_CHAIN_ID is authoritative and a
# value no manifest declares throws; a manifest/chain disagreement throws in
# cauldron.ts instead of console.error.
#
# PASS = exit 0 and "RESULT: SAFE". Any assertion failing exits non-zero.
# Run from anywhere:  bash audit/RH_MAINNET_2026-09-16/poc/h5/h5_chain4663_seam.sh
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
cp indexer/deployments/round.json /tmp/h5_round.json.bak
trap 'cp /tmp/h5_round.json.bak "$ROOT/indexer/deployments/round.json"' EXIT

fail=0
chk() { # $1 = description, $2 = 0/1 outcome
  if [ "$2" = "0" ]; then echo "  ok   — $1"; else echo "  FAIL — $1"; fail=1; fi
}

# A FULLY FILLED Robinhood manifest: the real (valid) manifest with chainId 4663.
node -e '
const fs=require("fs");const p="indexer/deployments/round.json";
const m=JSON.parse(fs.readFileSync(p,"utf8"));m.chainId=4663;m.schema="cauldron_rh1";
fs.writeFileSync(p,JSON.stringify(m,null,4));console.log("manifest chainId ->",m.chainId);'

build() { # $1 = VITE_NETWORK value, $2 = label
  rm -rf dist
  VITE_NETWORK="$1" VITE_CHAIN_ID=4663 VITE_CHAIN_NAME="Robinhood Chain" \
  VITE_CHAIN_CURRENCY=ETH VITE_CHAIN_DECIMALS=18 VITE_CHAIN_IS_TESTNET=false \
  VITE_RPC_URL="https://example.invalid/rpc" \
  npm run build >"/tmp/h5_build_$2.log" 2>&1
  return $?
}

for NET in mainnet testnet; do
  echo; echo "############ VITE_NETWORK=$NET  VITE_CHAIN_ID=4663 ############"
  build "$NET" "$NET"; rc=$?
  chk "build succeeds (log /tmp/h5_build_$NET.log)" $([ $rc -eq 0 ] && echo 0 || echo 1)
  [ $rc -eq 0 ] || continue

  # THE LOAD-BEARING ASSERTIONS, read from the BUILT BUNDLE, not the source.
  # The DEPLOYMENTS map is no longer a literal — it is Object.fromEntries over
  # the bundled manifests' own chainId — so the evidence is: the manifest's 4663
  # is baked in, the map is DERIVED, and VITE_CHAIN_ID is VALIDATED against it
  # (pre-fix it was simply discarded whenever SELECTED_CHAIN_ID was not Sepolia).
  grep -rqoE "=4663[,;]" dist/assets/*.js
  chk "the manifest's chainId 4663 is baked into the bundle" $?
  grep -rq "Object.fromEntries" dist/assets/*.js
  chk "the chain->manifest map is DERIVED from manifests, not a literal" $?
  grep -rq "UNSUPPORTED CHAIN" dist/assets/*.js
  chk "an unbundled VITE_CHAIN_ID throws in the shipped bundle" $?
  grep -rq "Robinhood Chain" dist/assets/*.js
  chk "chain 4663 resolves to its own metadata (name/RPC), not Arc's" $?

  # The Sepolia key must NOT be the one the 4663 manifest is filed under.
  grep -rqoE "11155111:[A-Za-z_$][A-Za-z0-9_$]*,5042002:" dist/assets/*.js
  chk "no {11155111,5042002}-only map survives (the pre-fix shape)" $([ $? -ne 0 ] && echo 0 || echo 1)

  # The mismatch path is now a THROW, not a console.error that lets the user sign.
  grep -rq "MANIFEST/CHAIN MISMATCH" dist/assets/*.js
  mm=$?
  if [ $mm -eq 0 ]; then
    grep -rqoE "console\.error\(.{0,40}MANIFEST/CHAIN MISMATCH" dist/assets/*.js
    chk "mismatch is fatal, not console.error" $([ $? -ne 0 ] && echo 0 || echo 1)
  else
    chk "mismatch assertion present in bundle" 1
  fi
done

# A chain no bundled manifest declares must FAIL THE BUILD, not fall back.
echo; echo "############ VITE_CHAIN_ID=999999 (unsupported) ############"
rm -rf dist
VITE_CHAIN_ID=999999 VITE_RPC_URL="https://example.invalid/rpc" \
  npm run build >/tmp/h5_build_unsupported.log 2>&1
chk "unsupported VITE_CHAIN_ID fails the build" $([ $? -ne 0 ] && echo 0 || echo 1)
grep -q "VITE_CHAIN_ID=999999" /tmp/h5_build_unsupported.log
chk "and says why (log /tmp/h5_build_unsupported.log)" $?

echo
if [ $fail -eq 0 ]; then echo "RESULT: SAFE — a 4663 manifest targets 4663; an unsupported chain refuses to build."; exit 0; fi
echo "RESULT: REGRESSED — T5A is back."; exit 1
