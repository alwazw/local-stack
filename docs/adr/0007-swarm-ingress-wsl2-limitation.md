# ADR-0007: Swarm Ingress Routing Mesh on WSL2

**Date:** 2026-06-28
**Status:** Accepted Limitation

## Context
Docker Swarm's ingress routing mesh does not function correctly on WSL2. Published ports are listening on the host but connections timeout. The routing mesh proxy accepts connections but cannot forward them to backend containers.

## Decision
Accept the limitation and use internal overlay network connectivity for service-to-service communication (verified working). External access works via Cloudflare Tunnel (traefik routes traffic from cloudflared).

## Consequences
- Cannot access services via localhost:port from the WSL2 host
- All inter-service communication works via overlay DNS (verified)
- External access via Cloudflare Tunnel works (verified)
- For debugging, use `docker exec <container> curl http://localhost:<port>`
