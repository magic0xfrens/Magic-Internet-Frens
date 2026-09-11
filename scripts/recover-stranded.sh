#!/usr/bin/env bash
# Recover stranded ETH from past editions — the pots that need NO timelock and NO wait.
#
# Derived from audit/FINAL_BLIND_2026-09-11/STUCK_VALUE.md (Sepolia, chainId 11155111).
# Every call below was fork-simulated before being written here. This script re-checks
# live state before each send and SKIPS anything that no longer matches, so it is safe
# to re-run: an already-drained vault is skipped, not retried.
#
#   ./scripts/recover-stranded.sh                       # dry run: shows what it would do, sends nothing
#   ./scripts/recover-stranded.sh --send                # broadcast, prompting for the password (needs a real TTY)
#   ./scripts/recover-stranded.sh --send -p ~/.pw       # broadcast reading the keystore password from a file
#   ./scripts/recover-stranded.sh --send --pk           # broadcast using RECOVERY_PK from .env.recovery (no TTY, no password)
#
# If you see "Device not configured (os error 6)", foundry could not open a terminal to prompt
# for the keystore password. Either run this from a normal terminal, or use -p:
#     printf '%s' 'your-keystore-password' > ~/.cauldron-pw && chmod 600 ~/.cauldron-pw
#     ./scripts/recover-stranded.sh --send -p ~/.cauldron-pw
#     rm -f ~/.cauldron-pw        # delete it afterwards
#
# NOT included on purpose:
#   - r33/34 (6.888 ETH): already armed, matures ~2026-09-12 20:05 UTC. DO NOT re-arm:
#     running scripts/arm-old-emergency.sh would push it two more days out.
#   - r32 (5.547 ETH): needs arming first, then a 300 s delay.
#   - Round 38 (0.919 ETH): LIVE. Recovering it KILLS round 38. Do it at redeploy, not now.
set -uo pipefail

RPC="${RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
DEPLOYER="${DEPLOYER:-0xc94400e90bb652afa02740bff50824e14069c133}"
ACCOUNT="${ACCOUNT:-deployer}"
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

SEND=0
PWFILE=""
USE_PK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --send) SEND=1 ;;
    -p|--password-file) shift; PWFILE="${1:-}" ;;
    --pk) USE_PK=1 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

PWARGS=()
SIGNER_DESC="keystore account '$ACCOUNT' (interactive prompt)"
if [ -n "$PWFILE" ]; then
  if [ ! -r "$PWFILE" ]; then echo "ABORT: cannot read password file '$PWFILE'" >&2; exit 1; fi
  PWARGS=(--account "$ACCOUNT" --password-file "$PWFILE")
  SIGNER_DESC="keystore account '$ACCOUNT' (password file)"
elif [ "$USE_PK" = "1" ]; then
  ENVF="$(dirname "$0")/../.env.recovery"
  [ -r "$ENVF" ] || { echo "ABORT: cannot read $ENVF" >&2; exit 1; }
  # shellcheck disable=SC1090
  set -a; . "$ENVF"; set +a
  if [ -z "${RECOVERY_PK:-}" ]; then
    echo "ABORT: RECOVERY_PK is empty in $ENVF — paste the key after the '=' and save." >&2; exit 1
  fi
  case "$RECOVERY_PK" in 0x*) : ;; *) RECOVERY_PK="0x$RECOVERY_PK" ;; esac
  DERIVED=$(cast wallet address --private-key "$RECOVERY_PK" 2>/dev/null | tr 'A-Z' 'a-z')
  WANT=$(echo "$DEPLOYER" | tr 'A-Z' 'a-z')
  if [ -z "$DERIVED" ]; then
    echo "ABORT: RECOVERY_PK is not a valid private key (could not derive an address)." >&2; exit 1
  fi
  if [ "$DERIVED" != "$WANT" ]; then
    echo "ABORT: that key controls $DERIVED, but the funds are owned by $WANT." >&2
    echo "       Refusing to send from the wrong account. Check the key." >&2; exit 1
  fi
  PWARGS=(--private-key "$RECOVERY_PK")
  SIGNER_DESC="private key from .env.recovery (verified = $WANT)"
else
  PWARGS=(--account "$ACCOUNT")
fi

if [ "$SEND" = "1" ]; then
  echo "MODE: BROADCAST — transactions will be sent from $DEPLOYER"
  echo "SIGNER: $SIGNER_DESC"
else
  echo "MODE: DRY RUN — nothing will be sent. Re-run with --send to broadcast."
fi
echo "RPC:  $RPC"

CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null)
if [ "$CHAIN" != "11155111" ]; then
  echo "ABORT: expected Sepolia (11155111), got '${CHAIN:-<no response>}'." >&2
  exit 1
fi

GAS_START=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
echo "Gas balance: $(cast to-unit "${GAS_START:-0}" ether) ETH"
echo

# --- Pot 1: 11 old perp vaults. Gated only on share ownership: no owner, no timelock. ---
VAULTS=(
  0xFd34f4b2c87C7C7580b479d3Da08E458a10c085E
  0xabD9Dbb68edb2b36ca06a6A4c3b51FfC86F02772
  0x6Bb4D151cA52b95F68914a04F739ED85439B03a0
  0x00B07D1e07C1a39e7DA2BBD7C614805c4e2A4389
  0x06dB1ea16180d6D3aefED3B4B54fF962431Ce46E
  0x744cDC7E21CEEEc51ACDF9Bf393505cC7FAB4E78
  0xFbFbCDd4baC7092006cCF856398aA61C6fdbDfAd
  0x561027Fd8aFf4D70F355e9516ca29856BFA21bb0
  0xadEc1faCD4a6810090192792a2A148563bC39088
  0xe59C81f5a253e30B9eE7E3e8b91F30da1467A2b2
  0x8932BF0585e4b4a4Aa962f606035842F5017aEd1
)

sent=0; skipped=0; failed=0
echo "=== Pot 1: perp vaults (expect ~9.4525 ETH across 11) ==="
for V in "${VAULTS[@]}"; do
  SH=$(cast call "$V" "ethShareOf(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  if [ -z "${SH:-}" ]; then
    echo "  $V  SKIP (no response — RPC error, not a zero; re-run)"
    skipped=$((skipped+1)); continue
  fi
  if [ "$SH" = "0" ]; then
    echo "  $V  SKIP (0 shares — already recovered)"
    skipped=$((skipped+1)); continue
  fi
  if [ "$SEND" = "1" ]; then
    BEFORE=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
    ERR=$(cast send "$V" "withdrawEth(uint256)" "$SH" \
         --rpc-url "$RPC" "${PWARGS[@]}" 2>&1 >/dev/null)
    if [ -z "$ERR" ]; then
      AFTER=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
      DELTA=$(( AFTER - BEFORE ))
      echo "  $V  SENT   net $(cast to-unit $DELTA ether) ETH (after gas)"
      sent=$((sent+1))
    else
      echo "  $V  FAILED: $(echo "$ERR" | head -1)"
      failed=$((failed+1))
    fi
  else
    echo "  $V  would withdraw shares=$SH"
  fi
done

# --- Pot 2: v7 "GNOME". emergencyAdmin IS the deployer EOA; build predates arming. ---
GNOME=0x09579fbb9657322012c0c155f5af95eecca4010b
echo
echo "=== Pot 2: v7 GNOME $GNOME (expect ~2.7992 ETH) ==="
ADMIN=$(cast call "$GNOME" "emergencyAdmin()(address)" --rpc-url "$RPC" 2>/dev/null | awk '{print tolower($1)}')
if [ "$ADMIN" != "$(echo "$DEPLOYER" | tr 'A-Z' 'a-z')" ]; then
  echo "  SKIP: emergencyAdmin is '${ADMIN:-<no response>}', not the deployer. Do not force it."
else
  if [ "$SEND" = "1" ]; then
    BEFORE=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
    E1=$(cast send "$GNOME" "emergencyWithdrawLP(uint256)" 1 \
      --rpc-url "$RPC" "${PWARGS[@]}" 2>&1 >/dev/null)
    [ -z "$E1" ] && echo "  emergencyWithdrawLP(1) SENT" || echo "  emergencyWithdrawLP(1) FAILED: $(echo "$E1" | head -1)"
    E2=$(cast send "$GNOME" "emergencySweep(address)" 0x0000000000000000000000000000000000000000 \
      --rpc-url "$RPC" "${PWARGS[@]}" 2>&1 >/dev/null)
    [ -z "$E2" ] && echo "  emergencySweep(native) SENT" || echo "  emergencySweep(native) FAILED: $(echo "$E2" | head -1)"
    AFTER=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
    echo "  net $(cast to-unit $(( AFTER - BEFORE )) ether) ETH (after gas)"
  else
    echo "  would call emergencyWithdrawLP(1) then emergencySweep(address(0))"
  fi
fi

echo
GAS_END=$(cast balance "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null)
echo "=== Result ==="
echo "vaults sent=$sent skipped=$skipped failed=$failed"
echo "deployer balance: $(cast to-unit "${GAS_START:-0}" ether) -> $(cast to-unit "${GAS_END:-0}" ether) ETH"
if [ "$SEND" = "1" ]; then
  python3 -c "print('net recovered: %.6f ETH (after gas)' % ((int('$GAS_END')-int('$GAS_START'))/1e18))"
else
  echo "(dry run — nothing sent)"
fi
echo
echo "Still outstanding, deliberately not attempted here:"
echo "  6.888 ETH  r33/34   armed, matures ~2026-09-12 20:05 UTC. DO NOT run arm-old-emergency.sh."
echo "  5.547 ETH  r32      needs arming, then a 300 s delay."
echo "  0.919 ETH  round 38 LIVE — recovering it kills round 38. Do it at redeploy."
