# AEF3 Operations Runbook

Autonomous Engineer Framework v3 — Docker Compose Stack

---

## 1. Stack Overview

| Property | Value |
|---|---|
| Root directory | `/mnt/d/docker` |
| Config | `docker-compose.yml` (single source of truth) |
| Total services | 31 |
| Compose profiles | `ai`, `ci`, `management`, `monitoring`, `network`, `productivity`, `security` |
| Always-on (no profile) | `postgres`, `redis` |
| Data volumes | `compose/*/data`, `compose/*/config` |
| Named volumes | `hermes_home`, `hermes_agent_src`, `hermes_workspace`, `omniroute_data`, `qdrant_data`, `gitea_data`, `n8n_data`, `grafana_data`, `uptime_kuma_data`, `loki_data`, `portainer_data`, `dockge_data`, `authentik_media`, `guacd_drive`, `guacd_record`, `cloudflared_bin` |
| Networks (all external) | `proxy`, `database`, `ai-ml`, `agent-communication`, `security`, `monitoring` |
| Secrets | `./secrets/*.txt` mounted at `/run/secrets/<name>` |
| Environment | WSL2 + Docker Desktop |

### Service inventory by profile

| Profile | Services |
|---|---|
| **ai** | `agent-zero`, `litellm`, `mcpo`, `ollama`, `openwebui`, `hermes-agent`, `hermes`, `omniroute`, `traefik`, `qdrant`, `searxng` |
| **network** | `cloudflared`, `cloudflared-installer` |
| **security** | `authentik-server`, `authentik-worker`, `vaultwarden` |
| **monitoring** | `prometheus`, `grafana`, `uptime-kuma`, `loki`, `promtail`, `cadvisor`, `dozzle` |
| **productivity** | `guacd`, `guacamole` |
| **ci** | `gitea`, `n8n` |
| **management** | `portainer`, `dockge`, `homepage` |
| *(none)* | `postgres`, `redis` |

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

### Start all services

```bash
cd /mnt/d/docker
docker compose --profile '*' up -d
```

### Start by profile

```bash
# AI + Monitoring only
docker compose --profile ai --profile monitoring up -d

# AI profile (includes traefik, which is in the ai profile)
docker compose --profile ai up -d

# Security + data layer
docker compose up -d postgres redis && docker compose --profile security up -d
```

### Start specific services

```bash
# Core data layer first (postgres + redis have no profile, always included)
docker compose up -d postgres redis

# Specific service
docker compose up -d hermes agent-zero
```

### Verify startup

```bash
# Check all service statuses
docker compose --profile '*' ps

# Check only unhealthy/failed services
docker compose --profile '*' ps | grep -v 'healthy\|running'

# Wait for all services to become healthy (poll loop)
watch -n 5 'docker compose --profile '*' ps --format "table {{.Name}}\t{{.Status}}"'

# Quick health summary
docker compose --profile '*' ps --format '{{.Name}}: {{.State}} ({{.Health}})'
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

### Graceful stop all

```bash
cd /mnt/d/docker
docker compose --profile '*' down
```

### Stop specific services

```bash
# Stop without removing containers
docker compose stop hermes agent-zero

# Stop entire profile
docker compose --profile monitoring down
docker compose --profile productivity down
```

### Stop and remove containers + networks (keeps volumes)

```bash
docker compose --profile '*' down
```

### DANGER: Stop and remove volumes (DESTRUCTIVE)

```bash
# This deletes ALL data in named volumes (postgres, redis, grafana, etc.)
# Only use when rebuilding from scratch
docker compose --profile '*' down -v

# Verify what volumes will be deleted before running:
docker compose --profile '*' config | grep -A1 'volumes:'
```

### Emergency kill

```bash
# For unresponsive containers
docker compose stop <name>
docker kill <name>
```

---

## 4. Restart Procedures

### Restart single service

```bash
docker compose restart <name>

# Example
docker compose restart postgres
```

### Recreate with updated configuration

```bash
# Single service (picks up docker-compose.yml changes)
docker compose up -d --force-recreate <name>

# Without rebuilding image
docker compose up -d --force-recreate --no-build <name>
```

### Recreate all services

```bash
docker compose --profile '*' up -d --force-recreate
```

### Restart with fresh image

```bash
# Pull latest images, then recreate
docker compose --profile '*' pull
docker compose --profile '*' up -d --force-recreate
```

### Restart data layer (postgres + redis)

Services that depend on postgres/redis will break during the restart. Order matters:

```bash
# 1. Stop dependent services first
docker compose --profile ci down
docker compose --profile security down
docker compose --profile productivity down
docker compose up -d --force-recreate postgres redis

# 2. Wait for health
docker compose ps postgres redis

# 3. Restart dependents
docker compose --profile ci up -d
docker compose --profile security up -d
docker compose --profile productivity up -d
```

---

## 5. Health Check Procedures

### Check all service status

```bash
docker compose --profile '*' ps
```

### Check individual service logs

```bash
# Last 50 lines
docker compose logs <name> --tail 50

# Follow in real-time
docker compose logs -f <name>

# Since a specific time
docker compose logs --since 2025-06-16T10:00:00 <name>

# Logs for an entire profile
docker compose --profile monitoring logs --tail 100
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
docker compose logs <name> --tail 100

# 2. Check if container exists at all
docker ps -a --filter name=<name>

# 3. Check config rendering
docker compose config --service <name>

# 4. Check network connectivity
docker network ls
docker inspect <name> --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool

# 5. Check secret files exist on host
ls -la secrets/

# 6. Try starting with visible output
docker compose up <name>
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
docker compose up -d --force-recreate <name>
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

### Profile-specific debugging

```bash
# Check what services a profile would start
docker compose --profile ai config --services

# Dry-run (shows what would be created)
docker compose --profile ai up -d --dry-run

# Check service dependencies
docker compose config --service <name> | grep -A5 'depends_on'
```

---

## 7. Known Issues & Workarounds

### Traefik — Let's Encrypt certificate provisioning blocked

**Symptom:** Traefik logs show DNS challenge failures or ACME timeouts.

**Root cause:** Proxy network outbound HTTPS (port 443) to Let's Encrypt is blocked by upstream firewall/ISP.

**Workaround:**
- Cloudflare DNS challenge may still work if port 443 outbound to Cloudflare is allowed
- If fully blocked, use HTTP challenge (requires port 80 inbound) or self-signed certificates
- Check Traefik logs: `docker compose logs traefik --tail 200 | grep -i acme`

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
docker compose logs cloudflared 2>&1 | grep -iE 'quic|http2|degraded'
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
docker compose logs ollama --tail 50
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

### Volume backup

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

# Backup bind-mounted data directories
tar czf backups/compose-data-$(date +%Y%m%d).tar.gz compose/*/data
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

# Export rendered compose config
docker compose --profile '*' config > backups/compose-config-$(date +%Y%m%d).yml
```

### Restore from backup

```bash
# Restore database
gunzip < backups/aef3-full-20260616.sql.gz | docker exec -i postgres psql -U alwazw

# Restore a volume
docker run --rm \
  -v gitea_data:/data \
  -v $(pwd)/backups:/backup:ro \
  alpine tar xzf /backup/gitea_data-20260616.tar.gz -C /data

# Restore secrets
cp -r secrets-backup-20260616/* secrets/
docker compose --profile '*' up -d --force-recreate
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
| `postgres` | authentik-server, authentik-worker, guacamole, gitea, n8n | See data-layer restart below |
| `redis` | authentik-server, authentik-worker, omniroute | Stop dependents, restart redis, restart dependents |
| `traefik` | all Traefik-routed services | Brief outage for all routed services |
| `hermes-agent` | hermes | Restart hermes after hermes-agent |
| `guacd` | guacamole | Restart guacamole after guacd |
| `cloudflared-installer` | cloudflared | Runs once; only restart if binary missing |
| `cloudflared` | (none, but routes traffic) | Brief outbound tunnel outage |

### Profile-based rolling restart procedure

```bash
# 1. Monitoring (no critical dependencies)
docker compose --profile monitoring down
docker compose --profile monitoring up -d
docker compose --profile monitoring ps

# 2. Management (no critical dependencies)
docker compose --profile management down
docker compose --profile management up -d
docker compose --profile management ps

# 3. Productivity (depends on guacd)
docker compose --profile productivity down
docker compose --profile productivity up -d
docker compose --profile productivity ps

# 4. CI/CD (depends on postgres)
docker compose --profile ci down
docker compose --profile ci up -d
docker compose --profile ci ps

# 5. Security (depends on postgres + redis)
docker compose --profile security down
docker compose --profile security up -d
docker compose --profile security ps

# 6. Network
docker compose --profile network down
docker compose --profile network up -d
docker compose --profile network ps

# 7. AI (depends on redis via omniroute; traefik in this profile)
docker compose --profile ai down
docker compose --profile ai up -d
docker compose --profile ai ps
```

### Data-layer coordinated restart

```bash
# Full data layer restart with dependent services
# Phase 1: Stop all profile-dependent services
docker compose --profile ci down
docker compose --profile security down
docker compose --profile productivity down

# Phase 2: Restart data layer
docker compose down postgres redis
docker compose up -d postgres redis

# Phase 3: Wait for health
until docker compose ps postgres 2>/dev/null | grep -q healthy; do
  echo "Waiting for postgres..."
  sleep 5
done

# Phase 4: Restart dependents
docker compose --profile ci up -d
docker compose --profile security up -d
docker compose --profile productivity up -d
```

---

## 10. Emergency Procedures

### Full stack recovery from scratch

```bash
cd /mnt/d/docker

# 1. Tear down everything, removing all data
docker compose --profile '*' down -v

# 2. Remove dangling images
docker image prune -af

# 3. Remove unused networks (except the external ones)
docker network prune -f

# 4. Ensure external networks exist
for net in proxy database ai-ml agent-communication security monitoring; do
  docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
done

# 5. Verify secrets
ls secrets/*.txt

# 6. Pull fresh images
docker compose --profile '*' pull

# 7. Start everything
docker compose --profile '*' up -d

# 8. Wait for health checks
sleep 120
docker compose --profile '*' ps

# 9. Run integration tests
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

# Rotate Postgres password (most complex — requires DB-level change too)
docker exec postgres psql -U alwazw -c "ALTER USER alwazw WITH PASSWORD '$(cat secrets/postgres_password.txt)';"
docker compose up -d --force-recreate postgres authentik-server authentik-worker guacamole gitea n8n

# Rotate Redis password
docker compose stop redis
# Update secrets/redis_password.txt
docker compose up -d --force-recreate redis
docker compose up -d --force-recreate authentik-server authentik-worker omniroute

# Rotate LiteLLM key
docker compose up -d --force-recreate agent-zero litellm

# Rotate all at once (if rotating everything)
docker compose --profile '*' up -d --force-recreate

# 4. Verify
docker compose --profile '*' ps
python3 scripts/integration_test.py
```

### Network recovery (iptables reset)

```bash
# If Docker networking is broken (e.g., after WSL2 restart or Windows update):

# 1. Stop all containers
docker compose --profile '*' down

# 2. Restart Docker (WSL2)
# From PowerShell (Windows):
#   wsl --shutdown
#   # Then restart WSL

# 3. Verify networks exist
for net in proxy database ai-ml agent-communication security monitoring; do
  docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
done

# 4. Check iptables FORWARD rules
sudo iptables -L FORWARD -n -v
sudo iptables -L DOCKER-FORWARD -n -v

# 5. If FORWARD policy is DROP and no ACCEPT rules, reset Docker
sudo systemctl restart docker

# 6. Restart stack
docker compose --profile '*' up -d

# 7. Verify inter-container connectivity
docker exec agent-zero ping -c 1 litellm
docker exec litellm ping -c 1 ollama
```

### Container image recovery

```bash
# If images are corrupted or missing:

# 1. Remove broken images
docker rmi $(docker images --filter "dangling=true" -q) 2>/dev/null

# 2. Pull specific image if known
docker pull postgres:16-alpine
docker pull redis:7-alpine
docker pull traefik:latest

# 3. Pull all images from compose
docker compose --profile '*' pull

# 4. If registry is unreachable, load from backup
docker load -i /path/to/image-backup.tar

# 5. Rebuild custom images
docker compose build agent-zero

# 6. Verify
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```

### Postgres data recovery

```bash
# If postgres data is corrupted but backup exists:

# 1. Stop postgres and dependents
docker compose --profile ci down
docker compose --profile security down
docker compose --profile productivity down
docker compose stop postgres

# 2. Backup current data
mv compose/data/postgres/data compose/data/postgres/data.corrupted

# 3. Restore from dump
mkdir compose/data/postgres/data
docker run --rm -i \
  -v $(pwd)/compose/data/postgres/data:/var/lib/postgresql/data \
  -v $(pwd)/backups:/backups:ro \
  postgres:16-alpine bash -c "
    chown 999:999 /var/lib/postgresql/data &&
    psql -f /backups/aef3-full-latest.sql.gz
  "

# 4. Restart
docker compose up -d postgres
docker compose --profile ci up -d
docker compose --profile security up -d
docker compose --profile productivity up -d
```

### Traefik ACME certificate recovery

```bash
# If acme.json is corrupted or certificates expired:

# 1. Backup current state
cp compose/network/traefik/data/acme.json compose/network/traefik/data/acme.json.bak

# 2. Stop traefik
docker compose stop traefik

# 3. Remove corrupted acme.json (Traefik will request new certs)
rm compose/network/traefik/data/acme.json

# 4. Restart
docker compose up -d traefik

# 5. Monitor certificate issuance
docker compose logs -f traefik 2>&1 | grep -iE 'acme|certificate|tls'
```

---

## Appendix A: Quick Reference

### Common commands

```bash
cd /mnt/d/docker

# View all running services
docker compose --profile '*' ps

# View logs for a service
docker compose logs -f <name> --tail 100

# Restart a service
docker compose restart <name>

# Enter a container shell
docker exec -it <name> sh        # Alpine-based
docker exec -it <name> bash      # Debian-based
docker exec -it postgres psql -U alwazw -d aef3

# Check disk usage
docker system df
docker compose --profile '*' ps --format '{{.Name}}' | xargs -I{} docker inspect {} --format '{{.Name}}: {{.SizeRw}}'

# Prune unused resources
docker system prune -af --volumes   # DANGER: removes everything unused
```

### Port map

| Service | Host Port | Container Port |
|---|---|---|
| Traefik HTTP | 80 | 80 |
| Traefik HTTPS | 443 | 443 |
| Traefik Dashboard | 8080 | 8080 |
| Portainer Edge | 8000 | 8000 |
| Homepage | 3004 | 3000 |
| Grafana | 3000 | 3000 |
| OpenWebUI | 3000 | 8080 |
| Uptime Kuma | 3002 | 3001 |
| Gitea | 3001 | 3000 |
| Gitea SSH | 2222 | 22 |
| Loki | 3100 | 3100 |
| LiteLLM | 4000 | 4000 |
| Dockge | 5001 | 5001 |
| Postgres | 5432 | 5432 |
| n8n | 5678 | 5678 |
| Qdrant | 6333 | 6333 |
| Redis | 6379 | 6379 |
| MCPO | 8000 | 8000 |
| SearXNG | 8080 | 8080 |
| Agent Zero | 8501 | 80 |
| Agent Zero API | 8081 | 8080 |
| Hermes | 8787 | 8787 |
| Authentik | 9000 | 9000 |
| Prometheus | 9090 | 9090 |
| Portainer | 9443 | 9443 |
| Ollama | 11434 | 11434 |
| Omniroute | 20128 | 20128 |

### Domain map (via Traefik)

| Subdomain | Service |
|---|---|
| `chat.${DOMAIN}` | OpenWebUI |
| `hermes.${DOMAIN}` | Hermes |
| `omniroute.${DOMAIN}` | Omniroute |
| `auth.${DOMAIN}` | Authentik |
| `vault.${DOMAIN}` | Vaultwarden |
| `gitea.${DOMAIN}` | Gitea |
| `n8n.${DOMAIN}` | n8n |
| `rdp.${DOMAIN}` | Guacamole |
| `traefik.${DOMAIN}` | Traefik Dashboard |
| `cadvisor.${DOMAIN}` | cAdvisor |
| `logs.${DOMAIN}` | Dozzle |
| `portainer.${DOMAIN}` | Portainer |
| `dockge.${DOMAIN}` | Dockge |
| `home.${DOMAIN}` | Homepage |
| `search.${DOMAIN}` | SearXNG |
