# AEF3 Service Inventory

> **Stack:** AEF3 Docker Compose
> **Date:** 2026-06-16
> **Total Services:** 31 defined | 31 running | 27 healthy | 4 no-healthcheck (normal)
> **Location:** `/mnt/d/docker/docker-compose.yml`

---

## 1. Executive Summary

| Service | Profile | Status | URL | Networks | Secrets |
|---------|---------|--------|-----|----------|---------|
| **traefik** | ai | healthy | https://traefik.wazzan.us | proxy | cf_api_email, cf_dns_api_token |
| **agent-zero** | ai | healthy | http://localhost:8501 (API: 8081) | ai-ml, agent-communication | litellm_key, ssh_deploy_key |
| **hermes-agent** | ai | healthy | internal only | ai-ml, agent-communication | - |
| **hermes** | ai | healthy | https://hermes.wazzan.us | proxy, ai-ml, agent-communication | hermes_password |
| **litellm** | ai | healthy | http://localhost:4000 | proxy, ai-ml | litellm_key |
| **ollama** | ai | healthy | http://localhost:11434 | ai-ml | - |
| **mcpo** | ai | healthy | http://localhost:8000 | ai-ml | - |
| **omniroute** | ai | healthy | https://omniroute.wazzan.us | proxy, ai-ml, database | redis_password |
| **openwebui** | ai | healthy | https://chat.wazzan.us | proxy, ai-ml | webui_secret_key |
| **qdrant** | ai | healthy | http://localhost:6333 | ai-ml | - |
| **searxng** | ai | healthy | https://search.wazzan.us | proxy, ai-ml | webui_secret_key |
| **authentik-server** | security | healthy | https://auth.wazzan.us | proxy, database, security | authentik_secret, redis_password, postgres_password |
| **authentik-worker** | security | healthy | internal only | database, security | authentik_secret, redis_password, postgres_password |
| **vaultwarden** | security | healthy | https://vault.wazzan.us | proxy, security | vw_admin_token |
| **prometheus** | monitoring | healthy | http://localhost:9090 | monitoring | - |
| **grafana** | monitoring | healthy | http://localhost:3000 | monitoring | - |
| **uptime-kuma** | monitoring | healthy | http://localhost:3002 | monitoring | - |
| **loki** | monitoring | no-hc | http://localhost:3100 | monitoring | - |
| **promtail** | monitoring | no-hc | internal only | monitoring | - |
| **cadvisor** | monitoring | healthy | https://cadvisor.wazzan.us | monitoring, proxy | - |
| **dozzle** | monitoring | no-hc | https://logs.wazzan.us | proxy | - |
| **portainer** | management | no-hc | https://portainer.wazzan.us | proxy | - |
| **dockge** | management | healthy | https://dockge.wazzan.us | proxy | - |
| **homepage** | management | healthy | https://home.wazzan.us | proxy | - |
| **gitea** | ci | healthy | https://gitea.wazzan.us | proxy, database | postgres_password, gitea_secret |
| **n8n** | ci | healthy | https://n8n.wazzan.us | proxy, database | n8n_key, postgres_password |
| **guacd** | productivity | healthy | internal only | ai-ml | - |
| **guacamole** | productivity | healthy | https://rdp.wazzan.us | proxy, ai-ml, database | postgres_password, guac_admin_pass |
| **cloudflared** | network | no-hc | Cloudflare tunnel | proxy | cf_tunnel_token |
| **postgres** | always-on | healthy | localhost:5432 | database | postgres_password |
| **redis** | always-on | healthy | localhost:6379 | database | redis_password |

> **cloudflared-installer** is a one-shot container (exited, normal behavior).

---

## 2. Detailed Inventory by Category

### 2.1 AI Core (10 services)

The AI profile is the largest category, containing the full machine-learning stack including LLM inference, vector search, agent orchestration, and web interfaces.

| Service | Role | External Access | Key Ports | Dependencies |
|---------|------|-----------------|-----------|--------------|
| **traefik** | Reverse proxy & TLS termination | https://traefik.wazzan.us | 80, 443 | Cloudflare DNS |
| **agent-zero** | Autonomous agent runtime | :8501 (UI), :8081 (API) | 8501, 8081 | litellm, ssh_deploy_key |
| **hermes-agent** | PM agent (Hermes reasoning) | Internal only | - | agent-communication |
| **hermes** | Hermes orchestration layer | https://hermes.wazzan.us | - | agent-communication |
| **litellm** | LLM API gateway (OpenAI-compatible) | :4000 | 4000 | litellm_key |
| **ollama** | Local LLM inference engine | :11434 | 11434 | - |
| **mcpo** | MCP (Model Context Protocol) orchestrator | :8000 | 8000 | - |
| **omniroute** | Intelligent request routing | https://omniroute.wazzan.us | - | redis_password |
| **openwebui** | Chat UI for LLMs | https://chat.wazzan.us | - | webui_secret_key |
| **qdrant** | Vector database | :6333 | 6333, 6334 | - |
| **searxng** | Privacy-focused metasearch | https://search.wazzan.us | - | webui_secret_key |

**Shared secret:** `webui_secret_key` is used by both openwebui and searxng.

### 2.2 Security (3 services)

Authentication, authorization, and secrets management for the entire stack.

| Service | Role | External Access | Key Ports | Dependencies |
|---------|------|-----------------|-----------|--------------|
| **authentik-server** | Identity provider & SSO | https://auth.wazzan.us | - | postgres, redis, authentik_secret |
| **authentik-worker** | Async task worker for authentik | Internal only | - | postgres, redis, authentik_secret |
| **vaultwarden** | Bitwarden-compatible password manager | https://vault.wazzan.us | - | vw_admin_token |

**Note:** authentik-server and authentik-worker share the same three secrets (`authentik_secret`, `redis_password`, `postgres_password`).

### 2.3 Monitoring (7 services)

Full observability stack: metrics, logs, container stats, uptime, and log streaming.

| Service | Role | External Access | Key Ports | Notes |
|---------|------|-----------------|-----------|-------|
| **prometheus** | Metrics collection & storage | :9090 | 9090 | Scrapes cadvisor, own metrics |
| **grafana** | Metrics visualization dashboards | :3000 | 3000 | Connects to Prometheus |
| **uptime-kuma** | Uptime monitoring & alerting | :3002 | 3002 | Monitors all public endpoints |
| **loki** | Log aggregation (Grafana Loki) | :3100 | 3100 | Scratch image; no healthcheck |
| **promtail** | Log shipper to Loki | Internal only | - | No healthcheck |
| **cadvisor** | Container resource metrics | https://cadvisor.wazzan.us | - | Exposed via proxy for Grafana |
| **dozzle** | Real-time container log viewer | https://logs.wazzan.us | - | No healthcheck |

### 2.4 Management (3 services)

Infrastructure management and dashboarding.

| Service | Role | External Access | Key Ports | Notes |
|---------|------|-----------------|-----------|-------|
| **portainer** | Docker container management UI | https://portainer.wazzan.us | - | No healthcheck |
| **dockge** | Docker Compose management UI | https://dockge.wazzan.us | - | Manages compose stacks |
| **homepage** | Hompage / application dashboard | https://home.wazzan.us | - | Landing page for all services |

### 2.5 CI/CD (2 services)

Source control and workflow automation.

| Service | Role | External Access | Key Ports | Dependencies |
|---------|------|-----------------|-----------|--------------|
| **gitea** | Self-hosted Git server | https://gitea.wazzan.us | - | postgres_password, gitea_secret |
| **n8n** | Workflow automation platform | https://n8n.wazzan.us | - | n8n_key, postgres_password |

### 2.6 Productivity (3 services)

Remote desktop access via Apache Guacamole.

| Service | Role | External Access | Key Ports | Dependencies |
|---------|------|-----------------|-----------|--------------|
| **guacd** | Guacamole daemon (protocol translation) | Internal only | 4822 | - |
| **guacamole** | Web-based remote desktop gateway | https://rdp.wazzan.us | - | guacd, postgres_password, guac_admin_pass |

### 2.7 Network (1 service + 1 one-shot)

Secure outbound connectivity via Cloudflare Tunnel.

| Service | Role | External Access | Key Ports | Dependencies |
|---------|------|-----------------|-----------|--------------|
| **cloudflared** | Cloudflare Tunnel daemon | Tunnel to CF edge | - | cf_tunnel_token |
| **cloudflared-installer** | One-shot cert installer | Exited (normal) | - | - |

### 2.8 Infrastructure (2 services, always-on)

Shared data services available to all profiles. These have no profile guard and start unconditionally.

| Service | Role | External Access | Key Ports | Dependencies |
|---------|------|-----------------|-----------|--------------|
| **postgres** | PostgreSQL relational database | localhost:5432 | 5432 | postgres_password |
| **redis** | Redis in-memory cache & broker | localhost:6379 | 6379 | redis_password |

---

## 3. Network Topology

### 3.1 Custom Networks

| Network | Subnet | Purpose | Services |
|---------|--------|---------|----------|
| **proxy** | 172.18.0.0/16 | Traefik reverse proxy + all externally-facing services | traefik, cloudflared, cadvisor, dozzle, portainer, dockge, homepage, all `*.wazzan.us` services |
| **ai-ml** | 172.21.0.0/16 | AI/ML services intercommunication | agent-zero, hermes, hermes-agent, litellm, ollama, mcpo, omniroute, openwebui, qdrant, searxng, guacd, guacamole |
| **database** | (auto-assigned) | Database layer isolation | postgres, redis, authentik-server, authentik-worker, omniroute, gitea, n8n, guacamole |
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
guacd                          X
guacamole             X        X        X
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
    |       +-- CI/CD: gitea, n8n
    |       +-- Productivity: guacamole
    |
    +-- localhost:PORT --> direct port access (non-proxied)

[ai-ml: 172.21.0.0/16] <-- AI services internal communication
    |
    +-- ollama, qdrant, mcpo (data providers)
    +-- litellm (LLM gateway)
    +-- agent-zero, hermes, hermes-agent (agents)
    +-- guacd, guacamole (productivity bridge)

[database] <-- Shared data layer
    |
    +-- postgres (5432), redis (6379)
    +-- Consumers: authentik, omniroute, gitea, n8n, guacamole

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

- **Total secrets defined:** 17 Docker secrets in `docker-compose.yml`
- **`.env` file:** Contains ZERO secrets (ports, domains, non-sensitive configuration only)
- **Mount path:** All secrets mounted as read-only files at `/run/secrets/<name>`
- **Fallback:** Services without native `_FILE` environment variable support use entrypoint wrapper scripts to read secrets at startup

### 4.2 Secret Inventory

| Secret Name | Used By | Purpose |
|-------------|---------|---------|
| `cf_api_email` | traefik | Cloudflare account email for DNS challenge |
| `cf_dns_api_token` | traefik | Cloudflare API token for TLS certificate issuance |
| `cf_tunnel_token` | cloudflared | Cloudflare Tunnel authentication token |
| `litellm_key` | agent-zero, litellm | LiteLLM API access key (shared) |
| `ssh_deploy_key` | agent-zero | SSH key for deployment access |
| `hermes_password` | hermes | Hermes service authentication |
| `redis_password` | omniroute, authentik-server, authentik-worker, redis | Redis authentication (shared across 4 services) |
| `webui_secret_key` | openwebui, searxng | Shared secret key for web UI services |
| `postgres_password` | authentik-server, authentik-worker, gitea, n8n, guacamole, postgres | PostgreSQL authentication (shared across 6 services) |
| `authentik_secret` | authentik-server, authentik-worker | Authentik internal secret (shared) |
| `vw_admin_token` | vaultwarden | Vaultwarden admin authentication token |
| `n8n_key` | n8n | N8N encryption key |
| `gitea_secret` | gitea | Gitea internal secret |
| `guac_admin_pass` | guacamole | Guacamole admin password |

### 4.3 Secret Sharing Groups

| Secret | Consumer Count | Services |
|--------|---------------|----------|
| `postgres_password` | 6 | postgres, authentik-server, authentik-worker, gitea, n8n, guacamole |
| `redis_password` | 4 | redis, omniroute, authentik-server, authentik-worker |
| `litellm_key` | 2 | litellm, agent-zero |
| `webui_secret_key` | 2 | openwebui, searxng |
| `authentik_secret` | 2 | authentik-server, authentik-worker |
| `cf_api_email` | 1 | traefik |
| `cf_dns_api_token` | 1 | traefik |
| `cf_tunnel_token` | 1 | cloudflared |
| `ssh_deploy_key` | 1 | agent-zero |
| `hermes_password` | 1 | hermes |
| `vw_admin_token` | 1 | vaultwarden |
| `n8n_key` | 1 | n8n |
| `gitea_secret` | 1 | gitea |
| `guac_admin_pass` | 1 | guacamole |

### 4.4 Secret Rotation Notes

When rotating shared secrets:
- `postgres_password` affects 6 services -- restart all consumers after rotation
- `redis_password` affects 4 services -- restart all consumers after rotation
- `authentik_secret` must be rotated on both server and worker simultaneously

---

## 5. Healthcheck Summary

### 5.1 Status Overview

| Status | Count | Services |
|--------|-------|----------|
| Healthy | 27 | All services except loki, promtail, dozzle, portainer |
| No healthcheck | 4 | loki, promtail, dozzle, portainer |
| One-shot (exited) | 1 | cloudflared-installer (normal) |

### 5.2 Services Without Healthchecks

| Service | Reason | Risk Level | Notes |
|---------|--------|------------|-------|
| **loki** | Scratch image (no shell for healthcheck) | Low | Standard limitation for scratch-based images |
| **promtail** | Log shipper daemon | Low | Depends on Loki; monitored via Loki health |
| **dozzle** | Lightweight log viewer | Low | Stateless; fast restart if needed |
| **portainer** | Management UI | Medium | Container management interface; monitor via uptime-kuma |

### 5.3 Healthcheck Coverage

- **Coverage rate:** 27/30 runtime services have healthchecks (90%)
- The 4 services without healthchecks are either scratch-image constrained (loki), stateless viewers (dozzle), or management tools (portainer)

---

## 6. Startup Order & Dependencies

### 6.1 Dependency Tiers

Services should start in this order (Docker Compose `depends_on` may override):

```
Tier 0: Infrastructure (always-on, no profile guard)
  postgres, redis

Tier 1: Core Proxy & Network
  traefik (DNS certs), cloudflared (tunnel)

Tier 2: Database-Dependent Services
  authentik-server, authentik-worker (needs postgres + redis)
  gitea (needs postgres)
  n8n (needs postgres)
  guacamole (needs postgres + guacd)
  omniroute (needs redis)

Tier 3: AI/ML Stack
  ollama, qdrant, mcpo (data providers, no deps)
  litellm (LLM gateway, may depend on ollama models)
  searxng (metasearch)
  openwebui (UI, depends on litellm)
  agent-zero (needs litellm_key, ssh_deploy_key)
  hermes, hermes-agent (agent orchestration)

Tier 4: Monitoring Stack
  loki, promtail (log pipeline)
  prometheus (metrics collection)
  cadvisor (container metrics, scraped by prometheus)
  grafana (visualization, depends on prometheus + loki)
  uptime-kuma (uptime monitoring)
  dozzle (log viewer)

Tier 5: Management & UI
  portainer, dockge, homepage
  vaultwarden (password manager)
```

### 6.2 Critical Dependency Chains

```
postgres ─┬─► authentik-server ─► authentik-worker
          ├─► gitea
          ├─► n8n
          └─► guacamole

redis ────┬─► authentik-server
          └─► omniroute

guacd ───► guacamole

ollama ──► litellm ──► agent-zero
                      └─► openwebui

prometheus ─► grafana
loki ──────► grafana
```

### 6.3 Profile Activation

Services are activated via Docker Compose profiles:

```bash
# AI stack (largest profile)
docker compose --profile ai up -d

# Security stack
docker compose --profile security up -d

# Monitoring stack
docker compose --profile monitoring up -d

# Management stack
docker compose --profile management up -d

# CI/CD stack
docker compose --profile ci up -d

# Productivity stack
docker compose --profile productivity up -d

# Network stack
docker compose --profile network up -d

# All profiles + always-on services
docker compose --profile ai --profile security --profile monitoring \
               --profile management --profile ci --profile productivity \
               --profile network up -d
```

> **Note:** `postgres` and `redis` have no profile and start unconditionally with any `docker compose up`.

---

## Appendix A: Public Endpoints

All publicly accessible services are routed through Traefik on the `proxy` network:

| Domain | Service | Profile |
|--------|---------|---------|
| traefik.wazzan.us | traefik | ai |
| hermes.wazzan.us | hermes | ai |
| omniroute.wazzan.us | omniroute | ai |
| chat.wazzan.us | openwebui | ai |
| search.wazzan.us | searxng | ai |
| auth.wazzan.us | authentik-server | security |
| vault.wazzan.us | vaultwarden | security |
| cadvisor.wazzan.us | cadvisor | monitoring |
| logs.wazzan.us | dozzle | monitoring |
| portainer.wazzan.us | portainer | management |
| dockge.wazzan.us | dockge | management |
| home.wazzan.us | homepage | management |
| gitea.wazzan.us | gitea | ci |
| n8n.wazzan.us | n8n | ci |
| rdp.wazzan.us | guacamole | productivity |

**Not proxied (localhost only):** agent-zero (:8501, :8081), litellm (:4000), ollama (:11434), mcpo (:8000), qdrant (:6333), prometheus (:9090), grafana (:3000), uptime-kuma (:3002), loki (:3100), postgres (:5432), redis (:6379)

---

## Appendix B: Quick Reference

### Port Map (localhost only)

| Port | Service | Protocol |
|------|---------|----------|
| 3000 | grafana | HTTP |
| 3002 | uptime-kuma | HTTP |
| 3100 | loki | HTTP |
| 4000 | litellm | HTTP |
| 4822 | guacd (internal) | TCP |
| 5432 | postgres | TCP |
| 6333 | qdrant | HTTP |
| 6379 | redis | TCP |
| 8000 | mcpo | HTTP |
| 8081 | agent-zero (API) | HTTP |
| 8501 | agent-zero (UI) | HTTP |
| 9090 | prometheus | HTTP |
| 11434 | ollama | HTTP |

### Configuration Files

| File | Purpose |
|------|---------|
| `/mnt/d/docker/docker-compose.yml` | Stack definition |
| `/mnt/d/docker/.env` | Non-sensitive configuration (ports, domains) |
| `/mnt/d/docker/secrets/` | Docker secret files |
