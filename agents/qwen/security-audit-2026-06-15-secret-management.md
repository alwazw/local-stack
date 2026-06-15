# Security Audit: Secret Management Architecture

**Date:** 2026-06-15
**Auditor:** Qwen (Architecture)
**Scope:** All services in AEF3 docker-compose stack
**Trigger:** Critical security violation — secrets passed as file paths instead of values

---

## Critical Finding: Previous Architecture Was Fundamentally Broken

### What Was Wrong

The `.env` file contained **file paths as values** for secrets:
```
CF_DNS_API_TOKEN=/home/alwazw/docker/secrets/cf_dns_api_token.txt
CF_API_KEY=/home/alwazw/docker/secrets/cf_api_key.txt
LITELLM_MASTER_KEY_FILE=/home/alwazw/docker/secrets/litellm_key.txt
REDIS_PASSWORD=PzH4sqKhZKzwGVBYpu3S5S6f742n6vXZtA4O8LHTQUI=
AUTHENTIK_SECRET_KEY=5HcPEkNgrQOaXhpH5Tp/SaSXdDHQHU7511OLWd/W8x4=
GRAFANA_ADMIN_PASSWORD=admin
```

When Docker Compose substituted these, services received **literal file path strings** instead of the actual secret values.

### Impact
- **Traefik:** Cloudflare API received the path string `/home/alwazw/docker/secrets/cf_dns_api_token.txt` as the DNS token → `400 Invalid format for X-Auth-Key header`
- **LiteLLM:** Master key was set to a file path → API authentication broken
- **All services with hardcoded passwords:** Passwords in `.env` visible to any process that can read the file
- **Rate limiting:** Let's Encrypt rate-limited the domain due to repeated failed ACME challenges

---

## Corrected Architecture

### Principles

1. **`.env` file contains ZERO secrets** — only non-sensitive configuration (ports, domains, hostnames)
2. **All secrets are files** in `./secrets/*.txt` with restrictive permissions (`chmod 600`)
3. **Docker Compose `secrets:` section** mounts secrets at `/run/secrets/<name>` inside containers
4. **Services read secrets via:**
   - `_FILE` environment variable suffix (Postgres, LiteLLM, OpenWebUI, Vaultwarden)
   - Entrypoint wrapper scripts (Traefik, Authentik, Hermes, Omniroute)
   - Inline shell commands (Redis)

### Secret Flow Diagram

```
secrets/*.txt (host, chmod 600)
    ↓ Docker Compose secrets: section
/run/secrets/<name> (container, read-only)
    ↓
Service reads via:
  - _FILE env var (native support)
  - Entrypoint wrapper (no native support)
  - Inline shell command (simple cases)
```

### Services and Their Secret Handling

| Service | Secret(s) | Method | Notes |
| :--- | :--- | :--- | :--- |
| **Traefik** | `cf_api_email`, `cf_dns_api_token` | Entrypoint wrapper | Reads files, exports `CF_API_EMAIL`, `CF_DNS_API_TOKEN` |
| **Cloudflared** | `cf_tunnel_token` | Entrypoint wrapper | Reads file, passes as `--token` arg |
| **LiteLLM** | `litellm_key` | `_FILE` env var | `LITELLM_MASTER_KEY_FILE=/run/secrets/litellm_key` |
| **OpenWebUI** | `webui_secret_key` | `_FILE` env var | `WEBUI_SECRET_KEY_FILE=/run/secrets/webui_secret_key` |
| **Postgres** | `postgres_password` | `_FILE` env var | `POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password` |
| **Redis** | `redis_password` | Inline shell | `redis-server --requirepass $$(cat /run/secrets/redis_password)` |
| **Authentik** | `authentik_secret`, `redis_password`, `postgres_password` | Entrypoint wrapper | Maps to `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_REDIS__PASSWORD`, etc. |
| **Hermes** | `hermes_password` | Entrypoint wrapper | Exports `HERMES_WEBUI_PASSWORD` |
| **Vaultwarden** | `vw_admin_token` | `_FILE` env var | `ADMIN_TOKEN_FILE=/run/secrets/vw_admin_token` |
| **Omniroute** | `redis_password` | Entrypoint wrapper | Constructs `REDIS_URL` from password |
| **Agent Zero** | `litellm_key`, `ssh_deploy_key` | `_FILE` + file path | `LITELLM_MASTER_KEY_FILE`, `SSH_KEY_PATH` |

---

## Files Created/Modified

### New Files
| File | Purpose |
| :--- | :--- |
| `compose/network/traefik/entrypoint-wrapper.sh` | Reads CF secrets, exports env vars, execs Traefik |
| `compose/network/cloudflared/entrypoint-wrapper.sh` | Reads tunnel token, execs cloudflared |
| `compose/security/authentik/entrypoint-wrapper.sh` | Maps secrets to Authentik-specific env var names |
| `compose/ai/hermes/entrypoint-wrapper.sh` | Reads Hermes password, exports env var |
| `compose/ai/omniroute/entrypoint-wrapper.sh` | Reads Redis password, constructs REDIS_URL |
| `secrets/cf_api_email.txt` | Cloudflare API email (moved from .env for consistency) |

### Modified Files
| File | Change |
| :--- | :--- |
| `.env` | **STRIPPED ALL SECRETS** — now contains only ports, domains, non-sensitive config |
| `.env.example` | Updated with secret file list documentation |
| `docker-compose.yml` | Added `secrets:` section (17 secrets), updated all services, removed `env_file` where unnecessary |

---

## Security Posture Before vs After

| Aspect | Before | After |
| :--- | :--- | :--- |
| Secrets in `.env` | 14 secrets (passwords, API keys, tokens) | 0 secrets |
| Secrets hardcoded in YAML | Multiple (`REDIS_PASSWORD`, `AUTHENTIK_SECRET_KEY`) | None |
| Secret file permissions | Mixed (some `644`, some `600`) | All `600` (owner read/write only) |
| Docker secrets usage | 2 of 15 secrets | 17 of 17 secrets |
| Secrets in container env | Visible in `docker inspect` | Only via `_FILE` or runtime read |
| Traefik CF credentials | File path string (broken) | Actual token value (working) |

---

## Remaining Vulnerabilities

### 1. Outbound Network Blocked on `proxy` Network
- **Issue:** Traefik container cannot reach Let's Encrypt API (`dial tcp 172.65.32.248:443: i/o timeout`)
- **Cause:** Docker `proxy` network (172.18.0.0/16) has restricted outbound access
- **Impact:** No TLS certificates can be obtained for `*.wazzan.us` subdomains
- **Fix needed:** Check iptables rules, Docker daemon config, or recreate the `proxy` network

### 2. Let's Encrypt Rate Limit
- **Issue:** Domain `omniroute.wazzan.us`, `vault.wazzan.us`, `traefik.wazzan.us` rate-limited for authorization failures
- **Cause:** Previous broken credentials caused repeated failed ACME challenges
- **Impact:** Cannot obtain certificates for ~1 hour from last failure
- **Fix:** Wait for rate limit to expire (auto-resolves)

### 3. Authentik Middleware Reference
- **Issue:** `traefik.http.routers.traefik.middlewares=authentik@docker` was removed because authentik middleware doesn't exist yet
- **Impact:** Traefik dashboard is not behind authentication
- **Fix needed:** Configure Authentik middleware after Authentik is healthy

### 4. `.env` File Still Readable by Group/World
- **Issue:** `.env` file permissions may allow other users to read non-sensitive config (ports, domains)
- **Fix:** `chmod 640 .env` or restrict to docker group

---

## Verification Checklist

- [x] `.env` contains zero secrets
- [x] All 17 secrets defined in `docker-compose.yml` `secrets:` section
- [x] All secret files have `chmod 600` permissions
- [x] Traefik loads secrets from `/run/secrets/` (confirmed in logs)
- [x] Traefik health check passes
- [x] No hardcoded secrets in any YAML file
- [ ] Traefik can obtain TLS certificates (blocked by network issue)
- [ ] All services start with new secrets architecture
- [ ] Authentik middleware configured and working

---

## Entrypoint Wrapper Pattern

For services that don't support `_FILE` environment variables, use this pattern:

```sh
#!/bin/sh
# entrypoint-wrapper.sh
set -e

# Read secret, export with correct env var name
if [ -f /run/secrets/secret_name ]; then
    export CORRECT_ENV_VAR=$(cat /run/secrets/secret_name | tr -d '\n\r')
fi

# Execute original command
exec "$@"
```

Mount as: `- ./path/to/entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro`
Set as: `entrypoint: ["/entrypoint-wrapper.sh"]`

---

**Next audit:** Run this document as reference when verifying all services start correctly and obtain TLS certificates.
