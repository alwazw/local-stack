#!/bin/sh
set -e

# Read secrets from Docker secrets files
if [ -f /run/secrets/authentik_secret ]; then
    export AUTHENTIK_SECRET_KEY=$(cat /run/secrets/authentik_secret)
fi

if [ -f /run/secrets/redis_password ]; then
    export AUTHENTIK_REDIS__PASSWORD=$(cat /run/secrets/redis_password)
fi

if [ -f /run/secrets/postgres_password ]; then
    export AUTHENTIK_POSTGRESQL__PASSWORD=$(cat /run/secrets/postgres_password)
fi

# Execute the main command
exec "$@"
