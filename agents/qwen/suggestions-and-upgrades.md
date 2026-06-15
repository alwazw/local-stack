# 🗺️ AEF3 Stack — Triage & Upgrade Tracking

> **Purpose:** Living governance document for the Autonomous Engineer Framework v3 stack.
> All findings triaged strictly by impact: **[HIGH PRIORITY]**, **[MEDIUM PRIORITY]**, or **[LOW PRIORITY]**.
>
> **Maintained by:** Qwen Agent  
> **Created:** 2026-06-15  
> **Last updated:** 2026-06-15

---

## 🔴 HIGH PRIORITY

### 1. authentik-worker unhealthy for 2+ hours
- **Status:** Active issue
- **Observed:** `docker compose ps` shows `authentik-worker Up 5 hours (unhealthy)`. Healthcheck reports "Worker hasn't updated heartbeat in threshold" with delta >2800s.
- **Impact:** Authentik's Celery worker is not processing tasks (user cleanup, LDAP sync, OAuth updates). SSO/authentication flows will fail or stall.
- **Root cause:** Worker process is alive but Celery heartbeat is stale. Likely caused by postgres/redis restart breaking the worker's connection without auto-recovery.
- **Fix:** `docker compose restart authentik-worker` or recreate. Add `depends_on` with `condition: service_healthy` for postgres and redis.
- **File:** `docker-compose.yml` — `authentik-worker` service

### 2. postgres exposed on all interfaces (0.0.0.0:5432)
- **Status:** Active security risk
- **Observed:** `docker inspect postgres` shows `"HostIp":""` (binds to 0.0.0.0).
- **Impact:** PostgreSQL with password auth is accessible from any network interface. On WSL2 with Docker Desktop, this may be reachable from the Windows host or other WSL instances.
- **Fix:** Change port binding to `"127.0.0.1:${PORT_POSTGRES}:5432"`.
- **File:** `docker-compose.yml` — `postgres` service, `ports` section

### 3. vaultwarden exposed on all interfaces (0.0.0.0:8082)
- **Status:** Active security risk
- **Observed:** `docker inspect vaultwarden` shows `"HostIp":""`.
- **Impact:** Password manager accessible from any interface before authentication is configured.
- **Fix:** Change to `"127.0.0.1:${PORT_VAULTWARDEN}:80"`.
- **File:** `docker-compose.yml` — `vaultwarden` service

### 4. authentik-server exposed on all interfaces (0.0.0.0:9000)
- **Status:** Active security risk
- **Observed:** `docker inspect authentik-server` shows `"HostIp":""`.
- **Impact:** Identity provider admin UI accessible from any interface.
- **Fix:** Change to `"127.0.0.1:${PORT_AUTHENTIK}:9000"`.
- **File:** `docker-compose.yml` — `authentik-server` service

### 5. WEBUI_SECRET_KEY_FILE not set in .env
- **Status:** Active misconfiguration
- **Observed:** `.env` has `# WEBUI_SECRET_KEY_FILE=...` (commented out). Every `docker compose` command warns: `"WEBUI_SECRET_KEY_FILE" variable is not set`.
- **Impact:** OpenWebUI generates a new secret key on every restart, invalidating all sessions. Users get logged out randomly.
- **Fix:** Uncomment the line or generate a new key: `WEBUI_SECRET_KEY_FILE=${DATA_ROOT}/secrets/open_web_ui.txt`
- **File:** `.env`

### 6. Insecure secret file permissions
- **Status:** Active security risk
- **Observed:** Several files in `secrets/` have `755` (world-executable) or `644` (world-readable) permissions:
  - `agent_zero_key.txt` — 755
  - `github_token.txt` — 755
  - `open_web_ui.txt` — 755
  - `ssh_deploy_key.pub` — 644
- **Impact:** Any local user or compromised process can read API keys, tokens, and deploy keys.
- **Fix:** `chmod 600 secrets/*_key.txt secrets/*_token.txt secrets/*_password.txt secrets/*_key.txt` and `chmod 644 secrets/*.pub`
- **Files:** `secrets/`

### 7. Traefik dashboard exposed without auth on 0.0.0.0:8080
- **Status:** Active security risk
- **Observed:** Traefik's `8080:8080` port binding exposes the dashboard API on all interfaces. The dashboard label references `authentik@docker` middleware, but that only applies to the Traefik router (HTTPS path), not the direct port 8080 access.
- **Impact:** Unauthenticated access to Traefik dashboard reveals all service configurations, routes, and middleware.
- **Fix:** Either bind to `127.0.0.1:8080:8080` or add basic auth middleware to the dashboard.
- **File:** `docker-compose.yml` — `traefik` service, `ports` section

---

## 🟡 MEDIUM PRIORITY

### 8. No Docker Compose profiles for selective startup
- **Status:** Architectural gap
- **Observed:** `docker compose up -d` starts all 14 services. On a dev machine, this consumes significant resources (RAM, CPU).
- **Impact:** Slow startup, high memory usage, no way to run just AI stack or just security stack.
- **Fix:** Add `profiles:` to services:
  - `ai` — ollama, litellm, openwebui, hermes, hermes-agent, omniroute, agent-zero, mcpo
  - `security` — authentik-server, authentik-worker, vaultwarden
  - `infra` — traefik, postgres, redis
  - Core infra (postgres, redis, traefik) should have no profile (always start)
- **File:** `docker-compose.yml`

### 9. No monitoring/observability stack deployed
- **Status:** Missing capability
- **Observed:** `.env` defines ports for `PORT_GRAFANA=3003`, `PORT_PROMETHEUS=9090`, `PORT_LOKI=3100`, `PORT_UPTIME=3002` — none are in `docker-compose.yml`.
- **Impact:** No visibility into service health, resource usage, or uptime. Debugging relies on `docker logs` only.
- **Fix:** Deploy Prometheus + Grafana + optionally Loki for log aggregation and Uptime Kuma for health monitoring.
- **Files:** `docker-compose.yml`, `compose/monitoring/` (new)

### 10. OpenWebUI data stored as bind mount (inconsistency)
- **Status:** Inconsistency
- **Observed:** `openwebui` uses `./compose/ai/openwebui/data:/app/backend/data` (bind mount) while most other services use named volumes.
- **Impact:** Bind mounts to `/mnt/d/docker` on WSL2 have known performance issues with SQLite WAL files. OpenWebUI's `webui.db` and `chroma.sqlite3` are both affected.
- **Fix:** Migrate to named volume `openwebui_data:/app/backend/data` and move existing data.
- **File:** `docker-compose.yml` — `openwebui` service

### 11. Hermes homepage labels use `https://` but localhost is `http://`
- **Status:** Cosmetic/configuration drift
- **Observed:** Hermes labels: `homepage.href=https://hermes.${DOMAIN}` — but direct localhost access is `http://localhost:8787`.
- **Impact:** Homepage dashboard links will be broken for local development until DNS + TLS is configured.
- **Fix:** Use `http://${DOMAIN}:${PORT_HERMES}` for localhost-friendly URLs (matching agent-zero's pattern).
- **File:** `docker-compose.yml` — `hermes` service, `labels` section

### 12. agent-zero image may be stale
- **Status:** Potential staleness
- **Observed:** `agent-zero` uses `frdel/agent-zero:latest`. The upstream project has low activity. The custom `agent_zero_langgraph` code in `compose/ai/agent-zero/` builds its own image but isn't referenced in the root compose.
- **Impact:** May be running an outdated base image. The custom LangGraph layer is not deployed.
- **Fix:** Verify upstream image freshness. Consider switching to the custom-built image defined in `compose/ai/agent-zero/Dockerfile`.
- **Files:** `docker-compose.yml`, `compose/ai/agent-zero/Dockerfile`

### 13. Missing healthcheck on mcpo
- **Status:** Reliability gap
- **Observed:** `mcpo` service has no `healthcheck:` block. It shows `Up 35 hours` with no health status indicator.
- **Impact:** Docker won't auto-restart mcpo if it becomes unresponsive. Dependent services (agent-zero) can't detect mcpo failures.
- **Fix:** Add healthcheck: `curl -f http://localhost:8000/docs` or similar.
- **File:** `docker-compose.yml` — `mcpo` service

### 14. authentik-worker missing `depends_on` with health conditions
- **Status:** Reliability gap
- **Observed:** `authentik-worker` has no `depends_on` block. When postgres or redis restarts, the worker's Celery connection breaks and the heartbeat goes stale (see HIGH PRIORITY #1).
- **Impact:** Worker becomes unhealthy after any database/redis restart.
- **Fix:** Add `depends_on: { postgres: { condition: service_healthy }, redis: { condition: service_healthy } }`.
- **File:** `docker-compose.yml` — `authentik-worker` service

### 15. Many PORT_ vars defined for un-deployed services
- **Status:** Forward planning / cleanup
- **Observed:** `.env` defines ports for services not yet in `docker-compose.yml`:
  - `PORT_HOMEPAGE=3004`, `PORT_SEARXNG=8080`, `PORT_GRAFANA=3003`
  - `PORT_PROMETHEUS=9090`, `PORT_LOKI=3100`, `PORT_UPTIME=3002`
  - `PORT_GITEA=3001`, `PORT_N8N=5678`, `PORT_PORTAINER=9443`
  - `PORT_GUACAMOLE=8081`, `PORT_WOODPECKER=8001`, `PORT_DOCKGE=5001`
  - `PORT_AFFINE=8083`, `PORT_LOGSEQ=8084`, `PORT_PLANE=8085`
- **Impact:** No harm, but indicates planned services that may need deployment.
- **Fix:** Deploy priority services (monitoring stack first). Clean up unused vars if plans change.
- **File:** `.env`

---

## 🟢 LOW PRIORITY

### 16. PORT_OMNIRUTE typo
- **Status:** Cosmetic
- **Observed:** `PORT_OMNIRUTE` in `.env` — should be `PORT_OMNIROUTE`.
- **Impact:** No functional impact, but confusing for maintenance.
- **Fix:** Rename variable and update all references. Requires updating both `.env` and `docker-compose.yml`.
- **Files:** `.env`, `docker-compose.yml`

### 17. Inconsistent port binding format
- **Status:** Style inconsistency
- **Observed:** Some services use `"0.0.0.0:${PORT}:X"` (agent-zero, ollama), others use `"${PORT}:X"` (litellm, hermes, omniroute, postgres). Both work, but the implicit binding differs.
- **Impact:** No functional impact, but harder to audit security posture.
- **Fix:** Standardize on `"127.0.0.1:${PORT}:X"` for all services in local dev, `"0.0.0.0:${PORT}:X"` only for production-facing services.
- **File:** `docker-compose.yml`

### 18. No .env.example documentation
- **Status:** Onboarding gap
- **Observed:** `.env.example` exists but may not document all variables. No README explaining what each variable does.
- **Impact:** New contributors or future-you won't understand the configuration.
- **Fix:** Generate `.env.example` from current `.env` with comments explaining each section.
- **File:** `.env.example`

### 19. Named volumes vs bind mounts inconsistency
- **Status:** Architectural inconsistency
- **Observed:** Mix of named volumes (`hermes_home`, `omniroute_data`, `authentik_media`) and bind mounts (`./compose/ai/openwebui/data`, `./compose/data/postgres/data`, `./compose/security/vaultwarden/data`).
- **Impact:** Named volumes are more portable and avoid WSL2 filesystem performance issues. Bind mounts are easier for direct file access.
- **Fix:** Standardize: use named volumes for application data (databases, caches), bind mounts for config files and code.
- **File:** `docker-compose.yml`

### 20. No backup strategy for persistent data
- **Status:** Operational gap
- **Observed:** No cron jobs, scripts, or automation for backing up PostgreSQL, Redis, OpenWebUI, or Vaultwarden data.
- **Impact:** Data loss risk if volumes are corrupted or accidentally deleted.
- **Fix:** Add backup scripts and schedule via cron or a dedicated backup container (e.g., `offen/docker-volume-backup`).
- **Files:** `scripts/` (new), `docker-compose.yml`

---

## 📋 Remediation Order

Execute in this order for maximum impact:

1. **Fix authentik-worker** — restart or recreate (#1, #14)
2. **Lock down port bindings** — postgres, vaultwarden, authentik, traefik dashboard (#2, #3, #4, #7)
3. **Fix WEBUI_SECRET_KEY_FILE** — uncomment in .env (#5)
4. **Fix secret permissions** — chmod 600 (#6)
5. **Add compose profiles** — enable selective startup (#8)
6. **Deploy monitoring stack** — Prometheus + Grafana (#9)
7. **Migrate OpenWebUI to named volume** (#10)
8. **Add healthcheck to mcpo** (#13)
9. **Fix cosmetic issues** — typo, labels, consistency (#11, #16, #17)
10. **Document and backup** (#18, #20)

---

## 📌 Quick Reference: Port Security Audit

| Service | Current Binding | Recommended | Risk |
|---|---|---|---|
| postgres | `0.0.0.0:5432` | `127.0.0.1:5432` | HIGH — DB exposed |
| vaultwarden | `0.0.0.0:8082` | `127.0.0.1:8082` | HIGH — passwords exposed |
| authentik | `0.0.0.0:9000` | `127.0.0.1:9000` | HIGH — IdP exposed |
| traefik dashboard | `0.0.0.0:8080` | `127.0.0.1:8080` | HIGH — routes exposed |
| redis | `127.0.0.1:6379` | ✅ Correct | OK |
| litellm | `0.0.0.0:4000` | `127.0.0.1:4000` | MEDIUM — API key needed |
| openwebui | `0.0.0.0:3000` | `127.0.0.1:3000` | MEDIUM — no auth yet |
| hermes | `0.0.0.0:8787` | `127.0.0.1:8787` | MEDIUM — password only |
| omniroute | `0.0.0.0:20128` | `127.0.0.1:20128` | MEDIUM — API key off |
| ollama | `0.0.0.0:11434` | `127.0.0.1:11434` | LOW — no secrets |
| mcpo | `0.0.0.0:8000` | `127.0.0.1:8000` | LOW — internal tool |
| agent-zero | `0.0.0.0:8501` | `127.0.0.1:8501` | LOW — internal tool |
| traefik (80/443) | `0.0.0.0:80,443` | Keep 0.0.0.0 | OK — reverse proxy |
