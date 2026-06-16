---
name: docker-network-troubleshooting
description: Diagnose and fix Docker network connectivity issues on WSL2 — broken bridge forwarding, missing MASQUERADE rules, DNS resolution, and outbound traffic blocks
source: auto-skill
extracted_at: '2026-06-15T20:25:25.646Z'
---

# Docker Network Troubleshooting (WSL2)

## Symptom Taxonomy

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| DNS resolves, TCP times out | Missing FORWARD iptables rule | Add `DOCKER-FORWARD` ACCEPT rule |
| Can reach containers, can't reach internet | Missing MASQUERADE rule | Add `POSTROUTING` MASQUERADE rule |
| Container can't reach container on same network | Bridge forwarding broken | Recreate network or add iptables rules |
| Works from host, fails from container | Network isolation (correct behavior) | Verify expected network isolation |

## Diagnostic Workflow

### Step 1: Verify Container Network Membership
```bash
docker inspect <container> --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

### Step 2: Test Inter-Container Connectivity
```bash
# Test TCP port from inside container
docker exec <source> python3 -c "
import socket; s=socket.socket(); s.settimeout(3)
s.connect(('<target>', <port>))
print('OK')
s.close()
"
# Or with wget/curl if available
docker exec <source> wget -qO- --timeout=3 http://<target>:<port>/
```

### Step 3: Test Outbound Connectivity
```bash
docker exec <container> wget -qO- --timeout=5 https://pypi.org/simple/ 2>&1 | head -3
```

### Step 4: Check Bridge Interfaces
```bash
# List Docker bridges
ip link show | grep br-

# Find bridge for a network
docker network inspect <network> --format '{{.Id}} {{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

### Step 5: Check iptables Rules
```bash
# FORWARD chain (inter-container)
sudo iptables -L DOCKER-FORWARD -n -v --line-numbers

# POSTROUTING chain (outbound NAT)
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers

# Check if bridge has MASQUERADE rule
sudo iptables -t nat -L POSTROUTING -n -v | grep br-XXXX
```

### Step 6: Check Container DNS
```bash
docker exec <container> cat /etc/resolv.conf
# Should show nameserver 127.0.0.11 (Docker internal DNS)
```

## Fixes

### Fix 1: Missing FORWARD Rule (Inter-Container Connectivity)

When containers on the same Docker bridge network can't reach each other:

```bash
# Find the bridge interface
BRIDGE="br-$(docker network inspect <network> --format '{{.Id}}' | cut -c1-12)"

# Add ACCEPT rule to DOCKER-FORWARD chain
sudo iptables -I DOCKER-FORWARD 3 -i $BRIDGE -j ACCEPT
sudo iptables -I DOCKER-BRIDGE 2 -i $BRIDGE -j DOCKER
```

**This fixed:** ai-ml network (br-1813ea894891), database network (br-a661348a0ada), and **proxy network (br-7a145f88f192)**

### Fix 1b: Allow Return Traffic (DOCKER-CT Chain)

When containers can send outbound but don't receive responses:

```bash
# Add RELATED,ESTABLISHED rule for return traffic
BRIDGE="br-7a145f88f192"  # proxy bridge
sudo iptables -I DOCKER-CT 4 -o $BRIDGE -m state --state RELATED,ESTABLISHED -j ACCEPT
```

**This fixed:** proxy network outbound — containers could send requests but Cloudflare edge responses were being dropped.

### Fix 2: Missing MASQUERADE Rule (Outbound Connectivity)

When containers can reach each other but can't reach the internet:

```bash
# Find the network subnet
SUBNET=$(docker network inspect <network> --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
BRIDGE=$(docker network inspect <network> --format '{{.Id}}' | cut -c1-12)

# Add MASQUERADE rule for outbound traffic
sudo iptables -t nat -A POSTROUTING -s $SUBNET -o eth0 -j MASQUERADE
```

**This fixed:** ai-ml network (172.21.0.0/16) — containers couldn't reach pypi.org

### Fix 3: Allow All Outbound Traffic

If the DOCKER-FORWARD chain has policy DROP and no outbound rules:

```bash
sudo iptables -I DOCKER-FORWARD 1 -o eth0 -j ACCEPT
```

### Fix 4: Network Recreation (When All Else Fails)

If iptables rules don't fix it, recreate the network:

```bash
# Create a new network
docker network create temp-bridge

# Connect both containers to the new network
docker network connect temp-bridge <container1>
docker network connect temp-bridge <container2>

# Test connectivity
docker exec <container1> curl -s http://<container2>:<port>/

# Update docker-compose.yml to include the new network persistently
# Then recreate containers to use it by default
```

## WSL2-Specific Issues

### Docker Desktop Network State Loss

Docker Desktop on WSL2 can lose iptables state after:
- Container restarts
- Docker Desktop service restart
- Windows sleep/resume cycles

**Symptoms:** Networks that worked before suddenly don't forward traffic between containers.

**Symptoms:** Containers that could reach pypi.org suddenly can't.

**Permanent fix:** Restart Docker Desktop service, or recreate the affected network.

### Multiple Bridge Networks

When you have many Docker networks, each gets its own bridge interface. The iptables rules must be set up for each bridge. Docker usually handles this automatically but on WSL2 it sometimes misses rules.

**Check all bridges have FORWARD rules:**
```bash
for net in $(docker network ls --format '{{.Name}}'); do
  subnet=$(docker network inspect $net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
  [ -n "$subnet" ] && echo "$net: $subnet"
done
```

## Service-Specific Network Requirements

| Service | Required Networks | Why |
|---------|------------------|-----|
| **hermes** | proxy, ai-ml, **agent-communication** | Needs agent-communication for outbound internet access (pypi.org) — ai-ml lacks MASQUERADE |
| **agent-zero** | ai-ml, agent-communication | Agent API calls between hermes-agent and agent-zero |
| **cloudflared** | proxy | Needs outbound HTTPS + QUIC (UDP 7844) to Cloudflare edge |
| **traefik** | proxy | External traffic routing + outbound to Let's Encrypt |
| **authentik-server** | proxy, database, security | DB access + external SSO |
| **guacamole** | proxy, ai-ml, database | Remote desktop + DB |
| **omniroute** | proxy, ai-ml, database | AI gateway + Redis + external |

## Verification After Fix

```bash
# Test inter-container
docker exec <source> python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('<target>', <port>)); print('OK')"

# Test outbound
docker exec <container> wget -qO- --timeout=5 https://pypi.org/simple/ | head -1

# Test all services
docker compose --profile '*' ps --format '{{.Name}}\t{{.Status}}' | grep -v healthy
```
