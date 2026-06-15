---
name: langgraph-docker-deploy
description: Pattern for extending a third-party Docker image with LangGraph + FastAPI orchestration — entrypoint wrapper, supervisord coexistence, volume mounts, and WSL2 gotchas.
source: auto-skill
extracted_at: '2026-06-15T00:35:36.607Z'
---

# Deploying LangGraph Orchestration Inside an Existing Docker Image

When you need to add a LangGraph-based multi-agent orchestration layer (with REST API, LLM integration, MCP tools, SSH deployment) on top of a third-party Docker image that already runs its own services via supervisord.

## Architecture Pattern

```
┌─────────────────────────────────────────────────┐
│  Docker Image: <base>:latest                     │
│                                                   │
│  ENTRYPOINT ["/entrypoint.sh"]                   │
│  CMD ["/exe/initialize.sh", "${BRANCH}"]         │
│                                                   │
│  entrypoint.sh:                                  │
│    1. Start API server in background (&)          │
│    2. exec "$@"  → chains to original CMD       │
│                                                   │
│  supervisord (from CMD):                          │
│    - Original service (web UI, gateway, etc.)     │
│    - Cron, tunnel, SSH, search engine             │
│                                                   │
│  API server (background PID):                     │
│    - FastAPI on port 8080 (mapped to host 8081)   │
│    - LangGraph CEO orchestration graph            │
│    - LLM client → LiteLLM proxy                   │
│    - MCP client → MCPO bridge                     │
│    - SSH deployer → production VMs                │
│    - Project memory → JSON vector store           │
└─────────────────────────────────────────────────┘
```

## Dockerfile Pattern

```dockerfile
FROM <base-image>:latest

# 1. Install system deps FIRST (before pip)
RUN python3 -m ensurepip --upgrade || apt-get update && apt-get install -y python3-pip openssh-client

# 2. Fix typing_extensions conflict (common with Kali/Debian sid base images)
RUN python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
    typing_extensions>=4.15.0

# 3. Install Python dependencies
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    langgraph>=0.2.0 \
    langchain-core>=0.3.0 \
    pydantic>=2.0.0 \
    httpx>=0.27.0 \
    fastapi>=0.115.0 \
    uvicorn[standard]>=0.32.0 \
    paramiko>=3.5.0

# 4. Copy custom module
COPY my_module/ /app/my_module/

# 5. Entrypoint wrapper
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 6. Create required directories
RUN mkdir -p /app/projects /app/audit

WORKDIR /app

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/exe/initialize.sh", "${BRANCH}"]
```

## Entrypoint Wrapper Script

The key pattern: start the API server in the background, then `exec "$@"` to chain to the original CMD.

```bash
#!/bin/sh
# Start the API server in the background
python3 -m my_module.api_server &
API_PID=$!
echo "API server started (PID $API_PID)"

# Execute the original CMD
exec "$@"
```

**Why this works:**
- `exec "$@"` replaces the shell process with the original CMD (e.g., supervisord)
- The API server runs as a background PID alongside supervisord
- Container lifecycle is managed by the original CMD (supervisord), not the API server
- If the original CMD exits, the container stops — even if the API server is still running

## Critical Gotchas (in order of encounter)

### 1. Entrypoint vs CMD conflict
**Symptom:** Container crash-loops with `sh: 2: /app/start.sh: not found`
**Cause:** Overriding `command:` in docker-compose replaces CMD entirely. The base image's initialization script never runs.
**Fix:** Use ENTRYPOINT wrapper (above). Never use `command:` in docker-compose when extending a base image with its own CMD.

### 2. Missing branch parameter
**Symptom:** Container crash-loops with `Error: Branch parameter is empty`
**Cause:** The base image's `initialize.sh` requires a branch argument via CMD. When ENTRYPOINT is added, CMD must be explicitly re-declared in the Dockerfile.
**Fix:** Add `CMD ["/exe/initialize.sh", "${BRANCH}"]` to Dockerfile. Add `BRANCH=main` to `.env`.

### 3. Relative volume mount paths in nested compose files
**Symptom:** Secrets mount appears empty inside container (`ls /secrets/` shows empty directory)
**Cause:** From `compose/ai/service/`, `../../secrets` resolves to `compose/secrets`, not the project root `secrets/`.
**Fix:** Count directory levels carefully:
```yaml
# From compose/ai/service/docker-compose.yml:
#   compose/ai/service/ → compose/ai/ → compose/ → project root/
volumes:
  - ../../../secrets:/secrets:ro   # 3 levels up to reach project root
  - ../../projects:/app/projects   # 2 levels up for sibling directory
```

### 4. System packages vs pip packages
**Symptom:** Docker build fails with `ERROR: No matching distribution found for openssh-client`
**Cause:** `openssh-client` is an apt package, not a pip package. Cannot be installed via `pip install`.
**Fix:** Install system packages in a separate `RUN` line with `apt-get`:
```dockerfile
RUN apt-get update && apt-get install -y python3-pip openssh-client
RUN python3 -m pip install --no-cache-dir --break-system-packages ...
```

### 5. typing_extensions version conflict
**Symptom:** Docker build fails with `ERROR: Cannot uninstall typing_extensions`
**Cause:** Kali/Debian sid base images ship an older `typing_extensions` that pip refuses to overwrite.
**Fix:** Install with `--ignore-installed` as a separate step BEFORE other dependencies:
```dockerfile
RUN python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
    typing_extensions>=4.15.0 && \
    python3 -m pip install --no-cache-dir --break-system-packages \
    langgraph>=0.2.0 ...
```

### 6. LiteLLM health check tolerance
**Symptom:** API health endpoint reports `llm_available: false` even though LiteLLM is reachable
**Cause:** LiteLLM returns HTTP 400 (not 200/401) when reachable but has config issues (e.g., no connected DB). Strict health check (`status_code in (200, 401)`) rejects this.
**Fix:** Accept any non-server-error response:
```python
def is_available(self) -> bool:
    response = client.get(f"{self.base_url}/health", headers=self._headers())
    return response.status_code < 500  # Any reachable response
```

### 7. WSL2 9p filesystem caching
**Symptom:** Files written inside container to a volume-mounted directory appear stale on WSL2 host side. `stat` on host shows old modification time even though container confirms fresh data.
**Cause:** WSL2's 9p filesystem protocol caches directory entries aggressively.
**Fix:** Always verify data by reading from inside the container with `docker exec`, not from the host filesystem. Run `sync` on host to flush, but don't rely on it.

### 8. Port conflicts in multi-service containers
**Symptom:** `docker compose up` fails with `Bind for 0.0.0.0:8080 failed: port is already allocated`
**Cause:** Base image already exposes port 80. API server on 8080 conflicts with another service on the host.
**Fix:** Use a non-standard host port mapping:
```yaml
ports:
  - "${PORT_SERVICE}:80"            # Base image web UI
  - "${PORT_SERVICE_API:-8081}:8080" # API server (default 8081, configurable)
```
Add `PORT_SERVICE_API=8081` to `.env`.

### 9. Secrets path resolution inside container
**Symptom:** `LITELLM_MASTER_KEY_FILE` points to a path that doesn't exist inside the container, even though the file exists on the host.
**Cause:** The env var was set to the host path (`/home/user/docker/secrets/key.txt`) instead of the container mount path (`/secrets/key.txt`).
**Fix:** Always set file path env vars to the **container-side** mount path:
```yaml
environment:
  LITELLM_MASTER_KEY_FILE: "/secrets/litellm_key.txt"  # Container path, not host path
  SSH_KEY_PATH: "/secrets/ssh_deploy_key"
volumes:
  - ../../../secrets:/secrets:ro
```

### 10. Pip not available in base image
**Symptom:** `pip: command not found` or `python3 -m pip: No module named pip`
**Cause:** Some base images (Kali, minimal Debian) don't include pip.
**Fix:** Bootstrap with `ensurepip` first, fall back to apt:
```dockerfile
RUN python3 -m ensurepip --upgrade || apt-get update && apt-get install -y python3-pip
```

## Stdlib PoC → LangGraph Migration Pattern

Before committing to the LangGraph dependency, build a zero-dependency PoC using Python stdlib that mirrors LangGraph's execution model:

| Stdlib PoC | LangGraph Equivalent |
| :--- | :--- |
| `dataclass GraphState` | `TypedDict` state schema |
| Custom `Graph` class with node/edge dict | `StateGraph.add_node()` + `add_edge()` |
| `Edge` with `condition` lambda | `add_conditional_edges()` with router function |
| Direct function calls | `app.stream(state, config)` |
| Manual checkpoint dict | `MemorySaver` checkpointer |
| `simulate_hermes_signoff()` | `interrupt()` human-in-the-loop breakpoint |

**Benefits:**
- Validates graph topology with zero dependencies
- Proves audit trail works before adding framework overhead
- Reduces migration risk — the LangGraph port is mechanical, not architectural
- Tests can run without `pip install` on any Python 3.10+ system

## Module Structure

```
agent_zero_langgraph/
├── __init__.py
├── __main__.py          # python3 -m agent_zero_langgraph entry point
├── state.py             # TypedDict state schema for LangGraph
├── models.py            # Pydantic models (Contract, Scope, Risk, etc.)
├── agents.py            # Sub-agent classes (PMAgent, DevAgent, DevOpsAgent)
├── graph.py             # LangGraph StateGraph with nodes + conditional edges
├── audit.py             # Structured audit trail writer (AUDIT_DIR env var)
├── llm_client.py        # LiteLLM proxy client (httpx-based)
├── mcp_client.py        # MCP tool server client via MCPO bridge
├── ssh_deploy.py        # SSH deployment with health-check + auto-rollback
├── memory.py            # Cross-project context retention (JSON vector store)
├── api.py               # FastAPI REST endpoints for delegation
├── api_server.py        # Uvicorn runner
├── run_demo.py          # CLI demo runner
├── tests.py             # Original test suite (21 tests)
└── tests_phase5.py      # Integration tests (22 tests, pytest)
```

## Testing Strategy

1. **Stdlib PoC tests** — Run with `python3 tests.py` (zero dependencies)
2. **LangGraph tests** — Run inside container: `docker exec <name> python3 -m module.tests`
3. **Phase 5 integration tests** — Requires pytest: `docker exec <name> python3 -m pytest module/tests_phase5.py -v`
4. **Live API test** — `docker exec <name> curl -s http://localhost:8080/api/v1/health`
5. **End-to-end task** — `docker exec <name> curl -s -X POST http://localhost:8080/api/v1/tasks -H "Content-Type: application/json" -d '...'`

Always run tests **inside the container**, not on the host — the module depends on container-side paths and network access to other Docker services.
