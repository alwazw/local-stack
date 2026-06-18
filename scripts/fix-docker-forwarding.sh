#!/bin/bash
# Fix Docker outbound internet access on WSL2
# Docker Desktop on WSL2 sometimes loses FORWARD chain rules for custom bridge networks.
# This script auto-discovers all Docker bridge networks and adds explicit ACCEPT rules
# so containers can reach the internet and communicate intra-network.
#
# Run after WSL2 restart or Docker Desktop restart:
#   sudo bash /mnt/d/docker/scripts/fix-docker-forwarding.sh

set -e

ETH_IFACE="eth0"

echo "Discovering Docker bridge networks..."

# Auto-discover all bridge networks and their interfaces
ip -o link show | grep -oP 'br-[a-f0-9]+' | sort -u | while read BRIDGE; do
    # Find network name for this bridge
    NET_NAME=""
    while IFS=: read -r NAME ID; do
        if ip link show "$BRIDGE" 2>/dev/null | grep -q "${ID:0:12}"; then
            NET_NAME="$NAME"
            break
        fi
    done < <(docker network ls --format '{{.Name}}:{{.ID}}')

    if [ -z "$NET_NAME" ]; then
        NET_NAME="unknown"
    fi

    if ip link show "$BRIDGE" &>/dev/null; then
        # Intra-bridge: container ↔ container on same network
        if ! sudo iptables -C FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT 2>/dev/null; then
            sudo iptables -I FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT
            echo "  ✓ Added intra-bridge FORWARD for $NET_NAME ($BRIDGE)"
        else
            echo "  - Intra-bridge rule exists for $NET_NAME ($BRIDGE)"
        fi

        # Outbound: container → internet
        if ! sudo iptables -C FORWARD -i "$BRIDGE" -o "$ETH_IFACE" -j ACCEPT 2>/dev/null; then
            sudo iptables -I FORWARD -i "$BRIDGE" -o "$ETH_IFACE" -j ACCEPT
            echo "  ✓ Added outbound FORWARD for $NET_NAME ($BRIDGE)"
        else
            echo "  - Outbound rule exists for $NET_NAME ($BRIDGE)"
        fi

        # Inbound: internet → container (return traffic)
        if ! sudo iptables -C FORWARD -i "$ETH_IFACE" -o "$BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
            sudo iptables -I FORWARD -i "$ETH_IFACE" -o "$BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT
            echo "  ✓ Added inbound FORWARD for $NET_NAME ($BRIDGE)"
        else
            echo "  - Inbound rule exists for $NET_NAME ($BRIDGE)"
        fi
    else
        echo "  ✗ Bridge $BRIDGE ($NET_NAME) not found"
    fi
done

echo ""
echo "Done. Docker containers should now have full connectivity."
echo "Verify with: docker exec <container> curl -s https://api.telegram.org"
