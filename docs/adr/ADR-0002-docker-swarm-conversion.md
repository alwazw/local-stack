# ADR-0002: Docker Swarm Conversion

**Status:** Accepted  
**Date:** 2026-06-26  
**Context:** Branch `overhaul/swarm-conversion` — single-node to Swarm migration

## Problem

The stack runs in standalone Docker Compose mode on a single WSL2 host. While functional, this limits:

- Multi-node scalability (future VM cluster expansion).
- Built-in service mesh and overlay networking.
- Rolling update strategies and rollback capabilities.
- Native secret/config management (currently using file-based secrets workaround).
- Global service mode for node-level agents (e.g., cAdvisor for per-node metrics).

## Decision

Convert all 32 compose files and the root `docker-compose.yml` from standalone Compose format to Docker Swarm format:

- `docker compose` → `docker stack deploy` workflow.
- Port bindings remain `127.0.0.1:${PORT}:target` for local access.
- Named volumes replaced with volume declarations compatible with Swarm.
- `deploy:` blocks added for resource limits, placement, and mode.
- Overlay networks replace bridge networks for inter-service communication.

### Phased Approach

1. **Phase 1:** Convert root compose file (networks, secrets, includes → stack definition).
2. **Phase 2:** Convert all 31 service compose files to Swarm-compatible format.
3. **Phase 3:** Validate stack deployment and service health.
4. **Phase 4:** Enable multi-node mode (requires additional VM hosts).

## WSL2 Ingress Limitation

**Critical constraint:** Docker Swarm's routing mesh (ingress network) does **not** work correctly on WSL2. The `ingress` overlay network uses iptables NAT rules that WSL2's virtualized network stack does not fully support.

### Impact
- Services with `endpoint_mode: vip` or published ports may not be reachable from the Windows host.
- `127.0.0.1` port bindings work but `0.0.0.0` bindings are unreliable.

### Workaround
- Use `--publish mode=host,target=<port>` for services that need external access.
- Keep Traefik as the sole entrypoint on ports 80/443.
- All other services remain `127.0.0.1`-bound, accessible only from the WSL2 host.

## Consequences

### Positive
- Future-ready for multi-node expansion.
- Native rolling updates (`--update-parallelism`, `--update-delay`).
- Built-in health check integration with task replacement.
- cAdvisor can use `mode: global` for per-node metrics.

### Negative
- WSL2 ingress limitation restricts port publishing options.
- Swarm adds operational complexity for single-node deployments.
- File-based secrets remain (Swarm secrets require `docker secret create`).
- Compose `include:` does not work with `docker stack deploy` — all services must be in a single stack file or use `docker stack deploy` multiple times.

## Alternatives Considered

1. **Stay with standalone Compose** — simpler, but no multi-node path.
2. **Kubernetes (k3s/kind)** — more powerful but significantly higher complexity for this workload.
3. **Nomad** — lighter than K8s but less ecosystem integration.
