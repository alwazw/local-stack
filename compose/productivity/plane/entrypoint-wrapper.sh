#!/bin/sh
# Plane entrypoint wrapper — reads DATABASE_URL and REDIS_URL from Docker secrets
# then chains to the original entrypoint script
set -e

if [ -f /run/secrets/plane_database_url ]; then
    export DATABASE_URL="$(cat /run/secrets/plane_database_url | tr -d '\n\r')"
fi

if [ -f /run/secrets/plane_redis_url ]; then
    export REDIS_URL="$(cat /run/secrets/plane_redis_url | tr -d '\n\r')"
fi

if [ -f /run/secrets/plane_secret_key ]; then
    export SECRET_KEY="$(cat /run/secrets/plane_secret_key | tr -d '\n\r')"
fi

echo "[plane-wrapper] DATABASE_URL is set: $([ -n "$DATABASE_URL" ] && echo 'YES' || echo 'NO')" >&2
echo "[plane-wrapper] REDIS_URL is set: $([ -n "$REDIS_URL" ] && echo 'YES' || echo 'NO')" >&2
echo "[plane-wrapper] Starting Plane via original entrypoint" >&2

# Chain to the original entrypoint
exec "$@"
