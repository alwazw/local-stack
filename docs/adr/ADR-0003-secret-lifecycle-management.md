# ADR-0003: Secret Lifecycle Management

**Status:** Accepted  
**Date:** 2026-06-15  
**Context:** Security hardening — eliminating secrets from .env files

## Problem

The original `.env` file contained 17+ plaintext credentials. This created several risks:

- Credentials committed to version control via `.env` (despite `.gitignore`, accidents happen).
- No rotation procedure — secrets were set once and never changed.
- No audit trail for who created or accessed each secret.
- File permissions were inconsistent (some secrets world-readable: 755, 644).

## Decision

Adopt a **file-based secrets** pattern with the following rules:

1. **Zero secrets in `.env`**: The `.env` file contains only configuration (ports, paths, domains). No passwords, tokens, or keys.
2. **Secret files on disk**: Each secret stored as a plain text file in `secrets/<name>.txt`.
3. **Docker secrets section**: Root `docker-compose.yml` declares all secrets with `file:` source pointing to `secrets/<name>.txt`.
4. **`_FILE` convention**: Services that support it read secrets via `PASSWORD_FILE=/run/secrets/secret_name` env vars.
5. **Entrypoint wrapper**: For services without native `_FILE` support, an entrypoint script reads `/run/secrets/` and exports the value as a regular env var before exec.
6. **Permissions**: All secret files set to `chmod 600`. Public keys (`.pub`) set to `chmod 644`.

### Rotation Procedure

```bash
# 1. Generate new secret
openssl rand -base64 32 > secrets/postgres_password.txt
chmod 600 secrets/postgres_password.txt

# 2. Restart affected services
docker compose up -d --force-recreate postgres

# 3. Verify service health
docker compose ps postgres
docker compose logs postgres | tail -20

# 4. Commit the change (secret file itself is .gitignored, only document the rotation)
git add docs/adr/ADR-0003-secret-lifecycle-management.md  # if procedure changed
```

### Git Protection

- `secrets/` directory in `.gitignore`.
- `.gitignore` itself includes a hardening rule: never commit files matching `*_key.txt`, `*_token.txt`, `*_password.txt`, `*_secret.txt`.
- `.env.example` shipped with placeholder values, never real credentials.

## Consequences

### Positive
- No secrets in environment variables or compose files — only file paths.
- Clear rotation procedure with rollback (keep old file until new one verified).
- Consistent permission model (600 for private, 644 for public).
- Compatible with both standalone Compose and Docker Swarm (with `docker secret create`).

### Negative
- Secret files exist on disk unencrypted — rely on filesystem permissions.
- No centralized secret manager (HashiCorp Vault, AWS Secrets Manager).
- Services without `_FILE` support need custom entrypoint wrappers.

## Alternatives Considered

1. **`.env` with `.gitignore`** — simple but accident-prone and no rotation path.
2. **Docker Swarm secrets** — better security but requires Swarm mode; not available in standalone Compose.
3. **HashiCorp Vault** — enterprise-grade but overkill for single-node deployments.
4. **`docker secret create`** — works in Swarm but secrets stored in Raft log; file-based is simpler for non-Swarm.
