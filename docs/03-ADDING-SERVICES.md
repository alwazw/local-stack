03-ADDING-SERVICES.md

# 03 — Adding New Services

## Template Location
`templates/service-template/`

Step 1: Copy Template
```bash
cd ~/docker/compose
cp -r../templates/service-template productivity/newapp
cd productivity/newapp
```
Step 2: Edit docker-compose.yml

```
services:
  newapp:
    image: newapp:latest
    container_name: newapp
    restart: unless-stopped
    env_file:
      -../../../.env
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER}:$(cat /run/secrets/postgres_password)@postgres:5432/newapp
    volumes:
      -./data:/data
    networks:
      - proxy
      - database
    secrets:
      - postgres_password
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.newapp.rule=Host(`newapp.${DOMAIN}`)"
      - "traefik.http.routers.newapp.entrypoints=websecure"
      - "traefik.http.routers.newapp.tls=true"
      - "traefik.http.routers.newapp.middlewares=authentik@docker"

secrets:
  postgres_password:
    file:../../../secrets/postgres_password.txt

networks:
  proxy:
    external: true
  database:
    external: true
```

Step 3: Create Database

```
docker exec -it postgres psql -U aef3 -c "CREATE DATABASE newapp;"
```

Step 4: Add to Homepage
Edit compose/orchestration/homepage/config/services.yaml:
```
- Productivity:
    - NewApp:
        icon: newapp.png
        href: https://newapp.${DOMAIN}
        description: New service
```

Step 5: Deploy
```
docker compose up -d
```

Step 6: Add Authentik Proxy

- Authentik Admin → Applications → Create
- Provider: Proxy Provider
- External host: https://newapp.${DOMAIN}
- Apply to Traefik middleware

Rules
- Always use ../../../.env
- Always use Docker secrets for passwords
- Always add to proxy network if web-facing
- Never expose DB ports except Postgres:5432 for admin
- Never use latest in prod — pin versions





