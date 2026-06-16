---
name: compose-debug
description: Iterative debugging patterns for Docker Compose stacks — common failure modes, healthcheck fixes, secret management, and WSL2 compatibility issues.
source: auto-skill
extracted_at: '2026-06-13T15:00:00.000Z'
---

# Docker Compose Stack Debugging

When bringing up a modular Docker Compose stack, follow this systematic approach:

## 1. Deploy in dependency order

Deploy services bottom-up: **network/proxy → databases → auth/security → core services → consumers**. After each deploy, check status:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## 2. Diagnose container states

| Status | Likely Cause | Fix |
|--------|-------------|-----|
| **Restarting (1)** | Config error, missing file, permission issue | `docker logs <name> --tail 30` |
| **Unhealthy** | Healthcheck command wrong or endpoint unavailable | Test manually with `docker exec` |
| **Health: starting** | Service still initializing | Wait for interval to pass |

## 3. Common failure patterns

### Mutual exclusivity conflicts
Some images (e.g., PostgreSQL) treat `_PASSWORD` and `_PASSWORD_FILE` as mutually exclusive. If `env_file` loads `POSTGRES_PASSWORD` AND the compose file sets `POSTGRES_PASSWORD_FILE`, the container crashes. **Fix**: Remove `env_file` and set values explicitly, or use only one method.

### `_FILE` suffix env vars
Docker secrets are mounted at `/run/secrets/`. The `_FILE` suffix convention means "read the value from this file path" — but not all images honor it. If `AUTHENTIK_SECRET_KEY_FILE=/run/secrets/key` fails, try passing the value directly: `AUTHENTIK_SECRET_KEY=<actual_value>`.

### `env_file` variable scope
Docker Compose `${VAR}` substitution uses the `.env` file from the directory where `docker compose` runs. When running from subdirectories, variables may not resolve. **Fix**: Hardcode values in the compose file or set `--env-file` explicitly.

### External `depends_on`
You cannot `depends_on` a service defined in another compose file (e.g., `depends_on: postgres` when postgres is in a different compose project). **Fix**: Remove `depends_on` and rely on retry logic, or use a single compose file.

### Docker API version negotiation
Older Traefik versions (v3.1-v3.3) fail to negotiate with Docker 29+ with error: `client version 1.24 is too old. Minimum supported API version is 1.40`. **Fix**: Use `traefik:latest` (v3.4+) which has updated Docker client libraries. `DOCKER_API_VERSION` env var does NOT fix this.

### WSL2 filesystem permissions
Paths under `/mnt/d` (or `/mnt/c`) use the Windows filesystem driver which doesn't support Linux permissions. Bind-mounted volumes that require specific ownership (e.g., `chown 999:999`) will fail with `PermissionError`. **Fix**: Use Docker named volumes instead of bind mounts for paths requiring Linux permissions.

### `--internal` networks block port publishing (silent failure)
Docker networks created with `--internal` **completely block host port publishing**. Containers will show `ports:` in compose config but `docker ps` will show no port bindings (e.g., `11434/tcp` instead of `0.0.0.0:11434->11434/tcp`). Connections to localhost will fail with "connection refused" even though the container is healthy. **Diagnose**: `docker network inspect <name> --format '{{.Internal}}'` returns `true`. **Fix**: `docker network rm <name> && docker network create <name>` (without `--internal`). Also update any bootstrap scripts that create the network.

## 4. Healthcheck debugging workflow

When a container is "unhealthy":

1. **Test manually**: `docker exec <name> <healthcheck-command>`
2. If tool not found (`exec: "curl": executable file not found`), discover available tools:
   ```bash
   docker exec <name> which curl wget python3 nc bash 2>&1
   docker exec <name> ls /bin 2>&1
   ```
3. Adapt healthcheck to available tools:
   - **Debian-based** (ollama): `bash -c "echo > /dev/tcp/localhost/<port>"`
   - **Python available** (litellm, agent-zero): `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:<port>/<path>')"`
   - **Alpine** (traefik): `wget --spider -q http://localhost:<port>/<path>`
   - **Rust-based** (vaultwarden): usually has `curl`

4. **Port mismatch**: Healthcheck must use the **internal container port**, not the external mapped port. Check `docker logs` to see which port the service listens on internally.

5. **Auth-protected endpoints**: Some health endpoints require authentication (e.g., LiteLLM `/health` needs master key). Use unauthenticated endpoints (e.g., `/routes`) or pass auth headers.

## 5. Traefik-specific fixes

- Remove deprecated `--providers.docker.swarmMode=false` (removed in v3)
- Ping endpoint needs explicit setup: `--ping=true`, `--ping.entrypoint=ping`, `--entrypoints.ping.address=:8080`
- Cloudflare DNS challenge needs direct env vars `CF_DNS_API_TOKEN` and `CF_API_KEY`, not file paths
- ACME cert errors don't prevent HTTP operation — Traefik runs fine but HTTPS certs fail until credentials are valid
- Label syntax: `traefik.http.routers.<name>.entrypoint=websecure` (singular, v2 syntax) causes `field not found` errors in v3. **Fix**: Use `entrypoints` (plural): `traefik.http.routers.<name>.entrypoints=websecure`

## 6. Authentik-specific fixes

- Requires `authentik` database to exist in PostgreSQL before startup
- `AUTHENTIK_SECRET_KEY` must be a direct value (not file path)
- Media volumes need Docker named volumes on WSL2 due to permission requirements
- Connects to Redis and PostgreSQL — ensure both are healthy first

## 7. MCPO-specific notes

MCPO is not a standalone server — it wraps an MCP server. It requires command arguments:
```yaml
command:
  - "--host"
  - "0.0.0.0"
  - "--port"
  - "8000"
  - "--"
  - "python3"
  - "-c"
  - "from mcp.server.fastmcp import FastMCP; mcp = FastMCP('my-tools'); mcp.run()"
```

**WSL2 note:** The `@anthropic/mcp-server-filesystem` MCP server crashes on WSL2 filesystem mounts (`/mnt/d`). Use an in-process Python MCP server instead to avoid subprocess crashes.

## 8. Hermes (official two-container setup)

Per the [official Docker docs](https://github.com/nesquena/hermes-webui/blob/master/docs/docker.md#scheduled-jobs-and-the-gateway-daemon), Hermes requires **two containers** for scheduled cron jobs to function:

### `hermes-agent` (gateway daemon)
- **Image:** `nousresearch/hermes-agent:latest`
- **Command:** Comment out `command: gateway run` to use the image's default CMD. If you explicitly set `command: gateway run`, you **must** also add `stdin_open: true` and `tty: true` — otherwise the gateway detects stdin is not a terminal and exits immediately with `Warning: Input is not a terminal (fd=0)` followed by `Goodbye!`, causing an infinite restart loop.
- **Env:**
  - `GATEWAY_ALLOW_ALL_USERS=true` (required for Docker access)
  - `HERMES_DASHBOARD_INSECURE=1` (allows incoming API handshakes without auth blocks)
- **Healthcheck:** Check `gateway_state.json`:
  ```yaml
  healthcheck:
    test: ["CMD", "sh", "-c", "test -f /home/hermes/.hermes/gateway_state.json && python3 -c \"import json; d=json.load(open('/home/hermes/.hermes/gateway_state.json')); exit(0 if d.get('gateway_state')=='running' else 1)\""]
  ```
- The gateway runs on port 8642 internally but **has no HTTP health endpoint** — use the state file healthcheck above.

### `hermes` (WebUI)
- **Image:** `ghcr.io/nesquena/hermes-webui:latest`
- **Required env:**
  - `HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui`
  - `HERMES_AGENT_HOST=hermes-agent` (tells WebUI to reach the agent container via Docker network)
- **Shared volumes:** Both containers mount the same `hermes_home` volume. The WebUI also mounts `hermes_agent_src:/home/hermeswebui/.hermes/hermes-agent:ro` (read-only) to install agent Python deps.

### Single-container warning
The community image `ghcr.io/roryford/hermes-station:latest` runs **only the WebUI** — no gateway daemon. Scheduled cron jobs will silently never fire. Always use the official two-container setup from `nesquena/hermes-webui`.

### Key gotchas
- The s6-overlay init takes 2-3 minutes on first start (UID/GID remap + skill sync)
- Gateway needs `HERMES_HOME=/home/hermes/.hermes` and `HERMES_UID=1000`/`HERMES_GID=1000`
- WebUI needs `WANTED_UID=1000`/`WANTED_GID=1000` for file permission alignment
- `gateway run` requires a TTY — if container is in restart loop with "Input is not a terminal", add `stdin_open: true` and `tty: true`, or remove the explicit command to use the default entrypoint

## 9. Consolidating modular compose files into a root docker-compose.yml

When services were previously deployed individually from subdirectory compose files, consolidate them into a single root `docker-compose.yml`:

### Path adjustments
- Change all `../../../.env` references to `.env` (relative to root)
- Change all volume bind mounts from relative paths like `./data` to `./compose/<category>/<service>/data`
- Change secret file paths from `../../../secrets/...` to `./secrets/...`
- Keep all network definitions as `external: true`

### Variable substitution
- Hardcoded secrets in subdirectory compose files must be converted to `${VAR}` references
- Ensure all referenced variables exist in the root `.env` file
- Remove `env_file` from services that have all env vars set explicitly (avoids `_PASSWORD` / `_PASSWORD_FILE` conflicts)

### Named volumes
- Declare all named volumes in the root file's top-level `volumes:` section
- Include both pre-existing volumes (e.g., `authentik_media`) and new ones (e.g., `hermes_data`, `omniroute_data`)

### Secrets
- Declare all secrets in the root file's top-level `secrets:` section
- Point file paths to `./secrets/<name>.txt`

### Migration procedure
1. Stop and remove all individual containers: `docker stop <names> && docker rm <names>`
2. Create root `docker-compose.yml` with all services consolidated
3. Run `docker compose config --quiet` to validate (ignores warnings)
4. Run `docker compose up -d` — Docker will pull new images and reuse existing volumes

## 10. Node.js-based containers (Omniroute, Hermes)

Containers running Node.js applications often lack `curl`, `wget`, and `python3`. For healthchecks, use bash TCP socket testing:

```yaml
healthcheck:
  test: ["CMD", "bash", "-c", "echo > /dev/tcp/localhost/<port>"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

Verify availability with: `docker exec <name> which python3 wget curl nc` and `docker exec <name> node --version`

## 11. Reorganizing services across compose directories

When moving services between category subdirectories (e.g., `compose/productivity/hermes` → `compose/ai/hermes`), maintain consistency across both root and subdirectory compose files:

### Directory moves
```bash
mv compose/<old-category>/<service> compose/<new-category>/<service>
```

### Root docker-compose.yml updates
1. **Move service definition** to the appropriate section (e.g., `# AI / ML`, `# Productivity`)
2. **Update homepage.group labels** to match the new category:
   ```yaml
   labels:
     - "homepage.group=AI Core"  # was "Productivity"
   ```
3. **Remove empty section headers** if the old category is now unused

### Subdirectory compose file updates
1. **env_file paths remain valid** — `../../../.env` still works since directory depth is unchanged
2. **Update homepage.group labels** to match root file
3. **Add missing network definitions** if the service joins new networks:
   ```yaml
   networks:
     proxy:
       external: true
     ai-ml:
       external: true
     database:          # newly added
       external: true
   ```

### Container name conflicts during recreation
When `docker compose up -d` fails with "container name already in use":
```bash
# docker compose stop/rm may not work if container is orphaned
docker stop <container-name>
docker rm <container-name>
docker compose up -d <service-name>
```

## 12. Cross-network service connectivity

Services that need to communicate must satisfy **both** requirements:

1. **Network membership**: Both services must be on the same Docker network
2. **Connection URL**: The client service needs the correct hostname/port URL

### Example: Omniroute connecting to Redis
```yaml
services:
  omniroute:
    environment:
      REDIS_URL: "redis://:${REDIS_PASSWORD}@redis:6379"
    networks:
      - proxy
      - ai-ml
      - database        # Required: Redis is on this network

  redis:
    networks:
      - database
```

**Symptom**: Service logs show "REDIS_URL not set" or "Using in-memory rate limiting" even though Redis is running.

**Diagnosis**:
```bash
docker inspect <container> --format '{{range .Config.Env}}{{println .}}{{end}}' | grep REDIS
docker network inspect <network-name>  # Check which containers are connected
```

**Fix**: Add the missing network to the service's `networks:` list AND set the connection URL environment variable.

## 13. Config drift between root and subdirectory compose files

When maintaining both a root `docker-compose.yml` and standalone per-service compose files (e.g., `compose/ai/hermes/docker-compose.yml`), they inevitably drift apart as manual edits are applied to one but not the other.

### Symptoms
- A service works fine from its standalone compose file but crashes when launched from the root file
- Environment variables present in one file but missing from the other
- Commands commented out in one file but active in the other

### Resolution workflow
1. **Read the standalone file first** — it's usually the more recently edited version
2. **Diff the two** to identify missing env vars, commented-out commands, and label changes:
   ```bash
   diff <(grep -A5 "environment:" docker-compose.yml) <(grep -A5 "environment:" compose/ai/<service>/docker-compose.yml)
   ```
3. **Sync root → standalone** for structural consistency (network names, volume names)
4. **Sync standalone → root** for service-specific tuning (env vars, commands, healthchecks)

### Prevention
- Treat the root `docker-compose.yml` as the source of truth
- After editing a standalone compose file, also apply the same change to the root file
- Use `docker compose config --services` to validate both files independently

## 14. Adding localhost port access for Traefik-routed services

Services behind Traefik often have no `ports:` block (relying on Traefik labels only). For local development without DNS/TLS, add host port mappings.

### Pattern
```yaml
services:
  myservice:
    # ... existing traefik labels stay ...
    ports:
      - "${PORT_MYSERVICE}:8080"   # or whatever internal port
```

### Security-sensitive services
Bind to `127.0.0.1` only to prevent LAN access:
```yaml
    ports:
      - "127.0.0.1:${PORT_REDIS}:6379"
      - "127.0.0.1:${PORT_POSTGRES}:5432"
```

### Verification
```bash
# Check actual port bindings (compose ps table sometimes truncates host IPs):
docker inspect <container> --format '{{json .HostConfig.PortBindings}}'

# Test connectivity:
curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>
```

### When to use
- During development before authentication is configured for external access
- For internal-only services (databases, caches) that should never be publicly accessible
- As a temporary measure while Traefik/DNS/certs are being set up

## 15. Docker Compose profiles for selective startup

When a stack has many services (14+), use `profiles` to enable selective startup and reduce resource usage:

### Profile assignment pattern
```yaml
services:
  # Core infra — no profile (always starts)
  postgres:
    ...
  redis:
    ...
  traefik:
    ...

  # AI services
  ollama:
    profiles: [ai]
  litellm:
    profiles: [ai]
  hermes:
    profiles: [ai]

  # Security services
  authentik-server:
    profiles: [security]
  vaultwarden:
    profiles: [security]

  # Monitoring
  prometheus:
    profiles: [monitoring]
  grafana:
    profiles: [monitoring]
```

### Usage
```bash
docker compose up -d                                          # core only (traefik, postgres, redis)
docker compose --profile ai up -d                             # + AI stack
docker compose --profile security up -d                       # + security stack
docker compose --profile ai --profile security up -d          # multiple profiles
docker compose --profile ai --profile security --profile monitoring up -d  # everything
```

### Key rules
- Services **without** a profile always start with `docker compose up`
- Services **with** a profile only start when that profile is activated
- `depends_on` services that have profiles will be pulled in automatically when the dependent is activated
- Use `docker compose config --services` to see which services are active (without `--profile`, only unprofiled services show)

## 16. Prometheus bind mount permission fix (WSL2)

Prometheus runs as `nobody` (UID 65534) inside its container. When using a bind mount for the data directory on WSL2, the host-owned directory causes a panic:

```
ERROR source=query_logger.go:113 msg="Error opening query log file" err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log
```

### Fix
```bash
sudo chown -R 65534:65534 /path/to/prometheus/data
docker compose --profile monitoring restart prometheus
```

### Prevention
When adding new services that run as non-root users (Prometheus=65534, Grafana=472), create the bind mount directory and set ownership before first `docker compose up`:
```bash
mkdir -p compose/monitoring/prometheus/data
sudo chown -R 65534:65534 compose/monitoring/prometheus/data

mkdir -p compose/monitoring/grafana/data
sudo chown -R 472:472 compose/monitoring/grafana/data
```

Alternatively, use named volumes which avoid WSL2 bind mount permission issues entirely.

## 17. Docker secrets `_FILE` pattern for services

When a service needs a secret value loaded from a file, use Docker Compose's built-in `secrets` mechanism instead of environment variable paths:

### Pattern
```yaml
services:
  openwebui:
    environment:
      WEBUI_SECRET_KEY_FILE: /run/secrets/webui_secret_key   # container path
    secrets:
      - webui_secret_key                                       # mount reference

secrets:
  webui_secret_key:
    file: ./secrets/open_web_ui.txt                            # host path
```

### Why this works
- Docker mounts the secret file at `/run/secrets/<secret_name>` with `0400` permissions
- The application reads the file path from the `_FILE` env var
- The secret never appears in environment variable listings (`docker inspect` won't show the value)
- Works with any `_FILE` suffix convention (e.g., `WEBUI_SECRET_KEY_FILE`, `ADMIN_TOKEN_FILE`)

### Common pitfall
Setting `WEBUI_SECRET_KEY_FILE=./secrets/open_web_ui.txt` (a host-relative path) as the env var value does NOT work — the path must be a **container-internal** path (`/run/secrets/...`). The host file is specified in the top-level `secrets:` section, not in the environment variable.

### When `_FILE` is missing
If a service generates a new random secret on every restart when `_FILE` is not set (e.g., OpenWebUI's session key), users get randomly logged out. **Always** uncomment and configure `_FILE` variables.

## 18. Uptime Kuma healthcheck gotcha

Uptime Kuma's Docker image does **not** include `wget`. A healthcheck using `wget` will fail with `executable file not found in $PATH`, causing the container to report `unhealthy` even though the application is running fine (listening on port 3001).

### Fix
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "-s", "http://localhost:3001/api/entry-page"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

### Diagnosis
```bash
docker inspect uptime-kuma --format '{{json .State.Health}}' | python3 -m json.tool
# Shows: "exec: \"wget\": executable file not found in $PATH"
docker exec uptime-kuma which curl wget node
# Shows: /usr/bin/curl (curl available, wget not)
```

### Lesson
Always verify available tools with `docker exec <name> which curl wget` before writing healthchecks. Node.js-based images often have `curl` but not `wget`.

## 19. Orphan container cleanup after force-recreate

When `docker rm -f` is used to remove containers, and `docker compose up -d` recreates them, Docker may assign hash-prefixed names (e.g., `da166086cf42_mcpo`, `dee5b5c6261b_authentik-worker`) instead of clean service names.

### Symptoms
- `docker ps` shows containers like `da166086cf42_mcpo` instead of `mcpo`
- `docker compose ps` lists both the orphan and the properly-named container
- Services work but monitoring/alerting breaks on name mismatches

### Fix
```bash
# Remove orphaned hash-prefixed containers
docker rm -f da166086cf42_mcpo dee5b5c6261b_authentik-worker

# Recreate with clean names
docker compose --profile ai --profile security --profile monitoring up -d --remove-orphans
```

### Prevention
Always use `--remove-orphans` when running `docker compose up -d` after any force-recreate:
```bash
docker compose up -d --remove-orphans
```

## 20. Systematic security hardening procedure

When hardening a Docker Compose stack for local development, follow this ordered checklist:

### Port binding lockdown
1. **Audit all port bindings**: `docker compose ps --format "{{.Name}}: {{.Ports}}"`
2. **Lock everything to 127.0.0.1** except the reverse proxy:
   ```yaml
   # Before (exposed to all interfaces):
   ports:
     - "${PORT_SERVICE}:8080"

   # After (localhost only):
   ports:
     - "127.0.0.1:${PORT_SERVICE}:8080"
   ```
3. **Keep 0.0.0.0 only for**: Traefik HTTP (80) and HTTPS (443) — these need to be externally reachable
4. **Verify**: `docker inspect <container> --format '{{json .HostConfig.PortBindings}}'`

### Secret management
5. **File permissions**: `chmod 600 secrets/*_key.txt secrets/*_token.txt secrets/*_password.txt`
6. **Docker secrets**: Convert env-based secrets to proper `secrets:` blocks (see §17)
7. **Public keys**: `chmod 644 secrets/*.pub` (public keys are safe to read)

### Service isolation
8. **Add profiles**: Group services by function (ai, security, monitoring) — see §15
9. **Network separation**: Ensure services only join networks they need
10. **Remove unused ports**: If a service is only accessed via Docker network, remove its `ports:` block

### Verification
```bash
# Check all port bindings are localhost-only (except traefik 80/443):
docker compose ps --format "{{.Name}}: {{.Ports}}" | grep -v "127.0.0.1" | grep -v "traefik"

# Check secret file permissions:
ls -la secrets/ | grep -v "^total" | awk '{print $1, $NF}'
```

## 21. Container-owned files blocking git operations (WSL2)

When Docker containers write files to bind-mounted directories, those files are owned by `root:root` (or the container's user). This causes `git add .` to fail with `Permission denied`.

### Symptoms
```
error: open("compose/ai/ollama/models/cache/model-recommendations.json"): Permission denied
error: unable to index file 'compose/ai/ollama/models/cache/model-recommendations.json'
fatal: updating files failed
```

### Root cause
The ollama container (running as root) writes cache files to a bind mount. The host user (`alwazw`) cannot read those files, so git cannot hash them.

### Fix (three-part)

**1. Fix ownership:**
```bash
sudo chown -R alwazw:alwazw compose/ai/ollama/models/
```

**2. Untrack from git:**
```bash
git rm --cached compose/ai/ollama/models/cache/model-recommendations.json
```

**3. Add to .gitignore:**
```gitignore
# 3b. AI Model Data & Caches (Runtime artifacts, not source)
compose/ai/ollama/models/
compose/ai/agent-zero/data/
compose/ai/agent-zero/work_dir/
compose/ai/openwebui/data/
compose/security/vaultwarden/data/
compose/network/traefik/data/
```

### Common affected directories
Any bind mount where the container writes files:
- `compose/ai/ollama/models/` — model downloads, cache files (root:root)
- `compose/monitoring/prometheus/data/` — TSDB, queries.active (nobody:65534)
- `compose/data/postgres/data/` — database files (postgres:999)

### Prevention
- Add all runtime data directories to `.gitignore` immediately when adding new bind-mount services
- Run `find compose/ -user root 2>/dev/null` periodically to check for unexpected root-owned files
- Prefer Docker named volumes for data directories that don't need direct host access

## 22. Root compose image mismatch with custom build

When a root `docker-compose.yml` and a subdirectory compose file reference different images for the same service, the container starts successfully but custom modules are missing.

### Symptoms
- Container shows as `healthy` in `docker ps`
- Custom API server or module doesn't start (no process found in `ps aux`)
- `docker exec <name> find /app/<module>/ -type f` returns empty
- Logs show base image services starting but no custom module output

### Root cause
Root compose references the base image (`frdel/agent-zero:latest`) while the subdirectory compose references the custom build (`agent-zero-langgraph:latest`). The root compose was never updated after the custom Dockerfile was created.

### Diagnosis workflow
```bash
# 1. Check if custom module exists inside container
docker exec <name> find /app/<module>/ -type f 2>/dev/null | head -5

# 2. Compare with build context
ls compose/<path>/<module>/

# 3. Check which image the running container uses
docker inspect <name> --format '{{.Config.Image}}'

# 4. Check root compose vs subdirectory compose
grep "image:" docker-compose.yml | grep <service>
grep "image:" compose/<path>/docker-compose.yml | grep <service>
```

### Fix
1. Update root compose to use the custom image
2. Add any missing environment variables, volumes, and port mappings from the subdirectory compose
3. Rebuild and recreate:
```bash
# Build from subdirectory context
cd compose/<path>/ && docker compose build

# Recreate from root
cd /mnt/d/docker
docker stop <name> && docker rm <name>
docker compose --profile <profile> up -d <service>
```

### Rebuild cycle (when image needs updating after code changes)
```bash
# 1. Sync source files to build context
cp agents/qwen/<module>/<file>.py compose/<path>/<module>/<file>.py

# 2. Rebuild image (from build context directory)
cd compose/<path>/ && docker compose build

# 3. Recreate container (from root)
cd /mnt/d/docker
docker stop <name> && docker rm <name>
docker compose --profile <profile> up -d <service>

# 4. Wait for initialization, then verify
sleep 15  # Allow entrypoint/supervisord to start
curl -s http://127.0.0.1:<port>/health | python3 -m json.tool
```

### Prevention
- When creating a custom Dockerfile in a subdirectory, always update the root compose's `image:` reference
- Keep environment variables, volumes, and port mappings in sync between root and subdirectory compose files
- Use the subdirectory compose file as the canonical reference for service-specific config

## 23. Docker bridge network inter-container forwarding broken (WSL2/Docker Desktop)

After container restarts on WSL2/Docker Desktop, Docker bridge networks can silently lose inter-container forwarding. DNS resolution works, but TCP connections between containers on the same network time out.

### Symptoms
- `docker exec container-A ping container-B` fails (ICMP blocked) or times out
- `docker exec container-A curl http://container-B:<port>` times out with exit code 28
- `docker exec container-A python3 -c "import socket; s.connect(('container-B', <port>))"` → `TimeoutError`
- Containers show as `healthy` individually but can't talk to each other
- The bridge interface (`br-<hash>`) shows `state UP` in `ip link show`
- `iptables -L DOCKER-FORWARD -v -n` shows no ACCEPT rules for the specific bridge interface

### Root cause
Docker Desktop's WSL2 backend loses iptables FORWARD chain entries for specific bridge interfaces after container restarts. The `DOCKER-FORWARD` chain has a `policy DROP` and only has rules for `docker0` and a subset of bridge interfaces. New or restarted containers on other bridges get dropped.

### Diagnosis
```bash
# Check which bridge interface corresponds to the network:
docker network inspect <network-name> --format '{{.Id}}'
ip link show | grep br-<first-12-chars-of-id>

# Check if the bridge has iptables rules:
sudo iptables -L DOCKER-FORWARD -v -n | grep br-<hash>
# If empty → that's the problem

# Verify by testing from a container on the affected network:
docker exec <container> python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('<target>', <port>))"
```

### Fix
Add iptables ACCEPT and DOCKER rules for the affected bridge interfaces:
```bash
# Find the bridge interface name:
BRIDGE_AIML="br-1813ea894891"    # ai-ml network
BRIDGE_DB="br-a661348a0ada"      # database network

# Add FORWARD ACCEPT rules (insert at position 3/4 to run before DROP):
sudo iptables -I DOCKER-FORWARD 3 -i $BRIDGE_AIML -j ACCEPT
sudo iptables -I DOCKER-FORWARD 4 -i $BRIDGE_DB -j ACCEPT

# Add DOCKER chain routing for port publishing:
sudo iptables -I DOCKER-BRIDGE 2 -i $BRIDGE_AIML -j DOCKER
sudo iptables -I DOCKER-BRIDGE 3 -i $BRIDGE_DB -j DOCKER
```

### Verification
```bash
# Test connectivity after fix:
docker exec <container-A> python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('<container-B>', <port>)); print('connected'); s.close()"
```

### Permanent fix
- Restart Docker Desktop service (resets all iptables rules correctly)
- Or recreate the affected network: `docker network rm <name> && docker network create <name>`
- These iptables rules are lost on Docker restart — consider adding them to a startup script

### Why reconnecting containers doesn't help
`docker network disconnect` + `docker network connect` only reassigns the container's veth pair to the bridge. If the bridge itself has no iptables FORWARD rules, traffic still gets dropped at the `DOCKER-FORWARD` chain.
