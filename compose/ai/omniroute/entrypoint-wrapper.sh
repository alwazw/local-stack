#!/bin/sh
# Omniroute entrypoint wrapper — reads Redis password from Docker secret
# and constructs the REDIS_URL before starting the service.

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

# Execute the original command
exec "$@"
