# AEF3 — Autonomous Engineer Framework v3

[![Services: 31](https://img.shields.io/badge/Services-31-blue)](docker-compose.yml)
[![Categories: 8](https://img.shields.io/badge/Categories-8-green)](compose/)
[![Secrets: 17](https://img.shields.io/badge/Secrets-17-orange)](secrets/)
[![IaC: Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)](terraform/)
[![License: Private](https://img.shields.io/badge/License-Private-red)](LICENSE)

A self-hosted, multi-agent AI engineering platform. AEF3 orchestrates **31 Docker services** across **8 functional categories** using a **modular Compose architecture** — each service owns its own `docker-compose.yml` under `compose/<category>/<service>/`, and the root file wires them together via `include:` directives.

**Domain:** `wazzan.us`

---

## Architecture

### Modular Include Structure

```
docker-compose.yml                          ← includes + secrets ONLY, zero service definitions
│
├── include:
│   ├── compose/network/traefik/            ← reverse proxy, TLS termination
│   ├── compose/network/cloudflared/        ← Cloudflare Tunnel
│   ├── compose/ai/agent-zero/              ← AI agent orchestrator
│   ├── compose/ai/litellm/                 ← LLM gateway
│   ├── compose/ai/ollama/                  ← local LLM inference
│   ├── compose/ai/...                      ← (10 AI services total)
│   ├── compose/data/postgres/              ← primary RDBMS
│   ├── compose/data/redis/                 ← cache + message broker
│   ├── compose/security/authentik-server/  ← SSO / identity
│   ├── compose/security/...                ← (3 security services total)
│   ├── compose/monitoring/prometheus/      ← metrics collection
│   ├── compose/monitoring/...              ← (7 monitoring services total)
│   ├── compose/management/portainer/       ← Docker management UI
│   ├── compose/management/...              ← (3 management services total)
│   ├── compose/ci/gitea/                   ← Git service
│   ├── compose/ci/n8n/                     ← workflow automation
│   ├── compose/productivity/guacd/         ← Guacamole proxy
│   └── compose/productivity/guacamole/     ← remote desktop gateway
│
└── secrets:                                ← 17 bind-mounted secret files
    ├── cf_dns_api_token → /run/secrets/cf_dns_api_token
    ├── postgres_password → /run/secrets/postgres_password
    └── ...
```

### Key Principle

**The root `docker-compose.yml` contains ZERO service definitions.** It only declares:
- `include:` — paths to per-service compose files
- `secrets:` — bind-mounted secret file mappings

Each service file is self-contained: it declares its own `services:`, `networks: (external: true)`, and `secrets: (external: true)`. This means any service can be started independently without the full stack.

---

## Quick Start

### Option A: Terraform (Production)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Option B: Docker Compose (Testing / Development)

```bash
# Start all 31 services
docker compose up -d

# Start a single service
docker compose -f compose/ai/agent-zero/docker-compose.yml up -d

# Start a category
docker compose -f compose/ai/litellm/docker-compose.yml \
               -f compose/ai/ollama/docker-compose.yml \
               -f compose/ai/qdrant/docker-compose.yml up -d
```

### Prerequisites

- Docker 24+ with Compose v2
- Terraform >= 1.5
- `.env` file (copy from `.env.example`)
- Secret files in `./secrets/` (run `./scripts/bootstrap.sh` to generate)

---

## Service Directory

Each service lives under `compose/<category>/<service>/docker-compose.yml` with its own networks, secrets, and volumes.

### Network (2 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| traefik | `compose/network/traefik/` | Reverse proxy, TLS termination, routing |
| cloudflared | `compose/network/cloudflared/` | Cloudflare Tunnel for external access |

### AI (10 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| agent-zero | `compose/ai/agent-zero/` | AI agent orchestrator |
| hermes | `compose/ai/hermes/` | Hermes AI WebUI |
| hermes-agent | `compose/ai/hermes-agent/` | Hermes AI gateway |
| litellm | `compose/ai/litellm/` | LLM proxy / router |
| mcpo | `compose/ai/mcpo/` | MCP-to-OpenAPI bridge |
| ollama | `compose/ai/ollama/` | Local LLM inference |
| omniroute | `compose/ai/omniroute/` | AI gateway (177+ providers) |
| openwebui | `compose/ai/openwebui/` | Chat UI for LLMs |
| qdrant | `compose/ai/qdrant/` | Vector database |
| searxng | `compose/ai/searxng/` | Privacy-respecting search |

### Data (2 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| postgres | `compose/data/postgres/` | Primary RDBMS (port 5432) |
| redis | `compose/data/redis/` | Cache + message broker (port 6379) |

### Security (3 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| authentik-server | `compose/security/authentik-server/` | SSO / identity provider |
| authentik-worker | `compose/security/authentik-worker/` | Authentik background worker |
| vaultwarden | `compose/security/vaultwarden/` | Password manager |

### Monitoring (7 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| prometheus | `compose/monitoring/prometheus/` | Metrics collection (port 9090) |
| grafana | `compose/monitoring/grafana/` | Dashboards + visualization |
| uptime-kuma | `compose/monitoring/uptime-kuma/` | Uptime monitoring (port 3002) |
| loki | `compose/monitoring/loki/` | Log aggregation (port 3100) |
| promtail | `compose/monitoring/promtail/` | Log shipper to Loki |
| cadvisor | `compose/monitoring/cadvisor/` | Container resource metrics |
| dozzle | `compose/monitoring/dozzle/` | Real-time Docker logs |

### Management (3 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| portainer | `compose/management/portainer/` | Docker management UI |
| dockge | `compose/management/dockge/` | Docker Compose management UI |
| homepage | `compose/management/homepage/` | Application dashboard |

### CI (2 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| gitea | `compose/ci/gitea/` | Self-hosted Git service |
| n8n | `compose/ci/n8n/` | Workflow automation |

### Productivity (2 services)

| Service | Compose Path | Purpose |
|---------|-------------|---------|
| guacd | `compose/productivity/guacd/` | Guacamole proxy daemon |
| guacamole | `compose/productivity/guacamole/` | Remote desktop gateway |

---

## Starting Services

### Full stack via root file

```bash
docker compose up -d
```

### Individual service

```bash
docker compose -f compose/ai/agent-zero/docker-compose.yml up -d
docker compose -f compose/monitoring/grafana/docker-compose.yml up -d
```

### Multiple services together

```bash
docker compose \
  -f compose/ai/litellm/docker-compose.yml \
  -f compose/ai/ollama/docker-compose.yml \
  -f compose/ai/qdrant/docker-compose.yml \
  up -d
```

### Stop and clean up

```bash
docker compose down                          # all included services
docker compose -f compose/ai/agent-zero/docker-compose.yml down   # single service
```

### View logs

```bash
docker compose logs -f agent-zero            # via root (if included)
docker compose -f compose/ai/agent-zero/docker-compose.yml logs -f   # standalone
```

---

## Terraform Usage

Infrastructure is managed via the `kreuzwerker/docker` provider. All Docker networks, volumes, secrets, and services are defined as Terraform resources.

### Directory Structure

```
terraform/
├── providers.tf              # Provider + backend configuration
├── variables.tf              # Input variables
├── terraform.tfvars          # Environment-specific values
├── networks.tf               # Docker networks
├── secrets.tf                # Secret file mappings
├── volumes.tf                # Named volume definitions
├── outputs.tf                # Service endpoints + summary
├── modules/
│   └── service/              # Reusable service module
│       ├── main.tf
│       └── outputs.tf
└── services/                 # Individual service definitions
```

### Commands

```bash
cd terraform

terraform init                # First time or after provider changes
terraform plan                # Preview changes
terraform apply               # Apply changes
terraform apply -auto-approve # CI/CD pipelines
terraform destroy             # Tear down entire stack
terraform apply -target=docker_network.ai_ml  # Target specific resource
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

---

## Secret Management

AEF3 uses **17 bind-mounted secret files**. No Docker Swarm is required — secrets are mounted as files into `/run/secrets/<name>` inside containers. Services consume them via `_FILE` environment variables or entrypoint wrapper scripts.

### Security Boundary

| File | Contains |
|------|----------|
| `.env` | Non-sensitive configuration (ports, usernames, paths) |
| `./secrets/*` | Passwords, tokens, keys, API credentials |

**Never** commit `.env` or any file in `./secrets/` to version control.

### Root docker-compose.yml declares secrets; services reference them as `external: true`

```yaml
# docker-compose.yml (root) — declares secret file source
secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt

# compose/data/postgres/docker-compose.yml — references it
services:
  postgres:
    secrets:
      - postgres_password
```

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
| Filesystem | ~10 tools | `/workspace` -> `./projects` |
| Git | ~5 tools | `/workspace` -> `./projects` |

**Total: 15 tools** available through the MCP bridge.

### Configuration

MCPO config lives at `compose/ai/mcpo/config.json`. Server implementations:
- `compose/ai/mcpo/filesystem_server.py`
- `compose/ai/mcpo/git_server.py`

---

## Monitoring

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

## Troubleshooting

### Service won't start — missing secret

```bash
ls -la secrets/
# Ensure all 17 files exist. Run ./scripts/bootstrap.sh to auto-generate.
```

### Network not found

```bash
docker network ls
# Create missing networks manually, or use Terraform to provision them.
```

### Traefik TLS not working

```bash
cat secrets/cf_dns_api_token.txt
docker compose -f compose/network/traefik/docker-compose.yml logs --tail=50
```

### Agent-Zero can't reach LiteLLM

```bash
# Verify both services are running and on the same network
docker inspect agent-zero | grep -A5 Networks
docker inspect litellm | grep -A5 Networks
```

### Postgres connection refused

```bash
docker inspect postgres --format='{{.State.Health.Status}}'
docker compose -f compose/data/postgres/docker-compose.yml logs
```

### Health Check Verification

```bash
docker ps --format '{{.Names}}: {{.Status}}' | grep -v healthy

curl -s http://localhost:9090/-/healthy      # Prometheus
curl -s http://localhost:3000/api/health     # Grafana
curl -s http://localhost:4000/health         # LiteLLM
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

1. **No secrets in commits.** `.gitignore` covers `secrets/`, `.env`, and `*.tfstate`.
2. **Each service gets its own compose file.** Add new services under `compose/<category>/<service>/docker-compose.yml`, never in the root file.
3. **Root file = includes only.** The root `docker-compose.yml` must only contain `include:` and `secrets:` — no service definitions.
4. **Self-contained service files.** Each compose file declares its own `networks: (external: true)` and `secrets: (external: true)`.
5. **Health checks required.** Every service must include a Docker health check.
6. **Terraform parity.** Adding a Docker Compose service also requires the corresponding Terraform resource.

### Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production — deployed via Terraform |
| `develop` | Integration testing |
| `feature/*` | New services or features |

### Adding a New Service

1. Create `compose/<category>/<service>/docker-compose.yml` with service, networks (external: true), and secrets (external: true).
2. Add the `include:` path to root `docker-compose.yml`.
3. Add the corresponding Terraform resource in `terraform/services/`.
4. If the service needs a new network, add it to `terraform/networks.tf`.
5. If the service needs secrets, add the file mapping to `terraform/secrets.tf`.
6. Update `outputs.tf` if the service is externally accessible.
7. Add the service to this README's service directory table.

---

## License

Private — All rights reserved. This project is not open-source.

---

## Quick Start Guide (Non-Technical)

### Deploy the Stack

```bash
# 1. Navigate to the project directory
cd ~/docker

# 2. Deploy (or update) the entire stack
docker stack deploy -c stack-merged.yml local-stack

# 3. Wait ~2 minutes for services to start
# Watch progress:
watch docker service ls
```

### Roll Back

```bash
# Remove the entire stack (stops all containers, keeps data)
docker stack rm local-stack

# Redeploy from the pre-swarm compose files (if needed)
env DOMAIN=wazzan.us docker compose --profile ai --profile ci --profile monitoring --profile network --profile management --profile security --profile productivity up -d
```

### Check Service Health

```bash
# List all services and their status (look for 1/1 in REPLICAS)
docker service ls

# Check a specific service's logs
docker service logs local-stack_postgres --tail 20

# Enter a running container for debugging
docker exec -it $(docker ps --filter name=local-stack_postgres -q) bash
```

### Where Things Live

| What | Where |
|------|-------|
| Compose files | `compose/<category>/<service>/docker-compose.yml` |
| Secrets | `~/docker/secrets/<name>.txt` (NEVER in .env) |
| Docker secrets | `docker secret ls` |
| Service data | Bind mounts in each service's compose file |
| Logs | `docker service logs local-stack_<service>` |
| Network configs | `docker network ls` (overlay networks) |

### Common Failure Recovery

| Problem | Fix |
|---------|-----|
| Service stuck in "Preparing" | `docker service update --force local-stack_<service>` |
| "bind source path does not exist" | Create the missing directory: `mkdir -p /path/to/dir` |
| Secret not found | `cat ~/docker/secrets/<name>.txt \| docker secret create docker_<name> -` |
| WSL2 networking broken | `sudo bash ~/docker/scripts/fix-docker-networking.sh` |
| Service crashed | Check logs: `docker service logs local-stack_<service> --tail 50` |

### Swarm Ingress Note

On WSL2, the Swarm routing mesh doesn't forward published ports to localhost. Services are accessible:
- **Internally**: via overlay DNS (e.g., `postgres:5432` from any container on the same network)
- **Externally**: via Cloudflare Tunnel (e.g., `https://grafana.wazzan.us`)
- **For debugging**: `docker exec <container> curl http://localhost:<port>`

**For baremetal Ubuntu deployment (no WSL2 limitations):** see [docs/baremetal-deployment.md](docs/baremetal-deployment.md)
