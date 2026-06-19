#!/bin/sh
# Cloudflared self-contained entrypoint wrapper
# Downloads cloudflared binary on first run (cached in volume), then runs tunnel
set -e

CLOUDFLARED_BIN="/data/cloudflared"
CLOUDFLARED_VERSION="${CLOUDFLARED_VERSION:-latest}"

# Download cloudflared if not present or if version changed
if [ ! -f "$CLOUDFLARED_BIN" ] || [ ! -x "$CLOUDFLARED_BIN" ]; then
    echo "[entrypoint] Downloading cloudflared binary..." >&2
    apk add --no-cache curl >/dev/null 2>&1 || true
    curl -fSL "https://github.com/cloudflare/cloudflared/releases/${CLOUDFLARED_VERSION}/download/cloudflared-linux-amd64" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
    echo "[entrypoint] Cloudflared downloaded successfully" >&2
fi

# Read tunnel token from Docker secret
TOKEN_FILE="/run/secrets/cf_tunnel_token"

if [ -f "$TOKEN_FILE" ]; then
    TUNNEL_TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n\r')
    echo "[entrypoint] Loaded Cloudflare tunnel token from secret" >&2
else
    echo "[entrypoint] ERROR: Cloudflare tunnel token not found at $TOKEN_FILE" >&2
    exit 1
fi

echo "[entrypoint] Starting cloudflared tunnel (HTTP/2 protocol)" >&2

# Run cloudflared with the token
# --no-autoupdate: binary is managed by this script
# --protocol http2: QUIC doesn't work on WSL2 Docker networking
exec "$CLOUDFLARED_BIN" tunnel --no-autoupdate --protocol http2 run --token "$TUNNEL_TOKEN"
