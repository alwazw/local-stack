#!/bin/sh
# Omniroute entrypoint wrapper — reads Redis password from Docker secret,
# runs the original permission check script, then starts the service.

set -e

# Read Redis password from Docker secret
if [ -f /run/secrets/redis_password ]; then
    REDIS_PASS=$(cat /run/secrets/redis_password | tr -d '\n\r')
    export REDIS_URL="redis://:${REDIS_PASS}@redis:6379"
    echo "[entrypoint] Loaded REDIS_URL from secret" >&2
else
    echo "[entrypoint] ERROR: redis_password secret not found" >&2
    exit 1
fi

# Run the original permission check (from omniroute image entrypoint)
if [ -x /tmp/check-permissions.sh ]; then
    echo "[entrypoint] Running permission check" >&2
    /tmp/check-permissions.sh >&2 || true
fi

# Execute the original command (node dev/run-standalone.mjs)
echo "[entrypoint] Starting Omniroute" >&2
exec "$@"
