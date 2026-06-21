# AEF3 Service Inventory

> **Stack:** AEF3 Docker Compose — Modular Architecture
> **Date:** 2026-06-16
> **Total Services:** 31 containers across 29 compose files
> **Architecture:** Each service has its own `compose/<category>/<service>/docker-compose.yml` included by the root `docker-compose.yml`

---

## 1. Executive Summary

| Service | Category | Profile | Compose File | Status | URL | Networks | Secrets |
|---------|----------|---------|--------------|--------|-----|----------|---------|
| **traefik** | network | ai | `compose/network/traefik/docker-compose.yml` | healthy | https://traefik.wazzan.us | proxy | cf_api_email, cf_dns_api_token |
| **agent-zero** | ai | ai | `compose/ai/agent-zero/docker-compose.yml` | healthy | http://localhost:8501 (API: 8081) | ai-ml, agent-communication | litellm_key, ssh_deploy_key, agent_zero_key |
| **hermes-agent** | ai | ai | `compose/ai/hermes-agent/docker-compose.yml` | healthy | internal only | ai-ml, agent-communication | - |
| **hermes** | ai | ai | `compose/ai/hermes/docker-compose.yml` | healthy | https://hermes.wazzan.us | proxy, ai-ml, agent-communication | hermes_password |
| **litellm** | ai | ai | `compose/ai/litellm/docker-compose.yml` | healthy | http://localhost:4000 | proxy, ai-ml | litellm_key |
| **ollama** | ai | ai | `compose/ai/ollama/docker-compose.yml` | healthy | http://localhost:11434 | ai-ml | - |
| **mcpo** | ai | ai | `compose/ai/mcpo/docker-compose.yml` | healthy | http://localhost:8000 | ai-ml | - |
| **omniroute** | ai | ai | `compose/ai/omniroute/docker-compose.yml` | healthy | https://omniroute.wazzan.us | proxy, ai-ml, database | redis_password |
| **openwebui** | ai | ai | `compose/ai/openwebui/docker-compose.yml` | healthy | https://chat.wazzan.us | proxy, ai-ml | webui_secret_key |
| **qdrant** | ai | ai | `compose/ai/qdrant/docker-compose.yml` | healthy | http://localhost:6333 | ai-ml | - |
| **searxng** | ai | ai | `compose/ai/searxng/docker-compose.yml` | healthy | https://search.wazzan.us | proxy, ai-ml | webui_secret_key |
| **authentik-server** | security | security | `compose/security/authentik-server/docker-compose.yml` | healthy | https://auth.wazzan.us | proxy, database, security | authentik_secret, redis_password, postgres_password |
| **authentik-worker** | security | security | `compose/security/authentik-worker/docker-compose.yml` | healthy | internal only | database, security | authentik_secret, redis_password, postgres_password |
| **vaultwarden** | security | security | `compose/security/vaultwarden/docker-compose.yml` | healthy | https://vault.wazzan.us | proxy, security | vw_admin_token |
| **prometheus** | monitoring | monitoring | `compose/monitoring/prometheus/docker-compose.yml` | healthy | http://localhost:9090 | monitoring | - |
| **grafana** | monitoring | monitoring | `compose/monitoring/grafana/docker-compose.yml` | healthy | http://localhost:3000 | monitoring | - |
| **uptime-kuma** | monitoring | monitoring | `compose/monitoring/uptime-kuma/docker-compose.yml` | healthy | http://localhost:3001 | monitoring | - |
| **loki** | monitoring | monitoring | `compose/monitoring/loki/docker-compose.yml` | no-hc | http://localhost:3100 | monitoring | - |
| **promtail** | monitoring | monitoring | `compose/monitoring/promtail/docker-compose.yml` | no-hc | internal only | monitoring | - |
| **cadvisor** | monitoring | monitoring | `compose/monitoring/cadvisor/docker-compose.yml` | healthy | https://cadvisor.wazzan.us | monitoring, proxy | - |
| **dozzle** | monitoring | monitoring | `compose/monitoring/dozzle/docker-compose.yml` | no-hc | https://logs.wazzan.us | proxy | - |
| **portainer** | management | management | `compose/management/portainer/docker-compose.yml` | no-hc | https://portainer.wazzan.us | proxy | - |
| **dockge** | management | management | `compose/management/dockge/docker-compose.yml` | healthy | https://dockge.wazzan.us | proxy | - |
| **homepage** | management | management | `compose/management/homepage/docker-compose.yml` | healthy | https://home.wazzan.us | proxy | - |
| **gitea** | ci | ci | `compose/ci/gitea/docker-compose.yml` | healthy | https://gitea.wazzan.us | proxy, database | postgres_password, gitea_secret |
| **n8n** | ci | ci | `compose/ci/n8n/docker-compose.yml` | healthy | https://n8n.wazzan.us | proxy, database | n8n_key, postgres_password |
| **woodpecker-server** | ci | ci | `compose/ci/woodpecker/docker-compose.yml` | healthy | https://ci.wazzan.us | proxy, database | gitea_secret |
| **woodpecker-agent** | ci | ci | `compose/ci/woodpecker/docker-compose.yml` | healthy | internal only | proxy | gitea_secret |
| **guacd** | productivity | productivity | `compose/productivity/guacd/docker-compose.yml` | healthy | internal only | ai-ml | - |
| **guacamole** | productivity | productivity | `compose/productivity/guacamole/docker-compose.yml` | healthy | https://rdp.wazzan.us | proxy, ai-ml, database | postgres_password, guac_admin_pass |
| **affine** | productivity | productivity | `compose/productivity/affine/docker-compose.yml` | healthy | https://affine.wazzan.us | proxy, database | redis_password |
| **plane-web** | productivity | productivity | `compose/productivity/plane/docker-compose.yml` | healthy | https://plane.wazzan.us (via plane-proxy) | proxy, ai-ml | - |
| **plane-api** | productivity | productivity | `compose/productivity/plane/docker-compose.yml` | healthy | internal only | proxy, ai-ml, database | gitea_secret |
| **plane-worker** | productivity | productivity | `compose/productivity/plane/docker-compose.yml` | healthy | internal only | ai-ml, database | - |
| **plane-proxy** | productivity | productivity | `compose/productivity/plane/docker-compose.yml` | healthy | https://plane.wazzan.us | proxy | - |
| **cloudflared** | network | network | `compose/network/cloudflared/docker-compose.yml` | no-hc | Cloudflare tunnel | proxy | cf_tunnel_token |
| **cloudflared-installer** | network | network | `compose/network/cloudflared/docker-compose.yml` | exited (one-shot) | - | - | - |
| **postgres** | data | (none — always-on) | `compose/data/postgres/docker-compose.yml` | healthy | localhost:5432 | database | postgres_password |
| **redis** | data | (none — always-on) | `compose/data/redis/docker-compose.yml` | healthy | localhost:6379 | database | redis_password |

> **cloudflared-installer** is a one-shot container (exited, normal behavior).

---

## 2. Detailed Inventory by Category

### 2.1 AI Core (10 services)

The AI profile is the largest category, containing the full machine-learning stack including LLM inference, vector search, agent orchestration, and web interfaces.

| Service | Role | Compose File | External Access | Key Ports | Secrets |
|---------|------|--------------|-----------------|-----------|---------|
| **traefik** | Reverse proxy & TLS termination | `compose/network/traefik/` | https://traefik.wazzan.us | 80, 443 | cf_api_email, cf_dns_api_token |
| **agent-zero** | Autonomous agent runtime | `compose/ai/agent-zero/` | :8501 (UI), :8081 (API) | 8501, 8081 | litellm_key, ssh_deploy_key, agent_zero_key |
| **hermes-agent** | PM agent (Hermes reasoning) | `compose/ai/hermes-agent/` | Internal only | - | - |
| **hermes** | Hermes orchestration layer | `compose/ai/hermes/` | https://hermes.wazzan.us | 8787 | hermes_password |
| **litellm** | LLM API gateway (OpenAI-compatible) | `compose/ai/litellm/` | :4000 | 4000 | litellm_key |
| **ollama** | Local LLM inference engine | `compose/ai/ollama/` | :11434 | 11434 | - |
| **mcpo** | MCP (Model Context Protocol) orchestrator | `compose/ai/mcpo/` | :8000 | 8000 | - |
| **omniroute** | Intelligent request routing | `compose/ai/omniroute/` | https://omniroute.wazzan.us | 20128 | redis_password |
| **openwebui** | Chat UI for LLMs | `compose/ai/openwebui/` | https://chat.wazzan.us | - | webui_secret_key |
| **qdrant** | Vector database | `compose/ai/qdrant/` | :6333 | 6333, 6334 | - |
| **searxng** | Privacy-focused metasearch | `compose/ai/searxng/` | https://search.wazzan.us | - | webui_secret_key |

**Shared secret:** `webui_secret_key` is used by both openwebui and searxng.

### 2.2 Security (3 services)

Authentication, authorization, and secrets management for the entire stack.

| Service | Role | Compose File | External Access | Key Ports | Secrets |
|---------|------|--------------|-----------------|-----------|---------|
| **authentik-server** | Identity provider & SSO | `compose/security/authentik-server/` | https://auth.wazzan.us | - | authentik_secret, redis_password, postgres_password |
| **authentik-worker** | Async task worker for authentik | `compose/security/authentik-worker/` | Internal only | - | authentik_secret, redis_password, postgres_password |
| **vaultwarden** | Bitwarden-compatible password manager | `compose/security/vaultwarden/` | https://vault.wazzan.us | - | vw_admin_token |

> authentik-server and authentik-worker are defined in separate compose files and share the same three secrets.

### 2.3 Monitoring (7 services)

Full observability stack: metrics, logs, container stats, uptime, and log streaming.

| Service | Role | Compose File | External Access | Key Ports | Notes |
|---------|------|--------------|-----------------|-----------|-------|
| **prometheus** | Metrics collection & storage | `compose/monitoring/prometheus/` | :9090 | 9090 | Scrapes cadvisor, own metrics |
| **grafana** | Metrics visualization dashboards | `compose/monitoring/grafana/` | :3000 | 3000 | Connects to Prometheus |
| **uptime-kuma** | Uptime monitoring & alerting | `compose/monitoring/uptime-kuma/` | :3001 | 3001 | Monitors all public endpoints |
| **loki** | Log aggregation (Grafana Loki) | `compose/monitoring/loki/` | :3100 | 3100 | Scratch image; no healthcheck |
| **promtail** | Log shipper to Loki | `compose/monitoring/promtail/` | Internal only | - | No healthcheck |
| **cadvisor** | Container resource metrics | `compose/monitoring/cadvisor/` | https://cadvisor.wazzan.us | - | Exposed via proxy for Grafana |
| **dozzle** | Real-time container log viewer | `compose/monitoring/dozzle/` | https://logs.wazzan.us | - | No healthcheck |

### 2.4 Management (3 services)

Infrastructure management and dashboarding.

| Service | Role | Compose File | External Access | Key Ports | Notes |
|---------|------|--------------|-----------------|-----------|-------|
| **portainer** | Docker container management UI | `compose/management/portainer/` | https://portainer.wazzan.us | - | No healthcheck |
| **dockge** | Docker Compose management UI | `compose/management/dockge/` | https://dockge.wazzan.us | - | Manages compose stacks |
| **homepage** | Homepage / application dashboard | `compose/management/homepage/` | https://home.wazzan.us | - | Landing page for all services |

### 2.5 CI/CD (4 containers, 3 compose files)

Source control, workflow automation, and continuous integration.

| Service | Role | Compose File | External Access | Key Ports | Secrets |
|---------|------|--------------|-----------------|-----------|---------|
| **gitea** | Self-hosted Git server | `compose/ci/gitea/` | https://gitea.wazzan.us | - | postgres_password, gitea_secret |
| **n8n** | Workflow automation platform | `compose/ci/n8n/` | https://n8n.wazzan.us | - | n8n_key, postgres_password |
| **woodpecker-server** | CI server | `compose/ci/woodpecker/` | https://ci.wazzan.us | 8001 | gitea_secret |
| **woodpecker-agent** | CI build agent | `compose/ci/woodpecker/` | Internal only | - | gitea_secret |

### 2.6 Productivity (6 containers, 3 compose files)

Remote desktop access and collaborative tools.

| Service | Role | Compose File | External Access | Key Ports | Secrets |
|---------|------|--------------|-----------------|-----------|---------|
| **guacd** | Guacamole daemon (protocol translation) | `compose/productivity/guacd/` | Internal only | 4822 | - |
| **guacamole** | Web-based remote desktop gateway | `compose/productivity/guacamole/` | https://rdp.wazzan.us | - | postgres_password, guac_admin_pass |
| **affine** | Collaborative knowledge base | `compose/productivity/affine/` | https://affine.wazzan.us | 8083 | redis_password |
| **plane-web** | Plane frontend | `compose/productivity/plane/` | via plane-proxy | - | - |
| **plane-api** | Plane API backend | `compose/productivity/plane/` | internal only | - | gitea_secret |
| **plane-worker** | Plane background worker | `compose/productivity/plane/` | internal only | - | - |
| **plane-proxy** | Plane reverse proxy | `compose/productivity/plane/` | https://plane.wazzan.us | 8085 | - |

### 2.7 Network (2 services + 1 one-shot)

Reverse proxy and secure outbound connectivity via Cloudflare Tunnel.

| Service | Role | Compose File | External Access | Key Ports | Secrets |
|---------|------|--------------|-----------------|-----------|---------|
| **traefik** | Reverse proxy & TLS termination | `compose/network/traefik/` | https://traefik.wazzan.us | 80, 443 | cf_api_email, cf_dns_api_token |
| **cloudflared** | Cloudflare Tunnel daemon | `compose/network/cloudflared/` | Tunnel to CF edge | - | cf_tunnel_token |
| **cloudflared-installer** | One-shot cert installer | `compose/network/cloudflared/` | Exited (normal) | - | - |

### 2.8 Infrastructure (2 services, always-on)

Shared data services available to all profiles. These have no profile guard and start unconditionally.

| Service | Role | Compose File | External Access | Key Ports | Secrets |
|---------|------|--------------|-----------------|-----------|---------|
| **postgres** | PostgreSQL relational database | `compose/data/postgres/` | localhost:5432 | 5432 | postgres_password |
| **redis** | Redis in-memory cache & broker | `compose/data/redis/` | localhost:6379 | 6379 | redis_password |

---

## 3. Network Topology

### 3.1 Custom Networks

| Network | Subnet | Purpose | Services |
|---------|--------|---------|----------|
| **proxy** | 172.18.0.0/16 | Traefik reverse proxy + all externally-facing services | traefik, cloudflared, cadvisor, dozzle, portainer, dockge, homepage, all `*.wazzan.us` services |
| **ai-ml** | 172.21.0.0/16 | AI/ML services intercommunication | agent-zero, hermes, hermes-agent, litellm, ollama, mcpo, omniroute, openwebui, qdrant, searxng, guacd, guacamole, plane-web, plane-api, plane-worker |
| **database** | (auto-assigned) | Database layer isolation | postgres, redis, authentik-server, authentik-worker, omniroute, gitea, n8n, guacamole, affine, plane-api, plane-worker, woodpecker-server |
| **security** | (auto-assigned) | Authentication service isolation | authentik-server, authentik-worker, vaultwarden |
| **monitoring** | (auto-assigned) | Observability stack isolation | prometheus, grafana, uptime-kuma, loki, promtail, cadvisor |
| **agent-communication** | (auto-assigned) | Hermes-to-Agent-Zero bridge | agent-zero, hermes, hermes-agent |

### 3.2 Network Membership Matrix

```
                    proxy  ai-ml  database  security  monitoring  agent-comm
traefik               X
agent-zero                   X                                  X
hermes-agent                 X                                  X
hermes                       X                                  X
litellm               X      X
ollama                       X
mcpo                         X
omniroute             X      X        X
openwebui             X      X
qdrant                       X
searxng               X      X
authentik-server      X               X         X
authentik-worker                      X         X
vaultwarden           X                         X
prometheus                                                X
grafana                                                     X
uptime-kuma                                                 X
loki                                                        X
promtail                                                    X
cadvisor              X                                     X
dozzle                X
portainer             X
dockge                X
homepage              X
gitea                 X        X
n8n                   X        X
woodpecker-server     X        X
woodpecker-agent      X
guacd                          X
guacamole             X        X        X
affine                X        X
plane-web             X        X
plane-api             X        X        X
plane-worker                   X        X
plane-proxy           X
cloudflared           X
postgres                          X
redis                               X
```

### 3.3 Network Flow Diagram

```
Internet
    |
    v
[Cloudflare Edge]
    |
    +-- cloudflared tunnel --> proxy network
    |
    v
[traefik] (proxy: 172.18.0.0/16)
    |
    +-- *.wazzan.us routes --> external-facing services
    |       |
    |       +-- AI: hermes, omniroute, openwebui, searxng
    |       +-- Security: authentik-server, vaultwarden
    |       +-- Monitoring: cadvisor, dozzle
    |       +-- Management: portainer, dockge, homepage
    |       +-- CI/CD: gitea, n8n, woodpecker-server
    |       +-- Productivity: guacamole, affine, plane-proxy
    |
    +-- localhost:PORT --> direct port access (non-proxied)

[ai-ml: 172.21.0.0/16] <-- AI services internal communication
    |
    +-- ollama, qdrant, mcpo (data providers)
    +-- litellm (LLM gateway)
    +-- agent-zero, hermes, hermes-agent (agents)
    +-- guacd, guacamole (productivity bridge)
    +-- plane-web, plane-api, plane-worker (project management)

[database] <-- Shared data layer
    |
    +-- postgres (5432), redis (6379)
    +-- Consumers: authentik, omniroute, gitea, n8n, guacamole, affine, plane, woodpecker

[security] <-- Auth isolation boundary
    |
    +-- authentik-server, authentik-worker, vaultwarden

[monitoring] <-- Observability stack
    |
    +-- prometheus -> scrapes cadvisor
    +-- loki <- promtail (log shipper)
    +-- grafana -> reads prometheus + loki
    +-- uptime-kuma (external health checks)

[agent-communication] <-- Hermes <-> Agent Zero bridge
    |
    +-- hermes, hermes-agent <-> agent-zero
```

---

## 4. Secret Management Architecture

### 4.1 Overview

- **Total secrets defined:** 18 secret sources in `docker-compose.yml` (root file)
- **Declaration pattern:** Secrets are declared with `file: ./secrets/<name>.txt` in the root `docker-compose.yml`
- **Service-level pattern:** Each service compose file declares secrets as `external: true`, referencing the root-level definitions
- **Mount path:** All secrets mounted as read-only files at `/run/secrets/<name>`
- **`.env` file:** Contains ZERO secrets (ports, domains, non-sensitive configuration only)
- **Fallback:** Services without native `_FILE` environment variable support use entrypoint wrapper scripts to read secrets at startup

### 4.2 How It Works

```
Root docker-compose.yml                    Service compose file
=======================                    ====================
secrets:                                   secrets:
  postgres_password:                         postgres_password:
    file: ./secrets/postgres_password.txt      external: true
```

The root file defines **where** the secret lives on disk (`file:`). Each service file declares it as `external: true`, meaning "use the secret already defined elsewhere in the compose project." Docker resolves the reference at compose-include time.

### 4.3 Secret Inventory

| Secret Name | Declared In | Used By | Purpose |
|-------------|-------------|---------|---------|
| `cf_api_email` | root compose | traefik | Cloudflare account email for DNS challenge |
| `cf_dns_api_token` | root compose | traefik | Cloudflare API token for TLS certificate issuance |
| `cf_api_key` | root compose | (unused) | Cloudflare API key (reserved) |
| `cf_tunnel_token` | root compose | cloudflared | Cloudflare Tunnel authentication token |
| `litellm_key` | root compose | agent-zero, litellm | LiteLLM API access key (shared) |
| `ssh_deploy_key` | root compose | agent-zero | SSH key for deployment access |
| `agent_zero_key` | root compose | agent-zero | Agent Zero API key |
| `hermes_password` | root compose | hermes | Hermes service authentication |
| `redis_password` | root compose | redis, omniroute, authentik-server, authentik-worker, affine | Redis authentication (shared across 5 services) |
| `webui_secret_key` | root compose | openwebui, searxng | Shared secret key for web UI services |
| `postgres_password` | root compose | postgres, authentik-server, authentik-worker, gitea, n8n, guacamole | PostgreSQL authentication (shared across 6 services) |
| `authentik_secret` | root compose | (legacy name) | - |
| `authentik_secret_key` | root compose | authentik-server, authentik-worker | Authentik internal secret (shared) |
| `vw_admin_token` | root compose | vaultwarden | Vaultwarden admin authentication token |
| `n8n_key` | root compose | n8n | N8N encryption key |
| `gitea_secret` | root compose | gitea, woodpecker-server, woodpecker-agent, plane-api | Gitea/CI secret (shared across 4 services) |
| `guac_admin_pass` | root compose | guacamole | Guacamole admin password |
| `github_token` | root compose | (reserved) | GitHub API token (reserved) |

### 4.4 Secret Sharing Groups

| Secret | Consumer Count | Services |
|--------|---------------|----------|
| `postgres_password` | 6 | postgres, authentik-server, authentik-worker, gitea, n8n, guacamole |
| `redis_password` | 5 | redis, omniroute, authentik-server, authentik-worker, affine |
| `gitea_secret` | 4 | gitea, woodpecker-server, woodpecker-agent, plane-api |
| `litellm_key` | 2 | litellm, agent-zero |
| `webui_secret_key` | 2 | openwebui, searxng |
| `authentik_secret_key` | 2 | authentik-server, authentik-worker |
| `cf_api_email` | 1 | traefik |
| `cf_dns_api_token` | 1 | traefik |
| `cf_api_key` | 1 | (reserved) |
| `cf_tunnel_token` | 1 | cloudflared |
| `ssh_deploy_key` | 1 | agent-zero |
| `agent_zero_key` | 1 | agent-zero |
| `hermes_password` | 1 | hermes |
| `vw_admin_token` | 1 | vaultwarden |
| `n8n_key` | 1 | n8n |
| `guac_admin_pass` | 1 | guacamole |
| `github_token` | 1 | (reserved) |

### 4.5 Secret Rotation Notes

When rotating shared secrets:
- `postgres_password` affects 6 services -- restart all consumers after rotation
- `redis_password` affects 5 services -- restart all consumers after rotation
- `gitea_secret` affects 4 services -- restart gitea, woodpecker-server, woodpecker-agent, plane-api
- `authentik_secret_key` must be rotated on both server and worker simultaneously

---

## 5. Healthcheck Summary

### 5.1 Status Overview

| Status | Count | Services |
|--------|-------|----------|
| Healthy | 27 | All services except loki, promtail, dozzle, portainer |
| No healthcheck | 4 | loki, promtail, dozzle, portainer |
| One-shot (exited) | 1 | cloudflared-installer (normal) |

### 5.2 Services Without Healthchecks

| Service | Compose File | Reason | Risk Level | Notes |
|---------|--------------|--------|------------|-------|
| **loki** | `compose/monitoring/loki/` | Scratch image (no shell for healthcheck) | Low | Standard limitation for scratch-based images |
| **promtail** | `compose/monitoring/promtail/` | Log shipper daemon | Low | Depends on Loki; monitored via Loki health |
| **dozzle** | `compose/monitoring/dozzle/` | Lightweight log viewer | Low | Stateless; fast restart if needed |
| **portainer** | `compose/management/portainer/` | Management UI | Medium | Container management interface; monitor via uptime-kuma |

### 5.3 Healthcheck Coverage

- **Coverage rate:** 27/31 runtime containers have healthchecks (87%)
- The 4 services without healthchecks are either scratch-image constrained (loki), stateless viewers (dozzle), or management tools (portainer)

---

## 6. Startup Order & Dependencies

### 6.1 Modular Startup

Each service is defined in its own compose file and can be started independently:

```bash
# Start a single service
docker compose -f compose/ai/ollama/docker-compose.yml up -d

# Start a category (all services in that directory)
docker compose -f compose/monitoring/prometheus/docker-compose.yml \
               -f compose/monitoring/grafana/docker-compose.yml up -d

# Start everything via root compose (uses include directives)
docker compose up -d

# Start specific profiles via root compose
docker compose --profile ai up -d
docker compose --profile security up -d
docker compose --profile monitoring up -d
docker compose --profile management up -d
docker compose --profile ci up -d
docker compose --profile productivity up -d
docker compose --profile network up -d
```

> **Note:** `postgres` and `redis` have no profile and start unconditionally with any `docker compose up`.

### 6.2 Dependency Tiers

Services should start in this order (Docker Compose `depends_on` within each file handles intra-file ordering):

```
Tier 0: Infrastructure (always-on, no profile guard)
  postgres (compose/data/postgres/), redis (compose/data/redis/)

Tier 1: Core Proxy & Network
  traefik (compose/network/traefik/), cloudflared (compose/network/cloudflared/)

Tier 2: Database-Dependent Services
  authentik-server (compose/security/authentik-server/ — needs postgres + redis)
  authentik-worker (compose/security/authentik-worker/ — needs postgres + redis)
  gitea (compose/ci/gitea/ — needs postgres)
  n8n (compose/ci/n8n/ — needs postgres)
  guacamole (compose/productivity/guacamole/ — needs postgres + guacd)
  omniroute (compose/ai/omniroute/ — needs redis)
  woodpecker-server (compose/ci/woodpecker/ — needs postgres)
  affine (compose/productivity/affine/ — needs postgres + redis)
  plane-api (compose/productivity/plane/ — needs postgres + redis)

Tier 3: AI/ML Stack
  ollama, qdrant, mcpo (data providers, no deps)
  litellm (LLM gateway, may depend on ollama models)
  searxng (metasearch)
  openwebui (UI, depends on litellm)
  agent-zero (needs litellm_key, ssh_deploy_key, agent_zero_key)
  hermes-agent (PM agent, no deps)
  hermes (compose/ai/hermes/ — depends_on hermes-agent)

Tier 4: Monitoring Stack
  loki, promtail (log pipeline — promtail depends_on loki)
  prometheus (metrics collection)
  cadvisor (container metrics, scraped by prometheus)
  grafana (visualization, depends_on prometheus)
  uptime-kuma (uptime monitoring)
  dozzle (log viewer)

Tier 5: Management & UI
  portainer, dockge, homepage
  vaultwarden (password manager)
```

### 6.3 Critical Dependency Chains

```
postgres ─┬─► authentik-server ─► authentik-worker
          ├─► gitea
          ├─► n8n
          ├─► guacamole
          ├─► woodpecker-server
          ├─► affine
          └─► plane-api

redis ────┬─► authentik-server
          ├─► omniroute
          ├─► affine
          └─► plane-api

guacd ───► guacamole

ollama ──► litellm ──► agent-zero
                      └─► openwebui

hermes-agent ─► hermes

prometheus ─► grafana
loki ──────► grafana
promtail ──► (ships to loki)

woodpecker-server ─► woodpecker-agent

plane-api ────┬─► plane-worker
              └─► plane-proxy
plane-web ────┘
```

---

## Appendix A: Public Endpoints

All publicly accessible services are routed through Traefik on the `proxy` network:

| Domain | Service | Profile | Compose File |
|--------|---------|---------|--------------|
| traefik.wazzan.us | traefik | ai | `compose/network/traefik/` |
| hermes.wazzan.us | hermes | ai | `compose/ai/hermes/` |
| omniroute.wazzan.us | omniroute | ai | `compose/ai/omniroute/` |
| chat.wazzan.us | openwebui | ai | `compose/ai/openwebui/` |
| search.wazzan.us | searxng | ai | `compose/ai/searxng/` |
| auth.wazzan.us | authentik-server | security | `compose/security/authentik-server/` |
| vault.wazzan.us | vaultwarden | security | `compose/security/vaultwarden/` |
| cadvisor.wazzan.us | cadvisor | monitoring | `compose/monitoring/cadvisor/` |
| logs.wazzan.us | dozzle | monitoring | `compose/monitoring/dozzle/` |
| portainer.wazzan.us | portainer | management | `compose/management/portainer/` |
| dockge.wazzan.us | dockge | management | `compose/management/dockge/` |
| home.wazzan.us | homepage | management | `compose/management/homepage/` |
| gitea.wazzan.us | gitea | ci | `compose/ci/gitea/` |
| n8n.wazzan.us | n8n | ci | `compose/ci/n8n/` |
| ci.wazzan.us | woodpecker-server | ci | `compose/ci/woodpecker/` |
| rdp.wazzan.us | guacamole | productivity | `compose/productivity/guacamole/` |
| affine.wazzan.us | affine | productivity | `compose/productivity/affine/` |
| plane.wazzan.us | plane-proxy | productivity | `compose/productivity/plane/` |

**Not proxied (localhost only):** agent-zero (:8501, :8081), litellm (:4000), ollama (:11434), mcpo (:8000), qdrant (:6333), prometheus (:9090), grafana (:3000), uptime-kuma (:3001), loki (:3100), postgres (:5432), redis (:6379), hermes (:8787), omniroute (:20128), openwebui (via proxy but also direct), portainer (:9443), dockge (:5001), homepage (:3004), guacd (:4822), plane-web (via plane-proxy), plane-api (internal), plane-worker (internal)

---

## Appendix B: Quick Reference

### Port Map (localhost only)

| Port | Service | Protocol |
|------|---------|----------|
| 3000 | grafana | HTTP |
| 3001 | uptime-kuma | HTTP |
| 3100 | loki | HTTP |
| 4000 | litellm | HTTP |
| 4822 | guacd (internal) | TCP |
| 5432 | postgres | TCP |
| 6333 | qdrant | HTTP |
| 6379 | redis | TCP |
| 8000 | mcpo | HTTP |
| 8000 | portainer (external) | TCP |
| 8081 | agent-zero (API) | HTTP |
| 8501 | agent-zero (UI) | HTTP |
| 8787 | hermes | HTTP |
| 9090 | prometheus | HTTP |
| 9443 | portainer | HTTPS |
| 11434 | ollama | HTTP |
| 20128 | omniroute | HTTP |

### Configuration Files

| File | Purpose |
|------|---------|
| `/mnt/d/docker/docker-compose.yml` | Root orchestrator — include directives, secrets, networks only |
| `/mnt/d/docker/.env` | Non-sensitive configuration (ports, domains) |
| `/mnt/d/docker/secrets/` | Docker secret files (read by root compose, mounted via external: true) |
| `compose/<category>/<service>/docker-compose.yml` | Individual service definitions |

### Per-Service Startup

```bash
# Each service can be started independently:
docker compose -f compose/ai/ollama/docker-compose.yml up -d
docker compose -f compose/monitoring/prometheus/docker-compose.yml up -d
docker compose -f compose/data/postgres/docker-compose.yml up -d

# Or combined via the root compose with profiles:
docker compose --profile ai up -d
```
