# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────────────────────
# resolve_signer — put the signing flags in SIGNER[] WITHOUT a key in argv.
#
# argv is world-readable (`ps -ef`), lands in shell history and is echoed by most
# CI logs. Seven scripts passed `--private-key "$PRIVATE_KEY"`, and keeper.sh's
# header claimed it "uses $PRIVATE_KEY by name only" — naming a variable does not
# stop the shell expanding it into the child's argv, which is exactly where it
# ended up. That comment described a protection that did not exist.
#
# PREFERRED — a foundry keystore. The key stays encrypted on disk; only an
# ACCOUNT NAME and a PASSWORD-FILE PATH reach argv, and neither is a secret:
#     cast wallet import deployer --interactive      # once, at a terminal
#     export KEYSTORE_ACCOUNT=deployer
#     export KEYSTORE_PASSWORD_FILE="$HOME/.cauldron/kspw"   # chmod 600
#
# FALLBACK — a raw PRIVATE_KEY still works so existing runbooks keep running, but
# it is ANNOUNCED on every run. cast has no way to take a raw key off argv: there
# is no ETH_PRIVATE_KEY / FOUNDRY_ETH_PRIVATE_KEY env var (checked against cast
# 1.4.4 — both are ignored and the wallet lookup fails). So the honest statement
# is "this mode exposes the key", not a comment claiming otherwise.
resolve_signer() {
  SIGNER=()
  if [ -n "${KEYSTORE_ACCOUNT:-}" ]; then
    [ -n "${KEYSTORE_PASSWORD_FILE:-}" ] || { echo "KEYSTORE_ACCOUNT set but KEYSTORE_PASSWORD_FILE is not" >&2; return 1; }
    [ -r "${KEYSTORE_PASSWORD_FILE}" ]   || { echo "cannot read KEYSTORE_PASSWORD_FILE: ${KEYSTORE_PASSWORD_FILE}" >&2; return 1; }
    SIGNER=(--account "$KEYSTORE_ACCOUNT" --password-file "$KEYSTORE_PASSWORD_FILE")
    return 0
  fi
  if [ -n "${PRIVATE_KEY:-}" ]; then
    echo "  ⚠ signing with a RAW PRIVATE_KEY: it will appear in this host's process table." >&2
    echo "    Prefer a keystore: cast wallet import <name> --interactive, then export KEYSTORE_ACCOUNT + KEYSTORE_PASSWORD_FILE." >&2
    SIGNER=(--private-key "$PRIVATE_KEY")
    return 0
  fi
  echo "no signer: set KEYSTORE_ACCOUNT + KEYSTORE_PASSWORD_FILE (preferred) or PRIVATE_KEY" >&2
  return 1
}
