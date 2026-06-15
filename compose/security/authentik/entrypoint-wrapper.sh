#!/bin/sh
# Authentik entrypoint wrapper — reads secrets from Docker-mounted files
# and exports them with the correct Authentik environment variable names.
#
# Usage: Set as container entrypoint. The original command is passed as arguments.

set -e

# Read secrets and export with Authentik-specific env var names
if [ -f /run/secrets/authentik_secret ]; then
    export AUTHENTIK_SECRET_KEY=$(cat /run/secrets/authentik_secret | tr -d '\n\r')
    echo "[entrypoint] Loaded AUTHENTIK_SECRET_KEY" >&2
fi

if [ -f /run/secrets/redis_password ]; then
    export AUTHENTIK_REDIS__PASSWORD=$(cat /run/secrets/redis_password | tr -d '\n\r')
    echo "[entrypoint] Loaded AUTHENTIK_REDIS__PASSWORD" >&2
fi

if [ -f /run/secrets/postgres_password ]; then
    export AUTHENTIK_POSTGRESQL__PASSWORD=$(cat /run/secrets/postgres_password | tr -d '\n\r')
    echo "[entrypoint] Loaded AUTHENTIK_POSTGRESQL__PASSWORD" >&2
fi

# Export any other secrets as-is (uppercase)
for secret_file in /run/secrets/*; do
    [ -f "$secret_file" ] || continue
    secret_name=$(basename "$secret_file")
    env_var=$(echo "$secret_name" | tr '[:lower:]' '[:upper:]')
    # Skip if already handled with specific names above
    case "$env_var" in
        AUTHENTIK_SECRET|REDIS_PASSWORD|POSTGRES_PASSWORD) continue ;;
    esac
    # Only export if not already set
    if [ -z "$(eval echo \$$env_var)" ]; then
        export "$env_var"=$(cat "$secret_file" | tr -d '\n\r')
        echo "[entrypoint] Loaded $env_var from /run/secrets/$secret_name" >&2
    fi
done

# Execute the original command
exec "$@"
