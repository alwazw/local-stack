#!/usr/bin/env bash
# fix-docker-networking.sh — Restore Docker bridge networking on WSL2
#
# ROOT CAUSE: WSL2 kernel sets bridge-nf-call-iptables=1, which routes
# L2 bridge traffic through iptables FORWARD chain. Docker Desktop's
# nftables/iptables backend creates ACCEPT rules only for docker0 (default
# bridge) but NOT for user-defined bridges. Combined with FORWARD policy DROP,
# this silently blocks ALL inter-container and outbound traffic on custom networks.
#
# This script is idempotent — safe to run multiple times.
# Run with: sudo bash /mnt/d/docker/scripts/fix-docker-networking.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[FIX]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check root
if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root (sudo)"
  exit 1
fi

# Check if bridge-nf-call-iptables is the problem
BRIDGE_NF=$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo "0")

if [[ "$BRIDGE_NF" != "1" ]]; then
  log_info "bridge-nf-call-iptables is OFF — Docker networking should be fine"
  exit 0
fi

log_warn "bridge-nf-call-iptables is ON — checking if Docker bridge rules are missing..."

# Check if the FORWARD chain has policy DROP with no bridge rules
FORWARD_POLICY=$(iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "ACCEPT")

if [[ "$FORWARD_POLICY" != "DROP" ]]; then
  log_info "FORWARD chain policy is $FORWARD_POLICY — no fix needed"
  exit 0
fi

# Check if our rules already exist
if iptables -C FORWARD -m physdev --physdev-is-bridged -j ACCEPT 2>/dev/null; then
  log_info "Same-bridge ACCEPT rule already exists — networking is patched"
else
  log_info "Adding same-bridge traffic ACCEPT rule..."
  iptables -I FORWARD 1 -m physdev --physdev-is-bridged -j ACCEPT
  log_info "Added: ACCEPT for same-bridge (inter-container) traffic"
fi

if iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
  log_info "RELATED,ESTABLISHED ACCEPT rule already exists"
else
  log_info "Adding RELATED,ESTABLISHED ACCEPT rule..."
  iptables -I FORWARD 2 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  log_info "Added: ACCEPT for RELATED,ESTABLISHED connections"
fi

# Find the primary outbound interface
OUTBOUND_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
if [[ -n "$OUTBOUND_IFACE" ]]; then
  if iptables -C FORWARD -o "$OUTBOUND_IFACE" -j ACCEPT 2>/dev/null; then
    log_info "Outbound ACCEPT rule for $OUTBOUND_IFACE already exists"
  else
    log_info "Adding outbound ACCEPT rule for $OUTBOUND_IFACE..."
    iptables -I FORWARD 3 -o "$OUTBOUND_IFACE" -j ACCEPT
    log_info "Added: ACCEPT for outbound container traffic via $OUTBOUND_IFACE"
  fi
else
  log_warn "Could not detect outbound interface — skipping outbound rule"
fi

# Add MASQUERADE for any Docker bridge networks missing NAT rules
log_info "Checking MASQUERADE rules for Docker networks..."
docker network ls --format '{{.Name}}' 2>/dev/null | while read -r net; do
  subnet=$(docker network inspect "$net" --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || true)
  bridge=$(docker network inspect "$net" --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)
  
  if [[ -n "$subnet" && -n "$bridge" && "$bridge" != "" ]]; then
    if ! iptables -t nat -C POSTROUTING -s "$subnet" ! -o "$bridge" -j MASQUERADE 2>/dev/null; then
      iptables -t nat -A POSTROUTING -s "$subnet" ! -o "$bridge" -j MASQUERADE
      log_info "Added MASQUERADE for $net ($subnet via $bridge)"
    fi
  fi
done

log_info "Docker networking fix applied successfully!"
log_info "Run 'docker ps' to verify containers are healthy"
