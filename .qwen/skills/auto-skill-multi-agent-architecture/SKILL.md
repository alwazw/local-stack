---
name: multi-agent-architecture
description: Blueprint for multi-agent system using Hermes (PM), Agent Zero (Builder), and Agent OS (Spec Bridge) — layered architecture, skill installation, MCP tooling, and delegation loop.
source: auto-skill
extracted_at: '2026-06-13T15:37:23.081Z'
---

# Multi-Agent System Architecture (Hermes PM + Agent Zero Builder)

## Architecture Layers

```
┌─────────────────────────────────────────────────┐
│  Layer 1: Orchestration — Hermes (PM)           │
│  - Task decomposition, spec writing, memory     │
│  - Delegates to Agent Zero via HTTP API         │
├─────────────────────────────────────────────────┤
│  Layer 2: Alignment Bridge — Agent OS           │
│  - Scans codebase, extracts standards           │
│  - Injects standards into specs                 │
├─────────────────────────────────────────────────┤
│  Layer 3: Execution — Agent Zero (Builder)      │
│  - Receives SPEC.md, executes via MCP tools     │
│  - Terminal-based code, tests, git operations   │
└─────────────────────────────────────────────────┘
```

## Key Concepts

### Skills (Procedural Memory)
- Local `SKILL.md` markdown files that teach agents *how to think/act*
- Zero network latency, adapt behavior to workflows
- Hermes discovers them in `~/.hermes/skills/<category>/<name>/SKILL.md`

### MCP (Model Context Protocol)
- Standardized protocol for agents to *act* on external systems
- Connects agents to tools (Git, Docker, databases, JIRA) via fixed JSON schemas
- Replaces ad-hoc scripts with deterministic tool interfaces

## Layer 1: Hermes PM Setup

### Install Skills
Clone skills into Hermes' skills volume (`hermes_home`):

```bash
# wondelai/skills — cross-platform management skills
git clone https://github.com/wondelai/skills.git /tmp/skills
# Copy PM-relevant categories:
# - software-development/clean-code, domain-driven-design, system-design
# - product-strategy/jobs-to-be-done, lean-startup, design-sprint
# - management/traction-eos, team-topologies, high-output-management
cp -r /tmp/skills/software-development/* /mnt/d/docker/volumes/docker_hermes_home/_data/skills/software-development/
```

### Install execplan-skill (long-running task management)
```bash
git clone https://github.com/tiann/execplan-skill.git /tmp/execplan
mkdir -p /mnt/d/docker/volumes/docker_hermes_home/_data/skills/software-development/execplan
cp /tmp/execplan/SKILL.md /mnt/d/docker/volumes/docker_hermes_home/_data/skills/software-development/execplan/
```

### Memory (Hindsight)
Hermes already installs `hindsight-client>=0.4.22` on startup. To enable:
- Configure in `~/.hermes/config.yaml` under `memory:` section
- Provider: `hindsight` with SQLite or vector store backend

### LLM Provider Configuration
Configure Hermes to use local Ollama via LiteLLM:
```yaml
# In ~/.hermes/config.yaml
model:
  default: ollama/llama3.1:8b
  provider: auto
  base_url: http://litellm:4000
```

### PM System Prompt (SOUL.md)
Create `~/.hermes/SOUL.md` with PM instructions:
- "You are a project manager agent"
- "When given a task: 1) Run agent-os to discover standards, 2) Write SPEC.md, 3) Delegate to Agent Zero"
- "Use delegation toolset to call Agent Zero API"

## Layer 2: Agent OS (Spec Bridge)

### Install
```bash
git clone https://github.com/buildermethods/agent-os.git /mnt/d/docker/tools/agent-os
```

It's a pure shell script tool — no dependencies. It:
1. Scans codebase to extract conventions into standards
2. Injects relevant standards into task context
3. Helps shape better specs

### Workflow Integration
When Hermes receives a task:
1. Hermes triggers `agent-os` scan on `/mnt/d/docker/`
2. Agent OS extracts `STANDARDS.md` from codebase patterns
3. Hermes incorporates standards into `SPEC.md`
4. Hermes passes `SPEC.md` to Agent Zero

### Custom Implementation (if agent-os docs inaccessible)
Since agent-os docs are behind a paywall, replicate its behavior:
```bash
# Scan codebase for patterns
grep -r "import\|from\|require\|use" --include="*.py" --include="*.js" --include="*.ts" /mnt/d/docker/ | \
  awk -F: '{print $1}' | sort | uniq -c | sort -rn > /tmp/import-patterns.txt

# Extract conventions into standards
cat > /mnt/d/docker/STANDARDS.md << 'EOF'
# Codebase Standards
## Import Patterns
...
EOF
```

## Layer 3: Agent Zero Builder Setup

### Agent Zero CEO Orchestration (LangGraph)
Agent Zero runs a **LangGraph StateGraph** as its CEO orchestration layer:
- **Graph topology:** `Intake → Scope Validation → PM Delegation → Dev Pool → Result Aggregation → DevOps Pool → Checkpoint`
- **Conditional edges:** Approval gate (Hermes sign-off or 24h veto window), sandbox verification routing
- **Checkpointing:** `MemorySaver` persists 9 checkpoints per execution for audit
- **Human-in-the-loop:** LangGraph `interrupt()` pauses graph at scope validation for board approval
- **Sub-agents:** Lightweight Python classes (`PMAgent`, `DevAgent`, `DevOpsAgent`) — not full LangGraph sub-graphs

### REST API for Delegation (FastAPI)
Agent Zero exposes a REST API on port 8081 for Hermes task delegation:

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/tasks` | POST | Submit contract JSON, execute graph |
| `/api/v1/tasks/{id}` | GET | Get task status and state |
| `/api/v1/tasks/{id}/approve` | POST | Human-in-the-loop approval |
| `/api/v1/tasks` | GET | List all active tasks |
| `/api/v1/projects` | GET | List projects in memory |
| `/api/v1/health` | GET | Service availability (LLM, MCP, SSH, Memory) |

### Integration Modules
| Module | Connects To | Purpose |
|---|---|---|
| `llm_client.py` | LiteLLM proxy (`http://litellm:4000`) | Real code generation via LLM |
| `mcp_client.py` | MCPO bridge (`http://mcpo:8000`) | Filesystem + Git tool operations |
| `ssh_deploy.py` | Production VMs (SSH key auth) | Deploy with health-check + auto-rollback |
| `memory.py` | `/app/data/memory/` (JSON store) | Cross-project context retention |

### Audit Trail
Structured artifacts written to volume-mounted `AUDIT_DIR` (`/app/audit → agents/qwen/`):
- `execution-graph.json` — Live graph state checkpoint
- `agent-registry.json` — Active sub-agents and roles
- `deployment-log.jsonl` — Append-only deployment events
- `decision-tree.md` — Human-readable decision log per contract

### MCP Servers
Deploy MCP servers on the `ai-ml` network for deterministic tool access:

| MCP Server | Purpose | Image |
|------------|---------|-------|
| Filesystem | File operations | `modelcontextprotocol/server-filesystem` |
| Git | Repo operations | `modelcontextprotocol/server-git` |
| PostgreSQL | DB access | Community server |
| Docker | Container mgmt | Community server |

### MCP Tool Execution Safety

When consuming MCP servers, agents MUST follow these constraints:

#### Filesystem MCP Boundaries
- File modifications restricted to `/mnt/d/docker/` and `~/docker/` ONLY
- Never write to `/run/secrets/` directly (managed via Docker Compose secrets)
- Never modify files owned by `root` without explicit escalation

#### Docker MCP Constraints
- Never restart adjacent running containers — isolate to single target
- Never remove containers/volumes without user confirmation
- Never modify Docker daemon configuration
- Never pull images without user confirmation
- All write operations logged to `agents/qwen/deployment-log.jsonl`

#### Lock Protocol for Concurrent Operations
When multiple sub-agents operate on shared resources (networks, databases, compose files):

```bash
# 1. Acquire lock
echo '{"agent":"qwen","task":"<id>","acquired":"<ISO8601>","resources":["<resource>"]}' \
  > /mnt/d/docker/.locks/<task_id>.lock

# 2. Execute task
# 3. Run full validation pipeline
# 4. Release lock ONLY after validation passes
rm /mnt/d/docker/.locks/<task_id>.lock
```

**Lock triggers:** Network changes, DB modifications, concurrent file writes, compose file edits
**No lock needed:** Read-only container inspection, file reads

#### No-Go Constraints (require human approval)
1. Modify Docker daemon configuration
2. Delete networks, volumes, or images
3. Modify `/etc/hosts`, firewall rules, system networking
4. Write secrets to logs or stdout
5. Expose services on `0.0.0.0` without authentication-first workflow
6. Bypass lock protocol for concurrent operations
7. Modify files outside `/mnt/d/docker/` via MCP

#### MCPO Bridge Registration
Register MCP servers in `compose/ai/mcpo/config.json`:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/mnt/d/docker"]
    },
    "docker": {
      "command": "npx",
      "args": ["-y", "docker-mcp"]
    }
  }
}
```
Mount into MCPO container: `./compose/ai/mcpo/config.json:/app/config.json:ro`

#### MCP Deployment Phases
1. **Phase 1** (current): MCPO bridge running, no servers registered
2. **Phase 2**: Register `mcp-server-filesystem` for code write persistence
3. **Phase 3**: Register `docker-mcp` for container lifecycle management
4. **Phase 4**: Register git/postgres/github MCP servers

### Agent Zero Instruments Bridge
Agent Zero has `/a0/instruments/` for tool definitions. Create MCP bridge instruments:
```python
# /a0/instruments/mcp_bridge.py
import httpx
async def call_mcp(server_url: str, tool_name: str, arguments: dict):
    """Call an MCP server tool endpoint"""
    async with httpx.AsyncClient() as client:
        resp = await client.post(f"{server_url}/tools/call", json={
            "tool": tool_name,
            "arguments": arguments
        })
        return resp.json()
```

### Builder SKILL.md
Create `/a0/knowledge/builder/SKILL.md`:
```markdown
# Builder Instructions
## Workflow
1. Receive SPEC.md from Hermes
2. Use MCP tools for Git, filesystem, database operations
3. Use shell for tests, builds, deployments
4. Report completion status to Hermes via callback

## Tool Usage
- Git operations: MCP Git server
- File operations: MCP Filesystem server
- DB queries: MCP PostgreSQL server
- Tests/Builds: Shell execution

## Completion
Write status to: /shared/workspace/status.json
```

## Communication Loop

### Hermes → Agent Zero Delegation

Three complementary mechanisms (all deployed and verified):

#### 1. Custom Hermes Skill (teaches Hermes the API)
Create a skill at `~/.hermes/skills/custom/<name>/SKILL.md` that documents the full API:
```bash
# Create skill directory and deploy
docker exec hermes-agent mkdir -p /home/hermes/.hermes/skills/custom/agent-zero-delegation
docker cp /host/path/skill.md hermes-agent:/home/hermes/.hermes/skills/custom/agent-zero-delegation/SKILL.md

# Verify skill is recognized
docker exec hermes-agent hermes skills list | grep agent-zero
```

Skill structure follows Hermes conventions:
```yaml
---
name: agent-zero-delegation
description: "Delegate build tasks to Agent Zero via REST API"
version: 1.0.0
author: Qwen (Architecture)
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [agent-zero, delegation, multi-agent, build, orchestration, api]
---
```

Include in the skill body: API reference (all endpoints with curl examples), delegation workflow (decompose → submit → monitor → approve → report), when to delegate vs handle directly, and a full example script.

#### 2. Watchdog Script (zero-LLM-cost monitoring)
Deploy a shell script to `~/.hermes/scripts/` that checks API health and reports task status:
```bash
docker cp /host/path/script.sh hermes-agent:/home/hermes/.hermes/scripts/script.sh
docker exec hermes-agent chmod +x /home/hermes/.hermes/scripts/script.sh
```

Script pattern — use `curl` to check health, parse JSON with `python3 -c`, output a structured status report that can be consumed by either `--no-agent` cron or agent-mode cron.

#### 3. Recurring Cron Job
```bash
# --accept-hooks is a GLOBAL flag (before 'cron'), not a subcommand flag
docker exec hermes-agent hermes --accept-hooks cron create "*/5 * * * *" \
  --name "agent-zero-watchdog" \
  --script hermes_delegate.sh \
  --no-agent \
  --deliver local \
  --repeat 999
```

**Key `hermes cron create` options:**
- `schedule` — cron expression (`*/5 * * * *`) or relative (`5m`, `every 2h`)
- `--script <name>` — script under `~/.hermes/scripts/` (basename only)
- `--no-agent` — skip LLM, deliver script stdout directly (zero cost)
- `--deliver local` — deliver script output to local Hermes logs (other options: `origin`, `telegram`, `discord`, `signal`)
- `--repeat N` — repeat count (omit for one-shot, `999` for long-running)

**Verification:**
```bash
docker exec hermes-agent hermes cron list    # Shows all scheduled jobs
docker exec hermes-agent bash /home/hermes/.hermes/scripts/<script>.sh  # Manual test
```

#### 4. Direct API Call (for intelligent delegation from agent-mode)
When Hermes needs to submit a task (not just monitor):
```bash
curl -s -X POST http://agent-zero:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{"project":"my-project","features":["feature1"],"auto_approve":true,"simulate":false}'
```

### Agent Zero → Hermes Callback
Agent Zero writes completion to shared location:
- **Option A:** Shared Docker volume (`hermes_shared:/shared/workspace/`)
- **Option B:** PostgreSQL table (`agent_task_status`)
- Hermes polls via its cron system (ticks every 60s)

### Shared Workspace
Create a Docker volume for inter-agent communication:
```yaml
# In docker-compose.yml
volumes:
  agent_workspace:
```
Mount to both:
- Hermes: `/shared/workspace/` — writes `SPEC.md`, reads `status.json`
- Agent Zero: `/shared/workspace/` — reads `SPEC.md`, writes `status.json`

## Reference Resources

- **Hermes Agent:** https://github.com/nesquena/hermes-webui
- **Awesome Hermes Directory:** https://github.com/0xNyk/awesome-hermes-agent
- **Agent OS:** https://github.com/buildermethods/agent-os
- **wondelai/skills:** https://github.com/wondelai/skills
- **MCP Servers:** https://github.com/modelcontextprotocol/servers
- **MCP Registry:** https://registry.modelcontextprotocol.io/

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Internet outage | Clone all repos first; skills are markdown files (fully local) |
| WSL2 filesystem | Use named volumes, not bind-mounts to `/mnt/d` |
| Agent-OS paywall | Replicate behavior with grep/ripgrep codebase scanning |
| MCP server crashes | Use in-process Python MCP servers (no external subprocess) |
| Hermes gateway TUI exit | Use `command: gateway run` + `GATEWAY_ALLOW_ALL_USERS=true` **and** `stdin_open: true` + `tty: true` in compose. Without TTY/stdin, the gateway detects `Input is not a terminal (fd=0)`, prints "Goodbye!" and exits — causing an infinite restart loop (`Restarting (0)`). s6 supervision alone does not fix this; it just keeps restarting the crashing process. |
