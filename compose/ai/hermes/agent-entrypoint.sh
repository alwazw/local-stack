#!/bin/sh
set -e

# 1. Setup paths for tools
MCP_BIN="/home/hermes/.hermes/mcp-bin"
export PATH="$MCP_BIN:$PATH"

# 2. Dynamic Secret Ingestion & s6-overlay Injection Engine
if [ -d /run/secrets ]; then
    echo "[Runtime Init] Extracting runtime credentials and injecting into service trees..." >&2
    
    # Create s6 environment override directory if it exists, otherwise fall back to standard profiles
    S6_ENV_DIR="/var/run/s6/container-environment"
    mkdir -p "$S6_ENV_DIR" 2>/dev/null || true

    for secret_file in /run/secrets/*; do
        if [ -f "$secret_file" ]; then
            secret_name=$(basename "$secret_file" | tr '[:lower:]' '[:upper:]')
            secret_value=$(cat "$secret_file" | tr -d '\r\n')

            # Export to the current shell memory
            export "$secret_name"="$secret_value"

            # CRITICAL FOR S6-OVERLAY: Write the variable to the s6 environment pool
            if [ -d "$S6_ENV_DIR" ]; then
                echo -n "$secret_value" > "$S6_ENV_DIR/$secret_name"
            fi
        fi
    done
fi

# 3. Handle dependency steps
if ! command -v qdrant-mcp-server >/dev/null 2>&1; then
    echo "[agent-entrypoint] Installing qdrant-mcp-server..." >&2
    mkdir -p "$MCP_BIN"
    npm install --prefix "$MCP_BIN" @mhalder/qdrant-mcp-server 2>&1 | tail -3
    ln -sf "$MCP_BIN/node_modules/.bin/qdrant-mcp-server" "$MCP_BIN/qdrant-mcp-server" 2>/dev/null || true
fi

# 4. Ensure gateway auto-starts on boot.
#    hermes_cli.container_boot reads $HERMES_HOME/gateway_state.json —
#    only state "running" triggers auto-start; anything else (missing,
#    draining, stopped) creates a `down` file that silently blocks the
#    gateway. Seed "running" if no state file exists or if it's stale.
HERMES_HOME="${HERMES_HOME:-/home/hermes/.hermes}"
GATEWAY_STATE="$HERMES_HOME/gateway_state.json"
if [ ! -f "$GATEWAY_STATE" ]; then
    echo "[agent-entrypoint] Seeding gateway_state.json for auto-start" >&2
    printf '{"gateway_state":"running","timestamp":0,"seeded_by":"entrypoint"}\n' > "$GATEWAY_STATE"
fi

# 5. Final handoff to process monitor
exec /init