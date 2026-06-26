# Stack Triage & Upgrade Tracking

> **Purpose:** Consolidated governance document for the Autonomous Engineer Framework v3 stack.
> Merged from agents/qwen/suggestions-and-upgrades.md and agents/gemini/suggestions-and-upgrades.md.
> All findings triaged by impact: **[HIGH PRIORITY]**, **[MEDIUM PRIORITY]**, or **[LOW PRIORITY]**.
>
> **Last updated:** 2026-06-26

---

## HIGH PRIORITY

### 1. authentik-worker unhealthy — heartbeat stale
- **Impact:** Celery worker not processing tasks (user cleanup, LDAP sync, OAuth updates). SSO/authentication flows will fail or stall.
- **Root cause:** Worker process alive but Celery heartbeat stale, likely from postgres/redis restart breaking connection without auto-recovery.
- **Fix:** Restart/recreate worker. Add `depends_on` with `condition: service_healthy` for postgres and redis.
- **Source:** Qwen triage #1 + #14

### 2. Port bindings exposed on all interfaces (0.0.0.0)
- **Affected services:** postgres (5432), vaultwarden (8082), authentik-server (9000), traefik dashboard (8080)
- **Impact:** Database, password manager, IdP admin UI, and routing config accessible from any network interface.
- **Fix:** Change all to `127.0.0.1:${PORT}:target`.
- **Source:** Qwen triage #2, #3, #4, #7

### 3. WEBUI_SECRET_KEY_FILE commented out in .env
- **Impact:** OpenWebUI generates a new secret key on every restart, invalidating all sessions.
- **Fix:** Uncomment or generate a new key: `WEBUI_SECRET_KEY_FILE=${DATA_ROOT}/secrets/open_web_ui.txt`
- **Source:** Qwen triage #5

### 4. Insecure secret file permissions
- **Affected files:** `agent_zero_key.txt` (755), `github_token.txt` (755), `open_web_ui.txt` (755), `ssh_deploy_key.pub` (644)
- **Impact:** Any local user or compromised process can read API keys and tokens.
- **Fix:** `chmod 600` for private secrets, `chmod 644` for `.pub` files only.
- **Source:** Qwen triage #6

### 5. Hardcoded credentials in .env and compose files
- **Impact:** Credentials visible in version control and environment dumps.
- **Fix:** Global remediation — migrate all hardcoded strings to Docker secrets or external secret manager.
- **Source:** Gemini triage

### 6. Hermes password evaluation — base64 escaping
- **Impact:** Secret injection may corrupt password values.
- **Fix:** Fix base64 string escaping and secret injection logic.
- **Source:** Gemini triage

### 7. Authentik DB volume permissions
- **Impact:** PostgreSQL permission denied error on volume data.
- **Fix:** Correct volume ownership/permissions in entrypoint or init script.
- **Source:** Gemini triage

---

## MEDIUM PRIORITY

### 8. No Docker Compose profiles for selective startup
- **Impact:** `docker compose up -d` starts all services, consuming significant resources on dev machines.
- **Fix:** Add `profiles:` to service groups: `ai`, `security`, `infra` (core services without profile).
- **Source:** Qwen triage #8

### 9. No monitoring/observability stack deployed
- **Impact:** No visibility into service health, resource usage, or uptime. Debugging relies on `docker logs` only.
- **Fix:** Deploy Prometheus + Grafana + Loki for log aggregation and Uptime Kuma for health monitoring.
- **Source:** Qwen triage #9

### 10. OpenWebUI data stored as bind mount (WSL2 performance)
- **Impact:** Bind mounts to `/mnt/d/docker` on WSL2 have known performance issues with SQLite WAL files.
- **Fix:** Migrate to named volume `openwebui_data:/app/backend/data`.
- **Source:** Qwen triage #10

### 11. Hermes homepage labels use `https://` but localhost is `http://`
- **Impact:** Homepage dashboard links broken for local development until DNS + TLS configured.
- **Fix:** Use `http://${DOMAIN}:${PORT_HERMES}` for localhost-friendly URLs.
- **Source:** Qwen triage #11

### 12. agent-zero image may be stale
- **Impact:** Running outdated base image; custom LangGraph layer not deployed.
- **Fix:** Verify upstream freshness. Consider switching to custom-built image in `compose/ai/agent-zero/Dockerfile`.
- **Source:** Qwen triage #12

### 13. Missing healthcheck on mcpo
- **Impact:** Docker won't auto-restart mcpo if unresponsive. Dependent services can't detect failures.
- **Fix:** Add healthcheck: `curl -f http://localhost:8000/docs`.
- **Source:** Qwen triage #13

### 14. API authentication for Agent Zero REST API
- **Impact:** Endpoints unprotected before external access configuration.
- **Fix:** Add API key authentication to all REST endpoints.
- **Source:** Gemini triage

### 15. Memory upgrade — JSON to Qdrant
- **Impact:** JSON-based `ProjectMemory` lacks semantic search capabilities for production scale.
- **Fix:** Transition to Qdrant vector store. Qdrant already running; needs client integration.
- **Source:** Gemini triage

### 16. Many PORT_ vars defined for un-deployed services
- **Impact:** No functional harm, but indicates planned services that may need deployment or cleanup.
- **Fix:** Deploy priority services (monitoring stack first). Clean up unused vars if plans change.
- **Source:** Qwen triage #15

---

## LOW PRIORITY

### 17. PORT_OMNIRUTE typo
- **Fix:** Rename to `PORT_OMNIROUTE` in `.env` and all references.
- **Source:** Qwen triage #16

### 18. Inconsistent port binding format
- **Impact:** Harder to audit security posture when mixing `0.0.0.0:${PORT}:X` and `${PORT}:X`.
- **Fix:** Standardize on `127.0.0.1:${PORT}:X` for local dev.
- **Source:** Qwen triage #17

### 19. No .env.example documentation
- **Impact:** New contributors won't understand variable purposes.
- **Fix:** Generate `.env.example` with comments explaining each section.
- **Source:** Qwen triage #18

### 20. Named volumes vs bind mounts inconsistency
- **Fix:** Standardize: named volumes for application data, bind mounts for config/code.
- **Source:** Qwen triage #19

### 21. No backup strategy for persistent data
- **Impact:** Data loss risk if volumes are corrupted or accidentally deleted.
- **Fix:** Add backup scripts or dedicated backup container (e.g., `offen/docker-volume-backup`).
- **Source:** Qwen triage #20

### 22. Hermes cron delegation
- **Fix:** Finalize automated task submission and polling.
- **Source:** Gemini triage

### 23. MCP Git integration
- **Fix:** Fully automate commits after sandbox verification.
- **Source:** Gemini triage

---

## Remediation Order

1. Fix authentik-worker (#1, #14 from original)
2. Lock down port bindings (#2 from original)
3. Fix WEBUI_SECRET_KEY_FILE (#3 from original)
4. Fix secret permissions (#4 from original)
5. Remove hardcoded credentials (#5 from original)
6. Fix Hermes password base64 escaping (#6 from original)
7. Fix Authentik DB volume permissions (#7 from original)
8. Add compose profiles (#8 from original)
9. Deploy monitoring stack (#9 from original)
10. Add healthcheck to mcpo (#13 from original)
11. Add API auth to Agent Zero (#14 from original)
12. Migrate OpenWebUI to named volume (#10 from original)
13. Fix cosmetic issues (#17, #16 from original)
14. Document and backup (#19, #21 from original)

---

## Quick Reference: Port Security Audit

| Service | Current Binding | Recommended | Risk |
|---|---|---|---|
| postgres | `0.0.0.0:5432` | `127.0.0.1:5432` | HIGH |
| vaultwarden | `0.0.0.0:8082` | `127.0.0.1:8082` | HIGH |
| authentik | `0.0.0.0:9000` | `127.0.0.1:9000` | HIGH |
| traefik dashboard | `0.0.0.0:8080` | `127.0.0.1:8080` | HIGH |
| redis | `127.0.0.1:6379` | Already correct | OK |
| traefik (80/443) | `0.0.0.0:80,443` | Keep 0.0.0.0 | OK — reverse proxy |

---

## Audit Trail

### 2026-06-14: Gemini Initialization
- Established baseline understanding of Phase 5 LangGraph infrastructure.
- Validated system state against `main-system-gap-analysis.md`.
- Mapped to Master Plan Phase 5 validation and transition.

### 2026-06-15: Qwen Deep Validation
- 20-item triage produced after deep validation pipeline.
- Port security audit table compiled from `docker inspect` output.
- Remediation order established by impact severity.

### 2026-06-26: Consolidation
- Merged Qwen and Gemini suggestion files into single document.
- Deduplicated overlapping items (monitoring, API auth, memory upgrade).
- Preserved source attribution for each finding.
