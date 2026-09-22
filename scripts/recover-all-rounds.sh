#!/usr/bin/env bash
#
# Sweep stranded LP out of EVERY retired deployment, in parallel.
#
# The per-round script this replaces (recover-old-lp.sh) hardcodes ONE
# registry/timelock pair, so it only ever drains whichever round it was last
# edited for — and its literals had drifted two rounds behind the manifest, so
# running it would have armed a stale registry, printed "armed", and left the
# live round's LP exactly where it was. Rounds are a list, so this takes a list.
#
# WHY PARALLEL. Each round costs 180 s (timelock) + 600 s (emergencyDelay) +
# 180 s + 180 s of pure waiting. Serially that is ~19 min per round; the waits
# are independent across rounds because each has its own timelock and its own
# immutable delay, so batching every round through each phase together costs
# one wait instead of N.
#
# PHASES (all rounds move through each together):
#   1. arm      schedule+execute armEmergency() -> starts emergencyDelay
#   2. settle   wait out the longest emergencyDelay
#   3. withdraw schedule+execute emergencyWithdrawLP(gen) -> ETH lands in the timelock
#   4. forward  schedule+execute a plain value transfer timelock -> deployer
#
# Arming also forces the redemption exit OPEN (the holder protection), which on
# a retired testnet round protects wallets we control — the point here is the
# LP, not the courtesy.
#
# Usage:
#   ./scripts/recover-all-rounds.sh            # dry run: scan and report only
#   ./scripts/recover-all-rounds.sh --execute  # actually move funds
#
set -uo pipefail

RPC="${RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
DEP="${DEP:-0xc94400e90bb652afa02740bff50824e14069c133}"
PM="${PM:-0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4}"
Z=0x0000000000000000000000000000000000000000000000000000000000000000
#  SALT. OpenZeppelin derives an operation id from (target, value, data,
#  predecessor, salt) and `schedule` demands state Unset -- so a salt that has
#  already been used for the same call reverts TimelockUnexpectedOperationState
#  forever after, even once it is Done. A retry therefore needs a FRESH salt, or
#  a round that was partially recovered can never be retried. Override to re-run.
SALT="${SALT:-0x0000000000000000000000000000000000000000000000000000000000000000}"
EXECUTE=0
[ "${1:-}" = "--execute" ] && EXECUTE=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE_KEY="${PRIVATE_KEY:-$(grep -E '^PRIVATE_KEY=' "$ROOT/contracts/solidity/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "\r')}"
[ -n "$PRIVATE_KEY" ] || { echo "no signer: set PRIVATE_KEY or contracts/solidity/.env"; exit 1; }

#  registry|timelock   — retired rounds only. The LIVE round must never be in
#  this list: draining it would pull the liquidity out from under a running
#  market. Add a round here only once its successor is deployed.
ROUNDS=(
  "0x018efe32379bfc3f38ed7e592f5c9f214b6e3ded|0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3"  # r38 (real admin 0x3925859C, resolved on chain)
  "0x7d04e39414b433a640a12127d67318c8a9a1ae00|0x00A35d18E06d846f9CE55Fe87434E839E8a3bf90"  # r39 recovered 0.6555
  "0xc788c1f669c00e865d81c8545bc3ebc673e56368|0xd15473b0e4e1aecf0d0de3f6a63d7e567694686c"  # r40
  "0xc233f32128f6da1356bad2aa1c75c87b624edec3|0xa7294714e38b2e0831fc04faf87de1eaf5d20d91"  # r42 recovered 1.1735
  "0xdda33532dade1d30bcc70e814d24a79c77bda766|0xc3f093bba8ac78e8f9a3dc93ba3dbe62e9954f53"  # r43 recovered 2.5320
)

say() { printf "\n\033[1m== %s\033[0m\n" "$*"; }
call() { cast call "$1" "$2" ${3:-} --rpc-url "$RPC" 2>/dev/null | tail -1 | sed 's/ .*//'; }
send() { cast send "$@" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null 2>&1; }

# ── SCAN ────────────────────────────────────────────────────────────────────
say "scanning ${#ROUNDS[@]} retired rounds"
LIVE=()
for e in "${ROUNDS[@]}"; do
  reg="${e%%|*}"; tl="${e##*|}"
  gen=$(call "$reg" 'currentGeneration()(uint256)')
  [ "${gen:-0}" = "0" ] && { echo "  $reg  never summoned, skipping"; continue; }
  #  ASK THE REGISTRY WHO ITS ADMIN IS. The manifest's `timelock` field is the
  #  GOVERNANCE timelock, which is not always the `emergencyAdmin` -- r38 ships
  #  0x3925859C as its admin while the manifest names 0x06705E8c. Scheduling the
  #  arm on the wrong timelock succeeds (a timelock will queue anything) and only
  #  fails at execute, where the registry rejects the caller -- so the run
  #  reports "scheduled" and silently recovers nothing.
  admin=$(cast call "$reg" 'emergencyAdmin()(address)' --rpc-url "$RPC" 2>/dev/null | tail -1)
  if [ -n "$admin" ] && [ "$(printf %s "$admin" | tr A-Z a-z)" != "$(printf %s "$tl" | tr A-Z a-z)" ]; then
    echo "  note: $reg emergencyAdmin=$admin (manifest said $tl) -- using the chain's answer"
    tl="$admin"
  fi
  pid=$(call "$reg" 'generationPositionId(uint256)(uint256)' "$gen")
  liq=0; [ "${pid:-0}" != "0" ] && liq=$(cast call "$PM" 'getPositionLiquidity(uint256)(uint128)' "$pid" --rpc-url "$RPC" 2>/dev/null | tail -1 | sed 's/ .*//')
  ready=$(call "$reg" 'emergencyReadyAt()(uint256)')
  printf "  %s  gen=%-3s pos=%-7s liq=%-26s armed=%s\n" "$reg" "$gen" "${pid:-0}" "${liq:-0}" "${ready:-0}"
  [ "${liq:-0}" != "0" ] && LIVE+=("$reg|$tl|$gen")
done

[ ${#LIVE[@]} -eq 0 ] && { echo "nothing with liquidity to recover"; exit 0; }
say "${#LIVE[@]} rounds hold liquidity"
[ "$EXECUTE" = "0" ] && { echo "dry run — re-run with --execute to move funds"; exit 0; }

# ── 1. ARM ──────────────────────────────────────────────────────────────────
say "1/4  arming (schedule)"
ARM=0x06e7b8db   # armEmergency()
for e in "${LIVE[@]}"; do
  IFS='|' read -r reg tl gen <<<"$e"
  if [ "$(call "$reg" 'emergencyReadyAt()(uint256)')" != "0" ]; then echo "  $reg already armed"; continue; fi
  send "$tl" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$reg" 0 "$ARM" "$Z" "$SALT" 180 \
    && echo "  $reg scheduled" || echo "  $reg schedule FAILED (already queued?)"
done
echo "  waiting 190s for the timelock..."; sleep 190
say "1/4  arming (execute)"
for e in "${LIVE[@]}"; do
  IFS='|' read -r reg tl gen <<<"$e"
  [ "$(call "$reg" 'emergencyReadyAt()(uint256)')" != "0" ] && { echo "  $reg already armed"; continue; }
  send "$tl" "execute(address,uint256,bytes,bytes32,bytes32)" "$reg" 0 "$ARM" "$Z" "$SALT"
  echo "  $reg readyAt=$(call "$reg" 'emergencyReadyAt()(uint256)')"
done

# ── 2. SETTLE ───────────────────────────────────────────────────────────────
say "2/4  waiting out emergencyDelay"
NOW=$(cast block latest --field timestamp --rpc-url "$RPC" 2>/dev/null)
MAXW=0
for e in "${LIVE[@]}"; do
  IFS='|' read -r reg tl gen <<<"$e"
  r=$(call "$reg" 'emergencyReadyAt()(uint256)'); w=$(( ${r:-0} - NOW ))
  [ "$w" -gt "$MAXW" ] && MAXW=$w
done
[ "$MAXW" -gt 0 ] && { echo "  longest wait ${MAXW}s"; sleep $(( MAXW + 15 )); } || echo "  all clocks already elapsed"

# ── 3. WITHDRAW ─────────────────────────────────────────────────────────────
say "3/4  emergencyWithdrawLP (schedule)"
for e in "${LIVE[@]}"; do
  IFS='|' read -r reg tl gen <<<"$e"
  cd=$(cast calldata "emergencyWithdrawLP(uint256)" "$gen")
  send "$tl" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$reg" 0 "$cd" "$Z" "$SALT" 180 \
    && echo "  $reg gen=$gen scheduled" || echo "  $reg schedule FAILED"
done
echo "  waiting 190s..."; sleep 190
say "3/4  emergencyWithdrawLP (execute)"
for e in "${LIVE[@]}"; do
  IFS='|' read -r reg tl gen <<<"$e"
  cd=$(cast calldata "emergencyWithdrawLP(uint256)" "$gen")
  send "$tl" "execute(address,uint256,bytes,bytes32,bytes32)" "$reg" 0 "$cd" "$Z" "$SALT"
  echo "  $tl holds $(cast from-wei "$(cast balance "$tl" --rpc-url "$RPC")") ETH"
done

# ── 4. FORWARD ──────────────────────────────────────────────────────────────
#  Amount is read AFTER the withdraw and encoded into the scheduled operation,
#  so the timelock moves exactly what it received. A round that yielded nothing
#  is skipped rather than scheduling a zero-value transfer that only burns gas.
say "4/4  forwarding to the deployer (schedule)"
declare -a FWD=()
for e in "${LIVE[@]}"; do
  IFS='|' read -r reg tl gen <<<"$e"
  amt=$(cast balance "$tl" --rpc-url "$RPC" 2>/dev/null)
  [ "${amt:-0}" = "0" ] && { echo "  $tl empty, skipping"; continue; }
  send "$tl" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$DEP" "$amt" 0x "$Z" "$SALT" 180 \
    && { FWD+=("$tl|$amt"); echo "  $tl -> $(cast from-wei "$amt") ETH scheduled"; }
done
[ ${#FWD[@]} -eq 0 ] && { echo "nothing to forward"; exit 0; }
echo "  waiting 190s..."; sleep 190
say "4/4  forwarding (execute)"
for e in "${FWD[@]}"; do
  IFS='|' read -r tl amt <<<"$e"
  send "$tl" "execute(address,uint256,bytes,bytes32,bytes32)" "$DEP" "$amt" 0x "$Z" "$SALT"
  echo "  $tl -> forwarded $(cast from-wei "$amt") ETH"
done

say "done"
echo "deployer: $(cast balance "$DEP" --rpc-url "$RPC" --ether 2>/dev/null | tail -1) ETH"
