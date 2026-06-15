#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[ -f .env ] || { echo "ERROR: .env missing"; exit 1; }
source .env

echo "[1/4] Secrets..."
mkdir -p secrets
for s in postgres_password redis_password authentik_secret litellm_key cf_api_key cf_tunnel_token guac_admin_pass vw_admin_token gitea_secret n8n_key; do
  [ -f "secrets/${s}.txt" ] || openssl rand -base64 32 > "secrets/${s}.txt"
  chmod 600 "secrets/${s}.txt"
done

echo "[2/4] Networks..."
for net in proxy database security apps monitoring management; do
  if ! docker network inspect $net >/dev/null 2>&1; then
    [ "$net" = "database" ] && docker network create $net --internal || docker network create $net
  fi
done
# ai-ml must NOT be internal (services need host port access)
if ! docker network inspect ai-ml >/dev/null 2>&1; then
  docker network create ai-ml
fi

echo "[3/4] Data dirs..."
mkdir -p compose/data/postgres/data compose/data/redis/data compose/ai/ollama/models compose/ai/openwebui/data
chown -R 999:999 compose/data/postgres/data 2>/dev/null || true

echo "[4/4] Done. Deploy core: cd compose/network/traefik && docker compose up -d"
