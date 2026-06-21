# Bootstrap Script Analysis & Customization Report

**Date:** 2026-06-18  
**Script:** `/mnt/d/docker/scripts/new_bootstrap.sh`

## Summary

Successfully analyzed your local Docker/Terraform stack and customized the bootstrap script to handle all bind mounts, special permissions, and infrastructure requirements.

---

## 1. Gitignore Directory Analysis

### Extracted from `.gitignore`

**Pattern: `data/`**
- Root-level data directory

**Pattern: `compose/*/data/`** (wildcard matching all subdirectories)
- `compose/network/traefik/data/`
- `compose/data/postgres/data/`
- `compose/security/vaultwarden/data/`

**Explicit directories:**
- `compose/ai/ollama/models/`
- `compose/ai/agent-zero/data/`
- `compose/ai/agent-zero/work_dir/`
- `compose/ai/openwebui/data/`
- `compose/security/vaultwarden/data/`
- `compose/network/traefik/data/`

**Total: 7 gitignored directory patterns**

---

## 2. Docker Compose Bind Mount Analysis

Scanned **34 docker-compose.yml** files for bind mounts (not named volumes).

### Critical Bind Mounts Found:

| Service | Host Path | Container Path | Purpose |
|---------|-----------|----------------|---------|
| **Traefik** | `./data` | `/data` | SSL certificates (acme.json) |
| **PostgreSQL** | `./data` | `/var/lib/postgresql/data` | Database files |
| **PostgreSQL** | `./init` | `/docker-entrypoint-initdb.d:ro` | Init scripts |
| **Ollama** | `./models` | `/root/.ollama` | LLM models |
| **Vaultwarden** | `./data` | `/data` | Password vault |
| **Agent Zero** | `./data` | `/app/data` | Agent memory |
| **Agent Zero** | `./work_dir` | `/app/work_dir` | Working directory |
| **Agent Zero** | `../../../projects` | `/app/projects` | Project files |
| **Agent Zero** | `../../../agents/qwen` | `/app/audit` | Audit logs |
| **Hermes Agent** | `/mnt/d/docker` | `/mnt/d/docker` | Host access |
| **Hermes Agent** | `/:/host` | `/host` | Root host access |
| **Hermes Agent** | `~/.ssh/id_ed25519` | `/home/hermes/.ssh/id_ed25519:ro` | SSH key |
| **Hermes Agent** | `~/.ssh/known_hosts` | `/home/hermes/.ssh/known_hosts:ro` | SSH hosts |
| **Authentik** | `./custom-templates` | `/templates` | Custom templates |

### Named Volumes (Managed by Docker, not pre-scaffolded):
- `hermes_home`, `hermes_agent_src`, `hermes_workspace`
- `authentik_media`, `grafana_data`, `uptime_kuma_data`
- `qdrant_data`, `guacd_drive`, `guacd_record`
- `gitea_data`, `n8n_data`, `loki_data`
- `portainer_data`, `dockge_data`, `cloudflared_bin`
- `omniroute_data`, `woodpecker_data`

---

## 3. Comprehensive Directory List (Deduplicated)

**Final array for bootstrap script:**

```bash
DIRECTORIES=(
    # Core data directories (from .gitignore: data/ and compose/*/data/)
    "data"                                    # Root data directory
    
    # Traefik (compose/network/traefik/data)
    "compose/network/traefik/data"
    
    # PostgreSQL (compose/data/postgres/data)
    "compose/data/postgres/data"
    "compose/data/postgres/init"              # Init scripts (tracked but ensure exists)
    
    # Ollama models (compose/ai/ollama/models)
    "compose/ai/ollama/models"
    
    # Agent Zero (compose/ai/agent-zero/data and work_dir)
    "compose/ai/agent-zero/data"
    "compose/ai/agent-zero/work_dir"
    
    # OpenWebUI (compose/ai/openwebui/data)
    "compose/ai/openwebui/data"
    
    # Vaultwarden (compose/security/vaultwarden/data)
    "compose/security/vaultwarden/data"
    
    # Agent Zero external mounts (from compose file: ../../../projects and ../../../agents/qwen)
    "projects"
    "agents/qwen"
    
    # Authentik custom templates (from compose file: ./custom-templates)
    "compose/security/authentik-server/custom-templates"
)
```

**Total: 11 directories to pre-scaffold**

---

## 4. Terraform Infrastructure Analysis

### Networks (6 total):
- `ai-ml` — AI services communication
- `agent-communication` — Agent bridge (WSL2 networking fix)
- `proxy` — Traefik + external services
- `database` — Database isolation
- `security` — Security services
- `monitoring` — Observability stack

### Volumes (17 total):
All managed by Terraform as Docker named volumes with `aef3` labels.

### Secrets (17 total):
All bind-mounted from `../secrets/` directory:
- `cf_api_email`, `cf_dns_api_token`, `cf_api_key`, `cf_tunnel_token`
- `authentik_secret`, `hermes_password`, `github_token`, `agent_zero_key`
- `gitea_secret`, `guac_admin_pass`, `litellm_key`, `n8n_key`
- `webui_secret_key`, `vw_admin_token`, `postgres_password`, `redis_password`
- `ssh_deploy_key`

### Variables:
- `domain` = `wazzan.us`
- `timezone` = `America/Toronto`
- `postgres_user` = `alwazw`
- `postgres_db` = `aef3`
- `enable_profiles` = `["ai", "security", "monitoring", "management", "ci", "productivity", "network"]`

---

## 5. Special Permissions & Customizations

### Traefik acme.json (Critical!)
```bash
TRAEFIK_ACME="$PROJECT_ROOT/compose/network/traefik/data/acme.json"
if [ -f "$TRAEFIK_ACME" ]; then
    chmod 600 "$TRAEFIK_ACME"
else
    touch "$TRAEFIK_ACME"
    chmod 600 "$TRAEFIK_ACME"
fi
```
**Why:** Traefik will refuse to start if acme.json permissions are not 600.

### PostgreSQL Data Directory
```bash
POSTGRES_DATA="$PROJECT_ROOT/compose/data/postgres/data"
if [ -d "$POSTGRES_DATA" ] && [ -z "$(ls -A "$POSTGRES_DATA")" ]; then
    chown 999:999 "$POSTGRES_DATA"
fi
```
**Why:** PostgreSQL runs as UID 999. Only set on fresh installs to preserve existing data.

### SSH Keys for Hermes Agent
```bash
SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_KNOWN="$HOME/.ssh/known_hosts"
chmod 600 "$SSH_KEY" 2>/dev/null
chmod 644 "$SSH_KNOWN" 2>/dev/null
```
**Why:** SSH requires strict permissions (600 for private, 644 for known_hosts).

### General Ownership
```bash
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/compose"
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/projects"
chown -R $(id -u):$(id -g) "$PROJECT_ROOT/agents"
```
**Why:** Prevents Docker from creating directories as root, which causes permission denied errors.

---

## 6. Enhanced Bootstrap Phases

### Phase 1: Environment Validation
- Checks for `docker`, `docker compose`, and `terraform`
- Validates secrets share path

### Phase 2: Secret Hydration
- Syncs `.env` from network share
- Syncs `secrets/` directory
- Secures all files with 600 permissions

### Phase 3: Directory Scaffolding
- Creates all 11 directories with `mkdir -p`
- Sets ownership to current user
- **NEW: Phase 3b** — Special permissions for Traefik, PostgreSQL, SSH

### Phase 4: Terraform Infrastructure
- Initializes Terraform with `-upgrade`
- Detects existing state (update vs. create)
- Plans and applies with auto-approve
- Creates networks, volumes, and infrastructure

### Phase 5: Profile Detection
- Reads `COMPOSE_PROFILES` from `.env` or uses defaults
- Builds docker compose command with all profiles
- Displays the command for transparency

### Phase 6: Docker Stack Deployment
- Pulls images first (with fallback)
- Starts services with `--wait` and 120s timeout
- Removes orphaned containers

### Post-Bootstrap: Health Checks
- Waits 5 seconds for stabilization
- Checks critical services: postgres, redis, traefik, litellm, hermes-agent
- Reports health status for each
- Provides next steps

---

## 7. Key Improvements Over Template

1. **Comprehensive directory list** — 11 vs. 7 directories (added postgres/init, projects, agents/qwen, authentik/custom-templates)

2. **Special permissions phase** — Handles Traefik acme.json, PostgreSQL ownership, SSH keys

3. **Profile detection** — Automatically reads COMPOSE_PROFILES from .env

4. **Health checks** — Post-bootstrap validation of critical services

5. **Better error handling** — `set -euo pipefail` instead of just `set -e`

6. **Idempotent operations** — Checks if directories exist before creating, preserves existing data

7. **Terraform state awareness** — Detects existing infrastructure vs. fresh install

8. **Image pull optimization** — Pulls images before starting, with fallback to local builds

9. **Colored output** — Green (success), Yellow (warnings), Red (errors), Blue (info)

10. **Next steps guidance** — Tells user what to do after bootstrap completes

---

## 8. Usage Instructions

```bash
# Make executable (already done)
chmod +x /mnt/d/docker/scripts/new_bootstrap.sh

# Run the bootstrap
cd /mnt/d/docker
./scripts/new_bootstrap.sh
```

### Expected Output:
```
Starting Smart Bootstrap for local-stack...
Project root: /mnt/d/docker

[1/6] Validating Environment...

[2/6] Hydrating Secrets from Network Share...
  ✓ Synced .env
  ✓ Synced secrets/
  ✓ Secrets secured with 600 permissions

[3/6] Scaffolding Ignored State Directories...
  ✓ Created: compose/network/traefik/data
  ✓ Created: compose/data/postgres/data
  ...

[3b/6] Setting Special Permissions...
  ✓ Created empty Traefik acme.json (600)
  ✓ PostgreSQL data directory owned by postgres (999:999)
  ✓ SSH private key secured (600)

[4/6] Applying Terraform Infrastructure...
  ✓ Existing Terraform state found, will update
  ✓ Terraform infrastructure ready

[5/6] Detecting Docker Compose Profiles...
  ✓ Profiles from .env: ai security monitoring management ci productivity network
  ✓ Compose command: docker compose --profile ai --profile security ...

[6/6] Launching Docker Orchestration...
  Pulling latest images...
  Starting services...

=============================================
Bootstrap Complete! Stack is initializing.
=============================================

Running health checks...
  ✓ postgres: healthy
  ✓ redis: healthy
  ✓ traefik: healthy
  ✓ litellm: healthy
  ✓ hermes-agent: healthy

✓ All critical services are healthy!

Next steps:
  1. Check logs: docker compose logs -f
  2. View status: docker compose ps
  3. Access services via Traefik dashboard: https://traefik.wazzan.us
```

---

## 9. Troubleshooting

### If Traefik fails to start:
```bash
# Check acme.json permissions
ls -la compose/network/traefik/data/acme.json
# Should show: -rw------- (600)

# Fix if needed
chmod 600 compose/network/traefik/data/acme.json
```

### If PostgreSQL fails with permission denied:
```bash
# Check ownership
ls -ld compose/data/postgres/data
# Should show: drwxr-xr-x 999 999 ...

# Fix if needed
sudo chown 999:999 compose/data/postgres/data
```

### If SSH keys fail in hermes-agent:
```bash
# Check SSH key permissions
ls -la ~/.ssh/id_ed25519
# Should show: -rw------- (600)

# Fix if needed
chmod 600 ~/.ssh/id_ed25519
```

### If services fail health checks:
```bash
# Check individual service logs
docker compose logs traefik
docker compose logs postgres
docker compose logs hermes-agent

# Restart specific service
docker compose restart traefik

# Full stack restart
docker compose down
./scripts/new_bootstrap.sh
```

---

## 10. Files Modified/Created

### Created:
- `/mnt/d/docker/scripts/new_bootstrap.sh` — Enhanced bootstrap script
- `/mnt/d/docker/docs/BOOTSTRAP_ANALYSIS.md` — This analysis document

### Read (for analysis):
- `/mnt/d/docker/.gitignore` — Extracted directory patterns
- `/mnt/d/docker/terraform/*.tf` — Infrastructure requirements
- 34 `docker-compose.yml` files — Bind mount analysis

---

## 11. Recommendations

1. **Add to .gitignore:**
   ```
   # Additional directories that should be ignored
   projects/
   agents/
   compose/security/authentik-server/custom-templates/
   ```

2. **Create README for secrets share:**
   Document what should be in `/mnt/vault/local-stack-secrets/`:
   - `.env` file
   - `secrets/` directory with all 17 secret files

3. **Add health check endpoints to outputs.tf:**
   ```hcl
   output "health_checks" {
     value = {
       postgres   = "docker exec postgres pg_isready"
       redis      = "docker exec redis redis-cli ping"
       traefik    = "curl -f http://localhost:8080/ping"
       litellm    = "curl -f http://localhost:4000/health"
       hermes     = "curl -f http://localhost:8787/health"
     }
   }
   ```

4. **Consider adding pre-flight checks:**
   - Verify Docker daemon is running
   - Check available disk space
   - Validate network connectivity

---

## Conclusion

The bootstrap script is now fully customized for your local stack with:
- ✅ All 11 required directories pre-scaffolded
- ✅ Special permissions for Traefik, PostgreSQL, and SSH
- ✅ Terraform integration with state awareness
- ✅ Profile detection from .env
- ✅ Post-bootstrap health checks
- ✅ Comprehensive error handling and user guidance

Ready to use! Run `./scripts/new_bootstrap.sh` to provision your entire stack.
