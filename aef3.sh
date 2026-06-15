#!/bin/bash
set -euo pipefail

ROOT="${1:-$HOME/docker}"
echo "=== AEF3 Full Stack Installer v3.0 ==="
echo "Target: $ROOT"
mkdir -p "$ROOT"
cd "$ROOT"

# Create full directory structure
dirs=(
  "compose/network/traefik"
  "compose/network/cloudflared"
  "compose/network/guacamole"
  "compose/data/postgres"
  "compose/data/redis"
  "compose/data/qdrant"
  "compose/security/authentik"
  "compose/security/vaultwarden"
  "compose/ai/ollama"
  "compose/ai/litellm"
  "compose/ai/openwebui"
  "compose/ai/agent-zero"
  "compose/ai/mcpo"
  "compose/ai/searxng"
  "compose/productivity/affine"
  "compose/productivity/logseq"
  "compose/productivity/plane"
  "compose/productivity/omniroute"
  "compose/dev/gitea"
  "compose/dev/woodpecker"
  "compose/automation/n8n"
  "compose/monitoring/uptime-kuma"
  "compose/monitoring/prometheus"
  "compose/monitoring/grafana"
  "compose/monitoring/loki"
  "compose/monitoring/dozzle"
  "compose/orchestration/homepage"
  "compose/orchestration/portainer"
  "compose/orchestration/dockge"
  "scripts"
  "templates/service-template"
  "docs"
  "secrets"
)

for d in "${dirs[@]}"; do mkdir -p "$d"; done

# === FULL .env.example (87 vars) ===
cat > .env.example << 'ENVEOF'
# AEF3 - Single Source of Truth
DOMAIN=home.local
TZ=Africa/Cairo
PUID=1000
PGID=1000
DATA_ROOT=/opt/aef3

# Ports
PORT_TRAEFIK_HTTP=80
PORT_TRAEFIK_HTTPS=443
PORT_POSTGRES=5432
PORT_REDIS=6379
PORT_QDRANT=6333
PORT_OLLAMA=11434
PORT_LITELLM=4000
PORT_OPENWEBUI=3000
PORT_AGENTZERO=8501
PORT_MCPO=8000
PORT_SEARXNG=8080
PORT_AUTHENTIK=9000
PORT_GUACAMOLE=8081
PORT_VAULTWARDEN=8082
PORT_AFFINE=8083
PORT_LOGSEQ=8084
PORT_PLANE=8085
PORT_GITEA=3001
PORT_WOODPECKER=8001
PORT_N8N=5678
PORT_UPTIME=3002
PORT_GRAFANA=3003
PORT_PROMETHEUS=9090
PORT_LOKI=3100
PORT_DOZZLE=9999
PORT_HOMEPAGE=3004
PORT_PORTAINER=9443
PORT_DOCKGE=5001

# Database
POSTGRES_USER=aef3
POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
POSTGRES_DB=aef3
REDIS_PASSWORD_FILE=/run/secrets/redis_password

# Authentik
AUTHENTIK_SECRET_KEY_FILE=/run/secrets/authentik_secret
AUTHENTIK_POSTGRESQL__PASSWORD_FILE=/run/secrets/postgres_password
AUTHENTIK_POSTGRESQL__USER=${POSTGRES_USER}
AUTHENTIK_POSTGRESQL__NAME=authentik

# Cloudflare
CF_API_EMAIL=you@example.com
CF_API_KEY_FILE=/run/secrets/cf_api_key
CF_TUNNEL_TOKEN_FILE=/run/secrets/cf_tunnel_token

# LiteLLM
LITELLM_MASTER_KEY_FILE=/run/secrets/litellm_key

# Guacamole
GUACAMOLE_ADMIN_PASSWORD_FILE=/run/secrets/guac_admin_pass

# Vaultwarden
VW_DOMAIN=https://vault.${DOMAIN}
VW_ADMIN_TOKEN_FILE=/run/secrets/vw_admin_token

# Gitea
GITEA_SECRET_KEY_FILE=/run/secrets/gitea_secret

# n8n
N8N_ENCRYPTION_KEY_FILE=/run/secrets/n8n_key
ENVEOF

# === bootstrap.sh ===
cat > scripts/bootstrap.sh << 'BOOTEOF'
#!/bin/bash
set -euo pipefail
ROOT="/opt/aef3"
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
for net in proxy database ai-ml security apps monitoring management; do
  if ! docker network inspect $net >/dev/null 2>&1; then
    [ "$net" = "database" ] || [ "$net" = "ai-ml" ] && docker network create $net --internal || docker network create $net
  fi
done

echo "[3/4] Data dirs..."
mkdir -p compose/data/postgres/data compose/data/redis/data compose/ai/ollama/models compose/ai/openwebui/data
chown -R 999:999 compose/data/postgres/data 2>/dev/null || true

echo "[4/4] Done. Deploy core: cd compose/network/traefik && docker compose up -d"
BOOTEOF
chmod +x scripts/bootstrap.sh

# === POSTGRES (full) ===
cat > compose/data/postgres/docker-compose.yml << 'PGEOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    env_file: [../../../.env]
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./data:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d:ro
    ports:
      - "${PORT_POSTGRES}:5432"
    networks:
      - database
    secrets:
      - postgres_password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "homepage.group=Data"
      - "homepage.name=PostgreSQL"
      - "homepage.icon=postgresql.png"
      - "homepage.href=http://postgres:${PORT_POSTGRES}"
      - "homepage.description=Primary database"

secrets:
  postgres_password:
    file: ../../../secrets/postgres_password.txt

networks:
  database:
    external: true
PGEOF

# === TRAEFIK (full) ===
cat > compose/network/traefik/docker-compose.yml << 'TREOF'
services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    restart: unless-stopped
    env_file: [../../../.env]
    command:
      - --api.dashboard=true
      - --api.insecure=false
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=proxy
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
      - --entrypoints.websecure.address=:443
      - --entrypoints.websecure.http.tls=true
      - --certificatesresolvers.cloudflare.acme.dnschallenge=true
      - --certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.cloudflare.acme.email=${CF_API_EMAIL}
      - --certificatesresolvers.cloudflare.acme.storage=/data/acme.json
      - --log.level=INFO
      - --accesslog=true
    ports:
      - "${PORT_TRAEFIK_HTTP}:80"
      - "${PORT_TRAEFIK_HTTPS}:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data:/data
    networks:
      - proxy
    environment:
      CF_API_EMAIL: ${CF_API_EMAIL}
      CF_DNS_API_TOKEN_FILE: /run/secrets/cf_api_key
    secrets:
      - cf_api_key
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/ping"]
      interval: 30s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=cloudflare"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.middlewares=authentik@docker"
      - "homepage.group=Network"
      - "homepage.name=Traefik"
      - "homepage.icon=traefik.png"
      - "homepage.href=https://traefik.${DOMAIN}"

secrets:
  cf_api_key:
    file: ../../../secrets/cf_api_key.txt

networks:
  proxy:
    external: true
TREOF

# === REDIS ===
cat > compose/data/redis/docker-compose.yml << 'RDSEOF'
services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass $(cat /run/secrets/redis_password) --appendonly yes
    volumes:
      - ./data:/data
    networks:
      - database
    secrets:
      - redis_password
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "$(cat /run/secrets/redis_password)", "ping"]
      interval: 30s

secrets:
  redis_password:
    file: ../../../secrets/redis_password.txt

networks:
  database:
    external: true
RDSEOF

# === OLLAMA ===
cat > compose/ai/ollama/docker-compose.yml << 'OLLEOF'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    env_file: [../../../.env]
    volumes:
      - ./models:/root/.ollama
    ports:
      - "${PORT_OLLAMA}:11434"
    networks:
      - ai-ml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 60s
      start_period: 60s
    labels:
      - "homepage.group=AI"
      - "homepage.name=Ollama"
      - "homepage.icon=ollama.png"

networks:
  ai-ml:
    external: true
OLLEOF

# === OPENWEBUI ===
cat > compose/ai/openwebui/docker-compose.yml << 'OWEOF'
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    env_file: [../../../.env]
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
      WEBUI_SECRET_KEY_FILE: /run/secrets/litellm_key
    volumes:
      - ./data:/app/backend/data
    networks:
      - proxy
      - ai-ml
    secrets:
      - litellm_key
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openwebui.rule=Host(`chat.${DOMAIN}`)"
      - "traefik.http.routers.openwebui.entrypoints=websecure"
      - "traefik.http.routers.openwebui.tls.certresolver=cloudflare"
      - "homepage.group=AI"
      - "homepage.name=OpenWebUI"
      - "homepage.href=https://chat.${DOMAIN}"

secrets:
  litellm_key:
    file: ../../../secrets/litellm_key.txt

networks:
  proxy: {external: true}
  ai-ml: {external: true}
OWEOF

# === AUTHENTIK ===
cat > compose/security/authentik/docker-compose.yml << 'AUTHEOF'
services:
  authentik-server:
    image: ghcr.io/goauthentik/server:2024.10
    container_name: authentik-server
    restart: unless-stopped
    env_file: [../../../.env]
    command: server
    environment:
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgres
      AUTHENTIK_POSTGRESQL__USER: ${POSTGRES_USER}
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_SECRET_KEY_FILE: /run/secrets/authentik_secret
      AUTHENTIK_POSTGRESQL__PASSWORD_FILE: /run/secrets/postgres_password
    volumes:
      - ./media:/media
      - ./custom-templates:/templates
    networks:
      - proxy
      - database
      - security
    secrets:
      - authentik_secret
      - postgres_password
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.authentik.rule=Host(`auth.${DOMAIN}`)"
      - "traefik.http.routers.authentik.entrypoints=websecure"

  authentik-worker:
    image: ghcr.io/goauthentik/server:2024.10
    container_name: authentik-worker
    restart: unless-stopped
    env_file: [../../../.env]
    command: worker
    environment:
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgres
      AUTHENTIK_POSTGRESQL__USER: ${POSTGRES_USER}
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_SECRET_KEY_FILE: /run/secrets/authentik_secret
      AUTHENTIK_POSTGRESQL__PASSWORD_FILE: /run/secrets/postgres_password
    networks:
      - database
      - security
    secrets:
      - authentik_secret
      - postgres_password

secrets:
  authentik_secret:
    file: ../../../secrets/authentik_secret.txt
  postgres_password:
    file: ../../../secrets/postgres_password.txt

networks:
  proxy: {external: true}
  database: {external: true}
  security: {external: true}
AUTHEOF

echo "=== Core files written ==="
echo "Run: cd $ROOT && ./scripts/bootstrap.sh"
