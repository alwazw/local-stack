# ADR-0006: Grafana Admin Secret Registration

**Date:** 2026-06-28
**Status:** Implemented

## Context
The `grafana_admin_password` Docker secret was defined in stack-merged.yml but not registered in the Swarm secret store. The secret file existed at `/home/alwazw/docker/secrets/grafana_admin_password.txt` with the real password, but the deploy process didn't pick it up. Additionally, a plaintext `GRAFANA_ADMIN_PASSWORD=admin` was in `.env`.

## Decision
1. Manually register the secret: `cat secrets/grafana_admin_password.txt | docker secret create docker_grafana_admin_password -`
2. Remove the plaintext password from `.env`
3. Also registered `cf_api_key` which was similarly missing

## Consequences
- Grafana now uses the real admin password from the Docker secret
- No passwords remain in `.env`
- Secret rotation requires: `docker secret rm <name> && docker secret create <name> <file> && docker service update --force <service>`
