#!/bin/sh
# Hermes WebUI entrypoint wrapper — reads password from Docker secret
# and exports it as HERMES_WEBUI_PASSWORD before starting the service.

set -e

# Read password from Docker secret
if [ -f /run/secrets/hermes_password ]; then
    export HERMES_WEBUI_PASSWORD=$(cat /run/secrets/hermes_password | tr -d '\n\r')
    echo "[entrypoint] Loaded HERMES_WEBUI_PASSWORD from secret" >&2
else
    echo "[entrypoint] ERROR: hermes_password secret not found at /run/secrets/hermes_password" >&2
    exit 1
fi

# Execute the original entrypoint/command
exec "$@"
