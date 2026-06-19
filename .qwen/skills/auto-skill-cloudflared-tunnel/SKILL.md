---
name: cloudflared-tunnel
description: Cloudflare Tunnel deployment in Docker — scratch image workarounds, proxy network outbound fix, token management via Docker secrets, and installer cleanup automation
source: auto-skill
extracted_at: '2026-06-15T21:51:08.482Z'
---

# Cloudflare Tunnel Deployment

## The Core Problem

`cloudflare/cloudflared:latest` is built **FROM scratch** — no shell, no binaries, no `/bin/sh`. This means:
- Entrypoint wrappers with `#!/bin/sh` fail: `exec /entrypoint-wrapper.sh: no such file or directory`
- No healthcheck possible (no sh, nc, wget, curl)
- Can't read secrets via shell commands inside the container

## Deployment Architecture

### Option 1: Busybox Sidecar + Shared Volume (working solution)

```yaml
volumes:
  cloudflared_bin:     # Shared volume for cloudflared binary

services:
  cloudflared-installer:
    image: alpine:latest
    container_name: cloudflared-installer
    profiles: [network]
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        apk add --no-cache curl && \
        curl -fSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /data/cloudflared && \
        chmod +x /data/cloudflared
    volumes:
      - cloudflared_bin:/data

  cloudflared:
    image: busybox:1.37     # Has /bin/sh, wget, ping
    container_name: cloudflared
    restart: unless-stopped
    profiles: [network]
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        TOKEN=$$(cat /run/secrets/cf_tunnel_token)
        exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "$$TOKEN"
    volumes:
      - cloudflared_bin:/usr/local/bin
    networks:
      - proxy
    secrets:
      - cf_tunnel_token
```

**How it works:**
1. `cloudflared-installer` downloads the 39MB binary to a shared named volume, then exits
2. `cloudflared` (busybox) reads the token from Docker secret and execs the binary
3. busybox provides `/bin/sh` for the entrypoint command

### Option 2: Self-Contained Alpine Container (PREFERRED — no sidecar needed)

Use `alpine:latest` with a self-contained entrypoint that downloads cloudflared on first run, caches it in a volume, and runs the tunnel:

```yaml
services:
  cloudflared:
    image: alpine:latest
    container_name: cloudflared
    restart: unless-stopped
    profiles: [network]
    entrypoint: ["/bin/sh", "/entrypoint-wrapper.sh"]
    environment:
      - CLOUDFLARED_VERSION=latest
    volumes:
      - ./entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro
      - cloudflared_bin:/data
    networks:
      - proxy
    secrets:
      - cf_tunnel_token
    depends_on:
      traefik:
        condition: service_healthy

volumes:
  cloudflared_bin:
```

**entrypoint-wrapper.sh:**
```bash
#!/bin/sh
set -e
CLOUDFLARED_BIN="/data/cloudflared"

# Download cloudflared if not present (cached in volume)
if [ ! -f "$CLOUDFLARED_BIN" ] || [ ! -x "$CLOUDFLARED_BIN" ]; then
    echo "[entrypoint] Downloading cloudflared binary..." >&2
    apk add --no-cache curl >/dev/null 2>&1 || true
    curl -fSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
      -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
fi

# Read token from secret
TUNNEL_TOKEN=$(cat /run/secrets/cf_tunnel_token | tr -d '\n\r')

# Run tunnel (--protocol http2 for WSL2, --no-autoupdate since binary is managed)
exec "$CLOUDFLARED_BIN" tunnel --no-autoupdate --protocol http2 run --token "$TUNNEL_TOKEN"
```

**Advantages over Option 1:**
- Single container — no installer sidecar trailing in `docker ps`
- Binary cached in volume — only downloads on first run or volume wipe
- Alpine has `curl` and `apk` — no need to `apk add curl` separately
- No `depends_on: service_completed_successfully` chain

### Option 3: Native `--token-file` Flag (if image supports it)

```yaml
cloudflared:
  image: cloudflare/cloudflared:latest
  entrypoint: ["cloudflared", "tunnel", "--no-autoupdate", "run"]
  command: ["--token-file", "/run/secrets/cf_tunnel_token"]
  secrets:
    - cf_tunnel_token
```

**This may NOT work** — the official cloudflared image may not have a `--token-file` flag. Verify first:
```bash
docker run --rm cloudflare/cloudflared:latest cloudflared tunnel run --help | grep token
```

## Network Requirements: Outbound Traffic

Cloudflared needs **outbound HTTPS + QUIC (UDP port 7844)** to reach Cloudflare edge servers. On WSL2/Docker Desktop, the `proxy` network often lacks proper iptables rules for outbound traffic.

### Symptoms

```
ERR Serve tunnel error error="DialContext error: dial tcp 198.41.200.233:7844: i/o timeout"
ERR Unable to establish connection with Cloudflare edge
INF Retrying connection in up to 1m4s
```

### Diagnosis

```bash
# Test outbound from container
docker exec cloudflared wget -qO- --timeout=5 https://cloudflare.com 2>&1
docker exec cloudflared ping -c 2 -W 3 8.8.8.8 2>&1

# Check proxy network bridge
docker network inspect proxy --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
# Output: 172.18.0.0/16

# Check if bridge has FORWARD rule
sudo iptables -L DOCKER-FORWARD -n -v | grep br-7a145f88f192  # proxy bridge

# Check MASQUERADE rule
sudo iptables -t nat -L POSTROUTING -n -v | grep "172.18"
```

### Fix: Add iptables Rules for Proxy Network

```bash
# Find the proxy bridge interface
BRIDGE="br-7a145f88f192"  # from docker network inspect proxy

# 1. FORWARD rule — allow traffic FROM proxy bridge
sudo iptables -I DOCKER-FORWARD 5 -i $BRIDGE -j ACCEPT
sudo iptables -I DOCKER-BRIDGE 5 -i $BRIDGE -j DOCKER

# 2. RETURN traffic — allow ESTABLISHED connections back TO proxy bridge
sudo iptables -I DOCKER-CT 4 -o $BRIDGE -m state --state RELATED,ESTABLISHED -j ACCEPT
```

**After fix, verify:**
```bash
docker exec cloudflared wget -qO- --timeout=5 https://cloudflare.com 2>&1 | head -3
# Should return HTML, not timeout
```

## Connection Verification

After restarting cloudflared, check for registered tunnel connections AND validate the transport protocol:

```bash
docker compose logs cloudflared --tail 50 | grep "Registered tunnel connection"
```

**Expected output (4 connections):**
```
INF Registered tunnel connection connIndex=0 ... location=yyz04 protocol=quic
INF Registered tunnel connection connIndex=1 ... location=yyz03 protocol=quic
INF Registered tunnel connection connIndex=2 ... location=yyz03 protocol=quic
INF Registered tunnel connection connIndex=3 ... location=yyz04 protocol=quic
```

**Pre-check summary — ALWAYS validate this, not just "Registered tunnel connection":**
```
|  COMPONENT         TARGET                     STATUS  DETAILS                                 |
|  DNS Resolution    region1.v2.argotunnel.com  PASS    DNS Resolved successfully               |
|  UDP Connectivity  region1.v2.argotunnel.com  FAIL    QUIC connection failed                  |
|  UDP Connectivity  region2.v2.argotunnel.com  FAIL    QUIC connection failed                  |
|  TCP Connectivity  region1.v2.argotunnel.com  PASS    HTTP/2 connection successful            |
|  TCP Connectivity  region2.v2.argotunnel.com  PASS    HTTP/2 connection successful            |
|  Cloudflare API    api.cloudflare.com:443     PASS    API is reachable                        |
|  SUMMARY: Environment ready with degraded transport. cloudflared will proceed using 'http2'.  |
```

**⚠ CRITICAL: Always check for "degraded transport" in logs.** Cloudflared may register initial connections via QUIC but then fail ongoing QUIC connectivity checks and fall back to HTTP/2. The tunnel is functional in HTTP/2 mode but suboptimal.

```bash
# Full validation script
CONNECTIONS=$(docker compose logs cloudflared --tail 100 | grep -c "Registered tunnel connection")
QUIC_CONN=$(docker compose logs cloudflared --tail 100 | grep "Registered tunnel connection" | grep -c "protocol=quic")
HTTP2_CONN=$(docker compose logs cloudflared --tail 100 | grep "Registered tunnel connection" | grep -c "protocol=http2")
DEGRADED=$(docker compose logs cloudflared --tail 50 | grep -c "degraded transport")

echo "Tunnel connections: $CONNECTIONS (QUIC: $QUIC_CONN, HTTP/2: $HTTP2_CONN)"
[ "$DEGRADED" -gt 0 ] && echo "⚠ DEGRADED mode — QUIC UDP 7844 blocked"
```

**QUIC failure on WSL2:** The QUIC precheck often fails on WSL2/Docker Desktop even with correct iptables rules (packets show as matched in `sudo iptables -L -v`). This is likely Windows Firewall or WSL2 virtual switch blocking outbound UDP at a layer below iptables. **The tunnel still works via HTTP/2 fallback** — it's just slower.

## Validation: Tunnel Connection Check

After starting cloudflared, validate tunnel connections:

```bash
docker compose logs cloudflared --tail 50 | grep "Registered tunnel connection"
```

**Full validation script:**
```bash
#!/bin/sh
CONNECTIONS=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep -c "Registered tunnel connection" || true)
QUIC_CONN=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep "Registered tunnel connection" | grep -c "protocol=quic" || true)
HTTP2_CONN=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep "Registered tunnel connection" | grep -c "protocol=http2" || true)
DEGRADED=$(docker compose logs cloudflared --tail 50 2>/dev/null | grep -c "degraded transport" || true)

echo "Tunnel connections: $CONNECTIONS (QUIC: $QUIC_CONN, HTTP/2: $HTTP2_CONN)"
[ "$DEGRADED" -gt 0 ] 2>/dev/null && echo "⚠ Running in DEGRADED mode (HTTP/2 fallback — QUIC UDP 7844 blocked)"
```

## Init Container Cleanup (Legacy — Option 1 only)

If using the old busybox sidecar + installer pattern (Option 1), the `cloudflared-installer` container is a one-shot that exits after downloading the binary. Clean it up after validating tunnel connections:

```bash
# Check installer exited and tunnel is connected
STATUS=$(docker inspect cloudflared-installer --format '{{.State.Status}}' 2>/dev/null || echo "none")
CONNECTIONS=$(docker compose logs cloudflared --tail 100 2>/dev/null | grep -c "Registered tunnel connection" || true)
[ "$CONNECTIONS" -ge 1 ] && [ "$STATUS" = "exited" ] && docker rm cloudflared-installer
```

**Better approach:** Migrate to Option 2 (self-contained alpine) to eliminate the installer entirely. See the "Init Container Absorption" pattern in the `init-container-absorption` skill.

## Token Management

The tunnel token is a JWT containing the tunnel ID. Store it as a Docker secret:

```bash
# Token file format (raw JWT string, no trailing newline)
printf '%s' 'eyJhIjoi...base64...' > secrets/cf_tunnel_token.txt
chmod 600 secrets/cf_tunnel_token.txt
```

**Extract tunnel ID from token (for debugging):**
```bash
cat secrets/cf_tunnel_token.txt | cut -d'.' -f1 | base64 -d 2>/dev/null
# Output: {"a":"...","t":"c94b55f4-9565-4d21-9e1d-6ed86d4779c5","s":"..."}
# The "t" field is the tunnel ID
```

## Traefik + Cloudflared Integration

When using both Traefik and Cloudflared:
- **Traefik** handles TLS termination and routing within your network
- **Cloudflared** tunnels external traffic to your Traefik proxy

**Recommended architecture:**
```
Internet → Cloudflare Edge → Cloudflare Tunnel → cloudflared container → Traefik (proxy network) → Services
```

**Important:** Cloudflared routes to Traefik's internal address. Configure your Cloudflare DNS records to point to the tunnel, and Traefik handles the rest via its Docker provider auto-discovery.

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `exec /entrypoint-wrapper.sh: no such file or directory` | scratch image has no shell | Use busybox sidecar pattern |
| `dial tcp ...:7844: i/o timeout` | Missing iptables rules for outbound | Add FORWARD + DOCKER-CT rules |
| `failed to validate token` | Invalid or expired tunnel token | Regenerate token in Cloudflare dashboard |
| `no delivery target resolved` | Wrong `--deliver` flag (Hermes cron) | Use `--deliver local` not `--deliver log` |
| `container name already in use` | Old cloudflared container exists | `docker rm -f cloudflared` before recreating |
