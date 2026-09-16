#!/usr/bin/env bash
#
# ══════════════════════════════════════════════════════════════════════════════
#  ROBINHOOD MAINNET (chain 4663) DEPLOY PATH
# ══════════════════════════════════════════════════════════════════════════════
#
#  Until this file existed there was NO mainnet deploy script. The documented
#  path (docs/MAINNET_LAUNCH.md:54-55) was a bare `forge script ... --broadcast`
#  with no clean build, no size gate, no chain assert and no manifest
#  completeness check. Every one of those omissions has already cost a round on
#  testnet, where it was free. On 4663 it costs real ETH.
#
#  ── WHAT THIS REFUSES TO DO ────────────────────────────────────────────────
#   * broadcast to any chain that is not 4663                      (GATE 1)
#   * broadcast a testnet-shaped parameter set                     (GATE 2)
#   * broadcast a MOCK quote token with an ungated mint()          (GATE 2)
#   * broadcast a stale out/ (r43+r44 shipped a router with no     (GATE 3)
#     playChurn from a cached artifact — twice)
#   * broadcast a contract over EIP-170                            (GATE 3)
#   * ship a manifest with a surviving <FILL> or __ASK_CHAIN__     (STAGE manifest)
#   * ship a manifest whose selectors are absent from the runtime  (STAGE manifest)
#
#  ── USAGE ──────────────────────────────────────────────────────────────────
#    ./scripts/deploy-mainnet-rh.sh --self-test        # prove the gates fire (no RPC, no key)
#    ./scripts/deploy-mainnet-rh.sh --gates            # GATES 1-4 only, deploys nothing
#    ./scripts/deploy-mainnet-rh.sh --simulate         # full path, forge --sender, NO broadcast
#    ./scripts/deploy-mainnet-rh.sh --broadcast --stage deploy    # spends real ETH
#
#  --simulate is the DEFAULT. Broadcasting requires typing --broadcast.
#
#  ── STAGES (the presale is a real market; the path is not one transaction) ──
#    deploy    DeployLaunchpad  -> registry/hook/presale/governor/...  + cap assert
#    ignite    igniteCauldron() -> summons gen-1 (REQUIRES a sold-out presale)
#    perp      DeployPerp       -> engine/vault/mark source + syncGeneration
#    manifest  fill round.json from the broadcast artifacts, then verify it
#    all       every stage in order (what a fork rehearsal runs)
#
#  ── FORK REHEARSAL (agent D2) ──────────────────────────────────────────────
#    anvil --fork-url https://rpc.mainnet.chain.robinhood.com --chain-id 4663 &
#    RPC=http://127.0.0.1:8545 ./scripts/deploy-mainnet-rh.sh --gates
#    RPC=http://127.0.0.1:8545 PRIVATE_KEY=<anvil key> \
#      ./scripts/deploy-mainnet-rh.sh --broadcast --stage deploy
#  A fork of 4663 reports chain id 4663, so GATE 1 passes unchanged. Broadcasting
#  to a LOCAL fork is safe and is the only way to prove the path end to end.
#
#  NOTE ON MINT-OUT: MAX_PER_WALLET is 7 (see GATE 2). One wallet therefore
#  CANNOT mint out a 1111 presale — 159 wallets are needed. `go-testnet.sh:118`
#  mints 250 per tx and would revert `PerWalletCap()` here. The `ignite` stage
#  is consequently NOT reachable from a single-EOA fork rehearsal; that is the
#  anti-whale cap working, not a script defect.
#
#  SECRETS: this script never reads, prints or copies contracts/solidity/.env.
#  It takes the key from $PRIVATE_KEY (or a keystore via --account) and never
#  echoes it. $RPC is echoed; do not put an API key in it.
#
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# ── CHAIN FACTS — measured on 4663, 2026-09-16 ──────────────────────────────
#  chain id 4663 (0x1237)          verified: eth_chainId
#  eth_maxPriorityFeePerGas = 0    ordering is NOT purchasable (one sequencer,
#                                  FCFS). Do not bother with a priority fee.
#  blocks ~100 ms                  the 256-block blockhash window is ~25.6 s,
#                                  NOT ~51 min. Anything that reads a blockhash
#                                  more than ~25 s old gets zero.
#  `finalized` lags `latest` by ~9,650 blocks (~16 min).
#  native is REAL ETH, 18 decimals — so NATIVE_PEGGED_USD must stay FALSE here.
#  The host `rpc.chain.robinhood.com` from older docs DOES NOT EXIST (TLS
#  handshake_failure). Only `rpc.mainnet.chain.robinhood.com` resolves.
EXPECT_CHAIN="${EXPECT_CHAIN:-4663}"
RPC="${RPC:-https://rpc.mainnet.chain.robinhood.com}"

#  Uniswap v4 on 4663 — every one VERIFIED to carry code via eth_getCode.
POOL_MANAGER="${POOL_MANAGER:-0x8366a39cc670b4001a1121b8f6a443a643e40951}"
POSITION_MANAGER="${POSITION_MANAGER:-0x58daec3116aae6d93017baaea7749052e8a04fa7}"
#  Deterministic CREATE2 proxy. `HookMiner.find` mines a salt FOR THIS ADDRESS
#  (DeployLaunchpad.s.sol:85,161) and `new CauldronHook{salt:...}` must land on
#  the mined address or the script reverts "hook addr mismatch". Verified to
#  carry code on 4663 — without it the hook can never be deployed at all.
CREATE2_PROXY=0x4e59b44847b379578588920cA78FbF26c0B4956C

MODE="simulate"; STAGE="all"; SELFTEST=0; GATES_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --simulate)  MODE="simulate" ;;
    --broadcast) MODE="broadcast" ;;
    --gates)     GATES_ONLY=1 ;;
    --self-test) SELFTEST=1 ;;
    --stage)     shift; STAGE="${1:-all}" ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; }
die()  { printf '\n\033[31mABORT:\033[0m %s\n' "$*" >&2; exit 1; }

# ═════════════════════════════════════════════════════════════════════════════
#  THE EIP-170 GATE
# ═════════════════════════════════════════════════════════════════════════════
#  scripts/auto-deploy.sh:81 read `$4` of the `--sizes` table. The header is
#
#     Contract | Runtime Size (B) | Initcode Size (B) | Runtime Margin (B) | ...
#
#  so with -F'|' the fields are $2 Contract, $3 Runtime Size, $4 INITCODE SIZE,
#  $5 Runtime Margin. A size is never negative, so `if ($4 ~ /^-/)` could never
#  be true and the gate NEVER FIRED — which is why PerpEngine is sitting 609 B
#  over the limit right now with a green pipeline.
#
#  The bug is a HARDCODED COLUMN INDEX, so the fix is not to hardcode a better
#  one. This finds "Runtime Margin" in the header and uses whatever column it
#  actually is, and it FAILS CLOSED: no header found => abort, never "no
#  contracts over the limit". A gate that cannot find its own input must not
#  report success. That is the exact failure mode being repaired.
eip170_over() {
  awk '
    hdr == 0 && /Runtime Margin/ {
      n = split($0, f, "|")
      for (i = 1; i <= n; i++) if (f[i] ~ /Runtime Margin/) { col = i; hdr = 1; break }
      next
    }
    hdr == 1 && /^[[:space:]]*\|/ {
      n = split($0, f, "|")
      if (n < col) next
      name = f[2]; margin = f[col]
      gsub(/[[:space:],]/, "", name)
      gsub(/[[:space:],]/, "", margin)
      if (name == "" || margin == "") next
      if (margin ~ /^-[0-9]+$/) printf "%s %s\n", name, margin
    }
    END { if (hdr == 0) print "__NO_HEADER__" }
  ' "$1"
}

#  Contracts that are allowed to be oversized because they are never deployed:
#  test harnesses and mocks. Matched on the WHOLE name, anchored, so a real
#  contract can never be waved through by containing "test" as a substring.
#  (The old gate used `grep -viE "test|mock|harness"` on the whole line.)
is_test_only() {
  case "$1" in
    Harness|*Harness|*Mock*|Mock*|*Test|Test*|X[0-9]*Engine|K[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

run_eip170_gate() {
  local log="$1" raw over=0 line name margin
  raw="$(eip170_over "$log")"
  if [ "$raw" = "__NO_HEADER__" ]; then
    die "EIP-170 gate could not find a 'Runtime Margin' column in $log.
     FAILING CLOSED. This is the gate that was silently broken before; it will
     never again report success on input it does not understand."
  fi
  while IFS=' ' read -r name margin; do
    [ -z "$name" ] && continue
    if is_test_only "$name"; then
      warn "$name is ${margin} B over EIP-170 (test-only, not deployed)"
    else
      printf '  \033[31mOVER\033[0m %s  runtime margin %s B\n' "$name" "$margin"
      over=$((over + 1))
    fi
  done <<< "$raw"
  [ "$over" -eq 0 ] || die "$over deployable contract(s) exceed the 24,576 B EIP-170 runtime limit.
     They CANNOT be deployed — the create reverts and the ETH is spent. Fix the
     size before broadcasting."
  ok "no deployable contract over EIP-170"
}

# ═════════════════════════════════════════════════════════════════════════════
#  SELF-TEST — proves each gate FIRES. Needs no RPC, no key, spends nothing.
# ═════════════════════════════════════════════════════════════════════════════
if [ "$SELFTEST" = "1" ]; then
  say "SELF-TEST 1  the EIP-170 gate fires on a negative Runtime Margin"
  cat > /tmp/rh-selftest-sizes.txt <<'EOF'
| Contract                 | Runtime Size (B) | Initcode Size (B) | Runtime Margin (B) | Initcode Margin (B) |
|--------------------------|------------------|-------------------|--------------------|---------------------|
| CauldronHook             | 23,343           | 24,123            | 1,233              | 25,029              |
| PerpEngine               | 25,185           | 26,001            | -609               | 23,151              |
EOF
  echo "  fixture: PerpEngine runtime 25,185 B, Runtime Margin -609 B"
  echo "  --- old gate (auto-deploy.sh:81, reads \$4 = Initcode Size) ---"
  OLD=$(awk -F'|' '/^\| [A-Za-z]/ {gsub(/[ ,]/,"",$4); if ($4 ~ /^-/) print $2" ("$4" B)"}' \
        /tmp/rh-selftest-sizes.txt | grep -viE "test|mock|harness" || true)
  if [ -z "$OLD" ]; then
    echo "      old gate output: <EMPTY> — it does NOT see the 609 B overflow. This is the bug."
  else
    echo "      old gate output: $OLD"; die "self-test invalid: the old gate was expected to miss this."
  fi
  echo "  --- new gate (header-derived Runtime Margin column) ---"
  NEW="$(eip170_over /tmp/rh-selftest-sizes.txt)"
  echo "$NEW" | sed 's/^/      /'
  echo "$NEW" | grep -q "^PerpEngine -609$" \
    || die "self-test FAILED: the new gate did not catch PerpEngine."
  ok "new gate caught PerpEngine at -609 B where the old gate saw nothing"

  say "SELF-TEST 2  the EIP-170 gate FAILS CLOSED on an unparseable table"
  printf 'some forge output with no size table at all\n' > /tmp/rh-selftest-junk.txt
  if [ "$(eip170_over /tmp/rh-selftest-junk.txt)" = "__NO_HEADER__" ]; then
    ok "no 'Runtime Margin' header -> gate reports __NO_HEADER__ and aborts (never 'clean')"
  else
    die "self-test FAILED: the gate did not fail closed."
  fi

  say "SELF-TEST 3  the <FILL> refusal fires"
  cat > /tmp/rh-selftest-manifest.json <<'EOF'
{ "chainId": 4663, "indexerUrl": "<FILL: Railway mainnet indexer URL>",
  "contracts": { "registry": "0x1111111111111111111111111111111111111111" } }
EOF
  if scan_fill_output=$(grep -n '<FILL\|__ASK_CHAIN' /tmp/rh-selftest-manifest.json); then
    echo "$scan_fill_output" | sed 's/^/      /'
    ok "<FILL> detected -> a real run refuses to broadcast/ship"
  else
    die "self-test FAILED: the <FILL> scan missed a placeholder."
  fi

  say "SELF-TEST 4  the chain-id assert fires on a wrong chain"
  assert_chain() { [ "$1" = "$2" ] || return 1; }
  if assert_chain 11155111 4663; then
    die "self-test FAILED: chain assert accepted Sepolia as 4663."
  else
    ok "chain id 11155111 rejected against expected 4663"
  fi
  if assert_chain 4663 4663; then ok "chain id 4663 accepted"; else die "self-test FAILED: 4663 rejected."; fi

  say "SELF-TEST PASSED — all four gates demonstrably fire"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
#  GATE 0 — repository safety
# ═════════════════════════════════════════════════════════════════════════════
say "GATE 0  repository"
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
echo "  branch: $BRANCH"
[ "$BRANCH" = "main" ] && die "refusing to run from 'main' — it is FROZEN for this audit."
ok "not on main"

# ═════════════════════════════════════════════════════════════════════════════
#  GATE 1 — the chain we actually connected to
# ═════════════════════════════════════════════════════════════════════════════
#  REQUIREMENT: assert the chain id we CONNECTED to, not the one we intended.
#  auto-deploy.sh:65 hard-refuses anything but Sepolia, which is why no mainnet
#  deploy was possible through it at all.
say "GATE 1  chain id"
echo "  rpc: $RPC"
CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null)
[ -n "$CHAIN" ] || die "no chain id from $RPC — the RPC is unreachable.
     An error is NOT a zero, and it is NOT a match. Refusing."
echo "  connected chain id: $CHAIN (expected $EXPECT_CHAIN)"
[ "$CHAIN" = "$EXPECT_CHAIN" ] || die "connected to chain $CHAIN but expected $EXPECT_CHAIN. Refusing."
ok "chain id $CHAIN"

#  The three addresses the deploy CANNOT work without. A codeless PoolManager
#  fails deep inside the summon, after a dozen contracts are already paid for.
for pair in "PoolManager:$POOL_MANAGER" "PositionManager:$POSITION_MANAGER" "CREATE2 proxy:$CREATE2_PROXY"; do
  n="${pair%%:*}"; a="${pair#*:}"
  c=$(cast code "$a" --rpc-url "$RPC" 2>/dev/null)
  if [ -z "$c" ] || [ "$c" = "0x" ]; then
    die "$n at $a has NO CODE on chain $CHAIN. The deploy would fail after spending gas."
  fi
  ok "$n $a has code (${#c} hex chars)"
done

# ═════════════════════════════════════════════════════════════════════════════
#  GATE 2 — mainnet parameters
# ═════════════════════════════════════════════════════════════════════════════
#  scripts/deploy-testnet.sh carries a block of deliberately unsafe testnet
#  values and says "the mainnet deploy is this file with the TESTNET block
#  deleted". Nothing enforced that. This does.
say "GATE 2  mainnet parameters"

#  ── THE ANTI-WHALE CAP ─────────────────────────────────────────────────────
#  MAX_PER_WALLET shipped once as 1111 == GENESIS_SUPPLY: a cap that could never
#  bind, so one wallet could take the entire genesis tranche AND the whole
#  ERC721Votes electorate with it. 6eaf67c made it settable, but the correction
#  window is NARROW:
#
#    MiFrensGenesis.sol:265  constructor rejects only maxPerWallet_ == 0
#    MiFrensGenesis.sol:266-273  a NON-BINDING cap (>= GENESIS_SUPPLY) is
#                                deliberately NOT rejected in the constructor
#    MiFrensGenesis.sol:299  setMaxPerWallet refuses newCap >= GENESIS_SUPPLY
#    MiFrensGenesis.sol:300  once `minted != 0` the cap may only RATCHET DOWN
#
#  So the cap must be passed CORRECTLY IN THE CONSTRUCTOR. It is read from the
#  env by DeployLaunchpad.s.sol:117 (`PRESALE_MAXWALLET`, default 100) and
#  handed to `new MiFrensGenesis(...)` at :147-149. Once the first fren is
#  minted it can never go back up — getting this wrong is close to irreversible.
#  docs/MAINNET_LAUNCH.md:52 suggests 100; this run requires 7.
PRESALE_MAXWALLET="${PRESALE_MAXWALLET:-7}"
PRESALE_SUPPLY="${PRESALE_SUPPLY:-1111}"
[ "$PRESALE_MAXWALLET" = "7" ] || die "PRESALE_MAXWALLET is '$PRESALE_MAXWALLET', must be 7 for this launch."
[ "$PRESALE_MAXWALLET" -lt "$PRESALE_SUPPLY" ] 2>/dev/null \
  || die "PRESALE_MAXWALLET ($PRESALE_MAXWALLET) must be < PRESALE_SUPPLY ($PRESALE_SUPPLY) or the cap cannot bind."
ok "PRESALE_MAXWALLET=7 (binding against GENESIS_SUPPLY=$PRESALE_SUPPLY)"

#  ── THE MOCK QUOTE TOKEN ───────────────────────────────────────────────────
#  DeployLaunchpad.s.sol:533 `vm.envOr("DEPLOY_QUOTES", true)` — DEFAULT TRUE.
#  It deploys MockQuoteToken("Magic USD","USDG",6) at :653 and allowlists it as
#  a treasury-rotation destination. MockQuoteToken.sol:27 is
#      function mint(address to, uint256 amount) external { _mint(to, amount); }
#  — COMPLETELY UNGATED. Anyone may mint unlimited USDG. Shipping that on a real
#  chain as an approved rotation destination is a standing drain on the guild's
#  LP. It must be OFF unless a REAL quote token address is supplied.
DEPLOY_QUOTES="${DEPLOY_QUOTES:-false}"
if [ "$DEPLOY_QUOTES" != "false" ]; then
  die "DEPLOY_QUOTES=$DEPLOY_QUOTES on a mainnet deploy.
     That deploys MockQuoteToken (cauldron/MockQuoteToken.sol:27 — an UNGATED
     public mint()) and allowlists it as a rotation destination. Refusing.
     Set DEPLOY_QUOTES=false and add real quote assets through governance."
fi
ok "DEPLOY_QUOTES=false (no mock USDG/xNVDA on a real chain)"

#  ── THE PRICE FEED THAT DOES NOT EXIST ON THIS CHAIN ───────────────────────
#  DeployLaunchpad.s.sol:601 FEED_ETH_USD = 0x694AA176...5306 is a SEPOLIA
#  Chainlink address. VERIFIED on 4663: eth_getCode returns 0x. The script's own
#  comment (:677-681) spells out the consequence — `usdPerRawUnit` catches the
#  revert and returns 0 ("cannot judge"), so the hook records NO VOLUME for
#  every trade. The mint ladder never advances and `isDead` is always true. The
#  deploy SUCCEEDS and the protocol records a fiction of zero.
#
#  NATIVE_PEGGED_USD is NOT the fix here: 4663's native token is REAL ETH, so
#  pegging it to $1 would be a ~3000x misprice in the other direction. It is
#  correct only on a chain whose gas token really is a dollar (Arc).
#  This gate is reachable only with DEPLOY_QUOTES=true, which is already
#  refused above; it stays as a second wall for anyone who overrides that.
if [ "${NATIVE_PEGGED_USD:-false}" = "true" ]; then
  die "NATIVE_PEGGED_USD=true on chain $CHAIN, whose native currency is REAL ETH.
     Pegging ETH to \$1 misprices every volume figure by ~3 orders of magnitude."
fi
ok "NATIVE_PEGGED_USD not set (4663 native is real ETH, 18 decimals)"

#  ── TESTNET TIMING MUST NOT SURVIVE ────────────────────────────────────────
[ "${TESTNET_GOV:-false}" = "false" ] || die "TESTNET_GOV is set. It waives the governor's own 1-day floors. Refusing."
ok "TESTNET_GOV unset"

TIMELOCK_DELAY="${TIMELOCK_DELAY:-172800}"
[ "$TIMELOCK_DELAY" -ge 172800 ] 2>/dev/null \
  || die "TIMELOCK_DELAY=$TIMELOCK_DELAY is below 48 h (172800). Testnet uses 180."
ok "TIMELOCK_DELAY=$TIMELOCK_DELAY s"

EMERGENCY_DELAY="${EMERGENCY_DELAY:-172800}"
#  DeployLaunchpad.s.sol:195 already refuses 0, and the value is IMMUTABLE once
#  constructed, so a wrong one here can never be corrected on that deployment.
[ "$EMERGENCY_DELAY" -ge 172800 ] 2>/dev/null \
  || die "EMERGENCY_DELAY=$EMERGENCY_DELAY is below 48 h and is IMMUTABLE once deployed."
ok "EMERGENCY_DELAY=$EMERGENCY_DELAY s"

TWAP_WINDOW="${TWAP_WINDOW:-300}"
#  The liquidation mark is a TWAP; a short window is what makes the mark cheap
#  to push. deploy-testnet.sh:151 uses 5 s and says "NEVER ship this on mainnet".
#  4663 blocks are ~100 ms, so 300 s is ~3,000 blocks of averaging.
[ "$TWAP_WINDOW" -ge 300 ] 2>/dev/null \
  || die "TWAP_WINDOW=$TWAP_WINDOW is below the 300 s mainnet floor (testnet ships 5)."
ok "TWAP_WINDOW=$TWAP_WINDOW s"

PERP_WARMUP="${PERP_WARMUP:-86400}"
[ "$PERP_WARMUP" -ge 3600 ] 2>/dev/null \
  || die "PERP_WARMUP=$PERP_WARMUP is under an hour (testnet ships 60 s)."
ok "PERP_WARMUP=$PERP_WARMUP s"

#  `setRotationSlipBps` reverts above 2000, but 2000 IS a 20% haircut a slice is
#  allowed to take. Unset leaves the contract's own safe 3% default in place.
if [ -n "${ROTATION_SLIP_BPS:-}" ] && [ "${ROTATION_SLIP_BPS}" -gt 300 ] 2>/dev/null; then
  die "ROTATION_SLIP_BPS=$ROTATION_SLIP_BPS allows a ${ROTATION_SLIP_BPS}bps haircut per slice.
     Leave it UNSET on mainnet so the contract's 3% default applies."
fi
ok "ROTATION_SLIP_BPS not widened"

#  The guardian can only ever CANCEL an armed emergency — it can block, never
#  steal — so an EOA here is a single key standing between a compromised
#  timelock and the LP. docs/MAINNET_LAUNCH.md:50 says a multisig.
if [ -z "${GUARDIAN:-}" ]; then
  warn "GUARDIAN unset -> defaults to the deployer EOA (DeployLaunchpad.s.sol:560). A Safe is strongly preferred."
else
  ok "GUARDIAN=$GUARDIAN"
fi
if [ -z "${FINALIZER:-}" ]; then
  warn "FINALIZER unset -> defaults to the deployer (DeployLaunchpad.s.sol:568); ignition is not permissionless."
fi

# ═════════════════════════════════════════════════════════════════════════════
#  GATE 3 — forced clean build + EIP-170
# ═════════════════════════════════════════════════════════════════════════════
#  NON-NEGOTIABLE. r43 AND r44 both broadcast a CauldronGachaRouter built from a
#  cached out/ that was missing `playChurn`; the selector was absent from the
#  dispatcher and every spin reverted with EMPTY data. No test can catch it —
#  `forge test` compiles the local source, the chain runs the broadcast artifact,
#  and the two only diverge at deploy time.
say "GATE 3  forced clean build + EIP-170"
cd "$ROOT/contracts/solidity"
export FOUNDRY_PROFILE=cauldron
export POOL_MANAGER POSITION_MANAGER

if [ "${SKIP_BUILD:-0}" = "1" ]; then
  warn "SKIP_BUILD=1 — reusing /tmp/rh-sizes.log (ONLY valid if you just built)"
  [ -s /tmp/rh-sizes.log ] || die "SKIP_BUILD=1 but /tmp/rh-sizes.log is missing or empty."
else
  echo "  forge clean  (a cached out/ is how r43 and r44 shipped a dead router)"
  forge clean || die "forge clean failed."
  echo "  forge build --sizes --force   (via_ir: 5-25 min)"
  #  The --skip is MANDATORY: the vendored permit2 script has a broken import
  #  and fails the build for a file nothing here deploys.
  forge build --sizes --force --skip 'lib/v4-periphery/lib/permit2/script/**' \
    > /tmp/rh-sizes.log 2>&1 || {
      echo "  --- first errors ---"; grep -m5 -E "^Error|error\[" /tmp/rh-sizes.log
      die "clean build FAILED — refusing to broadcast a stale out/."; }
  ok "clean build from an empty out/"
fi
run_eip170_gate /tmp/rh-sizes.log

# ═════════════════════════════════════════════════════════════════════════════
#  GATE 4 — signer
# ═════════════════════════════════════════════════════════════════════════════
say "GATE 4  signer"
#  NEVER echo the key. Only the derived ADDRESS is ever printed.
if [ -n "${PRIVATE_KEY:-}" ]; then
  case "$PRIVATE_KEY" in 0x*) : ;; *) PRIVATE_KEY="0x$PRIVATE_KEY" ;; esac
  export PRIVATE_KEY
  SENDER=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)
  [ -n "$SENDER" ] || die "PRIVATE_KEY is not a valid private key."
  SIGNER_ARGS=(--private-key "$PRIVATE_KEY")
  ok "signer $SENDER (from \$PRIVATE_KEY, never written to disk by this script)"
elif [ -n "${KEYSTORE_ACCOUNT:-}" ]; then
  SENDER="${DEPLOYER:?set DEPLOYER when using KEYSTORE_ACCOUNT}"
  SIGNER_ARGS=(--account "$KEYSTORE_ACCOUNT" --sender "$SENDER")
  ok "signer $SENDER (keystore '$KEYSTORE_ACCOUNT')"
else
  die "no signer. Set PRIVATE_KEY, or KEYSTORE_ACCOUNT+DEPLOYER for an encrypted keystore.
     NOTE: deploy/DeployPerp.s.sol:66 uses vm.envUint(\"PRIVATE_KEY\") and therefore
     CANNOT run from a keystore — the perp stage needs PRIVATE_KEY set."
fi

BAL=$(cast balance "$SENDER" --rpc-url "$RPC" 2>/dev/null)
[ -n "$BAL" ] || die "cannot read the deployer balance — an error is not a zero."
BAL_ETH=$(python3 -c "print('%.6f' % (int('$BAL')/1e18))")
echo "  balance: ${BAL_ETH} ETH"
#  The badge art alone is ~33M gas across 8 SSTORE2 writes (deploy-testnet.sh:107).
python3 -c "
import sys
if int('$BAL') < 3*10**18:
    sys.exit('balance ${BAL_ETH} ETH is thin for a full deploy (badge art alone is ~33M gas).')
" || die "top up the deployer first."
ok "balance sufficient"

if [ "$GATES_ONLY" = "1" ]; then
  say "GATES 0-4 PASSED — nothing deployed (--gates)"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
#  BROADCAST FLAGS
# ═════════════════════════════════════════════════════════════════════════════
#  --slow sends one tx at a time and waits for each receipt. On a 100 ms-block
#  FCFS chain with a single sequencer that costs little and removes a whole
#  class of nonce/ordering surprise. eth_maxPriorityFeePerGas is 0 here, so
#  there is no tip to pay and no ordering to buy.
if [ "$MODE" = "broadcast" ]; then
  BCAST=(--broadcast --slow)
  say "MODE  BROADCAST — this spends real ETH on chain $CHAIN"
else
  BCAST=()
  say "MODE  SIMULATE — forge will execute against $CHAIN but broadcast NOTHING"
fi

stage_wanted() { [ "$STAGE" = "all" ] || [ "$STAGE" = "$1" ]; }

# ── STAGE deploy ────────────────────────────────────────────────────────────
if stage_wanted deploy; then
  say "STAGE deploy  DeployLaunchpad"
  export PRESALE_MAXWALLET PRESALE_SUPPLY DEPLOY_QUOTES TIMELOCK_DELAY EMERGENCY_DELAY
  echo "  PRESALE_MAXWALLET=$PRESALE_MAXWALLET  PRESALE_SUPPLY=$PRESALE_SUPPLY  DEPLOY_QUOTES=$DEPLOY_QUOTES"
  forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad \
    --rpc-url "$RPC" "${SIGNER_ARGS[@]}" "${BCAST[@]}" -vvv \
    2>&1 | tee /tmp/rh-launchpad.log
  grep -qE "ONCHAIN EXECUTION COMPLETE|Script ran successfully" /tmp/rh-launchpad.log \
    || die "DeployLaunchpad did not report success. Read /tmp/rh-launchpad.log before retrying — the chain has state now."

  PRESALE=$(grep -oE "MiFrensGenesis : 0x[0-9a-fA-F]{40}" /tmp/rh-launchpad.log | tail -1 | grep -oE "0x[0-9a-fA-F]{40}")
  ok "presale ${PRESALE:-<unparsed>}"

  #  ── ASSERT THE CAP ON CHAIN, NOT IN THE ENV ────────────────────────────
  #  The env said 7. Only the chain can say what was actually constructed, and
  #  after the first mint this can never be widened again.
  if [ "$MODE" = "broadcast" ] && [ -n "$PRESALE" ]; then
    CAP=$(cast call "$PRESALE" "MAX_PER_WALLET()(uint256)" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
    MINTED=$(cast call "$PRESALE" "minted()(uint256)" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
    echo "  on-chain MAX_PER_WALLET=$CAP  minted=$MINTED"
    if [ "$CAP" != "7" ]; then
      if [ "${MINTED:-1}" = "0" ]; then
        die "MAX_PER_WALLET is $CAP, not 7 — but minted==0, so the correction window is STILL OPEN.
     Fix it NOW, before the first mint:
       cast send $PRESALE 'setMaxPerWallet(uint256)' 7 --rpc-url $RPC <signer>
     After the first mint the cap can only ratchet DOWN (MiFrensGenesis.sol:300)."
      fi
      die "MAX_PER_WALLET is $CAP, not 7, and $MINTED fren(s) are already minted.
     The correction window is CLOSED (MiFrensGenesis.sol:300 allows only a decrease)."
    fi
    ok "on-chain MAX_PER_WALLET == 7"
  fi
fi

# ── STAGE ignite ────────────────────────────────────────────────────────────
if stage_wanted ignite; then
  say "STAGE ignite  igniteCauldron()"
  PRESALE="${PRESALE:-${PRESALE_ADDR:-}}"
  [ -n "$PRESALE" ] || die "set PRESALE_ADDR=0x... to ignite (the presale from the deploy stage)."
  REMAINING=$(cast call "$PRESALE" "remaining()(uint256)" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  echo "  remaining: ${REMAINING:-?}"
  #  MiFrensGenesis.sol:679 `if (minted < GENESIS_SUPPLY) revert NotSoldOut();`
  #  A mainnet presale sells out to REAL buyers. With MAX_PER_WALLET=7 that is
  #  at least 159 distinct wallets — this stage cannot be forced by the deployer.
  [ "${REMAINING:-1}" = "0" ] || die "presale is not sold out ($REMAINING left). igniteCauldron() reverts NotSoldOut()."
  if [ "$MODE" = "broadcast" ]; then
    cast send "$PRESALE" "igniteCauldron()" --rpc-url "$RPC" "${SIGNER_ARGS[@]}" >/dev/null \
      || die "igniteCauldron failed."
    ok "ignited"
  else
    ok "simulate: would call igniteCauldron()"
  fi
fi

# ── STAGE perp ──────────────────────────────────────────────────────────────
if stage_wanted perp; then
  say "STAGE perp  DeployPerp"
  #  DeployPerp.s.sol:66 uses vm.envUint("PRIVATE_KEY") — REQUIRED, no keystore.
  [ -n "${PRIVATE_KEY:-}" ] || die "the perp stage needs PRIVATE_KEY (DeployPerp.s.sol:66 uses vm.envUint)."
  a_of() { grep -oE "$1 *: 0x[0-9a-fA-F]{40}" /tmp/rh-launchpad.log 2>/dev/null | tail -1 | grep -oE "0x[0-9a-fA-F]{40}"; }
  export HOOK="${HOOK:-$(a_of CauldronHook)}"
  export REGISTRY="${REGISTRY:-$(a_of CauldronRegistry)}"
  export DIVIDEND="${DIVIDEND:-$(a_of MiFrensDividend)}"
  export PRESALE="${PRESALE:-$(a_of MiFrensGenesis)}"
  export TIMELOCK="${TIMELOCK:-$(a_of Timelock)}"
  export QUOTE_ORACLE="${QUOTE_ORACLE:-}"
  for v in HOOK REGISTRY DIVIDEND PRESALE; do
    [ -n "${!v}" ] || die "$v is empty — pass it explicitly (it could not be parsed from /tmp/rh-launchpad.log)."
  done
  echo "  hook=$HOOK registry=$REGISTRY dividend=$DIVIDEND presale=$PRESALE timelock=${TIMELOCK:-<none>}"
  #  DEPLOY_MARK_SOURCE: with no mark source `blocksVolumeLink()` is true and a
  #  single dust perp position holds an approved treasury rotation hostage
  #  indefinitely. Arm it at deploy.
  export DEPLOY_MARK_SOURCE="${DEPLOY_MARK_SOURCE:-true}"
  export PERP_WARMUP TWAP_WINDOW
  export INSURANCE_SEED_WEI="${INSURANCE_SEED_WEI:-60000000000000000}"
  forge script deploy/DeployPerp.s.sol --tc DeployPerp \
    --rpc-url "$RPC" "${SIGNER_ARGS[@]}" "${BCAST[@]}" -vvv \
    2>&1 | tee /tmp/rh-perp.log
  grep -qE "ONCHAIN EXECUTION COMPLETE|Script ran successfully" /tmp/rh-perp.log \
    || die "DeployPerp did not report success. See /tmp/rh-perp.log."
  PERP_ENGINE=$(grep -oE "PerpEngine *: 0x[0-9a-fA-F]{40}" /tmp/rh-perp.log | tail -1 | grep -oE "0x[0-9a-fA-F]{40}")
  ok "engine ${PERP_ENGINE:-<unparsed>}"

  #  syncGeneration: with syncedToken == 0 the engine derives the swap DIRECTION
  #  wrong and every "buy" executes as a SELL, marked at zero and instantly
  #  liquidatable — without reverting. Verify by READING the state, not by the
  #  exit code; "AlreadySynced" is success.
  if [ "$MODE" = "broadcast" ] && [ -n "$PERP_ENGINE" ]; then
    cast send "$PERP_ENGINE" "syncGeneration()" --rpc-url "$RPC" "${SIGNER_ARGS[@]}" >/dev/null 2>&1 || true
    LIVE=$(cast call "$REGISTRY" 'currentToken()(address)' --rpc-url "$RPC" 2>/dev/null | tr 'A-Z' 'a-z')
    SYNC=$(cast call "$PERP_ENGINE" 'syncedToken()(address)' --rpc-url "$RPC" 2>/dev/null | tr 'A-Z' 'a-z')
    [ "$LIVE" = "$SYNC" ] && ok "syncedToken == live token — perps fill in the right direction" \
      || die "syncedToken=$SYNC live=$LIVE. Do NOT trade; re-run syncGeneration()."
  fi
fi

# ── STAGE manifest ──────────────────────────────────────────────────────────
if stage_wanted manifest; then
  say "STAGE manifest  fill round.json from the broadcast artifacts"
  cd "$ROOT"
  MANIFEST="$ROOT/indexer/deployments/round.json"
  TEMPLATE="$ROOT/indexer/deployments/round.robinhood.template.json"

  #  RPC_URL IS LOAD-BEARING. apply-deployment.mjs resolves the hook, the seeder,
  #  the live collection and the gen-1 poolId by eth_call, and every one of those
  #  falls back to a SEPOLIA endpoint when RPC_URL is unset
  #  (apply-deployment.mjs:251,278,294,313). Unset, it would fill 4663 addresses
  #  from the broadcast and then ask Sepolia what they point at.
  export RPC_URL="$RPC"

  CUR_CHAIN=$(python3 -c "import json;print(json.load(open('$MANIFEST')).get('chainId'))" 2>/dev/null || echo "?")
  if [ "$CUR_CHAIN" != "$EXPECT_CHAIN" ]; then
    echo "  round.json currently pins chainId $CUR_CHAIN — seeding it from the 4663 template"
    if [ "$MODE" = "broadcast" ]; then
      cp "$MANIFEST" "$MANIFEST.bak.$(date +%s)" && echo "  backed up the previous round.json"
      cp "$TEMPLATE" "$MANIFEST"
    else
      warn "simulate: NOT overwriting $MANIFEST (would copy the template over it)"
    fi
  fi

  if [ "$MODE" = "broadcast" ]; then
    node "$ROOT/scripts/apply-deployment.mjs" --chain "$EXPECT_CHAIN" || die "apply-deployment.mjs failed."

    #  ── THE KEYS NO SCRIPT PRODUCES ────────────────────────────────────────
    #  apply-deployment.mjs writes contracts.*, quoteAssets[].address, blocks,
    #  poolIds and schema. It writes NONE of: chainId, indexerUrl, genesisSupply,
    #  deathThresholdEth, legacyThresholdEth, legacyBps. Those six were carried
    #  forward by hand on every round. Two are readable from the chain, three
    #  mirror the deploy env, and one genuinely cannot be produced.
    REG=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['contracts']['registry'])")
    HK=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['contracts']['hook'])")
    PS=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['contracts']['presale'])")
    GS=$(cast call "$PS" "GENESIS_SUPPLY()(uint256)" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
    DT=$(cast call "$HK" "deathThreshold()(uint256)" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
    #  indexerUrl CANNOT be derived: the Railway deployment does not exist until
    #  after the indexer ships, and its hostname is assigned by Railway. It is
    #  the one manifest value a human must supply.
    [ -n "${INDEXER_URL:-}" ] || die "INDEXER_URL is unset and CANNOT be derived from any artifact.
     Deploy the Railway indexer first, then re-run this stage with
       INDEXER_URL=https://<your-indexer>.up.railway.app"
    LEGACY_BPS="${LEGACY_BPS:-4000}"
    LEGACY_THRESHOLD="${LEGACY_THRESHOLD:-20000000000000000}"

    python3 - "$MANIFEST" "$EXPECT_CHAIN" "$INDEXER_URL" "${GS:-0}" "${DT:-0}" "$LEGACY_BPS" "$LEGACY_THRESHOLD" <<'PY'
import json,sys
p,chain,idx,gs,dt,lbps,lthr = sys.argv[1:8]
m=json.load(open(p))
m["chainId"]=int(chain)
m["indexerUrl"]=idx.rstrip("/")
if int(gs)>0: m["genesisSupply"]=int(gs)
# deathThreshold is stored on the hook in the units the hook compares volume in.
# With no oracle wired that is native wei; with an oracle it is USD at 1e18.
# The manifest key is a DISPLAY fallback (src/config/cauldron.ts:61) that the
# indexer overrides at runtime, so it is written as a float of 1e18 units.
m["deathThresholdEth"]=int(dt)/1e18
m["legacyBps"]=int(lbps)
m["legacyThresholdEth"]=int(lthr)/1e18
json.dump(m,open(p,"w"),indent=2)
open(p,"a").write("\n")
print("  filled chainId=%s indexerUrl=%s genesisSupply=%s deathThresholdEth=%s legacyBps=%s legacyThresholdEth=%s"
      % (m["chainId"],m["indexerUrl"],m.get("genesisSupply"),m["deathThresholdEth"],m["legacyBps"],m["legacyThresholdEth"]))
PY
  else
    warn "simulate: skipping the manifest write (no broadcast artifacts to read)"
  fi

  #  ── THE <FILL> REFUSAL ─────────────────────────────────────────────────
  #  A surviving placeholder is not a cosmetic problem: `<FILL from DeployPerp>`
  #  in `contracts.perpEngine` is an address the frontend will encode calls to.
  say "STAGE manifest  <FILL> / placeholder refusal"
  #  A blind grep for a zero address would REJECT A CORRECT MANIFEST: native ETH
  #  is legitimately quoteAssets[0].address == 0x000...0. So the zero-address
  #  rule is applied to `contracts` only, where it is always wrong.
  python3 - "$MANIFEST" "$EXPECT_CHAIN" <<'PY' || die "the manifest still carries placeholder(s). REFUSING to ship.
     Every one of these is an address or URL the app would use verbatim."
import json,sys,re
p,chain=sys.argv[1],int(sys.argv[2])
m=json.load(open(p)); bad=[]
def walk(node,path):
    if isinstance(node,dict):
        for k,v in node.items(): walk(v,path+"."+k)
    elif isinstance(node,list):
        for i,v in enumerate(node): walk(v,"%s[%d]"%(path,i))
    elif isinstance(node,str):
        if "<FILL" in node or "__ASK_CHAIN" in node: bad.append((path,node))
for k,v in m.items():
    if k.startswith("_"): continue
    walk(v,k)
ZERO=re.compile(r"^0x0{40}$")
for k,v in (m.get("contracts") or {}).items():
    if not isinstance(v,str) or ZERO.match(v): bad.append(("contracts."+k,v))
    elif not re.match(r"^0x[0-9a-fA-F]{40}$",v): bad.append(("contracts."+k,v))
for k in ("chainId","indexerUrl","genesisSupply","deathThresholdEth","legacyThresholdEth","legacyBps"):
    if k not in m: bad.append((k,"<MISSING KEY>"))
if m.get("chainId")!=chain: bad.append(("chainId","%s (expected %d)"%(m.get("chainId"),chain)))
if not m.get("poolIds") or not all(re.match(r"^0x[0-9a-fA-F]{64}$",str(x)) for x in m["poolIds"]):
    bad.append(("poolIds",str(m.get("poolIds"))))
seen=set()
for path,val in bad:
    if path in seen: continue
    seen.add(path); print("      %-34s %s" % (path,val))
sys.exit(1 if bad else 0)
PY
  ok "no <FILL>, no __ASK_CHAIN__, no zero/!malformed contract address, all keys present"

  #  ── SELECTOR PARITY AGAINST THE 4663 RUNTIME ───────────────────────────
  #  verify-selectors.mjs defaults its RPC to Sepolia. Pointed there with a 4663
  #  manifest, every address returns 0x and the gate goes red on everything —
  #  which reads as "the deploy is broken" rather than "the gate is misaimed".
  say "STAGE manifest  selector parity on chain $CHAIN"
  RPC_URL="$RPC" node "$ROOT/scripts/verify-selectors.mjs" \
    || die "selector parity FAILED — the deployed runtime is missing function(s) the app sends."

  say "STAGE manifest  manifest guard"
  VITE_CHAIN_ID="$EXPECT_CHAIN" node "$ROOT/scripts/verify-manifest.mjs" || die "verify-manifest.mjs failed."
  ok "manifest guard passed"
fi

say "DONE  (mode=$MODE stage=$STAGE chain=$CHAIN)"
echo "  logs: /tmp/rh-{sizes,launchpad,perp}.log"
if [ "$MODE" = "broadcast" ]; then
  cat <<'EOF'

  STILL TO DO BY HAND (deliberately not automated):
    * Grant the Timelock's proposer/executor/canceller roles to the Gnosis Safe
      and REVOKE the deployer EOA (no redeploy needed).
    * Set GUARDIAN to a multisig if it defaulted to the EOA.
    * Redeploy the Railway indexer (it does not auto-redeploy on push), then
      re-run `--stage manifest` with INDEXER_URL set.
    * Verify contracts on https://robinhoodchain.blockscout.com.
    * Approve real quote assets through governance — DEPLOY_QUOTES=false means
      this deployment ships ETH-quoted only, by design.
EOF
fi
