# Docker Compose Stack Audit - 2026-06-18

## Summary
Cleaned up 7 empty/duplicate directories and integrated productivity services into the stack.

## Issues Fixed

### 1. Empty/Duplicate Directories Removed
The following directories contained no docker-compose.yml files and were removed:
- `compose/automation/` - Empty (n8n was moved to `ci/`)
- `compose/dev/` - Empty (gitea and woodpecker were moved to `ci/`)
- `compose/orchestration/` - Empty (dockge and homepage were moved to `management/`)
- `compose/agents/` - Empty (agent configurations are in root `agents/` directory)
- `compose/projects/` - Empty (project files are in root `projects/` directory)

**Impact:** Reduced directory clutter and eliminated confusion about where services are defined.

### 2. Productivity Services Integration
Added two productivity services that had compose files but weren't included in the stack:

#### Affine (Notion Alternative)
- **File:** `compose/productivity/affine/docker-compose.yml`
- **Profile:** `productivity` (opt-in)
- **Port:** 8083 (internal 3010)
- **URL:** https://affine.${DOMAIN}
- **Dependencies:** postgres, redis
- **Fixed:** Added missing `affine_data` volume declaration
- **Networks:** proxy, database

#### Plane (Jira Alternative)
- **File:** `compose/productivity/plane/docker-compose.yml`
- **Profile:** `productivity` (opt-in)
- **Port:** 8085 (internal 80)
- **URL:** https://plane.${DOMAIN}
- **Components:** plane-web, plane-api, plane-worker, plane-proxy
- **Dependencies:** postgres, redis
- **Networks:** proxy, database, ai-ml

### 3. Homepage Configuration Cleanup
- **Removed:** `compose/management/homepage/config/kubernetes.yaml` (placeholder file)
- **Fixed:** Port mapping from `127.0.0.1:3004:3000` to `3004:3000` (allow external Traefik routing)
- **Status:** Service is included but requires `management` profile to activate

### 4. Empty Productivity Directories Removed
- `compose/productivity/appflowy/` - Empty
- `compose/productivity/logseq/` - Empty

## Current Directory Structure

```
compose/
├── ai/                    # AI/ML services
│   ├── agent-zero/
│   ├── hermes/
│   ├── hermes-agent/
│   ├── litellm/
│   ├── mcpo/
│   ├── ollama/
│   ├── omniroute/
│   ├── open-terminal/
│   ├── openwebui/
│   ├── qdrant/
│   └── searxng/
├── ci/                    # CI/CD services
│   ├── gitea/
│   ├── n8n/
│   └── woodpecker/
├── data/                  # Database services
│   ├── postgres/
│   └── redis/
├── management/            # Management tools
│   ├── dockge/
│   ├── homepage/
│   └── portainer/
├── monitoring/            # Observability stack
│   ├── cadvisor/
│   ├── dozzle/
│   ├── grafana/
│   ├── loki/
│   ├── prometheus/
│   ├── promtail/
│   └── uptime-kuma/
├── network/               # Networking infrastructure
│   ├── cloudflared/
│   └── traefik/
├── productivity/          # Productivity tools
│   ├── affine/           # ← NEW: Added to stack
│   ├── guacamole/
│   ├── guacd/
│   └── plane/            # ← NEW: Added to stack
└── security/              # Authentication & secrets
    ├── authentik-server/
    ├── authentik-worker/
    └── vaultwarden/
```

## Service Profiles

Services are organized into Docker Compose profiles for flexible deployment:

| Profile | Services | Default |
|---------|----------|---------|
| (none) | Core infrastructure, AI, monitoring, security | ✅ Enabled |
| `productivity` | affine, plane, guacamole, guacd | ⭕ Opt-in |
| `management` | homepage, portainer, dockge | ⭕ Opt-in |

### Activating Profiles

To enable optional profiles:

```bash
# Enable productivity services
docker compose --profile productivity up -d

# Enable management dashboard
docker compose --profile management up -d

# Enable both
docker compose --profile productivity --profile management up -d
```

## Service Summary

### Core Services (Always Enabled)
- **AI Stack:** litellm, agent-zero, hermes, hermes-agent, ollama, qdrant, openwebui, searxng, mcpo
- **Infrastructure:** traefik, cloudflared, postgres, redis
- **Security:** authentik-server, authentik-worker, vaultwarden
- **Monitoring:** prometheus, grafana, loki, promtail, uptime-kuma, cadvisor, dozzle
- **CI/CD:** gitea, n8n, woodpecker

### Productivity Services (Profile: `productivity`)
- **guacamole/guacd:** Remote desktop gateway
- **affine:** Collaborative knowledge base (Notion alternative)
- **plane:** Project management (Jira alternative)

### Management Services (Profile: `management`)
- **homepage:** Application dashboard
- **portainer:** Docker management UI
- **dockge:** Docker Compose manager

## Configuration Notes

### Environment Variables
The following variables are referenced in compose files but should be set in `.env`:
- `POSTGRES_PASSWORD` - PostgreSQL password (also available as secret)
- `REDIS_PASSWORD` - Redis password (also available as secret)
- `POSTGRES_USER` - PostgreSQL username (default: `alwazw`)

**Note:** Passwords are available as Docker secrets at `/run/secrets/postgres_password` and `/run/secrets/redis_password`. Services should prefer reading from secrets files rather than environment variables.

### Port Mappings
- Homepage: 3004 (external), 3000 (internal container)
- Affine: 8083 (external), 3010 (internal container)
- Plane: 8085 (external), 80 (internal container)
- Guacamole: 8080 (external), 8080 (internal container)

### Networks
- **proxy:** Traefik reverse proxy network (external access)
- **database:** Internal database communication
- **ai-ml:** AI/ML service communication

## Verification

To verify the cleanup and new services:

```bash
# Check all services (including profiles)
docker compose --profile productivity --profile management config --services | wc -l
# Expected: 14 services

# Check only default services
docker compose config --services | wc -l
# Expected: 11 services

# Verify no orphaned directories
find compose/ -type d -empty
# Expected: No output

# Check for missing volumes
docker compose --profile productivity config 2>&1 | grep "refers to undefined"
# Expected: No output
```

## Next Steps

1. **Activate profiles as needed:**
   ```bash
   docker compose --profile productivity up -d
   ```

2. **Create application databases:**
   - Affine needs database `affine` in PostgreSQL
   - Plane needs database `plane` in PostgreSQL

3. **Configure authentication:**
   - Plane requires initial setup via web UI at first launch
   - Affine may require admin account creation

4. **Set up Traefik routing:**
   - Ensure DNS records exist for `affine.${DOMAIN}` and `plane.${DOMAIN}`
   - Verify Cloudflare SSL certificates are provisioned

## Files Modified

1. `/mnt/d/docker/docker-compose.yml` - Added affine and plane includes
2. `/mnt/d/docker/compose/management/homepage/docker-compose.yml` - Fixed port mapping
3. `/mnt/d/docker/compose/productivity/affine/docker-compose.yml` - Added volume declaration

## Files Removed

1. `/mnt/d/docker/compose/management/homepage/config/kubernetes.yaml` - Placeholder file
2. Empty directories: automation, dev, orchestration, agents, projects, productivity/appflowy, productivity/logseq
