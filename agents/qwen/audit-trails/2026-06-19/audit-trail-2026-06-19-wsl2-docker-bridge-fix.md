# Audit Trail: WSL2 Docker Bridge Networking Fix
**Date:** 2026-06-19  
**Agent:** Qwen  
**Duration:** ~1 hour  

---

## 1. Intentional Rationale

User reported services "always getting stuck re-starting" after the stack had been idle. Investigation revealed a **systemic networking failure** affecting ALL Docker custom bridge networks on WSL2, causing silent packet drops between containers. This was the root cause behind recurring health check failures, postgres connection timeouts, and cloudflared QUIC failures observed across multiple boot cycles.

---

## 2. Root Cause Analysis

### Primary Issue: WSL2 `bridge-nf-call-iptables` + Docker nftables gap

**The smoking gun:** WSL2 kernel sets `net.bridge.bridge-nf-call-iptables = 1`, which routes ALL Layer 2 bridge traffic (including inter-container on the same bridge) through the iptables FORWARD chain.

Docker Desktop's nftables/iptables backend creates ACCEPT rules **only for `docker0`** (the default bridge). Custom bridges (`database`, `proxy`, `ai-ml`, `monitoring`, etc.) get **no rules**. Combined with the FORWARD chain's **DROP policy**, this silently kills:

| Traffic Type | Impact |
|---|---|
| Inter-container (same bridge) | DROPPED — containers can't reach each other |
| Container → Internet (outbound) | DROPPED — containers can't reach external services |
| Host → Container (published ports) | WORKS — uses PREROUTING NAT, bypasses FORWARD |

**Why it recurs:** The rules are lost on every WSL2 restart, Windows sleep/hibernate, Docker Desktop update, or `wsl --shutdown`. Docker Desktop does not re-create the rules for custom bridges.

### Secondary Issues Discovered

| # | Service | Issue | Root Cause |
|---|---|---|---|
| 1 | **authentik-server/worker** | UNHEALTHY — postgres connection refused | Race condition: no `depends_on` for postgres (server); postgres starts but `pg_isready` passes before DB is fully ready (worker) |
| 2 | **cloudflared** | QUIC connections fail 100% | WSL2 Docker doesn't forward UDP properly through bridge networking |
| 3 | **promtail** | Can't reach loki:3100 | Loki had no healthcheck; promtail used simple `depends_on` (service_started only) |
| 4 | **n8n** | "Failed to hard-delete executions" + timeout | Postgres unreachable from n8n container on database network |
| 5 | **plane-api/worker** | Postgres connection errors, restarts | Same bridge networking issue |
| 6 | **gitea** | "Render failed: install template" (recurring) | Benign — gitea not yet initialized, healthcheck hits install page |
| 7 | **hermes-agent** | Telegram API unreachable | ISP/network-level block on Telegram IPs, not a Docker issue |
| 8 | **database network** | Missing MASQUERADE rule | 172.20.0.0/16 subnet had no NAT rule for outbound traffic |

---

## 3. Fixes Applied

### Immediate Fixes (Runtime)

```bash
# 1. Allow same-bridge inter-container traffic
sudo iptables -I FORWARD 1 -m physdev --physdev-is-bridged -j ACCEPT

# 2. Allow RELATED,ESTABLISHED return traffic
sudo iptables -I FORWARD 2 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# 3. Allow outbound container traffic
sudo iptables -I FORWARD 3 -o eth0 -j ACCEPT

# 4. Add missing MASQUERADE for database network
sudo iptables -t nat -A POSTROUTING -s 172.20.0.0/16 ! -o br-a661348a0ada -j MASQUERADE
```

### Container Restarts (post-fix)
- `authentik-server` — restarted, now healthy
- `authentik-worker` — restarted, now healthy
- `promtail` — restarted, now connecting to loki
- `n8n` — restarted, postgres connections working
- `plane-api` + `plane-worker` — restarted, no more DB errors
- `cloudflared` — recreated with `--protocol http2` flag

### Compose File Changes (Persistent)

| File | Change |
|---|---|
| `compose/network/cloudflared/docker-compose.yml` | Added `--protocol http2` to cloudflared command |
| `compose/security/authentik-server/docker-compose.yml` | Added `depends_on` for postgres and redis with `condition: service_healthy` |
| `compose/monitoring/loki/docker-compose.yml` | Added healthcheck definition (wget on /ready endpoint) |
| `compose/monitoring/promtail/docker-compose.yml` | Changed `depends_on` from simple list to `condition: service_healthy` |

### Scripts Created

| File | Purpose |
|---|---|
| `scripts/fix-docker-networking.sh` | Standalone idempotent script to restore Docker bridge networking |
| `scripts/stack-troubleshooter.sh` | Comprehensive self-diagnosing, self-healing stack monitor (living document) |

---

## 4. Preventive Measures

### `stack-troubleshooter.sh` — Living Document
The script encodes all known failure modes as automated checks with self-healing:

```
Usage:
  ./scripts/stack-troubleshooter.sh              # Full diagnostic + auto-heal
  ./scripts/stack-troubleshooter.sh --diagnose    # Diagnostic only
  ./scripts/stack-troubleshooter.sh --heal        # Apply fixes only
  ./scripts/stack-troubleshooter.sh --status      # Quick status
  ./scripts/stack-troubleshooter.sh --service X   # Deep-dive on one service
```

**7 automated checks:**
1. Docker bridge networking (WSL2 iptables)
2. Container health status
3. Service dependency validation
4. Cloudflared tunnel status
5. Log error scanning
6. Resource usage monitoring
7. Auto-heal (restart unhealthy containers)

### Post-Boot Recovery
After any WSL2 restart, run:
```bash
sudo bash /mnt/d/docker/scripts/fix-docker-networking.sh
```

---

## 5. Validation Results

### Final Stack State (post-fix)
- **37 containers** total (35 running, 1 exited migration, 1 exited installer)
- **0 unhealthy** containers
- **0 restart loops**
- **Inter-container connectivity:** ✓ (all networks)
- **Outbound internet:** ✓ (containers can reach external services)
- **Cloudflared tunnel:** ✓ (connected via HTTP/2)
- **Postgres connectivity:** ✓ (all dependent services connected)

### Known Benign Warnings (not issues)
- Gitea "install template" errors — gitea hasn't been initialized yet
- Hermes-agent Telegram failures — ISP-level block, not Docker
- Redis "not responding" — requires auth, `redis-cli` without password is expected
- Affine high CPU (175%) — normal for this application
- agent-zero/cadvisor high memory (~11%) — expected for AI agent and monitoring

---

## 6. Items Deferred

| Item | Reason |
|---|---|
| Persistent iptables via `.wslconfig` boot command | Requires Windows-side config change — user decision |
| Gitea initialization | Requires web UI interaction by user |
| Telegram connectivity for hermes-agent | ISP-level block, needs proxy/VPN solution |
| Grafana elasticsearch plugin permission error | Cosmetic — plugin auto-install fails on read-only volume |
