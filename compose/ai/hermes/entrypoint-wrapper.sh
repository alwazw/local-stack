#!/bin/sh
# Hermes WebUI entrypoint wrapper — reads password from Docker secret
# and exports it as HERMES_WEBUI_PASSWORD before starting the service.

set -e

# Read password from Docker secret
if [ -f /run/secrets/hermes_password ]; then
#    export HERMES_WEBUI_PASSWORD=$(cat /run/secrets/hermes_password | tr -d '\n\r')
#    echo "[entrypoint] Loaded HERMES_WEBUI_PASSWORD from secret" >&2
    PASSWORD=$(cat /run/secrets/hermes_password | tr -d '\n\r')
    # Write directly to the location start.sh sources after dropping root
    echo "HERMES_WEBUI_PASSWORD=\"$PASSWORD\"" > /apptoo/.env
    echo "[entrypoint] Safely stored HERMES_WEBUI_PASSWORD in /apptoo/.env" >&2
else
    echo "[entrypoint] ERROR: hermes_password secret not found at /run/secrets/hermes_password" >&2
    exit 1
fi

# Execute the original entrypoint/command
exec "$@"
