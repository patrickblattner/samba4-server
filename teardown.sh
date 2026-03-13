#!/bin/bash
# ============================================================================
# Samba 4 AD DC - Teardown Script
# Removes all containers, volumes, and generated files
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

if [ ! -d "${DEPLOY_DIR}" ]; then
  echo "No deployment found at ${DEPLOY_DIR}. Nothing to do."
  exit 0
fi

echo ""
echo -e "${RED}This will remove all Samba AD containers, volumes, and generated config.${NC}"
read -rp "Are you sure? [y/N]: " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

info "Stopping and removing containers..."
cd "${DEPLOY_DIR}"
docker compose --profile seed down -v 2>/dev/null || true

info "Removing generated files..."
rm -rf "${DEPLOY_DIR}"

ok "Teardown complete. All containers, volumes, and generated files removed."
echo ""
