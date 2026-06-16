# AEF3 Project Roadmap

**Autonomous Engineer Framework v3** — Multi-agent AI system with Hermes (PM) and Agent Zero (CEO) delegation, autonomous code generation, testing, and deployment.

> **Last updated:** 2026-06-16
> **Status:** Active development — Phase 5 complete, Code Generation pipeline in progress

---

## 1. Vision

Build a fully autonomous engineering workflow where a multi-agent AI system can:

1. **Plan** — Hermes (Project Manager) receives high-level instructions, decomposes them into actionable tasks, and delegates to Agent Zero (CEO).
2. **Execute** — Agent Zero orchestrates DevAgent and other specialist agents to generate, test, and deploy code autonomously via MCP tools.
3. **Validate** — Deep validation pipelines verify deployments go beyond `docker ps` — log scrutiny, stability observation, port compliance, and completion gates.
4. **Learn** — Agent memory evolves from static JSON files to Qdrant-backed vector embeddings for semantic retrieval and context-aware decision-making.
5. **Deploy** — Secure SSH-based deployment to production VMs with secret management, healthchecks, and observability dashboards.

### Core Principles

| Principle | Description |
|-----------|-------------|
| **Delegation over Centralization** | Hermes plans, Agent Zero executes — no single agent does everything |
| **Secrets Never in .env** | All 17 credentials managed via Docker secrets with `_FILE` environment variable patterns |
| **Validation over Assumption** | Every deployment verified through multi-step runtime validation, not just container status |
| **Profile-based Activation** | Services start selectively via Docker Compose profiles, not all-or-nothing |
| **Secure-by-default Networking** | `agent-communication` bridge for inter-container traffic, iptables rules for external access |

---

## 2. Completed Milestones

### Phase 5 — Full Integration Stack (2026-06-15)

| Milestone | Date | Commit | Notes |
|-----------|------|--------|-------|
| Phase 5 Full Integration (LLM, MCP, SSH, Memory, API, HITL) | 2026-06-15 | — | LLM integration, MCP tool layer, SSH deployment, memory system, REST API, human-in-the-loop |
| LangGraph Production Migration | 2026-06-15 | — | Migrated from CrewAI/AutoGen to LangGraph for graph-based agent orchestration |
| Hermes → Agent Zero Delegation Pipeline | 2026-06-15 | — | Full delegation pipeline with **43/43 integration tests passing** |
| Infrastructure Hardening & Security Remediation | 2026-06-15 | — | Security posture improvements across all services |
| Deep Validation & SOP Documentation | 2026-06-15 | — | Standard operating procedures and validation pipelines documented |
| MCP Tool Execution Layer Documentation | 2026-06-15 | — | MCP tool server architecture and execution flow documented |
| Production VM SSH Configuration | 2026-06-15 | — | vm2 (Ubuntu 26.04 WSL) configured for SSH-based deployment |

### Infrastructure & Networking (2026-06-15)

| Milestone | Date | Commit | Notes |
|-----------|------|--------|-------|
| Service Integration Expansion | 2026-06-15 | `ab0816c` | Scaled from 17 to **31 services** — observability, CI/CD, knowledge base, auth stack |
| Docker Network Connectivity Fix | 2026-06-15 | `6eee469` | iptables rules applied for 3 bridge networks restoring inter-container connectivity |
| Hermes Network Fix | 2026-06-15 | `950da4d` | Connected Hermes to `agent-communication` bridge for pypi.org access |
| Cloudflared Tunnel Deployment | 2026-06-15 | `06e566d` | HTTP/2 fallback tunnel for external access (QUIC blocked by WSL2) |
| Postgres Healthcheck Fix | 2026-06-15 | `3daef95` | Dual fallback healthcheck resolving postgres startup race conditions |

### Security & Secrets (2026-06-15)

| Milestone | Date | Commit | Notes |
|-----------|------|--------|-------|
| Secret Management Architecture Overhaul | 2026-06-15 | `b009ad0` | **Zero secrets in `.env`** — 17 credentials migrated to Docker secrets with entrypoint wrappers |

---

## 3. Current Sprint

| # | Initiative | Status | Blockers | Owner |
|---|-----------|--------|----------|-------|
| 1 | **Real Code Generation Pipeline** | In Progress | MCP Filesystem server registration | Agent Zero |
| 2 | **Upgrade Memory to Qdrant** | In Progress | Qdrant client integration in agents | DevAgent |
| 3 | **Omniroute Alibaba Provider Integration** | In Progress | UI setup for provider configuration | Agent Zero |

### Detail: Real Code Generation Pipeline

The pipeline flow: **LLM generates code → MCP writes files → MCP commits to Git**

- **LLM Code Generation**: Agent Zero invokes LLM (via Omniroute/Alibaba) to produce code artifacts
- **MCP File Write**: Code written to project directories via MCP Filesystem server (pending registration)
- **MCP Git Commit**: Changes auto-committed via MCP git server (pending integration)

### Detail: Qdrant Memory Upgrade

- **Current**: Agent memory stored as flat JSON files
- **Target**: Vector embeddings in Qdrant for semantic search and context retrieval
- **Status**: Qdrant service is running; agent-side client integration remains

### Detail: Omniroute Alibaba Provider

- **Current**: API keys created and configured
- **Remaining**: UI setup for provider selection and routing configuration

---

## 4. Planned Work

### Critical — Next 1–2 Weeks

| # | Initiative | Description | Dependencies | Success Criteria |
|---|-----------|-------------|--------------|------------------|
| 1 | **MCP Phase 2: Filesystem Registration** | Register Filesystem MCP server to the MCPO bridge | MCPO bridge running | Filesystem tools visible to agents |
| 2 | **MCP File Write Integration** | Enable DevAgent to write code to project directories via MCP | #1 complete | Agent can create/modify files in target directories |
| 3 | **MCP Git Integration** | Auto-commit generated code via MCP git server | #2 complete | Code changes committed to repo without manual intervention |
| 4 | **API Authentication: Agent Zero REST Endpoints** | Expose Agent Zero capabilities via authenticated REST API | Agent Zero running | External systems can invoke Agent Zero via REST |

### High Priority — Next 2–4 Weeks

| # | Initiative | Description | Dependencies | Success Criteria |
|---|-----------|-------------|--------------|------------------|
| 5 | **Qdrant Memory Upgrade** | Migrate agent memory from JSON files to vector embeddings in Qdrant | Qdrant client integration | Semantic memory queries return relevant context |
| 6 | **Real SSH Deployment Test** | End-to-end deployment: Agent Zero → vm2 via SSH | Code generation pipeline (#1–#3) | Code deployed to vm2 without manual steps |
| 7 | **Observability Wiring** | Connect Prometheus metrics to Grafana dashboards | Prometheus + Grafana running | Dashboards show real service metrics |
| 8 | **Authentik Middleware** | Configure Authentik SSO for Traefik-protected dashboards | Authentik + Traefik running | SSO login to monitoring dashboards |

### Medium Priority — Next 1–2 Months

| # | Initiative | Description | Dependencies | Success Criteria |
|---|-----------|-------------|--------------|------------------|
| 9 | **Traefik Let's Encrypt Fix** | Resolve proxy network outbound blocking preventing TLS certificate acquisition | Docker network config | Traefik obtains valid LE certificates |
| 10 | **Cloudflared QUIC Fix** | Resolve UDP 7844 blocking (WSL2 network limitation) | WSL2 network stack | QUIC protocol operational (not just HTTP/2 fallback) |
| 11 | **CI/CD Pipeline Testing** | Alpha test parallel validation — run CI/CD alongside production | Woodpecker + Gitea configured | Alpha tests pass without impacting production |
| 12 | **Homepage Dashboard Configuration** | Auto-discovery of services via Docker labels on Homepage dashboard | Homepage running | All services visible and status-tracked automatically |

### Low Priority — Future

| # | Initiative | Description | Current Status |
|---|-----------|-------------|----------------|
| 13 | **Woodpecker CI** | Self-hosted CI/CD pipeline | Needs Gitea OAuth setup |
| 14 | **Plane** | Open-source project management (Linear alternative) | Requires additional configuration |
| 15 | **Affine** | Collaborative knowledge base (Notion alternative) | Needs PostgreSQL migrations completed |
| 16 | **Logseq / AppFlowy** | Desktop-first knowledge and productivity apps | No official Docker images available |

---

## 5. Architecture Decisions Log

| Date | Decision | Alternatives Considered | Rationale |
|------|----------|------------------------|-----------|
| 2026-06-15 | **LangGraph for agent orchestration** | CrewAI, AutoGen | LangGraph provides explicit graph-based control flow, better suited for the Hermes → Agent Zero delegation pattern with deterministic state transitions |
| 2026-06-15 | **Docker secrets over .env for all credentials** | `.env` files, external vault | Docker secrets are encrypted in transit and at rest, scoped to specific services, and eliminated all 17 secrets from `.env` |
| 2026-06-15 | **Entrypoint wrappers for services without `_FILE` support** | Config file templating, custom Dockerfiles | Lightweight entrypoint scripts convert Docker secrets to `_FILE` environment variables without forking upstream images |
| 2026-06-15 | **Profile-based startup for selective service activation** | All-or-nothing `docker compose up`, multiple compose files | Docker Compose profiles allow operators to start only the services needed for a given task (e.g., `ai-agents`, `observability`, `ci-cd`) |
| 2026-06-15 | **`agent-communication` bridge for inter-container connectivity** | Default bridge, host networking | Dedicated bridge isolates agent traffic, enables fine-grained iptables rules, and supports the Hermes → Agent Zero → DevAgent communication pattern |

---

## 6. Metrics Dashboard

### Infrastructure Health

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Services defined | 31 | — | — |
| Services running | 31 | 100% | Pass |
| Services healthy | 27 | 100% | 87% |
| Healthcheck coverage | 90% (27/30 runtime) | 100% | Good |
| Secret coverage | 100% (17/17) | 100% | Pass |
| Network connectivity | 100% inter-container | 100% | Pass (post-iptables fix) |

### Test Coverage

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Integration tests passing | 43/43 | 100% | Pass |
| Delegation pipeline tests | 43/43 | 100% | Pass |

### Secret Management

| Metric | Value | Notes |
|--------|-------|-------|
| Secrets in `.env` | 0 | Zero-trust baseline achieved |
| Docker secrets configured | 17 | All credentials via `docker secret` |
| Entrypoint wrappers deployed | As needed | Services without native `_FILE` support |

---

## 7. Risk Register

| ID | Risk | Impact | Likelihood | Mitigation | Owner | Status |
|----|------|--------|------------|------------|-------|--------|
| R1 | **Traefik cannot obtain TLS certificates** due to proxy network outbound blocking | High | Medium | Restart Docker Desktop; add iptables rules for DNS/HTTPS outbound | Infrastructure | Open |
| R2 | **Cloudflared operating in degraded mode** — HTTP/2 fallback only, QUIC unavailable | Medium | High | WSL2 UDP limitation; monitor for WSL kernel updates that resolve UDP 7844 | Infrastructure | Accepted |
| R3 | **Secret rotation complexity** — manual rotation across 17 Docker secrets | Medium | Low | Documented rotation procedures; shared secret mapping table | Security | Mitigated |
| R4 | **WSL2 network instability** — bridge networks drop after host sleep/resume | High | Medium | iptables persistence rules; network reconnect scripts in `scripts/` | Infrastructure | Mitigated |
| R5 | **Postgres data loss** — multiple services depend on shared Postgres instance | Critical | Low | Automated `pg_dump` backups; volume mount verification | Data | Mitigated |
| R6 | **MCP server registration failures** — Filesystem/git servers fail to register on MCPO bridge | High | Medium | Fallback to direct file/git operations; healthcheck on MCPO bridge | Development | Open |
| R7 | **Code generation produces invalid artifacts** — LLM output fails syntax or logic checks | Medium | Medium | Pre-commit validation gates; unit test generation alongside code | Development | Open |

### Risk Heat Map

```
Impact
  Critical |        R5
  High     |   R1       R4
  Medium   |        R2        R3  R6  R7
           +--------------------------------
              Low    Medium    High
                    Likelihood
```

---

## Appendix A: Service Inventory

### AI Agents (Profile: `ai-agents`)

| Service | Role | Health |
|---------|------|--------|
| `hermes` | Project Manager — receives instructions, delegates tasks | Healthy |
| `agent-zero` | CEO — orchestrates specialist agents, executes plans | Healthy |
| `agent-dev` | Developer — generates and modifies code | Healthy |
| `mcp-tools` | MCP tool server bridge | Healthy |
| `qdrant` | Vector database for agent memory | Healthy |

### Infrastructure (Profile: `infrastructure`)

| Service | Role | Health |
|---------|------|--------|
| `traefik` | Reverse proxy and load balancer | Healthy |
| `cloudflared` | Secure tunnel for external access | Healthy (HTTP/2) |
| `authentik` | Identity provider and SSO | Healthy |
| `postgres` | Primary database | Healthy |
| `redis` | Cache and message broker | Healthy |

### Observability (Profile: `observability`)

| Service | Role | Health |
|---------|------|--------|
| `prometheus` | Metrics collection | Healthy |
| `grafana` | Dashboards and visualization | Healthy |
| `alertmanager` | Alert routing | Healthy |
| `homepage` | Service status dashboard | Healthy |

### CI/CD (Profile: `ci-cd`)

| Service | Role | Health |
|---------|------|--------|
| `gitea` | Self-hosted Git server | Healthy |
| `woodpecker` | CI/CD pipeline | Config pending |

### Knowledge & Productivity (Profile: `productivity`)

| Service | Role | Health |
|---------|------|--------|
| `plane` | Project management | Config pending |
| `affine` | Collaborative knowledge base | Migration pending |

---

## Appendix B: Quick Reference

### Network Topology

```
                    ┌─────────────────────┐
                    │   agent-communication │  ← Inter-agent bridge
                    │  (172.20.0.0/16)     │
                    └──┬─────────┬────────┬──┘
                       │         │        │
                  ┌────┴───┐ ┌──┴────┐ ┌─┴──────┐
                  │Hermes  │ │Agent  │ │DevAgent│
                  │(PM)    │ │Zero   │ │        │
                  │        │ │(CEO)  │ │        │
                  └────────┘ └───────┘ └────────┘

  ┌──────────────────┐    ┌──────────────────┐
  │  frontend (Traefik) │    │   monitoring     │
  │  :80, :443          │    │  :3000 (Grafana) │
  └──────────────────┘    └──────────────────┘
```

### Profile Activation

```bash
# Start AI agents only
docker compose --profile ai-agents up -d

# Start observability stack
docker compose --profile observability up -d

# Start everything
docker compose --profile ai-agents --profile observability --profile infrastructure up -d
```

### Secret Rotation

```bash
# Rotate a Docker secret
echo "new-value" | docker secret create my_secret -
# Update service to use new secret version
docker compose up -d <service>
```

---

*This roadmap is a living document. Update after each milestone completion or sprint review.*
