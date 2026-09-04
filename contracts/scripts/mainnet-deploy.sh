#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# MiFrens — Mainnet Deployment Runbook
#
# Interactive step-by-step guide for deploying the full MiFrens stack:
#   MiFrens NFT + FrenForge + FrenMarket
#
# Usage:
#   bash contracts/scripts/mainnet-deploy.sh
#   bash contracts/scripts/mainnet-deploy.sh --from-step 4   # resume from step 4
# ═══════════════════════════════════════════════════════════════════════════════

NETWORK="mainnet"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
ROOT_DIR="$(cd "$CONTRACTS_DIR/.." && pwd)"
DEPLOYMENTS_FILE="$CONTRACTS_DIR/deployments/mainnet.json"

# Parse --from-step argument
FROM_STEP=0
for arg in "$@"; do
    case "$arg" in
        --from-step)
            shift
            FROM_STEP="${1:-0}"
            shift
            ;;
        --from-step=*)
            FROM_STEP="${arg#*=}"
            ;;
    esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

banner() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

step_header() {
    local step_num="$1"
    local title="$2"
    echo ""
    echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}  Step $step_num: $title${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"
}

prompt_continue() {
    local msg="${1:-Press [Enter] to continue, [s] to skip}"
    echo ""
    read -rp "  $msg: " choice
    if [[ "$choice" == "s" || "$choice" == "S" ]]; then
        echo -e "  ${YELLOW}Skipped.${NC}"
        return 1
    fi
    return 0
}

run_cmd() {
    echo -e "  ${CYAN}\$ $*${NC}"
    echo ""
    if ! "$@"; then
        echo ""
        echo -e "  ${RED}FAILED: $*${NC}"
        echo -e "  ${RED}Fix the issue and re-run with --from-step to resume.${NC}"
        exit 1
    fi
    echo ""
    echo -e "  ${GREEN}Done.${NC}"
}

should_run() {
    local step_num="$1"
    [[ "$step_num" -ge "$FROM_STEP" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════

banner "MiFrens — Mainnet Deployment Runbook"

echo "  Network:    $NETWORK"
echo "  Contracts:  $CONTRACTS_DIR"
echo "  From step:  $FROM_STEP"
echo ""

# ─── Step 0: Pre-flight checks ───────────────────────────────────────────────

if should_run 0; then
    step_header 0 "Pre-flight checks"

    # Check DEPLOYER_MNEMONIC
    if [[ -z "${DEPLOYER_MNEMONIC:-}" ]]; then
        echo -e "  ${RED}ERROR: DEPLOYER_MNEMONIC environment variable is not set.${NC}"
        echo "  Export it before running this script:"
        echo "    export DEPLOYER_MNEMONIC=\"your mnemonic phrase here\""
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} DEPLOYER_MNEMONIC is set"

    # Check merkle.json
    MERKLE_JSON="$ROOT_DIR/compressed-traits/merkle.json"
    if [[ ! -f "$MERKLE_JSON" ]]; then
        echo -e "  ${RED}ERROR: compressed-traits/merkle.json not found.${NC}"
        echo "  Run: node scripts/compress-traits.mjs"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} merkle.json exists"

    # Check node_modules
    if [[ ! -d "$CONTRACTS_DIR/node_modules" ]]; then
        echo -e "  ${YELLOW}WARNING: contracts/node_modules not found. Run npm install first.${NC}"
    fi
    echo -e "  ${GREEN}✓${NC} Pre-flight checks passed"

    echo ""
    echo -e "  ${BOLD}Confirm the deployer wallet has sufficient BTC for mainnet fees.${NC}"
    prompt_continue "Press [Enter] when funded and ready" || true
fi

# ─── Step 1: Build all contracts ─────────────────────────────────────────────

if should_run 1; then
    step_header 1 "Build all contracts (nft + forge + market)"

    echo "  This will compile nft.wasm, frenforge.wasm, and frenmarket.wasm"
    if prompt_continue; then
        run_cmd bash -c "cd '$CONTRACTS_DIR' && npm run build:all"
    fi
fi

# ─── Step 2: Deploy MiFrens NFT + FrenForge ──────────────────────────────────

if should_run 2; then
    step_header 2 "Deploy MiFrens NFT + FrenForge"

    echo "  Deploys both contracts and saves addresses to deployments/mainnet.json"
    if prompt_continue; then
        run_cmd npx tsx "$SCRIPTS_DIR/deploy-all.ts" --network "$NETWORK"
        echo ""
        echo -e "  ${BOLD}IMPORTANT: Verify both contracts on OPScan before continuing.${NC}"
        prompt_continue "Press [Enter] after verifying on OPScan" || true
    fi
fi

# ─── Step 3: Configure contracts ─────────────────────────────────────────────

if should_run 3; then
    step_header 3 "Configure contracts (link NFT <-> FrenForge, set metadata)"

    echo "  Links MiFrens NFT with FrenForge renderer and sets metadata"
    if prompt_continue; then
        run_cmd npx tsx "$SCRIPTS_DIR/configure-contracts.ts" --network "$NETWORK"
    fi
fi

# ─── Step 4: Batch inscribe all traits ───────────────────────────────────────

if should_run 4; then
    step_header 4 "Batch inscribe all traits"

    echo "  Inscribes all trait data on-chain. This may take a while."
    if prompt_continue; then
        run_cmd npx tsx "$SCRIPTS_DIR/batch-inscribe-all.ts" --network "$NETWORK"
    fi
fi

# ─── Step 5: Mint treasury reserve ───────────────────────────────────────────

if should_run 5; then
    step_header 5 "Mint treasury reserve (77 NFTs)"

    echo "  Mints 77 NFTs to the treasury wallet"
    if prompt_continue; then
        run_cmd npx tsx "$SCRIPTS_DIR/mint-reserve.ts" --network "$NETWORK"
    fi
fi

# ─── Step 6: Deploy & configure FrenMarket ───────────────────────────────────

if should_run 6; then
    step_header 6 "Deploy & configure FrenMarket"

    echo "  Deploys the FrenMarket marketplace contract"
    if prompt_continue; then
        run_cmd npx tsx "$SCRIPTS_DIR/deploy-frenmarket.ts" --network "$NETWORK"
    fi
fi

# ─── Step 7: Summary ─────────────────────────────────────────────────────────

if should_run 7; then
    step_header 7 "Deployment Summary"

    if [[ -f "$DEPLOYMENTS_FILE" ]]; then
        echo "  Deployment data from $DEPLOYMENTS_FILE:"
        echo ""
        cat "$DEPLOYMENTS_FILE"
        echo ""
    else
        echo -e "  ${YELLOW}WARNING: $DEPLOYMENTS_FILE not found.${NC}"
        echo "  Addresses may need to be collected manually from the deploy logs."
    fi

    echo ""
    echo -e "  ${BOLD}REMINDER:${NC} Update src/constants/contracts.ts with the mainnet addresses above."
    echo "  Look for the 'bc' (mainnet) entry and fill in miFrens, frenForge, frenMarket, and treasury."
fi

# ═══════════════════════════════════════════════════════════════════════════════

banner "Deployment Runbook Complete"
echo -e "  ${GREEN}All steps finished. MiFrens is live on mainnet.${NC}"
echo ""
