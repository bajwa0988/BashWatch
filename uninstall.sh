#!/usr/bin/env bash
# =============================================================================
#  BashWatch Uninstaller
#  Run as root:  sudo bash uninstall.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "Run as root: sudo bash uninstall.sh"

INSTALL_DIR="/home/kali/bashwatch"
SERVICE_FILE="/etc/systemd/system/bashwatch.service"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      BashWatch — Uninstaller v1.0            ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

info "Stopping BashWatch service..."
systemctl stop bashwatch.service  2>/dev/null || true
systemctl disable bashwatch.service 2>/dev/null || true
success "Service stopped and disabled."

info "Removing service file..."
rm -f "$SERVICE_FILE"
systemctl daemon-reload
success "Service file removed."

# Offer to keep logs/forensics
read -rp "Delete logs and forensic bundles too? [y/N]: " choice
if [[ "${choice,,}" == "y" ]]; then
    rm -rf "$INSTALL_DIR"
    success "All BashWatch files removed."
else
    # Remove just the script; keep logs
    rm -f "${INSTALL_DIR}/bashwatch.sh"
    success "Script removed. Logs kept at ${INSTALL_DIR}/logs/"
fi

echo ""
success "Uninstall complete."
