#!/bin/sh
# Traefik entrypoint wrapper — reads secrets from Docker-mounted files
# and exports them as environment variables before starting Traefik.
#
# Usage: Mounted as /entrypoint-wrapper.sh, set as container entrypoint.
# Original Traefik command is passed as arguments.

set -e

# Read secrets from Docker secrets mount
for secret_file in /run/secrets/*; do
    secret_name=$(basename "$secret_file")
    # Skip directories
    [ -f "$secret_file" ] || continue
    
    case "$secret_name" in
        cf_dns_api_token)
            export CF_DNS_API_TOKEN=$(cat "$secret_file" | tr -d '\n\r')
            echo "[entrypoint] Loaded CF_DNS_API_TOKEN from secret" >&2
            ;;
        cf_api_key)
            export CF_API_KEY=$(cat "$secret_file" | tr -d '\n\r')
            echo "[entrypoint] Loaded CF_API_KEY from secret" >&2
            ;;
        cf_api_email)
            export CF_API_EMAIL=$(cat "$secret_file" | tr -d '\n\r')
            echo "[entrypoint] Loaded CF_API_EMAIL from secret" >&2
            ;;
        *)
            # Export any other secrets with uppercase name
            export "$(echo "$secret_name" | tr '[:lower:]' '[:upper:]')"=$(cat "$secret_file" | tr -d '\n\r')
            echo "[entrypoint] Loaded $secret_name from secret" >&2
            ;;
    esac
done

# Verify required secrets are loaded
if [ -z "$CF_DNS_API_TOKEN" ] && [ -z "$CF_API_KEY" ]; then
    echo "[entrypoint] ERROR: Neither CF_DNS_API_TOKEN nor CF_API_KEY secret found" >&2
    echo "[entrypoint] ERROR: Mount cf_dns_api_token or cf_api_key as Docker secret" >&2
    exit 1
fi

if [ -z "$CF_API_EMAIL" ]; then
    echo "[entrypoint] WARNING: CF_API_EMAIL not set, DNS challenge may fail" >&2
fi

echo "[entrypoint] Starting Traefik with secrets loaded" >&2

# Traefik's original entrypoint prepends 'traefik' if args start with '-'
# We need to do the same here since we're replacing the entrypoint
if [ "${1#-}" != "$1" ]; then
    set -- traefik "$@"
fi

# Execute the original command (Traefik)
exec "$@"
