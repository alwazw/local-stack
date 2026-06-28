# ADR-0005: Entrypoint Wrapper Bind Mounts

**Date:** 2026-06-28
**Status:** Implemented

## Context
Several services (authentik-worker, omniroute, plane-api, hermes-webui) reference `/entrypoint-wrapper.sh` as their entrypoint but did not bind-mount the script into the container. The scripts exist in each service's compose directory but were never mounted.

## Decision
Add explicit bind mounts for entrypoint-wrapper.sh in each affected service's compose file:
```yaml
volumes:
  - ./entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro
```
Also ensure each service has the required networks, secrets, and environment variables defined.

## Consequences
- Services that previously failed to start now work correctly
- Requires the entrypoint-wrapper.sh file to exist in each service's directory
- Bind mounts require the host path to exist (created missing media/ dirs for authentik-worker)
