# Swarm Stack Validation Report — 2026-06-26

## Service Status Summary

### ✅ Verified Working (13 services, internal endpoint validated)
| Service | Internal Check | Status |
|---------|---------------|--------|
| traefik | wget localhost:8080/ping → OK | ✅ Running |
| postgres | pg_isready → accepting connections | ✅ Running |
| redis | redis-cli ping → PONG | ✅ Running |
| prometheus | wget localhost:9090/-/healthy → Healthy | ✅ Running |
| searxng | wget localhost:8080 → HTML 200 | ✅ Running |
| dockge | node HTTP → 200 | ✅ Running |
| homepage | node HTTP → 200 | ✅ Running |
| uptime-kuma | node HTTP → 302 (redirect) | ✅ Running |
| cloudflared | logs: tunnel registered, HTTP/2 | ✅ Running |
| gitea | wget localhost:3000 → 200 | ✅ Running |
| qdrant | 1/1 replicas, port 6333 listening | ✅ Running |
| openwebui | 1/1 replicas, port 8080 listening | ✅ Running |
| mcpo | 1/1 replicas, port 8000 listening | ✅ Running |

### ✅ Overlay Network Connectivity
- DNS resolution: postgres → redis (10.0.6.5) ✅
- Cross-network: gitea → postgres:5432 OK ✅
- Database network: 3 containers (postgres 10.0.6.4, gitea 10.0.6.6, redis 10.0.6.8) ✅

### ⚠️ Initial Startup Issues (now resolved after network settled)
- 11 services had initial "missing network attachments" rejection
- All recovered after overlay networks fully initialized
- Each had 1 restart event (expected behavior)

### ❌ Failing Services (6 services)
| Service | Issue | Details |
|---------|-------|---------|
| affine | Crash loop (exit 1) | Node.js error — likely missing DATABASE_URL env var in Swarm |
| agent-zero | Failed (exit 255) | Supervisord processes terminated (run_searxng, run_cron, the_listener) |
| authentik-server | Not starting | Was waiting for postgres DNS during initial startup |
| authentik-worker | 4 restarts | Can't connect to postgres during startup window |
| vaultwarden | Complete (exited) | Container started then exited — may need different entrypoint |
| hermes-webui | 4 restarts | Depends on hermes-agent which isn't healthy |
| plane-api | 4 restarts | Startup race with postgres healthcheck |
| omniroute | 4 restarts | Startup issue |

### ⏳ Still Starting
- grafana, guacamole, guacd, hermes-agent, litellm, n8n, ollama, plane-api

### ❌ Known WSL2 Limitation
- Swarm ingress routing mesh doesn't work on WSL2
- Published ports (localhost:80, localhost:3000, etc.) time out
- Services are accessible internally via overlay network (verified)
- External access works via Cloudflare Tunnel (verified: cloudflared tunnel registered)
