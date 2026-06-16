---
name: docker-secrets
description: Complete Docker secrets architecture — zero secrets in .env, entrypoint wrapper pattern, _FILE convention, and gitignore hardening
source: auto-skill
extracted_at: '2026-06-15T17:25:36.130Z'
---

# Docker Secrets Architecture

**Core principle:** `.env` contains ZERO secrets. All credentials live in `./secrets/*.txt` and are mounted via Docker Compose `secrets:` as read-only files at `/run/secrets/<name>`.

## Critical Anti-Pattern: File Paths as Values

**Never do this in `.env`:**
```
# WRONG — service receives the literal path string, not the file contents
CF_DNS_API_TOKEN=/home/user/secrets/cf_dns_api_token.txt
REDIS_PASSWORD=mPfIVznCZRhSmutj3KBPOLIHT85dJS0Tg15ZbpzoVWg=
```

**Why it fails:** Docker substitutes `${CF_DNS_API_TOKEN}` with the literal string `/home/user/secrets/cf_dns_api_token.txt`. The service receives a file path instead of the actual credential. Traefik sent this path string to Cloudflare's API → `400 Invalid format for X-Auth-Key header`.

## Three Secret Reading Methods

### Method 1: `_FILE` Environment Variable (preferred)

For services that natively support reading secrets from files (Postgres, LiteLLM, OpenWebUI, Vaultwarden):

```yaml
services:
  postgres:
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password  # container path
    secrets:
      - postgres_password                                       # mount reference

  litellm:
    environment:
      LITELLM_MASTER_KEY_FILE: /run/secrets/litellm_key
    secrets:
      - litellm_key

secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt                       # host path
  litellm_key:
    file: ./secrets/litellm_key.txt
```

### Method 2: Entrypoint Wrapper Script

For services that don't support `_FILE` env vars (Traefik, Authentik, Hermes, Omniroute):

```yaml
services:
  traefik:
    entrypoint: ["/entrypoint-wrapper.sh"]
    command: [...]                                               # original traefik args
    volumes:
      - ./compose/network/traefik/entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro
    secrets:
      - cf_api_email
      - cf_dns_api_token
```

**Entrypoint wrapper template:**
```sh
#!/bin/sh
# entrypoint-wrapper.sh — reads Docker secrets, exports env vars, execs original command
set -e

# Read secrets and export with correct env var names
if [ -f /run/secrets/cf_dns_api_token ]; then
    export CF_DNS_API_TOKEN=$(cat /run/secrets/cf_dns_api_token | tr -d '\n\r')
fi

if [ -f /run/secrets/cf_api_email ]; then
    export CF_API_EMAIL=$(cat /run/secrets/cf_api_email | tr -d '\n\r')
fi

# For services with custom entrypoints that prepend the binary name:
# (e.g., Traefik's entrypoint prepends 'traefik' if args start with '-')
if [ "${1#-}" != "$1" ]; then
    set -- traefik "$@"
fi

# Execute the original command
exec "$@"
```

**Key gotchas:**
- Always `tr -d '\n\r'` to strip trailing newlines from secret files
- The entrypoint wrapper MUST call `exec "$@"` to replace the shell with the target process (otherwise signals don't propagate)
- For Traefik specifically: its original entrypoint prepends `traefik` to args starting with `-`. Replicate this logic or Traefik won't start.
- For Authentik: map to the correct double-underscore env var names (`AUTHENTIK_REDIS__PASSWORD`, `AUTHENTIK_POSTGRESQL__PASSWORD`)

### Method 3: Inline Shell Command

For simple cases like Redis:

```yaml
services:
  redis:
    command:
      - sh
      - -c
      - |
        redis-server \
          --requirepass "$$(cat /run/secrets/redis_password)" \
          --appendonly yes
    secrets:
      - redis_password
    healthcheck:
      test: ["CMD", "sh", "-c", "redis-cli -a $$(cat /run/secrets/redis_password) ping"]
```

## Complete `.env` Template (Zero Secrets)

```bash
# Core Settings
TZ=America/Toronto
PUID=1000
PGID=1000
DOMAIN=wazzan.us

# Ports only
PORT_TRAEFIK_HTTP=80
PORT_TRAEFIK_HTTPS=443
PORT_POSTGRES=5432
# ... more ports ...

# Non-sensitive config only
POSTGRES_USER=alwazw
POSTGRES_DB=aef3
```

## `.gitignore` Hardening

```gitignore
# Secrets — never track
.env
secrets/*
!secrets/*.pub
!secrets/README.md
```

After adding this, remove any previously tracked secrets:
```bash
git rm --cached secrets/*_key.txt secrets/*_password.txt secrets/*_token.txt
```

## Secret File Permissions

```bash
chmod 600 secrets/*.txt secrets/*.key    # owner read/write only
chmod 644 secrets/*.pub                   # public keys are safe to read
```

## Trailing Newlines in Secret Files (Critical)

**Secret files created with `echo` or text editors often have trailing newlines.** Services like n8n warn about this and it causes authentication failures:

```
[n8n] Warning: The file specified by DB_POSTGRESDB_PASSWORD_FILE contains leading or trailing whitespace
```

**Fix — strip trailing newlines from ALL secret files:**
```bash
# One-liner to fix all secrets at once
for f in secrets/*.txt secrets/*.key; do
    [ -f "$f" ] && printf '%s' "$(cat "$f")" > "$f" && chmod 600 "$f"
done

# Verify no trailing newlines
for f in secrets/*.txt; do [ -f "$f" ] && xxd "$f" | tail -1; done
# Should NOT end with 0a (newline byte)
```

**Prevention:** Always create secrets with `printf` not `echo`:
```bash
printf '%s' 'my-secret-value' > secrets/my_secret.txt
```

## Images Without Shell (scratch-based containers)

Some official images (e.g., `cloudflare/cloudflared`) are built FROM scratch — they have **no shell, no `/bin/sh`**. Entrypoint wrappers that use `#!/bin/sh` will fail with:

```
exec /entrypoint-wrapper.sh: no such file or directory
```

**Workaround 1: Use a shell-enabled sidecar image**
```yaml
# Download binary to shared volume first
cloudflared-installer:
  image: alpine:latest
  command: ["sh", "-c", "curl -fSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /data/cloudflared && chmod +x /data/cloudflared"]
  volumes:
    - cloudflared_bin:/data

cloudflared:
  image: busybox:1.37           # Has /bin/sh
  entrypoint: ["/bin/sh", "-c"]
  command:
    - |
      TOKEN=$$(cat /run/secrets/cf_tunnel_token)
      exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "$$TOKEN"
  volumes:
    - cloudflared_bin:/usr/local/bin
  secrets:
    - cf_tunnel_token
```

**Workaround 2: Use the image's native `--token-file` flag**
```yaml
cloudflared:
  image: cloudflare/cloudflared:latest
  entrypoint: ["cloudflared", "tunnel", "--no-autoupdate", "run"]
  command: ["--token-file", "/run/secrets/cf_tunnel_token"]
  secrets:
    - cf_tunnel_token
```
Only works if the application supports reading from a file directly.

## Images Without Healthcheck Capability (scratch-based)

Some official images are built FROM scratch and have **no shell, no binaries at all**:
- `grafana/loki:latest` — no sh, nc, wget, curl, ls, or any other tool
- `cloudflare/cloudflared:latest` — no sh or any shell

**Any healthcheck will fail** on these images:
```
exec: "nc": executable file not found in $PATH
```

**Solution:** Remove the healthcheck entirely. Verify health from the host instead:
```yaml
loki:
  image: grafana/loki:latest
  # NO healthcheck — scratch image has no binaries
  # Health verified from host: curl http://localhost:3100/ready
```

## Service-Specific Secret Mappings

| Service | Secret(s) | Method | Env Var Names |
| :--- | :--- | :--- | :--- |
| **Traefik** | `cf_api_email`, `cf_dns_api_token` | Entrypoint wrapper | `CF_API_EMAIL`, `CF_DNS_API_TOKEN` |
| **Cloudflared** | `cf_tunnel_token` | Entrypoint wrapper | Passed as `--token` CLI arg |
| **LiteLLM** | `litellm_key` | `_FILE` env var | `LITELLM_MASTER_KEY_FILE` |
| **OpenWebUI** | `webui_secret_key` | `_FILE` env var | `WEBUI_SECRET_KEY_FILE` |
| **Postgres** | `postgres_password` | `_FILE` env var | `POSTGRES_PASSWORD_FILE` |
| **Redis** | `redis_password` | Inline shell | N/A (read in command) |
| **Authentik** | `authentik_secret`, `redis_password`, `postgres_password` | Entrypoint wrapper | `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_REDIS__PASSWORD`, `AUTHENTIK_POSTGRESQL__PASSWORD` |
| **Hermes** | `hermes_password` | Entrypoint wrapper | `HERMES_WEBUI_PASSWORD` |
| **Vaultwarden** | `vw_admin_token` | `_FILE` env var | `ADMIN_TOKEN_FILE` |
| **Omniroute** | `redis_password` | Entrypoint wrapper | Constructs `REDIS_URL` |

## Verification Checklist

```bash
# 1. .env contains zero secrets
grep -iE "(password|secret|token|key)" .env | grep -v "^#" | grep -v "FILE"

# 2. All secrets defined in compose
grep -c "^  [a-z]" docker-compose.yml | grep secrets

# 3. Secret file permissions
ls -la secrets/

# 4. No secrets in git
git ls-files secrets/
# Should only show *.pub files

# 5. Traefik logs show secrets loaded
docker compose logs traefik --tail 10 | grep "Loaded"
```

## Migration from `.env` Secrets to Docker Secrets

1. Create `./secrets/<name>.txt` files for each secret
2. Add to `docker-compose.yml` top-level `secrets:` section
3. Add `secrets:` reference to the service definition
4. Change env vars from `${SECRET_VAR}` to `_FILE` or entrypoint wrapper
5. Remove the secret from `.env`
6. Remove `env_file: [.env]` from services that no longer need non-secret env vars
7. Verify service starts and authenticates correctly
8. Add secret pattern to `.gitignore`
9. `git rm --cached secrets/<name>.txt` if previously tracked
