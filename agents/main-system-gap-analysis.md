# System State & Gap Analysis

## 1. Executive Summary

| Attribute | Value |
| :--- | :--- |
| **Current Phase** | Phase 5 Complete — All Integrations Live (LLM, MCP, SSH, Memory, API, HITL). Secret management overhauled. All ports locked. |
| **Target Objective** | Establish fully autonomous, multi-project full-stack deployments managed by Agent Zero under Hermes' direction. |
| **Last Updated** | 2026-06-16 |
| **Framework** | **LangGraph** for Agent Zero orchestration with lightweight custom sub-agent wrappers. |
| **Infrastructure** | Modular composable architecture: root `docker-compose.yml` contains only `include:` directives, secrets, and networks. 31 services each defined in their own `compose/<category>/<service>/docker-compose.yml`. 8 categories. 7 compose profiles. 12 networks. 17 Docker secrets. |

**Modular Compose Architecture**
- **Root file** (`docker-compose.yml`): orchestration only — `include:` directives, 17 secrets, 12 networks. Zero service definitions.
- **31 individual compose files** under `compose/<category>/<service>/docker-compose.yml` — one per service.
- **8 categories**: `ai` (10), `ci` (3), `data` (2), `management` (3), `monitoring` (7), `network` (2), `productivity` (4), `security` (4).
- **Selective startup**: `docker compose --profile <name> up -d` pulls only the relevant include files.

**Infrastructure as Code (Terraform)**
- **Status:** Production-ready
- **Provider:** kreuzwerker/docker v3.x
- **State:** Local backend (terraform/terraform.tfstate)
- **Managed resources:** 6 networks, 16 volumes (22 total)
- **Imported from:** Existing Docker Compose deployment
- **Validation:** `terraform validate`, `terraform plan` shows no drift

**Terraform directory structure:**
```
terraform/
├── providers.tf          # Docker provider configuration
├── variables.tf          # Input variables (domain, timezone, etc.)
├── outputs.tf            # Service URLs and infrastructure summary
├── networks.tf           # 6 Docker networks with lifecycle rules
├── volumes.tf            # 16 named volumes
├── secrets.tf            # Secret file path mappings (non-Swarm)
├── terraform.tfvars      # Environment-specific values
├── modules/
│   └── service/          # Reusable service module
│       ├── main.tf
│       └── outputs.tf
└── services/             # Service definitions by category
    ├── infrastructure.tf # traefik, postgres, redis
    ├── ai-core.tf        # 10 AI services
    ├── security.tf       # 3 security services
    ├── monitoring.tf     # 7 monitoring services
    ├── management.tf     # 3 management services
    ├── ci-cd.tf          # 2 CI/CD services
    ├── productivity.tf   # 2 productivity service
    └── network.tf        # 2 network services
```

**Commands:**
```bash
cd terraform/
terraform init          # Initialize provider
terraform validate      # Validate configuration
terraform plan          # Preview changes
terraform apply         # Deploy infrastructure
terraform output        # View service URLs
```

---

## 2. Infrastructure Inventory

### 2.1 Architecture: Modular Compose

Root `docker-compose.yml` contains **only** `include:` directives, secrets, and networks. No service definitions exist in the root file. Each service is independently defined in its own compose file:

```
compose/
├── ai/
│   ├── agent-zero/docker-compose.yml
│   ├── hermes-agent/docker-compose.yml
│   ├── hermes/docker-compose.yml
│   ├── litellm/docker-compose.yml
│   ├── mcpo/docker-compose.yml
│   ├── ollama/docker-compose.yml
│   ├── omniroute/docker-compose.yml
│   ├── openwebui/docker-compose.yml
│   ├── qdrant/docker-compose.yml
│   └── searxng/docker-compose.yml
├── ci/
│   ├── gitea/docker-compose.yml
│   ├── n8n/docker-compose.yml
│   └── woodpecker/docker-compose.yml
├── data/
│   ├── postgres/docker-compose.yml
│   └── redis/docker-compose.yml
├── management/
│   ├── dockge/docker-compose.yml
│   ├── homepage/docker-compose.yml
│   └── portainer/docker-compose.yml
├── monitoring/
│   ├── cadvisor/docker-compose.yml
│   ├── dozzle/docker-compose.yml
│   ├── grafana/docker-compose.yml
│   ├── loki/docker-compose.yml
│   ├── prometheus/docker-compose.yml
│   ├── promtail/docker-compose.yml
│   └── uptime-kuma/docker-compose.yml
├── network/
│   ├── cloudflared/docker-compose.yml
│   └── traefik/docker-compose.yml
├── productivity/
│   ├── affine/docker-compose.yml
│   ├── guacd/docker-compose.yml
│   ├── guacamole/docker-compose.yml
│   └── plane/docker-compose.yml
└── security/
    ├── authentik-server/docker-compose.yml
    ├── authentik-worker/docker-compose.yml
    └── vaultwarden/docker-compose.yml
```

### 2.2 Service Status

| Metric | Count |
| :--- | :--- |
| Compose files (individual services) | 31 |
| Services running | 31 |
| Services healthy | 26 |
| No healthcheck | 5 (cloudflared, dozzle, loki, portainer, promtail) |

### 2.3 Services by Category

| Category | Services | Profile | Compose files |
| :--- | :--- | :--- | :--- |
| **AI** | agent-zero, hermes-agent, hermes, litellm, mcpo, ollama, omniroute, openwebui, qdrant, searxng | `ai` (default) | 10 |
| **CI/CD** | gitea, n8n, woodpecker | `ci` | 3 |
| **Data** | postgres, redis | — (core) | 2 |
| **Management** | portainer, dockge, homepage | `management` | 3 |
| **Monitoring** | prometheus, grafana, uptime-kuma, loki, promtail, cadvisor, dozzle | `monitoring` | 7 |
| **Network** | traefik, cloudflared | `network` | 2 |
| **Productivity** | affine, guacd, guacamole, plane | `productivity` | 4 |
| **Security** | authentik-server, authentik-worker, authentik, vaultwarden | `security` | 4 |

### 2.4 Compose Profiles (7)

`ai` (default), `security`, `monitoring`, `management`, `ci`, `productivity`, `network`

### 2.5 Docker Networks (12)

`agent-communication`, `ai-ml`, `apps`, `bridge`, `database`, `docker_default`, `host`, `management`, `monitoring`, `none`, `proxy`, `security`

**Bridge iptables rules configured for:** `ai-ml`, `database`, `proxy`

### 2.6 Secret Management

| Metric | Value |
| :--- | :--- |
| Secrets in root docker-compose.yml | 17 |
| Secrets in .env | 0 |
| Secret files on disk | 20 (includes ssh_deploy_key.pub, workspaceId2.txt, omniroute_api_key.txt) |

**All 17 Docker secrets (defined in root docker-compose.yml):**

| Secret | File | Purpose |
| :--- | :--- | :--- |
| `cf_api_email` | cf_api_email.txt | Cloudflare API email (Traefik DNS challenge) |
| `cf_dns_api_token` | cf_dns_api_token.txt | Cloudflare DNS API token |
| `cf_api_key` | cf_api_key.txt | Cloudflare API key |
| `cf_tunnel_token` | cf_tunnel_token.txt | Cloudflare tunnel token |
| `authentik_secret` | authentik_secret.txt | Authentik secret key |
| `hermes_password` | hermes_password.txt | Hermes agent password |
| `github_token` | github_token.txt | GitHub API token |
| `agent_zero_key` | agent_zero_key.txt | Agent Zero API key |
| `gitea_secret` | gitea_secret.txt | Gitea secret |
| `guac_admin_pass` | guac_admin_pass.txt | Guacamole admin password |
| `litellm_key` | litellm_key.txt | LiteLLM master API key |
| `n8n_key` | n8n_key.txt | N8N API key |
| `webui_secret_key` | open_web_ui.txt | Open WebUI secret |
| `vw_admin_token` | vw_admin_token.txt | Vaultwarden admin token |
| `postgres_password` | postgres_password.txt | PostgreSQL password |
| `redis_password` | redis_password.txt | Redis password |
| `ssh_deploy_key` | ssh_deploy_key | SSH deploy key (Ed25519) |

**Additional secret files on disk (not in docker-compose.yml secrets section):**
- `omniroute_api_key.txt` — Omniroute API key (used via env var)
- `ssh_deploy_key.pub` — SSH deploy public key
- `workspaceId2.txt` — Workspace ID reference (empty file)

**Secret consumption pattern:** Services read secrets via `_FILE` env vars (Postgres, Redis, Vaultwarden, etc.) or the entrypoint wrapper script (Traefik, Cloudflared).

### 2.7 Network Binding Policy

All service ports locked to `127.0.0.1` except traefik (ports 80/443 public-facing).

---

## 3. Infrastructure Milestone Matrix

| Module / Capability | Target Vision | Current Status | Next Action Required |
| :--- | :--- | :--- | :--- |
| **Hermes Liaison** | Complete context retention across all multi-project pipelines. | Achieved | `ProjectMemory` module live. JSON-based vector store with search. Upgrade to Qdrant for production scale. |
| **Handshake Protocol** | Strict JSON contract validation before code is executed. | Achieved | REST API `POST /api/v1/tasks` accepts contract JSON. Pydantic validation enforced. |
| **Agent Zero (CEO)** | Dynamic spawning of PM, Dev, and DevOps sub-agent layers via LangGraph. | Achieved | Sub-agents wired to real LLM (LiteLLM), MCP tools (MCPO), and SSH deployment. |
| **Workspace Isolation** | Zero cross-contamination across active Docker/Node stacks. | Achieved | `projects/` directory layout with `.project-manifest.json` template. |
| **Production VM** | Automated, sandbox-verified deployments via DevOps agent. | Achieved | SSH deployer with key-based auth, health-check retry, and auto-rollback. Target VM: vm2 (Ubuntu Server 26.04 WSL). |
| **Audit Trail** | Real-time execution graph, agent registry, and decision logs in `agents/qwen/`. | Achieved | 4 structured audit artifacts written to volume-mounted `AUDIT_DIR`. |
| **REST API** | HTTP interface for Hermes to Agent Zero delegation. | Achieved | FastAPI on port 8081. Endpoints: tasks CRUD, approval, health, projects, memory. |
| **Vector Memory** | Cross-project context retention for LLM injection. | Achieved (JSON) | `ProjectMemory` module with store/retrieve/search. API endpoints for project context. Qdrant running, client integration pending. |
| **Human-in-the-Loop** | Board approval/veto of contracts before execution. | Achieved | LangGraph `interrupt()` wired in `scope_validation_node`. REST API `POST /tasks/{id}/approve`. |

> **Status Keys:** Achieved / Deployed | In Progress / Partial | Pending / Blocker

---

## 4. Known Issues

| Issue | Severity | Impact | Status |
| :--- | :--- | :--- | :--- |
| Traefik Let's Encrypt outbound HTTPS blocked on proxy network | HIGH | TLS certificates cannot be provisioned for automated domain validation | Unresolved |
| Cloudflared QUIC UDP/7844 blocked by WSL2 | MEDIUM | Running in degraded HTTP/2 mode; tunnel functional but suboptimal latency | Unresolved (WSL2 limitation) |
| Authentik middleware not configured for Traefik dashboard | LOW | Dashboard lacks SSO protection via Authentik | Pending configuration |

---

## 5. Completed Milestones (Achieved)

### Directory Architecture Hardening
Host folder `~/docker/agents/qwen` actively bound as the immutable ground-truth audit trail.

### Multi-Agent Architecture Blueprint
Full blueprint documented in `agents/skills/hermes-multi-agent-architecture.md`.

### Framework Selection
**LangGraph** selected over CrewAI and AutoGen for Agent Zero CEO orchestration.

### PoC: CEO Orchestration Graph (Stdlib)
Zero-dependency Python PoC in `agents/qwen/poc/agent_zero/` (6 modules) validated graph topology, contract logic, and audit trail.

### LangGraph Production Migration
Full LangGraph `StateGraph` with 8 nodes, conditional edges, `MemorySaver` checkpointing, and Pydantic contract models in `agents/qwen/agent_zero_langgraph/` (12 modules). 21/21 tests pass.

### Docker Deployment
Custom image `agent-zero-langgraph:latest` with entrypoint wrapper. Container health: healthy. API server runs alongside Agent Zero services via supervisord.

### Phase 5: Full Integration Stack (LLM, MCP, SSH, Memory, API, HITL)
All external services connected. 22/22 Phase 5 tests pass. Live API verification confirms LLM, MCP, SSH, and Memory availability.

### Hermes to Agent Zero Delegation Pipeline
Hermes submits tasks via `POST http://agent-zero:8080/api/v1/tasks`. Watchdog cron polls every 5 minutes. Custom skill teaches Hermes the full API. Test task completed through 7-node graph in 15ms with 4 agents.

### Infrastructure Hardening & Security Remediation
All service ports locked to `127.0.0.1` (except traefik 80/443). Monitoring stack deployed. Compose profiles active. Secret management overhauled: `.env` has 0 secrets, all 17 mounted via Docker secrets.

- Terraform state management with local backend
- Lifecycle ignore_changes for networks (prevent recreation)
- Secret file path mapping without Docker Swarm
- Service module for reusable container definitions

### Deep Validation & SOP Documentation
17/17 containers passed 4-step deep validation pipeline. Stack Security and Operations Guide (`docs/stack-security-operations-guide.md`) — 661 lines.

### MCP Tool Execution Layer Documentation
SOP section 11 codified: MCP server usage, boundary restrictions, execution safety constraints, MCPO bridge architecture, mandatory lock protocol, 4-phase deployment roadmap.

### Production VM SSH Configuration (vm2)
Ubuntu Server 26.04 WSL VM created and reachable via `ssh vm2`. SSH remote authentication configured for `alwazw@vm2`. Deployer wired to `SSH_DEPLOY_HOST=vm2`.

### Modular Compose Architecture
Migrated from monolithic single-file compose to modular composable architecture. Root `docker-compose.yml` contains only `include:` directives, secrets, and networks. 31 services each have their own `compose/<category>/<service>/docker-compose.yml`. Selective startup via compose profiles.

---

## 6. Recent Commit History

| Commit | Description |
| :--- | :--- |
| `5368dfd` | 33 containers up (32 defined + cloudflared-installer) |
| `3daef95` | Fix postgres healthcheck dual fallback |
| `06e566d` | Fix cloudflared outbound + installer cleanup |
| `04cb8bf` | Remove loki healthcheck (scratch image) |
| `950da4d` | Fix hermes network (agent-communication for pypi) |
| `ab0816c` | Final service integration — all 31 services running |
| `82595a4` | Add 16 new services + integration test framework |
| `b009ad0` | Fix critical secret management architecture |
| `6eee469` | Fix inter-container networking |

---

## 7. Current Sprint (In Progress)

### Modular Compose Architecture
**Status:** Completed. All 31 services migrated to individual compose files under `compose/<category>/<service>/`. Root file contains only `include:` directives, secrets, and networks.

### Infrastructure as Code (Terraform)
Infrastructure as Code (Terraform) — 22 resources managed, all imported from existing deployment

### Real Code Generation Pipeline
**Owner:** Qwen (Architecture)
Replace simulated builds with real LLM-generated code, written to project directories via MCP, tested, and committed via MCP Git.
**Status:** LLM client wired to DevAgent. `simulate=false` flag triggers real LLM calls. Code generation works; file persistence via MCP pending.
**Next:** Wire MCP filesystem `write_file` to persist LLM-generated code to `projects/{name}/` directories.

### Upgrade Memory to Qdrant
**Owner:** Qwen (Architecture)
Replace JSON-based memory with Qdrant vector store for semantic search across projects.
**Status:** Qdrant already running in Docker. `ProjectMemory` module has clean interface for swap.
**Next:** Add `qdrant-client` dependency and implement vector embedding for project contexts.

### Omniroute Alibaba Provider Integration
**Owner:** Qwen (Architecture)
Add Alibaba Cloud provider to Omniroute routing layer.
**Status:** API key created (`omniroute_api_key.txt`). Provider configuration pending.
**Next:** Add provider via Omniroute web UI.

---

## 8. Immediate Next Steps (Ordered by Priority)

| # | Item | Status | Details |
| :--- | :--- | :--- | :--- |
| 1 | **MCP Phase 2: Register Filesystem MCP** | Pending | Connect `mcp-server-filesystem` to MCPO bridge for Agent Zero code write persistence. |
| 2 | **MCP File Write Integration** | Pending | Wire DevAgent to write LLM-generated code to project directories via MCP filesystem. |
| 3 | **MCP Git Integration** | Pending | Auto-commit generated code via MCP git server after sandbox verification. |
| 4 | **Qdrant Memory Upgrade** | Pending | Swap JSON memory backend with Qdrant vector store for semantic search. Qdrant running; needs client integration. |
| 5 | **API Authentication** | Pending | Add API key authentication to Agent Zero REST endpoints (required before external access). |
| 6 | **Real SSH Deployment Test** | Pending | Agent Zero DevOps agent deploys to `vm2` via SSH with key-based auth. VM configured, SSH auth ready. |
| 7 | **Observability Wiring** | Pending | Connect Prometheus scrape targets to Grafana dashboards for agent execution monitoring. |
| 8 | **Cloudflared QUIC Fix** | Pending | WSL2 UDP/7844 outbound blocked — investigate workaround or accept degraded HTTP/2 mode. |
| 9 | **Omniroute Alibaba Providers** | Pending | Add via web UI. API key ready. |
| 10 | **CI/CD Pipeline Testing** | Pending | Alpha test parallel validation alongside production processes. Duplicated effort accepted. |
| 11 | **Modular Service Lifecycle Management** | Pending | Test selective startup/shutdown of individual service compose files via profiles. Validate that removing/adding a service compose file works without affecting others. |

---

## 9. Alpha Testing Horizon

**Status:** Environment prepared for parallel validation.

Alpha phase verification tests run alongside production processes. Duplicated effort ensures absolute system reliability. Longer execution reporting times are accepted during this validation phase.

**Prerequisites established:**
- Monitoring stack (Prometheus, Grafana, Uptime Kuma) provides observability for test validation
- Compose profiles enable isolated testing of individual stacks
- Modular compose files allow selective service startup for isolated testing
- Port isolation ensures safe parallel execution without external exposure

**First alpha targets:**
- Hermes to Agent Zero delegation loop (cron-based task submission and polling)
- MCP filesystem write persistence (LLM-generated code committed to project directories)
- API authentication gate (protect endpoints before any remote access configuration)

---

## 10. Architecture Decision Log

| Date | Decision | Options Considered | Rationale |
| :--- | :--- | :--- | :--- |
| 2026-06-14 | **LangGraph** for Agent Zero | LangGraph, CrewAI, AutoGen, Custom Python | State-graph maps to hierarchy; native checkpointing for audit; production-ready |
| 2026-06-14 | **JSON contracts** over Markdown | JSON, Markdown, YAML | Machine-parseable for gate logic; renderable to MD for human audit log |
| 2026-06-14 | **Per-project MCP scoping** | Global MCP with path filters, per-project MCP instances | Hard isolation by design — no cross-contamination at protocol level |
| 2026-06-14 | **24h board veto window** | Immediate auto-approve, 1h, 24h, manual-only | Balances autonomy with oversight; adjustable per-project |
| 2026-06-14 | **Stdlib PoC before LangGraph** | Jump straight to LangGraph, build PoC first | Validates graph topology + contract logic with zero deps; reduces migration risk |
| 2026-06-14 | **AUDIT_DIR env var** | Hardcoded path, config file, env var | Container-portable; configurable per deployment; no code changes needed |
| 2026-06-14 | **Custom Dockerfile** | Extend base image, build from scratch, sidecar | Preserves Agent Zero's existing capabilities; adds LangGraph as overlay |
| 2026-06-14 | **Entrypoint wrapper for API** | Sidecar container, command override, entrypoint | Sidecar adds complexity; command override breaks base CMD; entrypoint is cleanest |
| 2026-06-15 | **FastAPI for REST API** | Flask, FastAPI, Express | Async-native, Pydantic integration, OpenAPI docs auto-generated |
| 2026-06-15 | **JSON-based memory (upgradeable)** | SQLite, Qdrant, JSON files | Zero-dep for MVP; clean interface for Qdrant swap later |
| 2026-06-15 | **Ed25519 SSH keys** | RSA, Ed25519, ECDSA | Modern, fast, smallest key size; standard for automated deployments |
| 2026-06-15 | **127.0.0.1 for all local services** | 0.0.0.0, 127.0.0.1, per-service | Security-first default; only reverse proxy (traefik) needs public binding |
| 2026-06-15 | **Docker Compose profiles** | Single compose file, profiles, separate files | Profiles give selective startup without file proliferation |
| 2026-06-15 | **Docker secrets for all credentials** | .env vars, file mounts, Docker secrets | Zero secrets in .env; all 17 secrets mounted via Docker secrets section |
| 2026-06-15 | **Watchdog cron `--no-agent`** | Full agent cron, no-agent script | Zero LLM cost for monitoring; agent mode reserved for intelligent delegation |
| 2026-06-15 | **Hermes custom skill for delegation** | MCP tool, webhook, REST API skill | Skill approach teaches Hermes the full API; reusable across sessions |
| 2026-06-16 | **Postgres healthcheck dual fallback** | Single healthcheck, dual fallback | Handles both Docker TCP health probe and internal pg_isready |
| 2026-06-16 | **Modular Compose Architecture** | Monolithic single file, include-based modular | Each service gets its own compose file for independent lifecycle management, easier debugging, and selective startup. Root file is pure orchestrator. |

---

## 11. File Index

| Path | Purpose |
| :--- | :--- |
| `agents/qwen/poc/agent_zero/` | Stdlib PoC (zero-dependency reference implementation) |
| `agents/qwen/agent_zero_langgraph/` | LangGraph production implementation (12 modules) |
| `agents/qwen/agent_zero_langgraph/api.py` | FastAPI REST delegation API |
| `agents/qwen/agent_zero_langgraph/api_server.py` | Uvicorn server runner |
| `agents/qwen/agent_zero_langgraph/llm_client.py` | LiteLLM proxy client |
| `agents/qwen/agent_zero_langgraph/mcp_client.py` | MCP tool server client |
| `agents/qwen/agent_zero_langgraph/ssh_deploy.py` | SSH deployment module |
| `agents/qwen/agent_zero_langgraph/memory.py` | Cross-project vector memory (JSON, upgradeable to Qdrant) |
| `agents/qwen/agent_zero_langgraph/tests_phase5.py` | Phase 5 integration tests (22 tests) |
| `agents/qwen/execution-graph.json` | Live graph execution state |
| `agents/qwen/agent-registry.json` | Active sub-agents and their roles |
| `agents/qwen/deployment-log.jsonl` | Append-only deployment event log |
| `agents/qwen/decision-tree.md` | Human-readable decision log per contract |
| `agents/qwen/suggestions-and-upgrades.md` | Triage and upgrade tracking |
| `agents/main-system-gap-analysis.md` | This file — master index |
| `agents/skills/hermes-multi-agent-architecture.md` | Architecture blueprint |
| `docs/stack-security-operations-guide.md` | Stack Security and Operations Guide (SOP) |
| `compose/ai/agent-zero/Dockerfile` | Custom LangGraph image build |
| `compose/ai/agent-zero/docker-compose.yml` | Agent Zero container orchestration config |
| `compose/ai/agent-zero/entrypoint.sh` | Entrypoint wrapper (API server + Agent Zero) |
| `compose/ai/agent-zero/scripts/hermes_delegate.sh` | Hermes watchdog polling script |
| `compose/ai/agent-zero/scripts/agent-zero-skill.md` | Delegation skill source (deployed to Hermes) |
| `compose/<category>/<service>/docker-compose.yml` | Individual service compose files (31 total, one per service) |
| `projects/template/` | Project directory template |
| `secrets/` | All 17+ secret files (no secrets in .env) |
| `docker-compose.yml` | Root orchestrator — `include:` directives only, 17 secrets, 12 networks. Zero service definitions. |
