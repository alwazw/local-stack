#!/bin/sh
# Affine entrypoint wrapper — reads DATABASE_URL from Docker secret
# then chains to the original docker-entrypoint.sh
set -e

if [ -f /run/secrets/affine_database_url ]; then
    export DATABASE_URL="$(cat /run/secrets/affine_database_url | tr -d '\n\r')"
fi

if [ -f /run/secrets/redis_password ]; then
    export REDIS_SERVER_PASSWORD="$(cat /run/secrets/redis_password | tr -d '\n\r')"
fi

echo "[affine-wrapper] DATABASE_URL is set: $([ -n "$DATABASE_URL" ] && echo 'YES' || echo 'NO')" >&2
echo "[affine-wrapper] Starting Affine via docker-entrypoint.sh" >&2

# Chain to the original entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
