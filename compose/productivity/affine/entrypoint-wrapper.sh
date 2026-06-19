#!/bin/sh
# Affine entrypoint wrapper — reads DATABASE_URL from Docker secret,
# runs migrations, then chains to the original docker-entrypoint.sh
set -e

if [ -f /run/secrets/affine_database_url ]; then
    export DATABASE_URL="$(cat /run/secrets/affine_database_url | tr -d '\n\r')"
fi

if [ -f /run/secrets/redis_password ]; then
    export REDIS_SERVER_PASSWORD="$(cat /run/secrets/redis_password | tr -d '\n\r')"
fi

echo "[affine-wrapper] DATABASE_URL is set: $([ -n "$DATABASE_URL" ] && echo 'YES' || echo 'NO')" >&2

# Run migrations before starting the main process
# Migrations are idempotent — safe to run on every startup
echo "[affine-wrapper] Running database migrations..." >&2
node ./scripts/self-host-predeploy.js

echo "[affine-wrapper] Starting Affine via docker-entrypoint.sh" >&2

# Chain to the original entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
