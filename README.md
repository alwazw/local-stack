# AEF3 — Autonomous Engineer Framework v3

[![Services: 31](https://img.shields.io/badge/Services-31-blue)](docker-compose.yml)
[![Networks: 6](https://img.shields.io/badge/Networks-6-green)](terraform/networks.tf)
[![Secrets: 17](https://img.shields.io/badge/Secrets-17-orange)](secrets/)
[![Profiles: 7](https://img.shields.io/badge/Profiles-7-purple)](docker-compose.yml)
[![IaC: Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)](terraform/)
[![License: Private](https://img.shields.io/badge/License-Private-red)](LICENSE)

A self-hosted, multi-agent AI engineering platform. AEF3 orchestrates 31 Docker containers across 7 functional profiles, managed via Terraform for production and Docker Compose for rapid testing. The stack spans an AI/ML core (agent-zero, hermes, litellm, ollama, qdrant), SSO/security (authentik, vaultwarden), CI/CD (gitea, n8n), full observability (prometheus, grafana, loki, cadvisor), and a Traefik + Cloudflare reverse-proxy layer with automatic TLS.

**Domain:** `wazzan.us`

---

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │              Internet (wazzan.us)               │
                    └──────────────────────┬──────────────────────────┘
                                           │
                    ┌──────────────────────▼──────────────────────────┐
                    │            Cloudflare CDN + Tunnel              │
                    └──────────────────────┬──────────────────────────┘
                                           │
              ┌────────────────────────────▼────────────────────────────┐
              │                   Traefik (proxy)                       │
              │            TLS termination, routing, LB                 │
              └──┬────┬────┬────┬────┬────┬────┬────┬────┬────┬──┬─────┘
                 │    │    │    │    │    │    │    │    │    │  │
  ┌──────────────▼─┐ ┌─▼────▼──┐│ ┌─▼─────▼──┐│││ ┌─▼──────▼┐ │ │
  │    AI / ML     │ │Security ││ │  CI/CD   ││││ │Monitoring│ │ │
  │                │ │         ││ │          ││││ │          │ │ │
  │ ┌────────────┐ │ │┌──────┐ ││ │┌────────┐│││ │┌────────┐│ │ │
  │ │agent-zero  │ │ ││auth- │ ││ ││ gitea  ││││ ││grafana ││ │ │
  │ └────────────┘ │ ││entik │ ││ │└────────┘│││ │└────────┘│ │ │
  │ ┌────────────┐ │ │└──────┘ ││ │┌────────┐│││ │┌────────┐│ │ │
  │ │hermes      │ │ │┌──────┐ ││ ││ n8n    ││││ ││prometh.││ │ │
  │ └────────────┘ │ ││vault │ ││ │└────────┘│││ │└────────┘│ │ │
  │ ┌────────────┐ │ ││warden│ ││ └──────────┘││ │┌────────┐│ │ │
  │ │litellm     │ │ │└──────┘ │└─────────────┘│ ││loki    ││ │ │
  │ └────────────┘ │ └─────────┘               │ │└────────┘│ │ │
  │ ┌────────────┐ │                           │ │┌────────┐│ │ │
  │ │ollama      │ │                           │ ││cadvisor││ │ │
  │ └────────────┘ │                           │ │└────────┘│ │ │
  │ ┌────────────┐ │                           │ │┌────────┐│ │ │
  │ │qdrant      │ │                           │ ││dozzle  ││ │ │
  │ └────────────┘ │                           │ │└────────┘│ │ │
  │ ┌────────────┐ │                           │ │┌────────┐│ │ │
  │ │openwebui   │ │                           │ ││uptime  ││ │ │
  │ └────────────┘ │                           │ │└────────┘│ │ │
  │ ┌────────────┐ │                           │ └──────────┘ │ │
  │ │mcpo        │ │                           └──────────────┘ │
  │ └────────────┘ │                                            │
  │ ┌────────────┐ │ ┌──────────────┐ ┌───────────────────────┐  │
  │ │omniroute   │ │ │   Database   │ │     Management        │  │
  │ └────────────┘ │ │ ┌──────────┐ │ │ ┌───────────────────┐ │  │
  │ ┌────────────┐ │ │ │ postgres │ │ │ │homepage/portainer │ │  │
  │ │searxng     │ │ │ │  redis   │ │ │ │dockge             │ │  │
  │ └────────────┘ │ │ └──────────┘ │ │ └───────────────────┘ │  │
  │ ┌────────────┐ │ └──────────────┘ └───────────────────────┘  │
  │ │guacamole   │ │                                             │
  │ └────────────┘ │                                             │
  └────────────────┴─────────────────────────────────────────────┘
```

### Network Topology

| Network | Purpose | Isolation |
|---------|---------|-----------|
| `proxy` | Traefik + externally-facing services | External |
| `ai-ml` | AI/ML stack (LLMs, vector DB, agents) | External |
| `agent-communication` | Agent-to-agent RPC bridge | External |
| `database` | Postgres, Redis, DB-dependent services | External |
| `security` | Authentik, Vaultwarden, SSO-protected services | External |
| `monitoring` | Prometheus, Grafana, Loki, cAdvisor | External |

---

## Quick Start

### Prerequisites

- Docker 24+ and Docker Compose v2
- Terraform >= 1.5
- `.env` file (copy from `.env.example` and customize)
- 17 secret files in `./secrets/` (see [Secret Management](#secret-management))

### Deploy with Terraform (Production)

```bash
cd terraform

terraform init
terraform plan
terraform apply -auto-approve
```

### Deploy with Docker Compose (Testing)

```bash
# Core services only (postgres, redis)
docker compose up -d

# Full stack with all profiles
docker compose --profile ai --profile security --profile monitoring \
  --profile management --profile ci --profile productivity --profile network up -d

# Single profile (e.g., AI stack only)
docker compose --profile ai up -d
```

---

## Service Inventory

| # | Service | Profile | Port | Internal Port | Domain / URL | Purpose |
|---|---------|---------|------|---------------|--------------|---------|
| 1 | traefik | ai | 80, 443 | 80, 443 | `traefik.wazzan.us` | Reverse proxy + TLS |
| 2 | cloudflared | network | — | — | — | Cloudflare Tunnel |
| 3 | agent-zero | ai | 8501, 8081 | 80, 8080 | `localhost:8501` | AI agent orchestrator |
| 4 | hermes-agent | ai | — | — | — | Hermes AI gateway |
| 5 | hermes | ai | 8787 | 8787 | `hermes.wazzan.us` | Hermes AI WebUI |
| 6 | litellm | ai | 4000 | 4000 | `localhost:4000` | LLM gateway / router |
| 7 | ollama | ai | 11434 | 11434 | `localhost:11434` | Local LLM inference |
| 8 | mcpo | ai | 8000 | 8000 | `localhost:8000` | MCP-to-OpenAPI bridge |
| 9 | openwebui | ai | 3000 | 8080 | `chat.wazzan.us` | Chat UI for LLMs |
| 10 | omniroute | ai | 20128 | 20128 | `omniroute.wazzan.us` | AI gateway (177+ providers) |
| 11 | qdrant | ai | 6333 | 6333 | `localhost:6333` | Vector database |
| 12 | searxng | ai | — | 8080 | `search.wazzan.us` | Privacy-respecting search |
| 13 | authentik-server | security | 9000 | 9000 | `auth.wazzan.us` | SSO / identity provider |
| 14 | authentik-worker | security | — | — | — | Authentik background worker |
| 15 | vaultwarden | security | 8082 | 80 | `vault.wazzan.us` | Password manager |
| 16 | postgres | — | 5432 | 5432 | `localhost:5432` | Primary RDBMS |
| 17 | redis | — | 6379 | 6379 | `localhost:6379` | Cache + message broker |
| 18 | prometheus | monitoring | 9090 | 9090 | `localhost:9090` | Metrics collection |
| 19 | grafana | monitoring | 3000 | 3000 | `localhost:3000` | Dashboards + visualization |
| 20 | uptime-kuma | monitoring | 3002 | 3001 | `localhost:3002` | Uptime monitoring |
| 21 | loki | monitoring | 3100 | 3100 | `localhost:3100` | Log aggregation |
| 22 | promtail | monitoring | — | — | — | Log shipper to Loki |
| 23 | cadvisor | monitoring | — | 8080 | `cadvisor.wazzan.us` | Container resource metrics |
| 24 | dozzle | monitoring | — | 8080 | `logs.wazzan.us` | Real-time Docker logs |
| 25 | portainer | management | 9443, 8000 | 9443, 8000 | `portainer.wazzan.us` | Docker management UI |
| 26 | dockge | management | 5001 | 5001 | `dockge.wazzan.us` | Docker Compose management |
| 27 | homepage | management | 3004 | 3000 | `home.wazzan.us` | Application dashboard |
| 28 | gitea | ci | 3001, 2222 | 3000, 22 | `gitea.wazzan.us` | Git service |
| 29 | n8n | ci | 5678 | 5678 | `n8n.wazzan.us` | Workflow automation |
| 30 | guacd | productivity | — | — | — | Guacamole proxy daemon |
| 31 | guacamole | productivity | — | 8080 | `rdp.wazzan.us` | Remote desktop gateway |

### Profile Activation

| Profile | Services | Description |
|---------|----------|-------------|
| *(none)* | postgres, redis | Core — always running |
| `ai` | 12 services | AI/ML stack (agents, LLMs, vector DB) |
| `network` | 2 services | Cloudflare tunnel |
| `security` | 3 services | Authentik SSO + Vaultwarden |
| `monitoring` | 7 services | Prometheus, Grafana, Loki, cAdvisor, Dozzle, Uptime Kuma |
| `ci` | 2 services | Gitea + n8n |
| `productivity` | 2 services | Guacamole remote desktop |
| `management` | 3 services | Portainer, Dockge, Homepage |

---

## Terraform Usage

Infrastructure is managed via the `kreuzwerker/docker` provider. All Docker networks, volumes, secrets, and services are defined as Terraform resources.

### Directory Structure

```
terraform/
├── providers.tf          # Provider + backend configuration
├── variables.tf          # Input variables
├── terraform.tfvars      # Environment-specific values
├── networks.tf           # 6 Docker networks
├── secrets.tf            # Secret file mappings (17 secrets)
├── volumes.tf            # Named volume definitions
├── outputs.tf            # Service endpoints + summary
├── modules/
│   └── service/          # Reusable service module
│       ├── main.tf
│       └── outputs.tf
└── services/             # Individual service definitions
```

### Commands

```bash
cd terraform

# Initialize (first time or after provider changes)
terraform init

# Preview changes
terraform plan

# Apply changes
terraform apply

# Apply with auto-approve (CI/CD pipelines)
terraform apply -auto-approve

# Destroy entire stack
terraform destroy

# Target a specific resource
terraform apply -target=docker_network.ai_ml
```

### Configuration (`terraform.tfvars`)

| Variable | Default | Description |
|----------|---------|-------------|
| `domain` | `wazzan.us` | Primary domain for TLS and routing |
| `timezone` | `America/Toronto` | Container timezone |
| `secrets_dir` | `../secrets` | Path to secret files |
| `postgres_user` | `alwazw` | PostgreSQL superuser |
| `postgres_db` | `aef3` | Default database name |
| `ssh_deploy_host` | `vm2` | Production VM hostname |
| `enable_profiles` | `[ai, security, ...]` | Active Compose profiles |

---

## Docker Compose Usage

Docker Compose is intended for quick testing and development. For production, use Terraform.

### Start Services

```bash
# Core only (postgres, redis — no profile)
docker compose up -d

# AI stack
docker compose --profile ai up -d

# Multiple profiles
docker compose --profile ai --profile monitoring up -d

# All profiles at once
docker compose --profile ai --profile security --profile monitoring \
  --profile management --profile ci --profile productivity --profile network up -d
```

### Stop & Cleanup

```bash
# Stop all services (all profiles)
docker compose --profile ai --profile security --profile monitoring \
  --profile management --profile ci --profile productivity --profile network down

# Stop and remove volumes
docker compose --profile ai down -v

# View logs
docker compose --profile ai logs -f agent-zero
docker compose logs -f --tail=100
```

### Service Health

All services include Docker health checks. View status:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

---

## Secret Management

AEF3 uses **17 bind-mounted secret files**. No Docker Swarm is required — secrets are mounted as files into `/run/secrets/<name>` inside containers. Services consume them via `_FILE` environment variables or entrypoint wrapper scripts.

### Security Boundary

| File | Contains |
|------|----------|
| `.env` | Non-sensitive configuration only (ports, usernames, paths) |
| `./secrets/*` | Passwords, tokens, keys, API credentials |

**Never** commit `.env` or any file in `./secrets/` to version control.

### Required Secret Files

| File | Used By | Description |
|------|---------|-------------|
| `cf_api_email.txt` | Traefik | Cloudflare account email |
| `cf_dns_api_token.txt` | Traefik | DNS API token (ACME challenge) |
| `cf_api_key.txt` | — | Cloudflare Global API key (backup) |
| `cf_tunnel_token.txt` | Cloudflared | Tunnel authentication token |
| `authentik_secret.txt` | Authentik | Bootstrap secret key |
| `hermes_password.txt` | Hermes | WebUI admin password |
| `guac_admin_pass.txt` | Guacamole | Admin password |
| `vw_admin_token.txt` | Vaultwarden | Admin access token |
| `gitea_secret.txt` | Gitea | `SECRET_KEY` |
| `litellm_key.txt` | LiteLLM, Agent-Zero | Master API key |
| `n8n_key.txt` | n8n | Encryption key |
| `open_web_ui.txt` | OpenWebUI, SearXNG | Shared secret key |
| `agent_zero_key.txt` | Agent-Zero | REST API key |
| `github_token.txt` | — | GitHub personal access token |
| `postgres_password.txt` | Postgres, Authentik, Gitea, n8n, Guacamole | Database superuser password |
| `redis_password.txt` | Redis, Authentik | Redis `requirepass` |
| `ssh_deploy_key` | Agent-Zero | SSH private key for deployments |

### Bootstrap

Run the bootstrap script to auto-generate missing secrets and create networks:

```bash
./scripts/bootstrap.sh
```

---

## MCP Integration

The **MCPO** (MCP-to-OpenAPI) bridge exposes Model Context Protocol servers as OpenAPI-compliant REST endpoints, enabling AI agents to interact with external tools via standard HTTP.

### Architecture

```
Agent-Zero ──HTTP──► MCPO (port 8000) ──► MCP Servers (filesystem, git)
                      │
                      └── OpenAPI docs: http://localhost:8000/docs
```

### Available MCP Servers

| Server | Tools | Mount |
|--------|-------|-------|
| Filesystem | ~10 tools | `/workspace` → `./projects` |
| Git | ~5 tools | `/workspace` → `./projects` |

**Total: 15 tools** available through the MCP bridge.

### Configuration

MCPO config lives at `compose/ai/mcpo/config.json`. Server implementations:
- `compose/ai/mcpo/filesystem_server.py`
- `compose/ai/mcpo/git_server.py`

---

## Monitoring & Observability

### Metrics Pipeline

```
cAdvisor ──► Prometheus ──► Grafana
Node/Host ──►   (scrape)   ──► (dashboards)
Services ──►               ──► (alerting)
```

### Log Pipeline

```
Promtail ──► Loki ──► Grafana (Explore)
(docker     (storage) (log queries)
 logs)
```

### Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | `http://localhost:3000` | Dashboards + visualization |
| Prometheus | `http://localhost:9090` | Metrics queries + alerting |
| Uptime Kuma | `http://localhost:3002` | Service uptime monitoring |
| Dozzle | `https://logs.wazzan.us` | Real-time container logs |
| cAdvisor | `https://cadvisor.wazzan.us` | Container resource metrics |

### Grafana Dashboards

Grafana is pre-configured with Prometheus as a data source. Dashboards cover:
- Container resource utilization (CPU, memory, network, disk I/O)
- Service health and availability
- AI/ML pipeline metrics (agent execution time, token usage)

---

## Development Workflow

### Environment Setup

1. **Clone and configure:**
   ```bash
   cp .env.example .env
   # Edit .env with your domain, ports, and usernames
   ```

2. **Create secrets:**
   ```bash
   ./scripts/bootstrap.sh
   # Or manually create files in ./secrets/
   ```

3. **Create networks (if using Docker Compose directly):**
   ```bash
   for net in proxy database ai-ml agent-communication security monitoring; do
     docker network create $net
   done
   ```

4. **Deploy:**
   ```bash
   cd terraform && terraform apply
   ```

### SSH Deployment Pipeline

Agent-Zero is configured to deploy code to a production VM via SSH:

- **Host:** `vm2` (configurable in `terraform.tfvars`)
- **User:** `alwazw` (configurable)
- **Key:** `secrets/ssh_deploy_key` (bind-mounted into container)

### Project Structure

```
/mnt/d/docker/
├── docker-compose.yml          # Root orchestration file
├── .env.example                # Non-sensitive configuration template
├── terraform/                  # Infrastructure as Code
│   ├── modules/service/        # Reusable service module
│   ├── services/               # Per-service Terraform
│   ├── networks.tf             # Network definitions
│   ├── secrets.tf              # Secret mappings
│   ├── volumes.tf              # Volume definitions
│   ├── outputs.tf              # Endpoint outputs
│   └── variables.tf            # Input variables
├── compose/                    # Per-service configuration
│   ├── ai/                     # AI/ML services
│   ├── data/                   # Database services
│   ├── network/                # Proxy + tunnel
│   ├── security/               # Auth + secrets
│   ├── monitoring/             # Observability stack
│   └── management/             # Admin tools
├── secrets/                    # Bind-mounted secret files
├── scripts/                    # Utility scripts
│   ├── bootstrap.sh            # Auto-generate secrets + networks
│   └── integration_test.py     # Integration test suite
├── agents/                     # Agent audit logs + memory
│   └── qwen/                   # Qwen agent state
├── projects/                   # Shared workspace (MCP filesystem)
└── templates/                  # Compose / config templates
```

### Adding a New Service

1. Add the service definition to `docker-compose.yml` under the appropriate profile.
2. Add the corresponding Terraform resource in `terraform/services/`.
3. If the service needs a new network, add it to `terraform/networks.tf` and reference it as `external: true` in Compose.
4. If the service needs secrets, add the file mapping to `terraform/secrets.tf` and the Compose `secrets` block.
5. Update the `outputs.tf` `service_endpoints` map if the service is externally accessible.

---

## Troubleshooting

### Common Issues

**Service won't start — missing secret**
```bash
ls -la secrets/
# Ensure all 17 files exist. Run ./scripts/bootstrap.sh to auto-generate.
```

**Network not found**
```bash
docker network ls | grep -E "proxy|database|ai-ml|agent-communication|security|monitoring"
# Create missing: docker network create <name>
```

**Traefik TLS not working**
```bash
# Verify Cloudflare DNS token
cat secrets/cf_dns_api_token.txt
# Check Traefik logs
docker compose --profile ai logs traefik --tail=50
```

**Agent-Zero can't reach LiteLLM**
```bash
# Verify both services are on ai-ml network
docker inspect agent-zero | grep -A5 Networks
docker inspect litellm | grep -A5 Networks
```

**Postgres connection refused**
```bash
# Check health status
docker inspect postgres --format='{{.State.Health.Status}}'
# View init logs
docker compose logs postgres
```

### Health Check Verification

```bash
# Check all service health statuses
docker ps --format '{{.Names}}: {{.Status}}' | grep -v healthy

# Manually verify a service endpoint
curl -s http://localhost:9090/-/healthy     # Prometheus
curl -s http://localhost:3000/api/health    # Grafana
curl -s http://localhost:4000/health        # LiteLLM
```

### Log Access

```bash
# Real-time logs via Dozzle: https://logs.wazzan.us
# Or via CLI:
docker compose logs -f --tail=100 <service-name>
```

### Port Conflicts

All ports bind to `127.0.0.1` except Traefik (80/443 on `0.0.0.0`) and Portainer edge agent (8000 on `0.0.0.0`). If a port is in use:

```bash
ss -tlnp | grep <port>
# Edit .env to change the host port mapping
```

---

## Contributing

### Guidelines

1. **No secrets in commits.** Verify `.gitignore` covers `secrets/`, `.env`, and `*.tfstate`.
2. **Test with Docker Compose first.** Run `docker compose --profile <name> up -d` before committing Terraform changes.
3. **Validate Terraform.** Run `terraform plan` and ensure no unintended changes.
4. **Document new services.** Update the service inventory table and architecture diagram.
5. **Health checks required.** Every service must include a Docker health check.

### Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production — deployed via Terraform |
| `develop` | Integration testing |
| `feature/*` | New services or features |

### PR Checklist

- [ ] `.env.example` updated with new configuration variables
- [ ] Terraform `plan` shows only intended changes
- [ ] Docker Compose health checks pass
- [ ] Service added to inventory table
- [ ] Network and secret mappings verified

---

## License

Private — All rights reserved. This project is not open-source.
