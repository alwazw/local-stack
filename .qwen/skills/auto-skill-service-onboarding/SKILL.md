---
name: service-onboarding
description: Procedure for onboarding new Docker Compose services — modular include pattern, profile gating, network wiring, Traefik routing, Homepage labels, secrets mounting, and integration testing
source: auto-skill
extracted_at: '2026-06-15T18:30:00.000Z'
---

# Docker Compose Service Onboarding

**Core principle:** Every service has its OWN compose file under `compose/<category>/<service>/docker-compose.yml`. The root `docker-compose.yml` contains ONLY `include:` directives and `secrets:` definitions — **NEVER** service definitions.

## Architecture: Modular Include Pattern

```
docker-compose.yml          ← ONLY include: + secrets: (NO services)
compose/
├── ai/agent-zero/docker-compose.yml
├── ai/litellm/docker-compose.yml
├── ci/gitea/docker-compose.yml
├── monitoring/loki/docker-compose.yml
├── network/traefik/docker-compose.yml
├── security/vaultwarden/docker-compose.yml
└── ... (one compose file per service)
```

**Root `docker-compose.yml` structure:**
```yaml
version: "3.8"
include:
  - compose/network/traefik/docker-compose.yml
  - compose/ai/agent-zero/docker-compose.yml
  # ... one per service (31 total)

secrets:
  postgres_password: { file: ./secrets/postgres_password.txt }
  # ... all 17 secret file mappings
```

## Service Directory Structure

Each service gets its own directory under `compose/<category>/<service>/`:

```
compose/
├── ai/qdrant/docker-compose.yml
├── ci/gitea/docker-compose.yml
├── monitoring/loki/
│   ├── docker-compose.yml
│   └── config.yaml
├── network/traefik/
│   ├── docker-compose.yml
│   └── entrypoint-wrapper.sh
└── productivity/guacamole/docker-compose.yml
```

## Profile System

Services are grouped by profile for controlled startup:

| Profile | Purpose | Default? |
|---------|---------|----------|
| `ai` | AI/ML core services | Yes |
| `security` | Authentik, Vaultwarden | No |
| `monitoring` | Prometheus, Grafana, Loki | No |
| `management` | Portainer, Dockge, Homepage | No |
| `ci` | Gitea, n8n, Woodpecker | No |
| `productivity` | Guacamole, Affine, Plane | No |
| `network` | Cloudflared | No |

**Start by profile:**
```bash
docker compose --profile ai --profile monitoring up -d
docker compose --profile '*' up -d    # All profiles
```

## Standard Service Template

```yaml
services:
  <service-name>:
    image: <image>:<tag>
    container_name: <service-name>
    restart: unless-stopped
    profiles: [<profile>]
    # ---- Secrets ----
    environment:
      SOME_SECRET_FILE: /run/secrets/<secret_name>     # _FILE suffix
      NON_SECRET_VAR: ${ENV_FROM_DOTENV}               # Non-sensitive from .env
    secrets:
      - <secret_name>
    # ---- Volumes ----
    volumes:
      - ./compose/<category>/<service>/config:/etc/config:ro  # Config files
      - <named_volume>:/data                                  # Persistent data
    # ---- Ports (localhost only for proxied services) ----
    ports:
      - "127.0.0.1:${PORT_<SERVICE>:-<default>}:<container_port>"
    # ---- Networks ----
    networks:
      - proxy           # If Traefik-routed
      - database        # If needs DB access
      - ai-ml           # If AI service
      - monitoring      # If monitoring service
    # ---- Dependencies ----
    depends_on:
      postgres:
        condition: service_healthy
    # ---- Health Check ----
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:<port>/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    # ---- Traefik Labels (for externally accessible services) ----
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.<name>.rule=Host(`<subdomain>.${DOMAIN}`)"
      - "traefik.http.routers.<name>.entrypoints=websecure"
      - "traefik.http.routers.<name>.tls.certresolver=cloudflare"
      - "traefik.http.services.<name>.loadbalancer.server.port=<container_port>"
      # ---- Homepage Labels ----
      - "homepage.group=<Category>"
      - "homepage.name=<Service Name>"
      - "homepage.icon=<icon>.png"
      - "homepage.href=https://<subdomain>.${DOMAIN}"
      - "homepage.description=<One-line description>"
```

## Secrets Mounting (Three Methods)

### Method 1: `_FILE` Env Var (preferred — native support)
```yaml
environment:
  POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
secrets:
  - postgres_password
```

### Method 2: Entrypoint Wrapper (services without native support)
```yaml
entrypoint: ["/entrypoint-wrapper.sh"]
volumes:
  - ./compose/<category>/<service>/entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro
secrets:
  - <secret_name>
```

See `docker-secrets` skill for the wrapper template.

### Method 3: Inline Shell (simple cases)
```yaml
command: ["sh", "-c", "app --password \"$$(cat /run/secrets/redis_password)\""]
```

## Named Volumes

Add to root `docker-compose.yml`:
```yaml
volumes:
  <service>_data:     # Persistent service data
  guacd_drive:        # Shared driver mount (Guacamole)
```

**Rule:** Use named volumes for data that should survive container recreation. Use bind-mounts for config files that live in the repo.

## Network Assignment

| Network | Services | Purpose |
|---------|----------|---------|
| `proxy` | All Traefik-routed services | External access |
| `database` | Services needing PostgreSQL/Redis | DB access |
| `ai-ml` | AI services + agents | ML communication |
| `agent-communication` | hermes-agent, agent-zero, **hermes** | Agent API calls + outbound internet |
| `monitoring` | Prometheus, Grafana, Loki | Metrics pipeline |
| `security` | Authentik, Vaultwarden | Security isolation |

**Note:** The `hermes` service needs `agent-communication` network in addition to `proxy` and `ai-ml` because the `ai-ml` network lacks proper MASQUERADE rules for outbound traffic (needed to reach pypi.org for dependency installation). See `docker-network-troubleshooting` skill.

**All networks are external** — created once and shared across compose stacks.

## Health Check Patterns

| Tool | Health Check Command | Notes |
|------|---------------------|-------|
| `wget` (alpine) | `["CMD", "wget", "--spider", "-q", "http://localhost:<port>/health"]` | Not available in all images |
| `curl` | `["CMD", "curl", "-f", "http://localhost:<port>/health"]` | Not available in all images |
| TCP check | `["CMD", "bash", "-c", "echo > /dev/tcp/localhost/<port>"]` | Requires bash |
| `nc` | `["CMD-SHELL", "nc -z localhost <port> || exit 1"]` | More widely available |
| Python | `["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:<port>/')"]` | Requires python3 |

**Important:** Always verify the tool exists in the container before using it. Many official images are scratch-based with no shell at all.

**⚠ Scratch-based images have NO healthcheck capability:** These images (e.g., `grafana/loki:latest`, `cloudflare/cloudflared:latest`) are built FROM scratch — they have no `/bin/sh`, no `nc`, no `wget`, no `curl`, no `ls`. Any healthcheck will fail with `executable file not found in $PATH`. **Solution:** Remove the healthcheck entirely and verify health externally:

```yaml
loki:
  image: grafana/loki:latest
  # NO healthcheck — scratch image has no binaries
  # Health verified from host: curl http://localhost:3100/ready
```

**Start period:** 15s for simple services, 30s for DB-dependent, 60s for AI/ML

## Integration Test

Run `scripts/integration_test.py` to validate all services:
```bash
python3 scripts/integration_test.py
```

Checks:
- Container running status
- Network membership matches expected configuration
- Docker secrets mounted correctly
- Traefik labels present for external services
- Homepage labels present for dashboard discovery
- Inter-service connectivity (hermes→agent-zero, litellm→ollama)

## Onboarding Checklist

For each new service:

1. [ ] Create `compose/<category>/<service>/docker-compose.yml`
2. [ ] Create service config files if needed (`config.yaml`, `settings.yml`, etc.)
3. [ ] Add service definition to root `docker-compose.yml` (single source of truth)
4. [ ] Assign correct `profiles: [...]`
5. [ ] Assign correct `networks: [...]`
6. [ ] Mount secrets (choose `_FILE`, wrapper, or inline method)
7. [ ] Add `ports:` with `127.0.0.1:` prefix (never `0.0.0.0:` for proxied services)
8. [ ] Add `healthcheck:` with appropriate start_period
9. [ ] Add Traefik labels (if externally accessible)
10. [ ] Add Homepage labels (all services)
11. [ ] Add named volume to root `volumes:` section
12. [ ] Add to `scripts/integration_test.py` `SERVICES` dict
13. [ ] **Create databases** — if the service uses PostgreSQL, create the database:
    ```bash
    docker exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "CREATE DATABASE <db_name>;"
    ```
    **Required databases by service:**
    | Database | Service |
    |----------|---------|
    | `n8n` | n8n |
    | `gitea` | Gitea |
    | `authentik` | Authentik (auto-created by init) |
    | `guacamole` | Guacamole |
    | `affine` | Affine |
    | `plane` | Plane |
    | `woodpecker` | Woodpecker CI |
14. [ ] Run `docker compose config --quiet` to validate
15. [ ] Run `python3 scripts/integration_test.py` to verify

## Common Gotchas

### Port Conflicts
- Always use `127.0.0.1:` prefix — never bind to `0.0.0.0:` unless the service is the proxy (Traefik)
- Use `${PORT_<NAME>:-<default>}` for configurable ports

### Secret File Paths
- **Host path:** `./secrets/<name>.txt` (relative to compose file)
- **Container path:** `/run/secrets/<name>` (Docker manages this)
- Never mix them up

### Entrypoint Wrapper + Command
- `entrypoint:` replaces the container's default entrypoint
- `command:` is passed as arguments to the entrypoint
- Wrapper must `exec "$@"` to run the original command
- For Traefik: wrapper must prepend `traefik` if args start with `-`

### Profile Inheritance
- Services without `profiles:` are always started (default profile)
- `docker compose up -d` starts only default-profile services
- `docker compose --profile '*' up -d` starts everything

### Network Recreation
- If inter-container connectivity breaks on a Docker bridge network (common on WSL2), create a new network and connect both containers to it:
  ```bash
  docker network create agent-communication
  docker network connect agent-communication hermes-agent
  docker network connect agent-communication agent-zero
  ```
- Update `docker-compose.yml` to include the new network persistently

### Docker Bridge Network Connectivity (WSL2)
If containers on the same Docker bridge network can't reach each other (DNS resolves, TCP times out), it's likely a missing iptables FORWARD rule. **Diagnose:**

```bash
# Test connectivity between containers
docker exec <source> python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('<target>', <port>)); print('OK')"

# Check bridge interface
docker network inspect <network> --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'

# Check iptables FORWARD chain
sudo iptables -L DOCKER-FORWARD -n -v
```

**Fix:** Add iptables rules for the affected bridge interface:
```bash
# Find the bridge interface name
ip link show | grep br-

# Add ACCEPT rules for the bridge (replace br-XXXX with actual interface)
sudo iptables -I DOCKER-FORWARD 3 -i br-XXXX -j ACCEPT
sudo iptables -I DOCKER-BRIDGE 2 -i br-XXXX -j DOCKER
```

This was needed for both the `ai-ml` (br-1813ea894891) and `database` (br-a661348a0ada) networks.
