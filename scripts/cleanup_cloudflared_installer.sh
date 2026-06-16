#!/bin/sh
# Cleanup + validation script for cloudflared
# 1. Validates tunnel connections AND transport protocol
# 2. Removes cloudflared-installer container when ready
# 3. Reports QUIC vs HTTP/2 status

echo "=== Cloudflared Validation ==="

# Check if cloudflared-installer exists
STATUS=$(docker inspect cloudflared-installer --format '{{.State.Status}}' 2>/dev/null || echo "none")

# Validate tunnel connections (use || true to avoid grep -c exit code 1)
CONNECTIONS=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep -c "Registered tunnel connection" || true)
QUIC_CONN=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep "Registered tunnel connection" | grep -c "protocol=quic" || true)
HTTP2_CONN=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep "Registered tunnel connection" | grep -c "protocol=http2" || true)

DEGRADED=$(docker compose logs cloudflared --tail 50 2>/dev/null | grep -c "degraded transport" || true)

echo "Tunnel connections: $CONNECTIONS (QUIC: $QUIC_CONN, HTTP/2: $HTTP2_CONN)"

if [ "$DEGRADED" -gt 0 ] 2>/dev/null; then
    echo "⚠️  Running in DEGRADED mode (HTTP/2 fallback — QUIC UDP 7844 blocked)"
    echo "   Likely cause: WSL2/Windows Firewall blocking outbound UDP port 7844"
    echo "   Tunnel is functional but suboptimal"
fi

if [ "$CONNECTIONS" -ge 1 ] 2>/dev/null; then
    if [ "$STATUS" = "exited" ]; then
        echo "🗑️  Removing cloudflared-installer container..."
        docker rm cloudflared-installer 2>/dev/null && echo "✅ Container removed" || echo "⚠️  Failed to remove"
    else
        echo "⏭️  cloudflared-installer status: $STATUS (not ready for cleanup)"
    fi
else
    echo "❌ No tunnel connections — cloudflared not working"
    exit 1
fi
