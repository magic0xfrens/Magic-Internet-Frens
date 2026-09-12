#!/usr/bin/env bash
# Gate, then deploy the full stack to Sepolia, then wire the off-chain side.
#
#   ./scripts/auto-deploy.sh --check      # gates only, deploys nothing (DEFAULT)
#   ./scripts/auto-deploy.sh --go         # gates, then deploys if they pass
#   ./scripts/auto-deploy.sh --go --skip-suite   # only if the suite was already verified clean
#
# It refuses to deploy unless the gates pass. That is the whole point: a testnet
# stack that ships a known regression teaches you nothing tomorrow.
#
# Signing: reads RECOVERY_PK from .env.recovery (gitignored), verifies it controls the
# expected deployer, bridges it to contracts/solidity/.env for the existing scripts, and
# removes that bridge file on exit — including on failure or Ctrl-C.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
RPC="${RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
DEPLOYER="${DEPLOYER:-0xc94400e90bb652afa02740bff50824e14069c133}"
BASELINE_COMMIT="1e98bb4"
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

MODE="check"; SKIP_SUITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --go) MODE="go" ;;
    --skip-suite) SKIP_SUITE=1 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

BRIDGE="$ROOT/contracts/solidity/.env"
BRIDGE_MADE=0
cleanup() { [ "$BRIDGE_MADE" = "1" ] && rm -f "$BRIDGE" && echo "[cleanup] removed the key bridge $BRIDGE"; }
trap cleanup EXIT INT TERM

say() { printf '\n=== %s ===\n' "$1"; }
die() { echo "ABORT: $*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# GATE 0 — signing material
# ─────────────────────────────────────────────────────────────────────────────
say "GATE 0  signer"
[ -r "$ROOT/.env.recovery" ] || die "no .env.recovery — the deployer key is required to deploy."
# shellcheck disable=SC1091
set -a; . "$ROOT/.env.recovery"; set +a
[ -n "${RECOVERY_PK:-}" ] || die "RECOVERY_PK is empty in .env.recovery."
case "$RECOVERY_PK" in 0x*) : ;; *) RECOVERY_PK="0x$RECOVERY_PK" ;; esac
DERIVED=$(cast wallet address --private-key "$RECOVERY_PK" 2>/dev/null | tr 'A-Z' 'a-z')
WANT=$(echo "$DEPLOYER" | tr 'A-Z' 'a-z')
[ -n "$DERIVED" ] || die "RECOVERY_PK is not a valid private key."
[ "$DERIVED" = "$WANT" ] || die "that key controls $DERIVED but the deployer is $WANT. Refusing."
BAL=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
[ -n "$BAL" ] || die "cannot read the deployer balance — RPC down? (an error is not a zero)"
BAL_ETH=$(python3 -c "print('%.6f' % (int('$BAL')/1e18))")
echo "signer verified: $DEPLOYER, balance ${BAL_ETH} ETH"
python3 -c "
import sys
if int('$BAL') < 3*10**18: sys.exit('ABORT: balance ${BAL_ETH} ETH is thin for a full deploy (badge art alone is ~33M gas). Top up first.')
" || exit 1

CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null)
[ "$CHAIN" = "11155111" ] || die "expected Sepolia (11155111), got '${CHAIN:-<no response>}'."

# ─────────────────────────────────────────────────────────────────────────────
# GATE 1 — build must be clean and every contract under EIP-170
# ─────────────────────────────────────────────────────────────────────────────
say "GATE 1  build + EIP-170"
cd "$ROOT/contracts/solidity"
export FOUNDRY_PROFILE=cauldron
export FORK_RPC="$RPC"
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4

forge build --sizes > /tmp/ad-sizes.log 2>&1 || {
  echo "--- first error ---"; grep -m3 -E "^Error|error\[" /tmp/ad-sizes.log; die "build failed."; }

OVER=$(awk -F'|' '/^\| [A-Za-z]/ {gsub(/[ ,]/,"",$4); if ($4 ~ /^-/) print $2" ("$4" B)"}' /tmp/ad-sizes.log \
       | grep -viE "test|mock|harness" || true)
if [ -n "$OVER" ]; then echo "$OVER"; die "contract(s) over the 24,576 B runtime limit."; fi
echo "build OK; no contract over EIP-170"

# ─────────────────────────────────────────────────────────────────────────────
# GATE 2 — the suite must show no NEW failures and no new skips
# ─────────────────────────────────────────────────────────────────────────────
# The 13 failures that were already red at $BASELINE_COMMIT. Anything else is ours.
BASELINE_FAILS="test_Inventory_200M
test_SurvivorsCanNeverBeClosed
test_SurvivorsUnclosableEvenWhenTheGateOpens
test_MinimumBookSizeAt12M
test_T02_POC_DustLegBurnsTheWholeMigrationMandate
test_T02_POC_FullMandateFlipsWithAThirdLeftBehind
test_T02_POC_PrimaryLegIsUnrotatableAfterTheFlip
test_T02_POC_MarkSourceDoesNotFollowTheRotation
test_T02_POC_MinCollateralBricksOpensOnASixDecimalQuote
test_T02_CONTROL_UnsquattedRotationPricesItself
test_T02_RETRACTED_ForeignInitializeOnTheDestinationKeyReverts
test_T02_CONTROL_LiveFeedRejectsThePushedVenue
test_T02_POC_FrozenCacheLetsAPushedVenueFillTheSlice"

if [ "$SKIP_SUITE" = "1" ]; then
  say "GATE 2  suite — SKIPPED by flag (you asserted it was already green)"
else
  say "GATE 2  full suite (~12 min)"
  forge test --threads 2 > /tmp/ad-suite.log 2>&1
  SUMMARY=$(grep -E "^Ran [0-9]+ test suites" /tmp/ad-suite.log | tail -1)
  [ -n "$SUMMARY" ] || { tail -20 /tmp/ad-suite.log; die "suite produced no summary line."; }
  echo "$SUMMARY"

  # regression set must be perfect
  XRES=$(forge test --match-path 'test/attacks/X*' 2>&1 | grep -E "^Ran [0-9]+ test suites" | tail -1)
  echo "regression set: ${XRES:-<no summary>}"
  echo "$XRES" | grep -q " 0 failed" || die "this run's own regression tests are not all green."

  # new failures = failing test names minus the baseline list
  grep -oE "\[FAIL[^]]*\] [A-Za-z0-9_]+" /tmp/ad-suite.log | awk '{print $NF}' | sort -u > /tmp/ad-fails.txt
  echo "$BASELINE_FAILS" | sort -u > /tmp/ad-baseline.txt
  NEW=$(comm -23 /tmp/ad-fails.txt /tmp/ad-baseline.txt || true)
  if [ -n "$NEW" ]; then
    echo "NEW failures (not red at $BASELINE_COMMIT):"
    while read -r t; do
      [ -z "$t" ] && continue
      echo "  - $t"
      grep -m1 -E "\[FAIL[^]]*\] $t" /tmp/ad-suite.log | sed 's/^/      /'
    done <<< "$NEW"
    die "the tree has regressions. Fix them, or re-run with --skip-suite only if you have judged each one."
  fi
  echo "no NEW failures vs baseline"

  SKIPPED=$(echo "$SUMMARY" | grep -oE "[0-9]+ skipped" | grep -oE "[0-9]+")
  [ "${SKIPPED:-0}" -le 1 ] || die "skip count grew to $SKIPPED (baseline 1) — coverage vanished silently."
  echo "skips: ${SKIPPED:-0} (baseline 1)"
fi

if [ "$MODE" = "check" ]; then
  say "GATES PASSED — nothing deployed (--check). Re-run with --go to deploy."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY
# ─────────────────────────────────────────────────────────────────────────────
say "DEPLOY  bridging the key for the existing scripts"
printf 'PRIVATE_KEY=%s\n' "$RECOVERY_PK" > "$BRIDGE"
chmod 600 "$BRIDGE"; BRIDGE_MADE=1
echo "wrote $BRIDGE (removed automatically on exit)"

cd "$ROOT"
say "DEPLOY  go-testnet.sh — arm-if-needed, deploy, mint out, finalize, fold the manifest"
echo "NOTE: step 1 arms the OLD registry only if emergencyReadyAt()==0, so an already-armed"
echo "      recovery (the 6.888 ETH maturing today) will be SKIPPED, not reset."
if ! ./scripts/go-testnet.sh 2>&1 | tee /tmp/ad-deploy.log; then
  die "deploy failed. Log: /tmp/ad-deploy.log — read it before retrying, the chain has state now."
fi

# ─────────────────────────────────────────────────────────────────────────────
# WIRE THE OFF-CHAIN SIDE
# ─────────────────────────────────────────────────────────────────────────────
say "WIRE  manifest"
MANIFEST="$ROOT/indexer/deployments/round.json"
[ -r "$MANIFEST" ] || die "no $MANIFEST — apply-deployment.mjs should have written it."
python3 - "$MANIFEST" <<'PY' || die "manifest is not valid JSON or is missing keys."
import json,sys
d=json.load(open(sys.argv[1]))
need=["registry","hook"]
missing=[k for k in need if not d.get(k)]
if missing: sys.exit("manifest missing: %s" % missing)
print("manifest ok: schema=%s registry=%s hook=%s" % (d.get("schema","?"), d["registry"], d["hook"]))
PY

say "WIRE  regenerating ABIs from the compiled artifacts"
cd "$ROOT/contracts/solidity"
for C in CauldronRegistry CauldronHook CauldronGovernor TreasuryGovernor QuoteRotator QuoteOracle \
         RedemptionExt PerpEngine PerpVault CauldronGachaRouter MiFrensDividend CollectionLedger; do
  OUT="$ROOT/indexer/abis/$C.json"
  if [ -f "$OUT" ]; then
    if forge inspect "$C" abi > "/tmp/ad-abi-$C.json" 2>/dev/null && [ -s "/tmp/ad-abi-$C.json" ]; then
      cp "/tmp/ad-abi-$C.json" "$OUT"; echo "  refreshed $C"
    else
      echo "  WARN could not inspect $C — left the existing ABI in place"
    fi
  fi
done

say "WIRE  frontend type-check and build"
cd "$ROOT"
npm run type-check > /tmp/ad-tsc.log 2>&1 && echo "type-check clean" \
  || { tail -15 /tmp/ad-tsc.log; die "type-check failed — the UI does not match the new ABIs."; }
npm run build > /tmp/ad-build.log 2>&1 && echo "build ok" \
  || { tail -15 /tmp/ad-build.log; die "frontend build failed."; }

say "VERIFY  post-deploy invariants"
REG=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['registry'])")
HOOK=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['hook'])")
ok=0; bad=0
chk() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "  OK   $1"; ok=$((ok+1)); else echo "  FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi
}
EMERG=$(cast call "$REG" "emergencyAdmin()(address)" --rpc-url "$RPC" 2>/dev/null | tr 'A-Z' 'a-z')
echo "  emergencyAdmin = ${EMERG:-<no response>}  (should be the timelock, NOT the deployer EOA)"
[ "$EMERG" = "$WANT" ] && { echo "  WARN emergencyAdmin is the deployer EOA, not a timelock"; bad=$((bad+1)); }
for PAIR in "hook:$HOOK"; do
  N="${PAIR%%:*}"; A="${PAIR#*:}"
  R=$(cast call "$A" "renounceOwnership()" --rpc-url "$RPC" 2>&1 | head -1)
  case "$R" in *revert*|*Error*|*error*) echo "  OK   $N renounceOwnership reverts";; *) echo "  FAIL $N renounceOwnership did NOT revert";; esac
done

say "DONE"
echo "deployed and wired. logs: /tmp/ad-{sizes,suite,deploy,tsc,build}.log"
echo "verify checks passed=$ok failed=$bad"
echo
echo "NEXT, by hand:"
echo "  cd indexer && railway up          # schema bumped -> clean reindex"
echo "  rm -f .env.recovery               # the plaintext key must not outlive the deploy"
echo "  6.888 ETH (r33/34) matures ~2026-09-12 20:05 UTC — recover it then."
echo "  0.919 ETH (old r38) is now safe to take: its successor exists."
