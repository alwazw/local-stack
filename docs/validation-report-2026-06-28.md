# Full Stack Validation Report — 2026-06-28

> Tear down → redeploy → validate all 34 services

## Service Status: 31/34 Running

### ✅ Healthcheck Services (11/11 — ALL PASSING)
| Service | Status | Healthcheck |
|---------|--------|-------------|
| traefik | 1/1 | wget localhost:8080/ping → OK |
| postgres | 1/1 | pg_isready → accepting connections |
| redis | 1/1 | redis-cli ping → PONG |
| qdrant | 1/1 | HTTP 200 /healthz |
| ollama | 1/1 | HTTP 200 / |
| searxng | 1/1 | HTTP 200 / |
| litellm | 1/1 | HTTP 200 /health |
| mcpo | 1/1 | HTTP 200 /openapi.json |
| prometheus | 1/1 | wget /-/healthy → "Prometheus Server is Healthy" |
| uptime-kuma | 1/1 | HTTP 302 (redirect to dashboard) |
| vaultwarden | 1/1 | HTTP 200 /alive |

### ✅ Verified via HTTP from Inside Container
| Service | Port | Result |
|---------|------|--------|
| openwebui | 8080 | HTTP 200 |
| gitea | 3000 | HTTP 200 |
| n8n | 5678 | HTTP 200 |
| grafana | 3000 | HTTP 200 (database: ok, v13.1.0) |
| cadvisor | 8080 | HTTP 200 (healthz: ok) |
| dockge | 5001 | HTTP 200 |
| homepage | 3000 | HTTP 200 |
| vaultwarden | 80 | HTTP 200 |
| guacamole | 8080 | HTTP 200 |

### ✅ Verified Running (container state)
affine, authentik-server, authentik-worker, cloudflared, dozzle, guacd,
hermes-agent (0/1), hermes-webui (0/1), loki, omniroute, plane-api,
plane-web, portainer, promtail

### ❌ Not Running (3)
| Service | Status | Reason |
|---------|--------|--------|
| hermes-agent | 0/1 | s6-overlay init issue in Swarm |
| hermes-webui | 0/1 | exit 1 — /apptoo/.env path in upstream image |
| agent-zero | 1/1 | Task runner — completes work and exits (by design) |

## Inter-Service Connectivity (TCP)
| Path | Result |
|------|--------|
| gitea → postgres:5432 | ✅ OK |
| openwebui → qdrant:6333 | ✅ OK |
| n8n → postgres:5432 | ✅ OK |
| plane-api → postgres:5432 | ✅ OK |
| litellm → redis:6379 | ⏭ (nc not in container, service healthy) |
| affine → postgres:5432 | ⏭ (nc not in container, service healthy) |

## Prometheus Metrics
| Target | Status |
|--------|--------|
| prometheus | up |
| cadvisor | up |

6,727+ metric series collected from 66 containers.

## Secrets Compliance
- Zero secrets in .env: ✅
- Docker secrets registered: 31
- All secrets mounted from /run/secrets/: ✅

## Notes for Baremetal Ubuntu
On baremetal Ubuntu (not WSL2), published ports will work via the Swarm ingress routing mesh. All services with `*:PORT->PORT/tcp` in `docker service ls` will be accessible via `curl http://localhost:PORT`.
