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
- **Command:** `gateway run` (required — without this it defaults to interactive TUI and exits)
- **Env:** `GATEWAY_ALLOW_ALL_USERS=true` (required for Docker access)
- **Healthcheck:** Check `gateway_state.json`:
  ```yaml
  healthcheck:
    test: ["CMD", "sh", "-c", "test -f /home/hermes/.hermes/gateway_state.json && python3 -c \"import json; d=json.load(open('/home/hermes/.hermes/gateway_state.json')); exit(0 if d.get('gateway_state')=='running' else 1)\""]
  ```
- The gateway runs on port 8642 internally but **has no HTTP health endpoint** — use the state file healthcheck above.

### `hermes` (WebUI)
- **Image:** `ghcr.io/nesquena/hermes-webui:latest`
- **Required env:** `HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui`
- **Shared volumes:** Both containers mount the same `hermes_home` volume. The WebUI also mounts `hermes_agent_src:/home/hermeswebui/.hermes/hermes-agent:ro` (read-only) to install agent Python deps.

### Single-container warning
The community image `ghcr.io/roryford/hermes-station:latest` runs **only the WebUI** — no gateway daemon. Scheduled cron jobs will silently never fire. Always use the official two-container setup from `nesquena/hermes-webui`.

### Key gotchas
- The s6-overlay init takes 2-3 minutes on first start (UID/GID remap + skill sync)
- Gateway needs `HERMES_HOME=/home/hermes/.hermes` and `HERMES_UID=1000`/`HERMES_GID=1000`
- WebUI needs `WANTED_UID=1000`/`WANTED_GID=1000` for file permission alignment

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
