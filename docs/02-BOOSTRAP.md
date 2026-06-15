

### **`/docs/02-BOOTSTRAP.md`**

# 02 — Bootstrap: Exact Commands

**Assumption:** You're in `~/docker/` and ran `aef3.sh`

1. Fix Permissions
```bash
sudo chown -R $USER:$USER ~/docker
```

2. Create.env

```
cd ~/docker
cp.env.example.env
nano.env
```

Required changes:
```
DOMAIN=home.local
CF_API_EMAIL=your@cloudflare.email
```

3. Run Bootstrap Script
```
./scripts/bootstrap.sh
```

Output should be:
```
[1/4] Secrets...
[2/4] Networks...
[3/4] Data dirs...
[4/4] Done
```

Verify:
```
ls secrets/ # Should show 10.txt files
docker network ls | grep -E 'proxy|database|ai-ml'
```

4. Deploy Postgres First
```
cd compose/data/postgres
docker compose up -d
docker compose logs -f # Wait for "database system is ready"
```

5. Deploy Redis
```
cd../redis
docker compose up -d
```

6. Deploy Traefik
```
cd../../network/traefik
docker compose up -d
docker compose logs -f # Wait for "Configuration loaded"
```

7. Deploy Authentik
```
cd../../security/authentik
docker compose up -d
```
Wait 2 min, then: http://<vm-ip>:9000

8. Deploy Ollama
```
cd../../ai/ollama
docker compose up -d
docker exec -it ollama ollama pull llama3.1:8b
```

9. Deploy OpenWebUI
```
cd../openwebui
docker compose up -d
```
Access: http://<vm-ip>:3000

10. Verify All
```
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
You should see: postgres, redis, traefik, authentik-server, ollama, openwebui

If any container is Restarting: docker logs <name>





