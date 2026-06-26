04-TROUBLESHOOTING.md

# 04 — Common Fuck-ups & Fixes

1. Permission denied on /opt/aef3

**Cause:** Ran script with sudo
**Fix:**
```bash
sudo chown -R $USER:$USER ~/docker
```

2. bootstrap.sh: cd: /opt/aef3: No such file or directory
Cause: Hardcoded path in script
Fix: Edit line 4 of scripts/bootstrap.sh:

```
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

3. Container restarting loop
Check: docker logs <container-name>
Common causes:

Postgres: data/ dir owned by root → sudo chown -R 999:999 compose/data/postgres/data
Redis: Secret not found → docker compose down &&./scripts/bootstrap.sh
Traefik: Port 80 in use → sudo lsof -i :80 kill or change PORT_TRAEFIK_HTTP
4. database network not found
Cause: Didn't run bootstrap or network creation
Fix:

```
docker network create database --internal
docker network create ai-ml --internal
docker network create proxy
```

5. Authentik 502 Bad Gateway
Cause: Started before Postgres ready
Fix:

```
cd compose/data/postgres && docker compose logs -f
# Wait for "database system is ready"
cd../../security/authentik && docker compose restart
```

6. Ollama no GPU
Check: docker exec -it ollama nvidia-smi
Fix: Reinstall nvidia-container-toolkit, restart docker

7. Can't reach app via domain
Cause: Using localhost but Traefik expects ${DOMAIN}
Fix 1: Add to /etc/hosts:

```
127.0.0.1 chat.home.local
127.0.0.1 auth.home.local
```

Fix 2: Use IP:PORT directly: http://<vm-ip>:3000

8. Secrets not found
Error: secret postgres_password not found
Fix:
```
./scripts/bootstrap.sh # Recreates secrets
cd compose/data/postgres
docker compose down && docker compose up -d
```

9. OpenWebUI can't connect to Ollama
Cause: Wrong network
Fix: Both must be on ai-ml network. Check:
```
docker network inspect ai-ml
```

Should show both containers.

10. Nuclear option — Start fresh
```
cd ~/docker
docker compose -f compose/data/postgres/docker-compose.yml down -v
docker compose -f compose/data/redis/docker-compose.yml down -v
rm -rf compose/*/data
./scripts/bootstrap.sh
```
Warning: Deletes all DB data

Getting Help
- docker ps -a — see what's dead
- docker logs <name> --tail 50 — last 50 lines
- docker compose config — validate yaml
- docker network ls — check networks exist

```
Paste each file into `~/docker/docs/` with the filename at the top. These cover 90% of issues you'll hit.

```
