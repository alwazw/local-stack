# Upgrade Recommendations

> Generated during the repository overhaul on branch `overhaul/swarm-conversion`.
> Date: 2026-06-26

## Executive Summary

This document consolidates findings from the system gap analysis, agent suggestion files (Qwen + Gemini), and the hands-on overhaul. Items are ranked by impact and effort.

---

## Immediate (Do Now)

### 1. Fix authentik-worker healthcheck dependency chain
- **Finding:** Worker heartbeat goes stale after postgres/redis restarts because it has no `depends_on` with health conditions.
- **Effort:** Low (add 5 lines to compose file)
- **Impact:** Prevents authentication service degradation after any database maintenance.

### 2. Lock down exposed port bindings
- **Finding:** postgres (5432), vaultwarden (8082), authentik-server (9000), traefik dashboard (8080) bind to `0.0.0.0`.
- **Effort:** Low (change port prefix in compose files)
- **Impact:** Eliminates direct network exposure for sensitive services.

### 3. Fix WEBUI_SECRET_KEY_FILE
- **Finding:** Commented out in `.env`, causing OpenWebUI to regenerate secrets on every restart.
- **Effort:** Low (uncomment one line)
- **Impact:** Stabilizes user sessions across restarts.

### 4. Correct secret file permissions
- **Finding:** Secret files have 755/644 permissions (world-executable/readable).
- **Effort:** Low (`chmod 600 secrets/*_key.txt secrets/*_token.txt secrets/*_password.txt`)
- **Impact:** Prevents local privilege escalation via secret theft.

---

## Short-Term (This Sprint)

### 5. Add missing healthchecks
- **Finding:** 5 services lack healthchecks: cloudflared, dozzle, loki, portainer, promtail. mcpo also missing one.
- **Effort:** Low (add `healthcheck:` blocks)
- **Impact:** Enables Docker auto-restart on failure; required for `depends_on: condition: service_healthy`.

### 6. Fix PORT_OMNIRUTE typo
- **Finding:** `PORT_OMNIRUTE` should be `PORT_OMNIROUTE`.
- **Effort:** Low (rename in `.env` + affected compose file)
- **Impact:** Improves maintainability; prevents confusion during audits.

### 7. Add API authentication to Agent Zero REST API
- **Finding:** All REST endpoints (`/api/v1/tasks`, etc.) are unprotected.
- **Effort:** Medium (add auth middleware, API key validation)
- **Impact:** Required before any external or cross-service access.

### 8. Fix Hermes base64 password escaping
- **Finding:** Password secret injection may corrupt base64-encoded values.
- **Effort:** Low (fix escaping in entrypoint or compose env)
- **Impact:** Ensures Hermes authentication works reliably.

### 9. Fix Authentik DB volume permissions
- **Finding:** PostgreSQL permission denied on volume data.
- **Effort:** Low (add init script or volume ownership fix)
- **Impact:** Prevents database startup failures.

---

## Medium-Term (Next Sprint)

### 10. Upgrade memory backend from JSON to Qdrant
- **Finding:** `ProjectMemory` uses JSON files; Qdrant is already running but not integrated.
- **Effort:** Medium (add `qdrant-client`, rewrite store/retrieve interface)
- **Impact:** Enables semantic search across projects; scales beyond file-count limits.

### 11. Deploy monitoring stack (Prometheus + Grafana + Loki)
- **Finding:** `.env` defines ports for monitoring services; none are deployed.
- **Effort:** Medium (compose files exist, need network wiring)
- **Impact:** Provides observability dashboards; replaces `docker logs` debugging.

### 12. Migrate OpenWebUI from bind mount to named volume
- **Finding:** Bind mount to `/mnt/d/docker` causes WSL2 SQLite WAL performance issues.
- **Effort:** Medium (data migration + compose change)
- **Impact:** Improves OpenWebUI database performance and reliability.

### 13. Standardize port binding format
- **Finding:** Mix of `0.0.0.0:${PORT}:X` and `${PORT}:X` makes security auditing harder.
- **Effort:** Low (batch replace across compose files)
- **Impact:** Consistent, auditable security posture.

### 14. Implement backup strategy
- **Finding:** No automated backups for PostgreSQL, Redis, OpenWebUI, or Vaultwarden.
- **Effort:** Medium (backup scripts + cron, or `offen/docker-volume-backup` container)
- **Impact:** Data loss prevention.

---

## Long-Term (Future Initiatives)

### 15. Docker Swarm multi-node expansion
- **Finding:** Currently single-node WSL2. Swarm conversion done but multi-node not yet enabled.
- **Effort:** High (provision additional VM hosts, configure overlay network, test ingress)
- **Impact:** Horizontal scalability, high availability, rolling updates.
- **Note:** WSL2 ingress limitation requires host-mode port publishing for external access.

### 16. MCP Git integration
- **Finding:** Agent-generated code not automatically committed.
- **Effort:** Medium (wire MCP git server, add post-verification commit hook)
- **Impact:** Full automation of code generation pipeline.

### 17. Hermes cron delegation finalization
- **Finding:** Automated task submission and polling not fully wired.
- **Effort:** Medium (finalize cron schedule, add error handling)
- **Impact:** Autonomous task delegation without manual triggers.

### 18. Omniroute Alibaba provider
- **Finding:** API key created but provider not configured.
- **Effort:** Low (web UI configuration)
- **Impact:** Multi-provider LLM routing with cost optimization.

---

## Resolved During Overhaul

| Item | Resolution |
|---|---|
| Duplicate gap analysis files | Consolidated into `agents/main-system-gap-analysis.md` (master) |
| Duplicate suggestion files | Merged into `agents/suggestions-and-upgrades.md` |
| Flat audit trail files | Organized into `agents/qwen/audit-trails/YYYY-MM-DD/` |
| Empty directories | Removed: `agents/gemini/skills/`, `compose/ai/agent-zero/work_dir/`, `compose/ai/litellm/config/workflows/` |
| No ADR documentation | Created 4 ADRs in `docs/adr/` |
| Disorganized docs | Moved operational guides to `docs/guides/` |
