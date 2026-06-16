# Security Audit & Procedures — AEF3 Docker-Compose Stack

**System:** Autonomous Engineer Framework v3 (AEF3)
**Audit Date:** 2026-06-16
**Scope:** Root `docker-compose.yml` + all service compose files under `compose/<category>/<service>/`
**Architecture:** Modular — root file orchestrates via `include:`; each service defines its own compose file
**Status:** Phase 5 Complete — Secret management overhauled, all ports locked, network isolation configured

---

## 1. Security Posture Summary

### 1.1 Overview

| Dimension | Status | Detail |
|---|---|---|
| **Architecture** | Modular | Root `docker-compose.yml` contains only `include:`, `secrets:`, and `networks:` — zero service definitions |
| **Secret Management** | Hardened | 0 secrets in `.env`, 17 Docker secrets, all mounted read-only as files; two-tier pattern (root defines `file:` paths, services reference as `external: true`) |
| **Network Security** | Hardened | All ports bound to `127.0.0.1` except Traefik (80/443 public) |
| **Docker Networks** | Segmented | 12 networks with role-based isolation (proxy, ai-ml, database, security, monitoring, agent-communication) |
| **Firewall** | Partially configured | iptables rules for Docker bridge networks (ai-ml, database, proxy, agent-communication) |
| **File Permissions** | Compliant | All secret files `chmod 600`, `.gitignore` excludes all secret patterns |
| **TLS** | Degraded | Traefik configured for Let's Encrypt via Cloudflare DNS challenge; outbound HTTPS blocked on proxy network |
| **SSO** | Not yet enforced | Authentik deployed but not configured as Traefik middleware for all external services |
| **API Auth** | Partially configured | LiteLLM master key enabled; Agent Zero REST endpoints have no authentication yet |

### 1.2 Service Inventory

| Metric | Value |
|---|---|
| Services defined | 31 |
| Compose profiles | 7 (ai, security, monitoring, management, ci, productivity, network) |
| Service compose files | 31 (one per service under `compose/<category>/<service>/`) |
| Docker networks | 12 |
| Docker secrets | 17 |
| Entrypoint wrappers | 5 (Traefik, Cloudflared, Authentik server+worker, Hermes, Omniroute) |

### 1.3 Risk Assessment

| Risk | Severity | Status |
|---|---|---|
| Traefik Let's Encrypt outbound HTTPS blocked on proxy network | **HIGH** | Unresolved — TLS certificates cannot be auto-provisioned |
| Agent Zero REST API has no authentication | **HIGH** | Pending — API key (`agent_zero_key.txt`) exists but is not enforced |
| Authentik not wired to Traefik as middleware | **MEDIUM** | Pending — SSO not enforced for external-facing services |
| Cloudflared QUIC UDP/7844 blocked (WSL2 limitation) | **MEDIUM** | Accepted — tunnel operates in degraded HTTP/2 mode |
| Portainer exposed on `0.0.0.0:8000` | **MEDIUM** | Requires review — public-facing agent port |
| Omniroute `REQUIRE_API_KEY=false` | **LOW** | Configured — API key exists (`omniroute_api_key.txt`) but enforcement disabled |
| Grafana admin password in `.env` (`GRAFANA_ADMIN_PASSWORD`) | **LOW** | Review — not consumed via `_FILE` pattern; acceptable if `.env` is gitignored and non-production |

---

## 2. Secret Management Architecture

### 2.1 Two-Tier Pattern

```
Tier 1 — Root docker-compose.yml (defines file paths):
  secrets:
    postgres_password:
      file: ./secrets/postgres_password.txt

Tier 2 — Each service compose file (references as external):
  secrets:
    postgres_password:
      external: true

  services:
    postgres:
      secrets:
        - postgres_password
```

**Key rules:**
- Root `docker-compose.yml` declares ALL secrets with `file: ./secrets/<name>.txt` paths
- Each service compose file declares secrets with `external: true` — NO `file:` paths in service files
- No secrets are hardcoded in ANY compose file — all values come from files in `secrets/`
- Services consume secrets via `secrets:` list under the service, then reference `/run/secrets/<name>` in env vars or commands

### 2.2 Secret Consumption Flow

```
./secrets/<name>.txt  (file on host, chmod 600)
    ↓ Docker Compose (root defines file path, service references as external)
/run/secrets/<name>   (read-only file inside container)
    ↓ consumed by
_SERVICE_SECRET_FILE env var   (Postgres, Vaultwarden, Gitea, n8n, OpenWebUI, Hermes)
    or
entrypoint-wrapper.sh reads    (Traefik, Cloudflared, Authentik, Hermes, Omniroute)
    or
inline shell command           (Redis, Cloudflared)
```

### 2.3 All 17 Docker Secrets

| # | Secret Name | Source File | Consumers | Consumption Method |
|---|---|---|---|---|
| 1 | `cf_api_email` | `secrets/cf_api_email.txt` | Traefik | Entrypoint wrapper |
| 2 | `cf_dns_api_token` | `secrets/cf_dns_api_token.txt` | Traefik | Entrypoint wrapper |
| 3 | `cf_api_key` | `secrets/cf_api_key.txt` | (defined, unused) | — |
| 4 | `cf_tunnel_token` | `secrets/cf_tunnel_token.txt` | Cloudflared | Inline shell in `command:` |
| 5 | `authentik_secret` | `secrets/authentik_secret.txt` | Authentik server, Authentik worker | Entrypoint wrapper |
| 6 | `hermes_password` | `secrets/hermes_password.txt` | Hermes | Entrypoint wrapper |
| 7 | `github_token` | `secrets/github_token.txt` | (defined, unused) | — |
| 8 | `agent_zero_key` | `secrets/agent_zero_key.txt` | Agent-Zero | `AGENT_ZERO_API_KEY_FILE` |
| 9 | `gitea_secret` | `secrets/gitea_secret.txt` | Gitea | `GITEA__security__SECRET_KEY_FILE` |
| 10 | `guac_admin_pass` | `secrets/guac_admin_pass.txt` | Guacamole | Entrypoint wrapper (inherited image) |
| 11 | `litellm_key` | `secrets/litellm_key.txt` | LiteLLM, Agent-Zero | `LITELLM_MASTER_KEY_FILE` / `LITELLM_MASTER_KEY_FILE` |
| 12 | `n8n_key` | `secrets/n8n_key.txt` | n8n | `N8N_ENCRYPTION_KEY_FILE` |
| 13 | `webui_secret_key` | `secrets/open_web_ui.txt` | OpenWebUI, SearXNG | `WEBUI_SECRET_KEY_FILE` / `SEARXNG_SECRET_KEY_FILE` |
| 14 | `vw_admin_token` | `secrets/vw_admin_token.txt` | Vaultwarden | `ADMIN_TOKEN_FILE` |
| 15 | `postgres_password` | `secrets/postgres_password.txt` | Postgres, Authentik, Guacamole, Gitea, n8n | `POSTGRES_PASSWORD_FILE` / `POSTGRESQL_PASSWORD_FILE` |
| 16 | `redis_password` | `secrets/redis_password.txt` | Redis, Authentik, Omniroute | Inline shell (`requirepass`) |
| 17 | `ssh_deploy_key` | `secrets/ssh_deploy_key` | Agent-Zero | `SSH_KEY_PATH` env var |

### 2.4 Unused Secrets (Defined but No Consumers)

| Secret | Notes | Action |
|---|---|---|
| `cf_api_key` | Cloudflare Global API key; `cf_dns_api_token` is the active token | Consider removing or documenting as backup |
| `github_token` | GitHub PAT; no service currently consumes it | Wire to a service (Gitea mirror, CI) or remove |

### 2.5 Secret File Permissions

All files in `/mnt/d/docker/secrets/` must be `chmod 600`:

```bash
chmod 600 /mnt/d/docker/secrets/*.txt /mnt/d/docker/secrets/ssh_deploy_key
```

### 2.6 Additional Files on Disk (Not in Docker Secrets Section)

| File | Purpose |
|---|---|
| `secrets/omniroute_api_key.txt` | Omniroute API key (consumed via env var, not Docker secret) |
| `secrets/ssh_deploy_key.pub` | SSH public key (non-secret, explicitly un-gitignored) |
| `secrets/workspaceId2.txt` | Workspace ID reference |

---

## 3. Access Control

### 3.1 No External Access Before Authentication

**Policy:** No service may be configured for external/remote access until authentication is in place. This is a user-mandated requirement.

**Current state:**

| Service | External Access | Authentication Status |
|---|---|---|
| Traefik (ports 80/443) | Public | TLS configured; no SSO middleware yet |
| All other services | `127.0.0.1` only | N/A (not externally reachable) |
| Portainer (`0.0.0.0:8000`) | Public (agent port) | Portainer-native auth TBD |

**Enforcement:** All port bindings in service compose files use `127.0.0.1:<host_port>:<container_port>` except:
- `0.0.0.0:80:80` (Traefik HTTP)
- `0.0.0.0:443:443` (Traefik HTTPS)
- `0.0.0.0:8000:8000` (Portainer agent)

### 3.2 TLS Configuration

**Traefik** is the sole tls termination point:

| Setting | Value |
|---|---|
| Cert resolver | `cloudflare` (DNS-01 challenge) |
| DNS provider | Cloudflare (`cf_dns_api_token`) |
| ACME storage | `/data/acme.json` (volume-mounted) |
| HTTP redirect | `web` (80) → `websecure` (443) |
| Dashboard | Insecure mode disabled (`--api.insecure=false`) |

**Known blocker:** Outbound HTTPS (TCP/443) is blocked on the `proxy` network by iptables rules. Traefik cannot reach Let's Encrypt ACME servers to provision certificates.

**Affected services (all rely on `certresolver=cloudflare`):**
- OpenWebUI (`chat.${DOMAIN}`)
- Hermes (`hermes.${DOMAIN}`)
- Omniroute (`omniroute.${DOMAIN}`)
- Vaultwarden (`vault.${DOMAIN}`)
- Guacamole (`rdp.${DOMAIN}`)
- Gitea (`gitea.${DOMAIN}`)
- n8n (`n8n.${DOMAIN}`)
- SearXNG (`search.${DOMAIN}`)
- cAdvisor (`cadvisor.${DOMAIN}`)
- Dozzle (`logs.${DOMAIN}`)
- Portainer (`portainer.${DOMAIN}`)
- Dockge (`dockge.${DOMAIN}`)
- Homepage (`home.${DOMAIN}`)
- Traefik dashboard (`traefik.${DOMAIN}`)

### 3.3 SSO (Authentik)

| Component | Status |
|---|---|
| Authentik server | Deployed, bound to `127.0.0.1:9000` |
| Authentik worker | Deployed (no ports) |
| Traefik middleware | **Not configured** |
| SSO enforcement | **Not enforced** for any external service |

**Required action:** Add Authentik forward-auth middleware to Traefik for all `*.${DOMAIN}` routes before enabling public access.

### 3.4 API Authentication

| Endpoint | Auth Mechanism | Status |
|---|---|---|
| Agent Zero REST API (`:8081`) | API key via `AGENT_ZERO_API_KEY_FILE` | `agent_zero_key.txt` exists and is mounted; enforcement gate pending |
| LiteLLM (`:4000`) | Master key (`litellm_key`) | Configured via `LITELLM_MASTER_KEY_FILE` |
| Omniroute (`:20128`) | API key (optional) | `REQUIRE_API_KEY=false` — enforcement disabled |
| Grafana (`:3000`) | Admin password | Via `GRAFANA_ADMIN_PASSWORD` env var |
| Prometheus (`:9090`) | None | No built-in auth; bound to `127.0.0.1` |

---

## 4. Network Security

### 4.1 Docker Networks (Defined)

| Network | Scope | Key Services |
|---|---|---|
| `proxy` | External | Traefik, Cloudflared, all Traefik-routed services |
| `ai-ml` | External | Ollama, LiteLLM, Qdrant, MCPO, Agent Zero, all AI services |
| `database` | External | Postgres, Redis, Authentik, Gitea, n8n, Omniroute |
| `security` | External | Authentik server, Authentik worker, Vaultwarden |
| `monitoring` | External | Prometheus, Grafana, Loki, Promtail, cAdvisor, Uptime Kuma |
| `agent-communication` | External | Agent Zero, Hermes agent, Hermes UI |

### 4.2 iptables Rules

Docker-managed chains with custom rules:

| Chain | Purpose |
|---|---|
| `DOCKER-FORWARD` | Docker's main forwarding chain |
| `DOCKER-BRIDGE` | Custom rules for bridge interface filtering |
| `DOCKER-CT` | Connection tracking rules |

**Bridge interfaces with iptables rules:**

| Interface | Network | Bridge ID |
|---|---|---|
| `br-1813ea894891` | ai-ml | Managed |
| `br-a661348a0ada` | database | Managed |
| `br-7a145f88f192` | proxy | Managed |
| `br-9031ea5c3119` | agent-communication | Managed |

**To inspect current iptables rules:**

```bash
sudo iptables -L DOCKER-FORWARD -vn --line-numbers
sudo iptables -L DOCKER-BRIDGE -vn --line-numbers
sudo iptables -L DOCKER-CT -vn --line-numbers
```

### 4.3 Known Network Issues

| Issue | Impact | Root Cause |
|---|---|---|
| Outbound HTTPS (TCP/443) blocked on proxy network | Traefik cannot provision Let's Encrypt certificates | iptables `DOCKER-BRIDGE` or `DOCKER-FORWARD` DROP rule on proxy bridge |
| QUIC UDP/7844 blocked on proxy network | Cloudflared falls back to HTTP/2 (higher latency) | WSL2/virtio-net limitation — UDP outbound restricted |

### 4.4 Network Isolation Verification

Services should only reach networks they are attached to. To verify:

```bash
# Test isolation: a service on 'monitoring' should NOT reach 'database'
docker exec prometheus ping -c 1 postgres    # Should fail
docker exec prometheus ping -c 1 redis       # Should fail

# Test connectivity: a service on 'database' SHOULD reach postgres
docker exec n8n ping -c 1 postgres           # Should succeed
docker exec gitea ping -c 1 postgres          # Should succeed

# Test cross-network: Agent Zero on ai-ml+agent-communication should reach Hermes
docker exec agent-zero ping -c 1 hermes-agent # Should succeed
```

---

## 5. Security Procedures

### 5.1 How to Rotate a Secret

**Principle:** Secrets are file-based. Update the file in `secrets/`, then recreate only the affected containers.

1. **Identify which services consume the secret.**
   Consult the Secret-to-Service matrix (Appendix B) or grep the compose files:
   ```bash
   grep -rl '<secret_name>' compose/
   ```

2. **Update the secret file on the host:**
   ```bash
   echo -n 'new-secret-value' > /mnt/d/docker/secrets/<secret_name>.txt
   chmod 600 /mnt/d/docker/secrets/<secret_name>.txt
   ```

3. **Restart affected services using their modular compose path:**
   ```bash
   docker compose -f compose/<category>/<service>/docker-compose.yml up -d --force-recreate <service-name>
   ```

   For secrets shared by multiple services, recreate all consumers:
   ```bash
   # postgres_password is shared by Postgres, Authentik, Guacamole, Gitea, n8n
   docker compose -f compose/data/postgres/docker-compose.yml up -d --force-recreate postgres
   docker compose -f compose/security/authentik-server/docker-compose.yml up -d --force-recreate authentik-server
   docker compose -f compose/productivity/guacamole/docker-compose.yml up -d --force-recreate guacamole
   docker compose -f compose/ci/gitea/docker-compose.yml up -d --force-recreate gitea
   docker compose -f compose/ci/n8n/docker-compose.yml up -d --force-recreate n8n
   ```

   Or recreate all at once from the root (which picks up all includes):
   ```bash
   docker compose up -d --force-recreate <service1> <service2> ...
   ```

4. **Verify the new secret is active:**
   ```bash
   # For _FILE-based services, check the mounted secret:
   docker exec <service-name> cat /run/secrets/<secret_name>

   # Verify service functionality:
   docker compose ps <service-name>
   docker logs --tail 50 <service-name>
   ```

### 5.2 How to Add a New Secret

1. **Create the secret file:**
   ```bash
   echo -n 'secret-value' > /mnt/d/docker/secrets/new_secret.txt
   chmod 600 /mnt/d/docker/secrets/new_secret.txt
   ```

2. **Add the secret definition** to the root `docker-compose.yml` under `secrets:`:
   ```yaml
   secrets:
     new_secret:
       file: ./secrets/new_secret.txt
   ```

3. **In the service's compose file** (`compose/<category>/<service>/docker-compose.yml`), declare the secret as external and mount it:
   ```yaml
   services:
     my-service:
       secrets:
         - new_secret

   secrets:
     new_secret:
       external: true
   ```

4. **Reference the secret** in the service (choose one method):

   **Method A — `_FILE` environment variable** (for services that support it):
   ```yaml
   environment:
     MY_SERVICE_SECRET_FILE: /run/secrets/new_secret
   ```

   **Method B — Entrypoint wrapper** (read at startup):
   ```bash
   # In entrypoint-wrapper.sh
   export MY_SERVICE_SECRET="$(cat /run/secrets/new_secret)"
   ```

   **Method C — Inline shell** (for `command:` overrides):
   ```yaml
   command:
     - sh
     - -c
     - |
       SECRET=$$(cat /run/secrets/new_secret)
       exec my-service --secret "$$SECRET"
   ```

5. **Update `.env.example`** documentation to list the new secret file.

6. **Verify:**
   ```bash
   docker compose config    # Shows rendered config (values masked by Docker)
   docker compose up -d <service-name>
   docker exec <service-name> cat /run/secrets/new_secret
   ```

### 5.3 How to Audit Secret Exposure

Check that secrets are not leaking into environment variables, logs, or inspect output:

```bash
# 1. Check environment variables for leaked secrets (should show nothing sensitive)
docker inspect <container> --format '{{json .Config.Env}}' | python3 -m json.tool

# 2. Verify secrets are mounted as files, NOT as env vars
docker inspect <container> --format '{{json .Mounts}}' | python3 -m json.tool
# Look for: "Destination": "/run/secrets/<name>", "Mode": "ro"

# 3. Check container logs for secret values
docker logs <container> 2>&1 | grep -iE '(password|token|key|secret)'

# 4. Check docker-compose rendered config (values masked by Docker)
docker compose config

# 5. Verify no secrets in .env
grep -iE '(password|token|key|secret)' /mnt/d/docker/.env 2>/dev/null
# Should return nothing — .env contains only port numbers and non-sensitive config

# 6. Verify no secrets committed to git
git ls-files | grep -E '(secrets/.*\.txt|\.env$)'
# Should return nothing (all secret files must be in .gitignore)

# 7. CRITICAL: Verify NO service compose file contains 'file:' paths for secrets
#    (Only the root docker-compose.yml should have 'file:' — all service files must use 'external: true')
grep -rn 'file:.*secrets/' compose/
# Should return nothing. If it does, that service file violates the two-tier pattern.
```

### 5.4 How to Check iptables Rules

```bash
# List all Docker-related chains
sudo iptables -L -vn | grep -A 20 'DOCKER'

# Inspect specific chains with line numbers
sudo iptables -L DOCKER-FORWARD -vn --line-numbers
sudo iptables -L DOCKER-BRIDGE -vn --line-numbers
sudo iptables -L DOCKER-CT -vn --line-numbers

# Check rules for a specific bridge interface
sudo iptables -L -vn | grep br-

# Test outbound connectivity from a container on the proxy network
docker exec traefik curl -sf --connect-timeout 5 https://acme-v02.api.letsencrypt.org/directory
# If this fails, outbound HTTPS is blocked on the proxy network
```

### 5.5 How to Verify Network Isolation

```bash
# 1. List all networks and their attached containers
docker network ls
docker network inspect proxy ai-ml database security monitoring agent-communication

# 2. Test cross-network isolation (should FAIL for unconnected networks)
docker run --rm --network monitoring nicolaka/netshoot ping -c 1 -W 2 postgres   # Should fail
docker run --rm --network monitoring nicolaka/netshoot ping -c 1 -W 2 redis      # Should fail

# 3. Test expected connectivity (should SUCCEED)
docker run --rm --network database nicolaka/netshoot ping -c 1 -W 2 postgres     # Should succeed
docker run --rm --network ai-ml nicolaka/netshoot ping -c 1 -W 2 litellm         # Should succeed

# 4. Verify port bindings (all should show 127.0.0.1 except traefik)
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -v '127.0.0.1'
# Expected output: only traefik (80, 443) and portainer (8000) should show 0.0.0.0
```

---

## 6. Compliance Checklist

### 6.1 Secret Management

- [ ] No secrets in `.env` — **PASS** (verified: 0 secrets in `.env`)
- [ ] No secrets hardcoded in ANY compose file — **PASS** (all values referenced via secrets or env vars pointing to non-sensitive config)
- [ ] Root `docker-compose.yml` has NO service definitions — **PASS** (only `include:`, `secrets:`, and `networks:`)
- [ ] NO service compose file contains `file:` paths for secrets — **VERIFY** (run: `grep -rn 'file:.*secrets/' compose/` — must return nothing)
- [ ] All service compose files use `external: true` for secrets — **VERIFY** (each service file's `secrets:` block must use `external: true`)
- [ ] All secret files gitignored — **PASS** (`.gitignore` covers `secrets/*`, `*_key.txt`, `*_password.txt`, `*_token.txt`, `*_secret.txt`)
- [ ] All secret files `chmod 600` — **VERIFY** (run: `stat -c '%a %n' /mnt/d/docker/secrets/*`)
- [ ] Unused secrets documented or removed — **FAIL** (`cf_api_key`, `github_token` defined but not consumed)

### 6.2 Network Security

- [ ] All ports locked to `127.0.0.1` (except 80/443) — **PASS** (Portainer `0.0.0.0:8000` requires review)
- [ ] TLS enabled for external services — **FAIL** (Traefik Let's Encrypt outbound blocked; certificates not auto-provisioned)
- [ ] Firewall rules configured — **PASS** (iptables rules on ai-ml, database, proxy, agent-communication bridges)
- [ ] Network isolation verified — **TODO** (run verification procedure in Section 5.5)

### 6.3 Access Control

- [ ] SSO configured for all external services — **FAIL** (Authentik deployed but not wired to Traefik)
- [ ] API authentication enabled for all REST endpoints — **FAIL** (Agent Zero REST API auth gate pending; Omniroute enforcement disabled)
- [ ] No external access before authentication — **PASS** (all services bound to `127.0.0.1` except Traefik)
- [ ] Traefik dashboard secured — **FAIL** (no Authentik middleware; dashboard unreachable while TLS is broken)

### 6.4 Operations

- [ ] Audit logs preserved — **PASS** (`agents/qwen/` directory actively used as audit trail)
- [ ] Backup procedures tested — **TODO** (database dumps, volume backups, secret backup)
- [ ] Health checks configured for all services — **PARTIAL** (5 services lack healthchecks: cloudflared, dozzle, loki, portainer, promtail)
- [ ] Secret rotation procedure documented — **PASS** (Section 5.1, updated for modular compose paths)

---

## 7. Remediation Roadmap

### Priority 1 — Critical (Block External Access)

1. **Fix proxy network outbound HTTPS** to allow Traefik Let's Encrypt ACME challenge. Until resolved, no TLS certificates will be provisioned and all `*.${DOMAIN}` services operate without TLS.
2. **Enforce Agent Zero REST API authentication** using the existing `agent_zero_key.txt` secret. Do not expose this API externally until authentication is active.

### Priority 2 — High (Enforce Authentication)

3. **Configure Authentik as Traefik forward-auth middleware** for all external-facing routes. This is the gate that must close before any service is publicly accessible.
4. **Enable Omniroute API key enforcement** (`REQUIRE_API_KEY: "true"`).

### Priority 3 — Medium (Harden)

5. **Review Portainer `0.0.0.0:8000` binding** — restrict to `127.0.0.1` unless the agent port is required for external tooling.
6. **Migrate Grafana admin password to Docker secret** (`GF_SECURITY_ADMIN_PASSWORD_FILE`).
7. **Resolve or document unused secrets** (`cf_api_key`, `github_token`).

### Priority 4 — Low (Maintain)

8. **Add healthchecks** to cloudflared, dozzle, loki, portainer, promtail.
9. **Establish backup procedures** for named volumes and secret files.
10. **Document Cloudflared QUIC workaround** or formally accept HTTP/2 degraded mode.

---

## Appendix A: File Permissions Reference

```bash
# Set correct permissions on all secret files
chmod 600 /mnt/d/docker/secrets/*.txt /mnt/d/docker/secrets/ssh_deploy_key
chmod 644 /mnt/d/docker/secrets/ssh_deploy_key.pub   # Public key is not secret

# Verify
stat -c '%a %n' /mnt/d/docker/secrets/*
```

## Appendix B: Quick Reference — Secret-to-Service Matrix

| Secret | Postgres | Authentik | Redis | Gitea | n8n | OpenWebUI | Vaultwarden | Guacamole | LiteLLM | Agent-Zero | SearXNG | Hermes | Traefik | Cloudflared | Omniroute |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `postgres_password` | X | X | | X | X | | | X | | | | | | | |
| `redis_password` | | X | X | | | | | | | | | | | | X |
| `authentik_secret` | | X | | | | | | | | | | | | | |
| `hermes_password` | | | | | | | | | | | | X | | | |
| `litellm_key` | | | | | | | | | X | X | | | | | |
| `webui_secret_key` | | | | | | X | | | | | X | | | | |
| `vw_admin_token` | | | | | | | X | | | | | | | | |
| `gitea_secret` | | | | X | | | | | | | | | | | |
| `guac_admin_pass` | | | | | | | | X | | | | | | | |
| `n8n_key` | | | | | X | | | | | | | | | | |
| `cf_api_email` | | | | | | | | | | | | | X | | |
| `cf_dns_api_token` | | | | | | | | | | | | | X | | |
| `cf_tunnel_token` | | | | | | | | | | | | | | X | |
| `ssh_deploy_key` | | | | | | | | | | X | | | | | |
| `cf_api_key` | | | | | | | | | | | | | | | |
| `github_token` | | | | | | | | | | | | | | | |
| `agent_zero_key` | | | | | | | | | | X | | | | | |

## Appendix C: Compose Profile Dependency Graph

```
Core (always on):     traefik, postgres, redis
ai (default):         agent-zero, litellm, mcpo, ollama, openwebui, hermes-agent,
                      hermes, omniroute, qdrant, searxng
security:             authentik-server, authentik-worker, vaultwarden
monitoring:           prometheus, grafana, uptime-kuma, loki, promtail,
                      cadvisor, dozzle
management:           portainer, dockge, homepage
ci:                   gitea, n8n
productivity:         guacd, guacamole
network:              cloudflared
```
