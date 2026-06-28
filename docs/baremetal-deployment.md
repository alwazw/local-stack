# Baremetal Ubuntu Deployment Guide

## Prerequisites
- Ubuntu 22.04+ with Docker Engine installed
- Docker Swarm initialized: `docker swarm init`
- All secret files in `~/docker/secrets/`

## Deploy
```bash
cd ~/docker
docker stack deploy -c stack-merged.yml local-stack
```

## Wait for services
```bash
watch docker service ls
# Wait until all show 1/1 (takes ~2 minutes)
```

## Validate
```bash
# All 31 services should be running
docker service ls --format '{{.Name}}\t{{.Replicas}}'

# Test services via published ports (works on baremetal, not WSL2)
curl http://localhost:8080/ping           # traefik
curl http://localhost:3000                # openwebui
curl http://localhost:9090/-/healthy      # prometheus
curl http://localhost:6333/healthz        # qdrant
curl http://localhost:3001                # gitea
curl http://localhost:4000/health         # litellm
curl http://localhost:5001                # dockge
curl http://localhost:3004                # homepage
curl http://localhost:8082/alive          # vaultwarden
curl http://localhost:8000/openapi.json   # mcpo
curl http://localhost:9000/if/health/live # authentik-server
curl http://localhost:20128               # omniroute
curl http://localhost:5678                # n8n
curl http://localhost:8083                # affine
curl http://localhost:8080/metrics        # cadvisor
```

## Prometheus Metrics
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3003 (admin / see secrets/grafana_admin_password.txt)
- cadvisor scraping: UP — collecting container metrics for entire stack

## Rollback
```bash
docker stack rm local-stack
# Or restore from pre-swarm compose:
docker compose --profile ai --profile ci --profile monitoring --profile network --profile management --profile security --profile productivity up -d
```

## Known Issues (3 services)
- **agent-zero**: exits after task completion (task runner design)
- **hermes-agent**: s6-overlay init issue in Swarm
- **hermes-webui**: upstream image path issue (/apptoo/.env)
