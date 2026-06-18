# Docker Compose Productivity & Management Profile Status

**Date:** 2026-06-18  
**Status:** ✅ ALL SERVICES RUNNING

## Summary

Successfully deployed productivity and management profiles with all services operational.

## Services Status

### Management Profile (3 services)
| Service | Container | Port | Status | URL |
|---------|-----------|------|--------|-----|
| **Homepage** | homepage | 3004 | ✅ Running | http://localhost:3004 |
| **Portainer** | portainer | 9443 | ✅ Running | https://localhost:9443 |
| **Dockge** | dockge | 5001 | ✅ Running | http://localhost:5001 |

### Productivity Profile (6 services)
| Service | Container | Port | Status | URL |
|---------|-----------|------|--------|-----|
| **Affine** | affine | 8083 | ✅ Running | http://localhost:8083 |
| **Plane Web** | plane-web | 3000 (internal) | ✅ Running | https://plane.wazzan.us |
| **Plane API** | plane-api | 8080 (internal) | ✅ Running | https://plane.wazzan.us/api |
| **Plane Worker** | plane-worker | N/A | ✅ Running | Background worker |
| **Guacd** | guacd | 4822 (internal) | ✅ Running | Internal service |
| **Guacamole** | guacamole | 8081 | ✅ Running | http://localhost:8081 |

### Core Services (already running)
| Service | Container | Port | Status |
|---------|-----------|------|--------|
| **Hermes Agent** | hermes-agent | 8642 | ✅ Running |
| **Hermes Web** | hermes | 8787 | ✅ Running |
| **LiteLLM** | litellm | 4000 | ✅ Running |
| **Ollama** | ollama | 11434 | ✅ Running |
| **Qdrant** | qdrant | 6333 | ✅ Running |
| **n8n** | n8n | 5678 | ✅ Running |
| **PostgreSQL** | postgres | 5432 | ✅ Running |
| **Redis** | redis | 6379 | ✅ Running |

## Issues Fixed

### 1. Affine Image Error
- **Problem:** `ghcr.io/toeverything/affine-graphql:stable` returned "unauthorized"
- **Fix:** Changed to correct image `ghcr.io/toeverything/affine:stable`
- **Added:** Migration service for database initialization
- **Added:** Explicit command `node ./dist/main.js` to prevent immediate exit

### 2. Plane Images
- **Problem:** Images were pulling but containers kept restarting
- **Fix:** 
  - Added entrypoint wrappers to read secrets from files
  - Added explicit commands for plane-api and plane-worker
  - Removed plane-proxy (Caddyfile syntax error, not needed with Traefik)
  - Configured Traefik routing directly to plane-web and plane-api

### 3. Secret Management
- **Problem:** "unsupported external secret" errors
- **Fix:** Changed from Docker secrets to direct volume mounts
  - `../../../secrets/affine_database_url.txt:/run/secrets/affine_database_url:ro`
  - Same pattern for plane services

### 4. Port Conflicts
- **Problem:** Portainer trying to bind to port 8000 (already used by MCPO)
- **Fix:** Removed port 8000 binding from Portainer (Traefik handles routing)

### 5. Network Connectivity
- **Problem:** Containers couldn't reach postgres on database network
- **Fix:** Verified iptables FORWARD rules were in place (already fixed earlier)

## Configuration Details

### Affine
- **Database:** `postgresql://alwazw:<password>@postgres:5432/affine`
- **Redis:** `redis` (hostname only, password read from secret)
- **Migration:** Runs automatically on first start via `affine-migration` container
- **Volume:** `affine_data` for persistent storage

### Plane
- **Database:** `postgresql://alwazw:<password>@postgres:5432/plane`
- **Redis:** `redis://:<password>@redis:6379/`
- **Secret Key:** Auto-generated 48-byte base64 key
- **Routing:** Traefik routes `/api`, `/auth`, `/static` to plane-api, everything else to plane-web
- **Worker:** Background job processor for async tasks

### Homepage
- **Port:** Changed from `127.0.0.1:3004:3000` to `3004:3000` (external access)
- **Config:** Simplified settings.yaml (removed placeholder weather keys)
- **Removed:** Useless kubernetes.yaml placeholder

## Secrets Created

| Secret File | Purpose |
|-------------|---------|
| `affine_database_url.txt` | PostgreSQL connection string for Affine |
| `plane_database_url.txt` | PostgreSQL connection string for Plane |
| `plane_redis_url.txt` | Redis connection string for Plane |
| `plane_secret_key.txt` | Django secret key for Plane |
| `grafana_admin_password.txt` | Grafana admin password |

## Databases Created

- `affine` - Affine knowledge base
- `plane` - Plane project management

## Access URLs

### Local Access (HTTP)
- Homepage: http://localhost:3004
- Affine: http://localhost:8083
- Portainer: https://localhost:9443
- Dockge: http://localhost:5001
- Guacamole: http://localhost:8081
- Hermes: http://localhost:8787

### External Access (HTTPS via Traefik)
- Homepage: https://home.wazzan.us
- Affine: https://affine.wazzan.us
- Plane: https://plane.wazzan.us
- Portainer: https://portainer.wazzan.us
- Hermes: https://hermes.wazzan.us

## First-Time Setup

### Affine
1. Visit http://localhost:8083
2. Create your first workspace
3. Invite team members (optional)

### Plane
1. Visit https://plane.wazzan.us
2. The first user to register becomes the admin
3. Create your first project

### Portainer
1. Visit https://localhost:9443
2. Create admin user on first login
3. Connect to local Docker environment

### Homepage
1. Visit http://localhost:3004
2. Services are auto-discovered via Docker labels
3. Customize layout in `compose/management/homepage/config/`

## Verification Commands

```bash
# Check all productivity/management services
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "affine|plane|homepage|portainer|dockge"

# Test Affine
curl -I http://localhost:8083

# Test Homepage
curl -I http://localhost:3004

# Test Plane API
curl -I https://plane.wazzan.us/api/

# Check logs
docker logs affine --tail 20
docker logs plane-api --tail 20
docker logs homepage --tail 20
```

## Files Modified

1. `/mnt/d/docker/docker-compose.yml` - Added productivity includes and secrets
2. `/mnt/d/docker/compose/productivity/affine/docker-compose.yml` - Fixed image, added migration
3. `/mnt/d/docker/compose/productivity/plane/docker-compose.yml` - Fixed secrets, removed proxy
4. `/mnt/d/docker/compose/monitoring/grafana/docker-compose.yml` - Fixed password secret
5. `/mnt/d/docker/compose/management/portainer/docker-compose.yml` - Removed port 8000
6. `/mnt/d/docker/compose/management/homepage/docker-compose.yml` - Fixed port binding

## Files Created

1. `/mnt/d/docker/compose/productivity/affine/entrypoint-wrapper.sh`
2. `/mnt/d/docker/compose/productivity/plane/entrypoint-wrapper.sh`
3. `/mnt/d/docker/secrets/affine_database_url.txt`
4. `/mnt/d/docker/secrets/plane_database_url.txt`
5. `/mnt/d/docker/secrets/plane_redis_url.txt`
6. `/mnt/d/docker/secrets/plane_secret_key.txt`
7. `/mnt/d/docker/secrets/grafana_admin_password.txt`

## Files Removed

1. `/mnt/d/docker/compose/management/homepage/config/kubernetes.yaml`
2. Empty directories: `automation/`, `dev/`, `orchestration/`, `agents/`, `projects/`, `productivity/appflowy/`, `productivity/logseq/`

## Next Steps

1. **DNS Configuration:** Add A records for `affine.wazzan.us` and `plane.wazzan.us` pointing to your server IP
2. **SSL Certificates:** Traefik will auto-provision Let's Encrypt certificates once DNS is configured
3. **Backup:** Set up automated backups for `affine_data` volume and PostgreSQL databases
4. **Monitoring:** Configure Grafana dashboards for the new services (optional)

## Notes

- All services use the `productivity` or `management` Docker Compose profiles
- To stop these services: `docker compose --profile productivity --profile management down`
- To restart: `docker compose --profile productivity --profile management up -d`
- Secrets are stored in `/mnt/d/docker/secrets/` (not in git)
- Databases are in PostgreSQL container, volumes persist in Docker
