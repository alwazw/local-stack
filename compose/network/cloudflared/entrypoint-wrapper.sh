#!/bin/sh
# Cloudflared entrypoint wrapper — reads tunnel token from Docker secret
# and passes it to cloudflared tunnel run command.
#
# Usage: Mounted as /entrypoint-wrapper.sh, set as container entrypoint.
# The TUNNEL_ID environment variable should be set in docker-compose.yml.

set -e

# Read tunnel token from Docker secret
TOKEN_FILE="/run/secrets/cf_tunnel_token"

if [ -f "$TOKEN_FILE" ]; then
    TUNNEL_TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n\r')
    export TUNNEL_TOKEN
    echo "[entrypoint] Loaded Cloudflare tunnel token from secret" >&2
else
    echo "[entrypoint] ERROR: Cloudflare tunnel token not found at $TOKEN_FILE" >&2
    exit 1
fi

echo "[entrypoint] Starting cloudflared tunnel" >&2

# Run cloudflared with the token (non-destructive mode, no auto-update)
exec cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
