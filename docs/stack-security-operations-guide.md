# Stack Security and Operations Guide (SOP)

> **AEF3 — Autonomous Engineer Framework v3**
> **Version:** 1.0.0
> **Last Updated:** 2026-06-15
> **Maintainer:** Qwen Agent
> **Scope:** All containers managed by `/mnt/d/docker/docker-compose.yml`

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Configuration Layer: .yml → .env → secrets/](#2-configuration-layer-yml--env--secrets)
3. [Port Binding Standards](#3-port-binding-standards)
4. [Docker Compose Profiles](#4-docker-compose-profiles)
5. [Secret Management](#5-secret-management)
6. [Healthcheck Standards](#6-healthcheck-standards)
7. [Mandatory Runtime Validation](#7-mandatory-runtime-validation)
8. [Known Warnings & Acceptable Anomalies](#8-known-warnings--acceptable-anomalies)
9. [Incident Response Procedures](#9-incident-response-procedures)
10. [Remediation Backlog](#10-remediation-backlog)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    docker-compose.yml                           │
│  Service definitions, networks, volumes, healthchecks, profiles │
│  References: ${VARIABLE} from .env, /run/secrets/* from secrets │
├─────────────────────────────────────────────────────────────────┤
│                         .env                                    │
│  Port assignments, service config, plaintext credentials        │
│  Convention: PORT_<SERVICE>=<number>                            │
│            : <SERVICE>_<KEY>_FILE=/run/secrets/<name>           │
├─────────────────────────────────────────────────────────────────┤
│                      secrets/                                    │
│  One file per credential, chmod 600, never committed to git     │
│  Mounted into containers via Docker secrets or volume mounts    │
├─────────────────────────────────────────────────────────────────┤
│                   compose/ (per-service configs)                 │
│  compose/ai/        → Ollama, LiteLLM, Hermes, Agent Zero, MCPO│
│  compose/security/  → Authentik, Vaultwarden                   │
│  compose/monitoring/→ Prometheus, Grafana, Uptime Kuma          │
│  compose/data/      → PostgreSQL, Redis                         │
│  compose/network/   → Traefik                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Service Inventory (17 containers)

| Service | Profile | Port | Network(s) | Image |
|---|---|---|---|---|
| traefik | *(always)* | 80, 443 (public), 8080 (local) | proxy | `traefik:latest` |
| postgres | *(always)* | 5432 (local) | database | `postgres:16-alpine` |
| redis | *(always)* | 6379 (local) | database | `redis:7-alpine` |
| ollama | ai | 11434 (local) | ai-ml | `ollama/ollama:latest` |
| litellm | ai | 4000 (local) | proxy, ai-ml | `ghcr.io/berriai/litellm:main-latest` |
| openwebui | ai | 3000 (local) | proxy, ai-ml | `ghcr.io/open-webui/open-webui:main` |
| hermes-agent | ai | — | ai-ml | `nousresearch/hermes-agent:latest` |
| hermes | ai | 8787 (local) | proxy, ai-ml | `ghcr.io/nesquena/hermes-webui:latest` |
| omniroute | ai | 20128 (local) | proxy, ai-ml, database | `diegosouzapw/omniroute:latest` |
| agent-zero | ai | 8501 (local) | ai-ml | `frdel/agent-zero:latest` |
| mcpo | ai | 8000 (local) | ai-ml | `ghcr.io/open-webui/mcpo:latest` |
| authentik-server | security | 9000 (local) | proxy, database, security | `ghcr.io/goauthentik/server:2024.10.1` |
| authentik-worker | security | — | database, security | `ghcr.io/goauthentik/server:2024.10.1` |
| vaultwarden | security | 8082 (local) | proxy, security | `vaultwarden/server:latest` |
| prometheus | monitoring | 9090 (local) | monitoring | `prom/prometheus:latest` |
| grafana | monitoring | 3003 (local) | monitoring | `grafana/grafana:latest` |
| uptime-kuma | monitoring | 3002 (local) | monitoring | `louislam/uptime-kuma:latest` |

---

## 2. Configuration Layer: .yml → .env → secrets/

### Mandatory Rules

1. **docker-compose.yml** defines service topology. It MUST reference `.env` for all ports and secrets via `${VARIABLE}` substitution. No hardcoded port numbers or credentials in compose files.

2. **.env** is the single source of truth for:
   - Port assignments: `PORT_<SERVICE>=<number>`
   - Domain: `DOMAIN=wazzan.us`
   - Timezone: `TZ=America/Toronto`
   - Service configuration (non-secret): `POSTGRES_USER`, `POSTGRES_DB`, `VW_DOMAIN`
   - Secret file references: `<SERVICE>_SECRET_KEY_FILE=/run/secrets/<name>`

3. **secrets/** directory contains one file per credential:
   - `chmod 600` on all files (owner read/write only)
   - `chmod 644` on `.pub` files only
   - Listed in `.gitignore` — **never committed to git**
   - Mounted into containers via Docker Compose `secrets:` or volume `:ro` mounts

### Secret Mounting Patterns

**Pattern A: Docker Secrets (preferred)**
```yaml
# In docker-compose.yml
services:
  openwebui:
    secrets:
      - webui_secret_key
secrets:
  webui_secret_key:
    file: ./secrets/open_web_ui.txt
```
Container receives the secret at `/run/secrets/webui_secret_key`.

**Pattern B: Volume Mount (for services without secrets support)**
```yaml
volumes:
  - ./secrets/litellm_key.txt:/run/secrets/litellm_key.txt:ro
```

### Adding a New Service — Checklist

- [ ] Add service to `docker-compose.yml` with `profiles:` if non-core
- [ ] Add `PORT_<SERVICE>=<number>` to `.env`
- [ ] Bind port to `127.0.0.1:${PORT_<SERVICE>}:<container_port>`
- [ ] Generate secret: `openssl rand -base64 32 > secrets/<service>_key.txt`
- [ ] Set `chmod 600 secrets/<service>_key.txt`
- [ ] Reference secret via `secrets:` block or volume mount
- [ ] Add `healthcheck:` block
- [ ] Add homepage labels if applicable
- [ ] Add to appropriate Docker network(s)
- [ ] Test: `docker compose --profile <profile> up -d`
- [ ] Verify: `docker logs <container> --tail 50`

---

## 3. Port Binding Standards

### Mandatory Rule

**All service ports MUST be bound to `127.0.0.1` in local development.**

The ONLY exception is Traefik's HTTP/HTTPS ports (80/443), which are the public-facing reverse proxy.

### Binding Format

```yaml
# CORRECT — local only
ports:
  - "127.0.0.1:${PORT_SERVICE}:8080"

# CORRECT — reverse proxy (public)
ports:
  - "0.0.0.0:${PORT_TRAEFIK_HTTP}:80"
  - "0.0.0.0:${PORT_TRAEFIK_HTTPS}:443"

# WRONG — exposes to all interfaces
ports:
  - "${PORT_SERVICE}:8080"          # implicit 0.0.0.0
  - "0.0.0.0:${PORT_SERVICE}:8080"  # explicit 0.0.0.0
```

### Current Port Security Audit

| Service | Binding | Status |
|---|---|---|
| traefik (80/443) | `0.0.0.0` | ✅ Correct — reverse proxy |
| traefik (8080 dashboard) | `127.0.0.1` | ✅ Locked |
| postgres | `127.0.0.1` | ✅ Locked |
| redis | `127.0.0.1` (implicit — no host port) | ✅ Locked |
| vaultwarden | `127.0.0.1` | ✅ Locked |
| authentik | `127.0.0.1` | ✅ Locked |
| All AI services | `127.0.0.1` | ✅ Locked |
| All monitoring | `127.0.0.1` | ✅ Locked |

---

## 4. Docker Compose Profiles

### Profile Definitions

| Profile | Services | Use Case |
|---|---|---|
| *(none)* | traefik, postgres, redis | Core infrastructure — always starts |
| `ai` | ollama, litellm, openwebui, hermes, hermes-agent, omniroute, agent-zero, mcpo | AI/ML stack |
| `security` | authentik-server, authentik-worker, vaultwarden | Identity & secrets |
| `monitoring` | prometheus, grafana, uptime-kuma | Observability |

### Usage

```bash
# Core infrastructure only
docker compose up -d

# Core + AI stack
docker compose --profile ai up -d

# Everything
docker compose --profile ai --profile security --profile monitoring up -d

# Tear down all (including profiles)
docker compose --profile ai --profile security --profile monitoring down

# View services without profiles
docker compose config --services
```

---

## 5. Secret Management

### Generation

```bash
# Generate a new secret
openssl rand -base64 32 > secrets/<service>_key.txt
chmod 600 secrets/<service>_key.txt
```

### Permissions

```bash
# Fix all secret permissions
chmod 600 secrets/*_key.txt secrets/*_password.txt secrets/*_token.txt secrets/*_secret.txt
chmod 644 secrets/*.pub
```

### .gitignore Coverage

The `.gitignore` file MUST contain these patterns:
```
.env
.secrets
*_key.txt
*_password.txt
*.env.local
*.env.*.local
```

### Verification

```bash
# Check no secrets would be committed
git diff --staged --name-only | grep -E "secrets/|\.env$"
# Should return nothing
```

---

## 6. Healthcheck Standards

### Mandatory Rule

**Every service MUST have a `healthcheck:` block.** No exceptions.

### Template

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:<port>/<health_endpoint>"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

### Tool Availability

Not all images have the same tools. Use these fallbacks:

| Priority | Command | Notes |
|---|---|---|
| 1 | `curl -f http://localhost:<port>/health` | Most common |
| 2 | `wget --spider -q http://localhost:<port>/health` | Alpine images |
| 3 | `bash -c "echo > /dev/tcp/localhost/<port>"` | TCP socket check |
| 4 | Application-specific | e.g., `pg_isready`, `redis-cli ping` |

### Known Tool Gotchas

- **uptime-kuma:** Does NOT have `wget` — use `curl` only
- **mcpo:** Has `curl` — use `/docs` endpoint
- **Prometheus:** Runs as `nobody` (UID 65534) — data directory MUST be `chown 65534:65534`

---

## 7. Mandatory Runtime Validation

### Constraint for All AI Agents

**No agent may mark a container deployment as complete based solely on `docker ps` uptime or return code.** The following deep validation pipeline is mandatory:

### Step 1: Structural Health Check

```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Pass criteria:** All target containers show `Up X minutes (healthy)`.

### Step 2: Exhaustive Log Scrutiny

For **every** container deployed or modified:

```bash
docker logs --tail 200 <container_name> 2>&1 | grep -iE \
  "error|warn|fatal|panic|exception|fail|timeout|crash|refused|denied"
```

**Classify findings:**
- **CLEAN:** No matches — container is operating normally
- **ACCEPTABLE:** Matches are from known pre-existing conditions (see §8)
- **ACTION REQUIRED:** New errors, crash loops, auth failures, or silent exceptions

### Step 3: Stability Observation

```bash
# Snapshot at T+0
docker ps --format "{{.Names}}: {{.Status}}" > /tmp/t0.txt
sleep 15
# Snapshot at T+15s
docker ps --format "{{.Names}}: {{.Status}}" > /tmp/t15.txt
diff /tmp/t0.txt /tmp/t15.txt
```

**Pass criteria:** Zero diff — no state changes, restarts, or health transitions.

### Step 4: Port Binding Verification

```bash
docker ps --format "{{.Names}}: {{.Ports}}" | grep "0.0.0.0"
```

**Pass criteria:** Only `traefik:80` and `traefik:443` show `0.0.0.0`.

### Completion Gate

A deployment task is complete ONLY when:
1. ✅ All containers report `healthy`
2. ✅ Log scrutiny shows no new actionable errors
3. ✅ 15-second stability window shows zero state changes
4. ✅ Port bindings comply with 127.0.0.1 standard
5. ✅ Verification report is written to `agents/qwen/`

---

## 8. Known Warnings & Acceptable Anomalies

These are expected and do NOT require action:

| Container | Warning | Reason | Severity |
|---|---|---|---|
| redis | `WARNING Memory overcommit must be enabled` | WSL2 kernel limitation — no sysctl access from container | LOW |
| traefik | ACME cert errors for `*.wazzan.us` | Cloudflare API key not yet configured / rate-limited | LOW |
| traefik | `middleware "authentik@docker" does not exist` | Authentik forward-auth not yet configured | LOW |
| openwebui | `CORS_ALLOW_ORIGIN IS SET TO '*'` | Acceptable for local dev; tighten for production | LOW |
| openwebui | `USER_AGENT environment variable not set` | Cosmetic warning from langchain | INFO |
| hermes-agent | `No messaging platforms enabled` | No Discord/Slack/Telegram configured | INFO |
| authentik-server | Transient `PostgreSQL connection failed` during startup | Normal — retries until postgres is healthy | INFO |
| authentik-worker | `CPendingDeprecationWarning` for Celery 6.0 | Upstream deprecation notice — no functional impact | INFO |
| agent-zero | Wikidata HTTP 403 | External API rate limit — search engine fallback | LOW |
| omniroute | `ARENA_ELO_SYNC` timeouts | External LMArena API — non-critical feature | LOW |
| grafana | Elasticsearch plugin permission denied | Bundled plugin — not needed for current dashboards | LOW |
| grafana | `database is locked (SQLITE_BUSY)` | Transient — auto-resolves on retry | INFO |

---

## 9. Incident Response Procedures

### Container Unhealthy

```bash
# 1. Check logs
docker logs <container> --tail 100

# 2. Check healthcheck details
docker inspect <container> --format '{{json .State.Health}}' | python3 -m json.tool

# 3. Restart if transient
docker compose --profile <profile> restart <service>

# 4. Recreate if persistent
docker compose --profile <profile> up -d --force-recreate <service>
```

### Container Name Conflict (orphan)

```bash
# Force remove orphan container
docker rm -f <container_name>

# Recreate with compose
docker compose --profile <profile> up -d --remove-orphans
```

### Prometheus Permission Error

```bash
# Fix data directory ownership
sudo chown -R 65534:65534 compose/monitoring/prometheus/data
docker compose --profile monitoring restart prometheus
```

### Authentik Worker Heartbeat Stale

```bash
# Ensure depends_on with health conditions exists
# Restart both postgres/redis if needed, then worker
docker compose --profile security restart postgres redis authentik-worker
```

---

## 10. Remediation Backlog

Items identified during deep validation that require future action:

| Priority | Item | Impact | Owner |
|---|---|---|---|
| MEDIUM | Configure Cloudflare API credentials for Traefik ACME | HTTPS for `*.wazzan.us` won't work | Human |
| MEDIUM | Configure `authentik@docker` middleware in Traefik | Forward-auth not functional | Agent |
| MEDIUM | Migrate plaintext secrets in `.env` to file-based references | AUTHENTIK_SECRET_KEY, CF keys, HERMES_WEBUI_PASSWORD, POSTGRES_PASSWORD, REDIS_PASSWORD, GRAFANA_ADMIN_PASSWORD | Agent |
| LOW | Fix `DATA_ROOT` mismatch (`/home/alwazw/docker` vs `/mnt/d/docker`) | `_FILE` paths referencing `${DATA_ROOT}` won't resolve | Agent |
| LOW | Change `GRAFANA_ADMIN_PASSWORD` from `admin` to secure value | Default password | Human |
| LOW | Fix redis `vm.overcommit_memory` at WSL2 host level | Background save may fail under memory pressure | Human |
| LOW | Configure Uptime Kuma initial monitors | Monitoring stack has no targets configured | Agent |
| LOW | Add Prometheus scrape targets for Docker daemon metrics | `host.docker.internal:9323` unreachable without daemon config | Agent |

---

*This SOP is a living document. Update after every infrastructure change.*
