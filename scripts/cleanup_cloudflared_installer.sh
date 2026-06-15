#!/bin/sh
# Cleanup script — removes cloudflared-installer container after
# validating cloudflared has established tunnel connections.
# Run as: bash /tmp/cleanup_cloudflared_installer.sh

set -e

# Check if cloudflared-installer exists and is in exited state
STATUS=$(docker inspect cloudflared-installer --format '{{.State.Status}}' 2>/dev/null || echo "none")
if [ "$STATUS" != "exited" ]; then
    echo "⏭️  cloudflared-installer not ready for cleanup (status: $STATUS)"
    exit 0
fi

# Validate cloudflared tunnel connections are established
CONNECTIONS=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep -c "Registered tunnel connection")

if [ "$CONNECTIONS" -ge 1 ]; then
    echo "✅ cloudflared has $CONNECTIONS registered tunnel connections"
    echo "🗑️  Removing cloudflared-installer container..."
    docker rm cloudflared-installer 2>/dev/null && echo "✅ Container removed" || echo "⚠️  Failed to remove container"
else
    echo "⚠️  cloudflared has $CONNECTIONS registered connections — not removing installer yet"
    exit 1
fi
