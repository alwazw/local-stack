# AEF3 Operations Runbook

Autonomous Engineer Framework v3 — Modular Docker Compose Stack

---

## 1. Stack Overview

| Property | Value |
|---|---|
| Root directory | `/mnt/d/docker` |
| Config | `docker-compose.yml` (orchestrator — uses `include:` to pull in individual service files) |
| Service definitions | 35 individual `compose/<category>/<service>/docker-compose.yml` files |
| Included in root | 34 services (via `include:` in root `docker-compose.yml`) |
| Standalone (not in root) | `woodpecker`, `affine`, `plane` |
| Data directories | `compose/<category>/<service>/data`, `compose/<category>/<service>/config` |
| Named volumes | `hermes_home`, `hermes_agent_src`, `hermes_workspace`, `omniroute_data`, `qdrant_data`, `gitea_data`, `n8n_data`, `grafana_data`, `uptime_kuma_data`, `loki_data`, `portainer_data`, `dockge_data`, `authentik_media`, `guacd_drive`, `guacd_record`, `cloudflared_bin` |
| Networks (all external) | `proxy`, `database`, `ai-ml`, `agent-communication`, `security`, `monitoring` |
| Secrets | `./secrets/*.txt` mounted at `/run/secrets/<name>` |
| Environment | WSL2 + Docker Desktop |

### Modular compose file inventory

Each service has its own `docker-compose.yml` under `compose/<category>/<service>/`:

| Category | Services (compose path) |
|---|---|
| **network** | `network/traefik/`, `network/cloudflared/` |
| **ai** | `ai/agent-zero/`, `ai/litellm/`, `ai/mcpo/`, `ai/ollama/`, `ai/openwebui/`, `ai/hermes-agent/`, `ai/hermes/`, `ai/omniroute/`, `ai/qdrant/`, `ai/searxng/` |
| **data** | `data/postgres/`, `data/redis/` |
| **security** | `security/authentik-server/`, `security/authentik-worker/`, `security/vaultwarden/` |
| **monitoring** | `monitoring/prometheus/`, `monitoring/grafana/`, `monitoring/uptime-kuma/`, `monitoring/loki/`, `monitoring/promtail/`, `monitoring/cadvisor/`, `monitoring/dozzle/` |
| **management** | `management/portainer/`, `management/dockge/`, `management/homepage/` |
| **ci** | `ci/gitea/`, `ci/n8n/` |
| **productivity** | `productivity/guacd/`, `productivity/guacamole/` |
| **standalone** (not in root `include:`) | `ci/woodpecker/`, `productivity/affine/`, `productivity/plane/` |

### Architecture pattern

```
docker-compose.yml                    ← root orchestrator (include: only)
├── compose/network/traefik/
│   └── docker-compose.yml            ← single-service compose file
├── compose/ai/agent-zero/
│   ├── docker-compose.yml            ← single-service compose file
│   └── data/                         ← service-specific data
├── compose/data/postgres/
│   ├── docker-compose.yml
│   └── data/                         ← postgres data dir
└── ... (35 services total)
```

---

## Terraform Operations

The AEF3 stack is managed via Terraform as the single source of truth.

### Terraform Directory
All Terraform configuration is in `terraform/`:
```
terraform/
├── providers.tf          # Docker provider (kreuzwerker/docker v3.x)
├── variables.tf          # Input variables
├── outputs.tf            # Service URLs, infrastructure summary
├── networks.tf           # 6 Docker networks
├── volumes.tf            # 16 named volumes
├── secrets.tf            # Secret file path mappings
├── terraform.tfvars      # Environment values
├── modules/service/      # Reusable container module
└── services/             # Service definition files
```

### Initialize
```bash
cd terraform/
terraform init
```

### Validate Configuration
```bash
terraform validate
```

### Preview Changes
```bash
terraform plan              # Show what would change
terraform plan -out=tfplan  # Save plan for apply
```

### Deploy Infrastructure
```bash
terraform apply             # Apply with interactive confirmation
terraform apply -auto-approve  # Non-interactive
terraform apply tfplan      # Apply saved plan
```

### View Outputs
```bash
terraform output                    # All outputs
terraform output service_endpoints  # Public URLs
terraform output local_endpoints    # Localhost URLs
terraform output -json infrastructure_summary  # Stack summary
```

### Import Existing Resources
When migrating from Docker Compose:
```bash
# Import networks
terraform import docker_network.ai_ml ai-ml
terraform import docker_network.agent_communication agent-communication
terraform import docker_network.proxy proxy
terraform import docker_network.database database
terraform import docker_network.security security
terraform import docker_network.monitoring monitoring

# Import volumes
terraform import docker_volume.<name> <name>
# Repeat for all 16 volumes
```

### State Management
```bash
terraform state list                    # List managed resources
terraform state show docker_network.proxy  # Show resource details
terraform state rm docker_network.proxy    # Remove from state (doesn't delete)
terraform refresh                       # Sync state with real infrastructure
```

### Drift Detection
```bash
terraform plan  # Shows any differences between state and real infrastructure
# No changes = infrastructure matches configuration
```

### Adding a New Service via Terraform
1. Add service definition to appropriate file in `terraform/services/`
2. Use the module pattern or direct `docker_container` resource
3. Add networks with `networks_advanced { name = docker_network.<name>.name }`
4. Mount secrets as volumes: `volumes { host_path = local.secret_files.<name>; container_path = "/run/secrets/<name>"; read_only = true }`
5. Run `terraform validate && terraform plan`
6. Run `terraform apply`

### Lifecycle Notes
- Networks have `lifecycle { ignore_changes = [labels] }` to prevent recreation
- One-shot containers (cloudflared-installer) have `lifecycle { ignore_changes = [all] }`
- Secrets are bind-mounted files (not Docker Swarm secrets) for non-Swarm compatibility

---

## 2. Startup Procedures

### Prerequisites

```bash
# Verify the proxy network exists (all networks are external and must be pre-created)
docker network ls | grep -E 'proxy|database|ai-ml|agent-communication|security|monitoring'

# If missing, create them:
docker network create proxy
docker network create database
docker network create ai-ml
docker network create agent-communication
docker network create security
docker network create monitoring

# Verify secrets exist
ls -la secrets/
```

### Start all services (root orchestrator)

From the project root, the root `docker-compose.yml` pulls in all 32 included services:

```bash
cd /mnt/d/docker
docker compose up -d
```

### Start a single service

Each service has its own compose file. Start it directly:

```bash
docker compose -f compose/ai/agent-zero/docker-compose.yml up -d
docker compose -f compose/data/postgres/docker-compose.yml up -d
docker compose -f compose/monitoring/grafana/docker-compose.yml up -d
```

### Start multiple specific services

Stack `-f` flags to start a subset without touching everything:

```bash
# AI core: LiteLLM + Ollama + OpenWebUI
docker compose \
  -f compose/ai/litellm/docker-compose.yml \
  -f compose/ai/ollama/docker-compose.yml \
  -f compose/ai/openwebui/docker-compose.yml \
  up -d

# Full monitoring stack
docker compose \
  -f compose/monitoring/prometheus/docker-compose.yml \
  -f compose/monitoring/grafana/docker-compose.yml \
  -f compose/monitoring/loki/docker-compose.yml \
  -f compose/monitoring/promtail/docker-compose.yml \
  -f compose/monitoring/cadvisor/docker-compose.yml \
  -f compose/monitoring/dozzle/docker-compose.yml \
  -f compose/monitoring/uptime-kuma/docker-compose.yml \
  up -d
```

### Start by category

Start all services within a category directory:

```bash
# All AI services
for f in compose/ai/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done

# All monitoring services
for f in compose/monitoring/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done

# Data layer (postgres + redis)
docker compose -f compose/data/postgres/docker-compose.yml up -d
docker compose -f compose/data/redis/docker-compose.yml up -d
```

### Start standalone services (not in root include:)

```bash
docker compose -f compose/ci/woodpecker/docker-compose.yml up -d
docker compose -f compose/productivity/affine/docker-compose.yml up -d
docker compose -f compose/productivity/plane/docker-compose.yml up -d
```

### Startup order

Services with dependencies should be started in order:

```bash
# 1. Data layer first (no dependencies)
docker compose -f compose/data/postgres/docker-compose.yml up -d
docker compose -f compose/data/redis/docker-compose.yml up -d

# 2. Network layer
docker compose -f compose/network/traefik/docker-compose.yml up -d
docker compose -f compose/network/cloudflared/docker-compose.yml up -d

# 3. Security (depends on postgres)
docker compose -f compose/security/authentik-server/docker-compose.yml up -d
docker compose -f compose/security/authentik-worker/docker-compose.yml up -d

# 4. AI (depends on redis via omniroute)
for f in compose/ai/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done

# 5. CI, Monitoring, Management, Productivity (can start in any order after data layer)
```

### Verify startup

```bash
# Check all running containers
docker ps

# Check a specific service
docker compose -f compose/ai/litellm/docker-compose.yml ps

# Check multiple services
docker compose -f compose/data/postgres/docker-compose.yml -f compose/data/redis/docker-compose.yml ps

# Wait for a service to become healthy
watch -n 5 'docker compose -f compose/data/postgres/docker-compose.yml ps'

# Quick health summary for all running containers
docker ps --format '{{.Names}}: {{.Status}}'
```

### Verify critical paths

```bash
# Database connectivity
docker exec postgres pg_isready -U alwazw -d aef3

# Redis connectivity
docker exec redis redis-cli -a "$(cat /run/secrets/redis_password.txt 2>/dev/null || cat secrets/redis_password.txt)" ping

# Traefik ping endpoint
docker exec traefik wget --spider -q http://localhost:8080/ping
```

---

## 3. Shutdown Procedures

### Graceful stop all (root orchestrator)

```bash
cd /mnt/d/docker
docker compose down
```

### Stop a single service

```bash
docker compose -f compose/ai/agent-zero/docker-compose.yml down
```

### Stop without removing containers

```bash
docker compose -f compose/ai/agent-zero/docker-compose.yml stop
```

### Stop multiple specific services

```bash
docker compose \
  -f compose/monitoring/prometheus/docker-compose.yml \
  -f compose/monitoring/grafana/docker-compose.yml \
  down
```

### Stop an entire category

```bash
for f in compose/monitoring/*/docker-compose.yml; do
  docker compose -f "$f" down
done
```

### DANGER: Stop and remove volumes (DESTRUCTIVE)

```bash
# This deletes data for the specified service(s)
docker compose -f compose/data/postgres/docker-compose.yml down -v

# Verify what volumes will be deleted before running:
docker compose -f compose/data/postgres/docker-compose.yml config | grep -A1 'volumes:'
```

### Emergency kill

```bash
# For unresponsive containers
docker compose -f compose/ai/agent-zero/docker-compose.yml stop
docker kill agent-zero
```

---

## 4. Restart Procedures

### Restart single service

```bash
docker compose -f compose/data/postgres/docker-compose.yml restart
```

### Recreate with updated configuration

```bash
# Single service (picks up compose file changes)
docker compose -f compose/ai/litellm/docker-compose.yml up -d --force-recreate

# Without rebuilding image
docker compose -f compose/ai/litellm/docker-compose.yml up -d --force-recreate --no-build
```

### Recreate all services (root orchestrator)

```bash
docker compose up -d --force-recreate
```

### Restart with fresh image

```bash
# Pull latest images for a specific service
docker compose -f compose/ai/agent-zero/docker-compose.yml pull
docker compose -f compose/ai/agent-zero/docker-compose.yml up -d --force-recreate

# Pull all included services
docker compose pull
docker compose up -d --force-recreate
```

### Restart data layer (postgres + redis)

Services that depend on postgres/redis will break during the restart. Order matters:

```bash
# 1. Stop dependent services first
docker compose -f compose/ci/gitea/docker-compose.yml down
docker compose -f compose/ci/n8n/docker-compose.yml down
docker compose -f compose/security/authentik-server/docker-compose.yml down
docker compose -f compose/security/authentik-worker/docker-compose.yml down
docker compose -f compose/productivity/guacamole/docker-compose.yml down

# 2. Restart data layer
docker compose -f compose/data/postgres/docker-compose.yml up -d --force-recreate
docker compose -f compose/data/redis/docker-compose.yml up -d --force-recreate

# 3. Wait for health
docker compose -f compose/data/postgres/docker-compose.yml ps
docker compose -f compose/data/redis/docker-compose.yml ps

# 4. Restart dependents
docker compose -f compose/ci/gitea/docker-compose.yml up -d
docker compose -f compose/ci/n8n/docker-compose.yml up -d
docker compose -f compose/security/authentik-server/docker-compose.yml up -d
docker compose -f compose/security/authentik-worker/docker-compose.yml up -d
docker compose -f compose/productivity/guacamole/docker-compose.yml up -d
```

---

## 5. Health Check Procedures

### Check a single service

```bash
docker compose -f compose/ai/litellm/docker-compose.yml ps
```

### Check multiple services

```bash
docker compose \
  -f compose/data/postgres/docker-compose.yml \
  -f compose/data/redis/docker-compose.yml \
  ps
```

### Check all running containers

```bash
docker ps
```

### Check individual service logs

```bash
# Last 50 lines
docker compose -f compose/ai/litellm/docker-compose.yml logs --tail 50

# Follow in real-time
docker compose -f compose/monitoring/loki/docker-compose.yml logs -f

# Since a specific time
docker compose -f compose/ai/agent-zero/docker-compose.yml logs --since 2025-06-16T10:00:00
```

### Check service health state

```bash
# Health status from docker inspect
docker inspect <name> --format '{{.State.Health.Status}}'

# Full health details
docker inspect <name> --format '{{json .State.Health}}' | python3 -m json.tool

# Last healthcheck output (shows the actual test output)
docker inspect <name> --format '{{range .State.Health.Log}}{{.Output}}{{end}}'

# Healthcheck test command used
docker inspect <name> --format '{{json .Config.Healthcheck}}' | python3 -m json.tool
```

### Run integration tests

```bash
cd /mnt/d/docker
python3 scripts/integration_test.py
```

### Service-specific health verification

```bash
# Postgres (dual fallback: socket + TCP)
docker exec postgres pg_isready -U alwazw -d aef3

# Redis
docker exec redis redis-cli -a "$(cat secrets/redis_password.txt)" ping

# Traefik
docker exec traefik wget --spider -q http://localhost:8080/ping

# Prometheus
curl -s http://localhost:$(grep PORT_PROMETHEUS .env.example | cut -d= -f2)/-/healthy

# Grafana
curl -s http://localhost:$(grep PORT_GRAFANA .env.example | cut -d= -f2)/api/health

# Loki (no container healthcheck; test from host)
curl -s http://localhost:$(grep PORT_LOKI .env.example | cut -d= -f2)/ready

# LiteLLM
curl -s http://localhost:$(grep PORT_LITELLM .env.example | cut -d= -f2)/health

# Hermes
curl -s http://localhost:$(grep PORT_HERMES .env.example | cut -d= -f2)/health

# Vaultwarden
docker exec vaultwarden curl -f http://localhost:80/alive

# Gitea
docker exec gitea wget --spider -q http://localhost:3000

# n8n
docker exec n8n wget --spider -q http://localhost:5678/healthz

# Uptime Kuma
docker exec uptime-kuma curl -f -s http://localhost:3001/api/entry-page

# Prometheus (via wget in container)
docker exec prometheus wget --spider -q http://localhost:9090/-/healthy

# Grafana (via wget in container)
docker exec grafana wget --spider -q http://localhost:3000/api/health
```

---

## 6. Troubleshooting

### Service won't start

```bash
# 1. Check logs
docker compose -f compose/<category>/<service>/docker-compose.yml logs --tail 100

# 2. Check if container exists at all
docker ps -a --filter name=<name>

# 3. Check config rendering
docker compose -f compose/<category>/<service>/docker-compose.yml config

# 4. Check network connectivity
docker network ls
docker inspect <name> --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool

# 5. Check secret files exist on host
ls -la secrets/

# 6. Try starting with visible output
docker compose -f compose/<category>/<service>/docker-compose.yml up
```

### Network connectivity

```bash
# Ping between containers
docker exec <src> ping -c 3 <dst>

# TCP connectivity test
docker exec <src> curl -v http://<dst>:<port>

# Test specific service paths
# Hermes Agent → Agent Zero
docker exec hermes-agent curl -v http://agent-zero:80

# Agent Zero → LiteLLM
docker exec agent-zero python3 -c "import urllib.request; urllib.request.urlopen('http://litellm:4000')"

# LiteLLM → Ollama
docker exec litellm curl -v http://ollama:11434

# Authentik → Postgres
docker exec authentik-server pg_isready -h postgres

# Omniroute → Redis
docker exec omniroute sh -c 'echo > /dev/tcp/redis/6379'
```

### Secret not loading

```bash
# List mounted secrets inside container
docker exec <name> ls -la /run/secrets/

# Read a specific secret
docker exec <name> cat /run/secrets/<secret_name>

# Verify host-side secret file exists and is non-empty
cat secrets/<secret_name>.txt | wc -c

# Rebuild container with fresh secrets
docker compose -f compose/<category>/<service>/docker-compose.yml up -d --force-recreate
```

### Database connectivity

```bash
# Postgres health check (dual fallback: socket then TCP)
docker exec postgres pg_isready -U alwazw -d aef3

# Connect and run query
docker exec -it postgres psql -U alwazw -d aef3 -c '\dt'

# List databases
docker exec -it postgres psql -U alwazw -c '\l'

# Check database size
docker exec -it postgres psql -U alwazw -d aef3 -c "SELECT pg_size_pretty(pg_database_size('aef3'));"
```

### Redis connectivity

```bash
# Ping (password from secret file)
docker exec redis redis-cli -a "$(cat secrets/redis_password.txt)" ping

# List keys
docker exec -it redis redis-cli -a "$(cat secrets/redis_password.txt)" keys '*'

# Info
docker exec redis redis-cli -a "$(cat secrets/redis_password.txt)" info server

# Check append-only file (persistence)
ls -la compose/data/redis/data/
```

### iptables / Docker FORWARD chain check

On WSL2, Docker may insert rules that conflict with Windows networking:

```bash
# Check Docker FORWARD rules
sudo iptables -L DOCKER-FORWARD -n -v

# Check if FORWARD policy is DROP (blocks inter-container traffic)
sudo iptables -L FORWARD -n -v

# If inter-container traffic is blocked, verify:
sudo iptables -L DOCKER-USER -n -v

# Reset iptables Docker rules (DANGER: restarts Docker networking)
# Only if you know what you're doing:
sudo iptables -F DOCKER-FORWARD
sudo iptables -F DOCKER-USER
```

### Service config debugging

```bash
# Render a single service's compose config
docker compose -f compose/ai/litellm/docker-compose.yml config

# Dry-run (shows what would be created)
docker compose -f compose/ai/agent-zero/docker-compose.yml up --dry-run

# Check service dependencies
docker compose -f compose/security/authentik-server/docker-compose.yml config | grep -A5 'depends_on'
```

---

## 7. Known Issues & Workarounds

### Traefik — Let's Encrypt certificate provisioning blocked

**Symptom:** Traefik logs show DNS challenge failures or ACME timeouts.

**Root cause:** Proxy network outbound HTTPS (port 443) to Let's Encrypt is blocked by upstream firewall/ISP.

**Workaround:**
- Cloudflare DNS challenge may still work if port 443 outbound to Cloudflare is allowed
- If fully blocked, use HTTP challenge (requires port 80 inbound) or self-signed certificates
- Check Traefik logs: `docker compose -f compose/network/traefik/docker-compose.yml logs --tail 200 | grep -i acme`

**Verification:**
```bash
docker exec traefik wget --spider -q https://acme-v02.api.letsencrypt.org/directory
```

### Cloudflared — QUIC blocked, running in HTTP/2 degraded mode

**Symptom:** Cloudflared logs show QUIC connection failures on UDP 7844.

**Root cause:** UDP port 7844 is blocked by firewall. Cloudflared falls back to HTTP/2 over TCP 443.

**Impact:** Degraded performance, higher latency. Functionally operational.

**Verification:**
```bash
docker compose -f compose/network/cloudflared/docker-compose.yml logs 2>&1 | grep -iE 'quic|http2|degraded'
```

**Note:** No workaround available; HTTP/2 fallback is automatic and acceptable.

### Postgres healthcheck — dual fallback

**Configuration:** The healthcheck uses `pg_isready` with socket first, then TCP fallback:
```
pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} || pg_isready -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB}
```

This handles cases where the Unix socket is not yet ready but TCP is (or vice versa).

### Loki — no container healthcheck

**Reason:** Loki uses a `scratch`-based image with no shell, `nc`, `wget`, or `curl`.

**Workaround:** Check health from the host:
```bash
curl -s http://localhost:3100/ready
```

Or from any container on the monitoring network:
```bash
docker exec prometheus wget --spider -q http://loki:3100/ready
```

### Ollama — slow model loading

**Symptom:** `ollama` service shows `starting` for extended periods.

**Cause:** Ollama loads models into VRAM on startup. The `start_period: 60s` may not be enough for large models.

**Workaround:** Check model loading status:
```bash
docker exec ollama ollama list
docker compose -f compose/ai/ollama/docker-compose.yml logs --tail 50
```

### Hermes Agent — dashboard state file dependency

**Symptom:** Hermes healthcheck fails until `/home/hermes/.hermes/gateway_state.json` exists.

**Cause:** Healthcheck reads `gateway_state.json` which is only created after the gateway starts running.

**Workaround:** Wait for `start_period: 60s`. Check:
```bash
docker exec hermes-agent cat /home/hermes/.hermes/gateway_state.json
```

---

## 8. Backup Procedures

### Database backup

```bash
cd /mnt/d/docker

# Full database dump
docker exec postgres pg_dump -U alwazw aef3 > backups/aef3-$(date +%Y%m%d-%H%M%S).sql

# Compressed
docker exec postgres pg_dump -U alwazw aef3 | gzip > backups/aef3-$(date +%Y%m%d-%H%M%S).sql.gz

# Specific tables
docker exec postgres pg_dump -U alwazw -t gitea_* -t n8n_* -t authentik_* aef3 > backups/aef3-tables-$(date +%Y%m%d).sql

# All databases (including postgres system DB)
docker exec postgres pg_dumpall -U alwazw | gzip > backups/aef3-full-$(date +%Y%m%d-%H%M%S).sql.gz
```

### Per-service data directory backup

Each service stores its data under `compose/<category>/<service>/data` and/or `compose/<category>/<service>/config`:

```bash
# Backup a specific service's data
tar czf backups/agent-zero-data-$(date +%Y%m%d).tar.gz compose/ai/agent-zero/data

# Backup all AI service data
tar czf backups/ai-data-$(date +%Y%m%d).tar.gz compose/ai/*/data compose/ai/*/config

# Backup monitoring data
tar czf backups/monitoring-data-$(date +%Y%m%d).tar.gz compose/monitoring/*/data compose/monitoring/*/config

# Backup all bind-mounted data directories
tar czf backups/all-compose-data-$(date +%Y%m%d).tar.gz compose/*/data compose/*/config
```

### Named volume backup

```bash
# Backup a named volume
VOLUME=gitea_data
docker run --rm \
  -v ${VOLUME}:/data:ro \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/${VOLUME}-$(date +%Y%m%d).tar.gz -C /data .

# Backup all named volumes
for vol in hermes_home qdrant_data grafana_data gitea_data n8n_data portainer_data; do
  docker run --rm \
    -v ${vol}:/data:ro \
    -v $(pwd)/backups:/backup \
    alpine tar czf /backup/${vol}-$(date +%Y%m%d).tar.gz -C /data .
done
```

### Secrets backup

```bash
# Backup secrets directory
cp -r secrets/ secrets-backup-$(date +%Y%m%d)/

# Encrypted backup (requires gpg)
tar czf - secrets/ | gpg --symmetric --cipher-algo AES256 -o secrets-backup-$(date +%Y%m%d).tar.gz.gpg
```

### Configuration backup

```bash
# Git commit current state
cd /mnt/d/docker
git status
git add .
git commit -m "backup $(date +%Y%m%d-%H%M%S)"

# Export rendered compose config for a specific service
docker compose -f compose/ai/litellm/docker-compose.yml config > backups/litellm-config-$(date +%Y%m%d).yml

# Export all included services config (root orchestrator)
docker compose config > backups/full-config-$(date +%Y%m%d).yml
```

### Restore from backup

```bash
# Restore database
gunzip < backups/aef3-full-20260616.sql.gz | docker exec -i postgres psql -U alwazw

# Restore a named volume
docker run --rm \
  -v gitea_data:/data \
  -v $(pwd)/backups:/backup:ro \
  alpine tar xzf /backup/gitea_data-20260616.tar.gz -C /data

# Restore a service's data directory
tar xzf backups/agent-zero-data-20260616.tar.gz -C /mnt/d/docker

# Restore secrets
cp -r secrets-backup-20260616/* secrets/
docker compose -f compose/<category>/<service>/docker-compose.yml up -d --force-recreate
```

---

## 9. Maintenance Windows

### Best times to restart

- **Low-traffic window:** 02:00–06:00 America/Toronto (UTC-4/UTC-5)
- **Avoid:** During active n8n workflow executions or Gitea CI/CD runs

### Services that can restart independently

These services have minimal or no `depends_on` and can be restarted without cascading effects:

| Service | Dependencies | Impact |
|---|---|---|
| `prometheus` | none | Metrics collection gap |
| `grafana` | prometheus | Dashboard unavailable |
| `uptime-kuma` | none | Monitoring gap |
| `loki` | none | Log ingestion gap |
| `promtail` | loki | Log shipping gap |
| `cadvisor` | none | Resource metrics gap |
| `dozzle` | none | Log viewer gap |
| `portainer` | none | Management UI gap |
| `dockge` | none | Compose UI gap |
| `homepage` | none | Dashboard gap |
| `ollama` | none | LLM inference gap |
| `mcpo` | none | MCP bridge gap |
| `qdrant` | none | Vector DB gap |
| `searxng` | none | Search gap |

### Services that require coordinated restart

These have `depends_on` conditions or serve as infrastructure:

| Service | Dependents | Restart procedure |
|---|---|---|
| `postgres` | authentik-server, authentik-worker, guacamole, gitea, n8n | Stop dependents, restart postgres, restart dependents |
| `redis` | authentik-server, authentik-worker, omniroute | Stop dependents, restart redis, restart dependents |
| `traefik` | all Traefik-routed services | Brief outage for all routed services |
| `hermes-agent` | hermes | Restart hermes after hermes-agent |
| `guacd` | guacamole | Restart guacamole after guacd |
| `cloudflared-installer` | cloudflared | Runs once; only restart if binary missing |
| `cloudflared` | (none, but routes traffic) | Brief outbound tunnel outage |

### Category-based rolling restart procedure

```bash
# 1. Monitoring (no critical dependencies)
for f in compose/monitoring/*/docker-compose.yml; do
  docker compose -f "$f" down
done
for f in compose/monitoring/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done

# 2. Management (no critical dependencies)
for f in compose/management/*/docker-compose.yml; do
  docker compose -f "$f" down && docker compose -f "$f" up -d
done

# 3. Productivity (depends on guacd)
docker compose -f compose/productivity/guacamole/docker-compose.yml down
docker compose -f compose/productivity/guacd/docker-compose.yml down
docker compose -f compose/productivity/guacd/docker-compose.yml up -d
docker compose -f compose/productivity/guacamole/docker-compose.yml up -d

# 4. CI (depends on postgres)
for f in compose/ci/*/docker-compose.yml; do
  docker compose -f "$f" down
done
for f in compose/ci/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done

# 5. Security (depends on postgres + redis)
for f in compose/security/*/docker-compose.yml; do
  docker compose -f "$f" down
done
for f in compose/security/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done

# 6. Network
for f in compose/network/*/docker-compose.yml; do
  docker compose -f "$f" down && docker compose -f "$f" up -d
done

# 7. AI (depends on redis via omniroute; traefik routes traffic)
for f in compose/ai/*/docker-compose.yml; do
  docker compose -f "$f" down
done
for f in compose/ai/*/docker-compose.yml; do
  docker compose -f "$f" up -d
done
```

### Data-layer coordinated restart

```bash
# Full data layer restart with dependent services
# Phase 1: Stop all dependent services
docker compose -f compose/ci/gitea/docker-compose.yml down
docker compose -f compose/ci/n8n/docker-compose.yml down
docker compose -f compose/security/authentik-server/docker-compose.yml down
docker compose -f compose/security/authentik-worker/docker-compose.yml down
docker compose -f compose/security/vaultwarden/docker-compose.yml down
docker compose -f compose/productivity/guacamole/docker-compose.yml down

# Phase 2: Restart data layer
docker compose -f compose/data/postgres/docker-compose.yml down
docker compose -f compose/data/redis/docker-compose.yml down
docker compose -f compose/data/postgres/docker-compose.yml up -d
docker compose -f compose/data/redis/docker-compose.yml up -d

# Phase 3: Wait for health
until docker inspect postgres --format '{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; do
  echo "Waiting for postgres..."
  sleep 5
done

# Phase 4: Restart dependents
docker compose -f compose/ci/gitea/docker-compose.yml up -d
docker compose -f compose/ci/n8n/docker-compose.yml up -d
docker compose -f compose/security/authentik-server/docker-compose.yml up -d
docker compose -f compose/security/authentik-worker/docker-compose.yml up -d
docker compose -f compose/security/vaultwarden/docker-compose.yml up -d
docker compose -f compose/productivity/guacamole/docker-compose.yml up -d
```

---

## 10. Emergency Procedures

### Full stack recovery from scratch

```bash
cd /mnt/d/docker

# 1. Tear down everything via root orchestrator, removing all data
docker compose down -v

# 2. Tear down standalone services
docker compose -f compose/ci/woodpecker/docker-compose.yml down -v 2>/dev/null
docker compose -f compose/productivity/affine/docker-compose.yml down -v 2>/dev/null
docker compose -f compose/productivity/plane/docker-compose.yml down -v 2>/dev/null

# 3. Remove dangling images
docker image prune -af

# 4. Remove unused networks (except the external ones)
docker network prune -f

# 5. Ensure external networks exist
for net in proxy database ai-ml agent-communication security monitoring; do
  docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
done

# 6. Verify secrets
ls secrets/*.txt

# 7. Pull fresh images (all included services)
docker compose pull

# 8. Start everything (root orchestrator)
docker compose up -d

# 9. Start standalone services
docker compose -f compose/ci/woodpecker/docker-compose.yml up -d 2>/dev/null
docker compose -f compose/productivity/affine/docker-compose.yml up -d 2>/dev/null
docker compose -f compose/productivity/plane/docker-compose.yml up -d 2>/dev/null

# 10. Wait for health checks
sleep 120
docker ps

# 11. Run integration tests
python3 scripts/integration_test.py
```

### Secret rotation emergency procedure

```bash
cd /mnt/d/docker

# 1. Backup current secrets
cp -r secrets/ secrets-pre-rotation-$(date +%Y%m%d-%H%M%S)/

# 2. Update secret files
# Edit the relevant files in secrets/
# Example: secrets/postgres_password.txt
echo "new_password_here" > secrets/postgres_password.txt

# 3. Force-recreate affected services (picks up new secret files)
# Services that use each secret:
#   postgres_password: postgres, authentik-server, authentik-worker, guacamole, gitea, n8n
#   redis_password: redis, authentik-server, authentik-worker, omniroute
#   litellm_key: agent-zero, litellm
#   webui_secret_key: openwebui, searxng
#   hermes_password: hermes
#   cf_*: traefik, cloudflared
#   gitea_secret: gitea
#   guac_admin_pass: guacamole
#   n8n_key: n8n
#   vw_admin_token: vaultwarden
#   authentik_secret: authentik-server, authentik-worker
#   ssh_deploy_key: agent-zero
#   agent_zero_key: agent-zero
#   github_token: agent-zero

# Rotate Postgres password (most complex — requires DB-level change too)
docker exec postgres psql -U alwazw -c "ALTER USER alwazw WITH PASSWORD '$(cat secrets/postgres_password.txt)';"
docker compose -f compose/data/postgres/docker-compose.yml up -d --force-recreate
docker compose -f compose/security/authentik-server/docker-compose.yml up -d --force-recreate
docker compose -f compose/security/authentik-worker/docker-compose.yml up -d --force-recreate
docker compose -f compose/productivity/guacamole/docker-compose.yml up -d --force-recreate
docker compose -f compose/ci/gitea/docker-compose.yml up -d --force-recreate
docker compose -f compose/ci/n8n/docker-compose.yml up -d --force-recreate

# Rotate Redis password
docker compose -f compose/data/redis/docker-compose.yml stop
echo "new_redis_password" > secrets/redis_password.txt
docker compose -f compose/data/redis/docker-compose.yml up -d --force-recreate
docker compose -f compose/security/authentik-server/docker-compose.yml up -d --force-recreate
docker compose -f compose/security/authentik-worker/docker-compose.yml up -d --force-recreate
docker compose -f compose/ai/omniroute/docker-compose.yml up -d --force-recreate

# Rotate LiteLLM key
docker compose -f compose/ai/agent-zero/docker-compose.yml up -d --force-recreate
docker compose -f compose/ai/litellm/docker-compose.yml up -d --force-recreate

# Rotate all at once (if rotating everything — root orchestrator)
docker compose up -d --force-recreate

# 4. Verify
docker ps
python3 scripts/integration_test.py
```

### Network recovery (iptables reset)

```bash
# If Docker networking is broken (e.g., after WSL2 restart or Windows update):

# 1. Stop all containers (root orchestrator)
docker compose down

# Also stop standalone services
for f in compose/ci/woodpecker compose/productivity/affine compose/productivity/plane compose/security/authentik; do
  docker compose -f "$f/docker-compose.yml" down 2>/dev/null
done

# 2. Restart Docker daemon
sudo service docker restart
# Or on systemd: sudo systemctl restart docker

# 3. Verify networks
docker network ls

# 4. Restart containers
docker compose up -d
```

### Single service disaster recovery

```bash
# If a service's data is corrupted:

# 1. Stop the service
docker compose -f compose/<category>/<service>/docker-compose.yml down

# 2. Back up the corrupted data (in case recovery is possible)
cp -r compose/<category>/<service>/data compose/<category>/<service>/data-corrupted-$(date +%Y%m%d)

# 3. Clear the data directory (or specific subdirectories)
rm -rf compose/<category>/<service>/data/*

# 4. Recreate with fresh state
docker compose -f compose/<category>/<service>/docker-compose.yml up -d

# 5. If the service uses a named volume instead of bind mounts:
docker volume rm <volume_name>
docker compose -f compose/<category>/<service>/docker-compose.yml up -d
```

### Rapid service isolation

When a single service is misbehaving (high CPU, memory leak, log spam):

```bash
# Disconnect from network (stop without removing)
docker compose -f compose/<category>/<service>/docker-compose.yml stop

# Or disconnect from specific network
docker network disconnect <network> <container_name>

# Inspect resource usage
docker stats <container_name>

# Check if it's the only consumer
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | sort -k2 -rn | head
```

---

## Quick Reference

### Common command patterns

| Action | Command |
|---|---|
| Start single service | `docker compose -f compose/<cat>/<svc>/docker-compose.yml up -d` |
| Start all (included) | `cd /mnt/d/docker && docker compose up -d` |
| Stop single service | `docker compose -f compose/<cat>/<svc>/docker-compose.yml down` |
| Restart single service | `docker compose -f compose/<cat>/<svc>/docker-compose.yml restart` |
| Recreate single service | `docker compose -f compose/<cat>/<svc>/docker-compose.yml up -d --force-recreate` |
| Check single service | `docker compose -f compose/<cat>/<svc>/docker-compose.yml ps` |
| Logs (single service) | `docker compose -f compose/<cat>/<svc>/docker-compose.yml logs --tail 50` |
| Logs (follow) | `docker compose -f compose/<cat>/<svc>/docker-compose.yml logs -f` |
| Render config | `docker compose -f compose/<cat>/<svc>/docker-compose.yml config` |
| Pull image | `docker compose -f compose/<cat>/<svc>/docker-compose.yml pull` |

### Category paths

| Category | Path |
|---|---|
| Network | `compose/network/` |
| AI | `compose/ai/` |
| Data | `compose/data/` |
| Security | `compose/security/` |
| Monitoring | `compose/monitoring/` |
| Management | `compose/management/` |
| CI | `compose/ci/` |
| Productivity | `compose/productivity/` |
