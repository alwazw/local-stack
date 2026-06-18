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

### Fix 1a: Intra-Bridge FORWARD Rule (Same-Network Container-to-Container)

When two containers on the SAME bridge network can't talk to each other (e.g., litellm → postgres on ai-ml), you need an **intra-bridge** FORWARD rule where `-i` and `-o` are the same interface:

```bash
# Find the bridge interface for the network
BRIDGE="br-$(docker network inspect ai-ml --format '{{.Id}}' | cut -c1-12)"

# Add intra-bridge ACCEPT rule (same interface in AND out)
sudo iptables -I FORWARD -i $BRIDGE -o $BRIDGE -j ACCEPT
```

**Why:** The FORWARD chain default policy is DROP. Even though both containers are on the same bridge, traffic still traverses the FORWARD chain (bridge → bridge). Without this rule, packets are dropped despite being on the same network.

**This fixed:** litellm → postgres connectivity on the ai-ml network (br-1813ea894891). Both were on the same network but TCP connections timed out.

### Fix 1b: Outbound FORWARD Rules (Container → Internet)

When containers can't reach the internet from custom bridge networks:

```bash
# Add outbound and return-traffic rules for a bridge
BRIDGE="br-<hash>"
sudo iptables -I FORWARD -i $BRIDGE -o eth0 -j ACCEPT
sudo iptables -I FORWARD -i eth0 -o $BRIDGE -m state --state RELATED,ESTABLISHED -j ACCEPT
```

**This fixed:** hermes-agent Telegram API connectivity (couldn't reach api.telegram.org from ai-ml or agent-communication networks).

### Fix 1c: Allow Return Traffic (DOCKER-CT Chain)

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

## Cloudflare IP Collision with Docker Networks

### Symptom
Containers can reach most internet hosts but fail to connect to Cloudflare-proxied services (registry.ollama.ai, api.telegram.org sometimes). The specific error is `dial tcp 172.64.80.1:443: i/o timeout` or `EAGAIN`.

### Root Cause
Cloudflare uses the `172.64.x.x` IP range for edge servers. Docker's default private network ranges (`172.17.0.0/16` through `172.31.0.0/16`) overlap with this. When a container resolves `registry.ollama.ai` → `172.64.80.1`, Docker's routing table sends the packet to the internal bridge network instead of the default gateway.

```bash
# From host — works fine:
$ ip route get 172.64.80.1
172.64.80.1 via 172.19.128.1 dev eth0 src 172.19.136.93

# From inside container — routes to wrong interface:
$ docker exec <container> python3 -c "
import socket
s = socket.socket()
s.settimeout(10)
s.connect(('172.64.80.1', 443))  # TIMES OUT
"
```

### Workarounds

1. **Download on host, copy into container:**
   ```bash
   curl -fsSL -o /tmp/model.gguf https://huggingface.co/...
   docker cp /tmp/model.gguf <container>:/tmp/model.gguf
   ```

2. **Use the host's Ollama API** instead of pulling inside the container:
   ```bash
   # From WSL2 host (no Docker routing issues)
   curl -X POST http://localhost:11434/api/pull -d '{"name":"nomic-embed-text"}'
   ```

3. **Use an HTTP proxy** for the container to route through the host:
   ```yaml
   environment:
     HTTPS_PROXY: "http://host.docker.internal:3128"
   ```

4. **Remap Docker networks** to non-overlapping ranges (nuclear option):
   ```bash
   # Edit /etc/docker/daemon.json
   {
     "default-address-pools": [
       {"base": "10.100.0.0/16", "size": 24}
     ]
   }
   ```

### Ollama GGUF Import Workaround (When `ollama pull` Fails)

When `ollama pull` fails inside the container due to the Cloudflare IP collision, import models manually via GGUF:

#### Step 1: Download GGUF from HuggingFace (on WSL2 host)
```bash
curl -fsSL -o /tmp/nomic-embed-text.gguf \
  "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q8_0.gguf"
```
HuggingFace uses `huggingface.co` which resolves to non-Cloudflare IPs — downloads work fine.

#### Step 2: Copy GGUF and Modelfile into Ollama container
```bash
docker cp /tmp/nomic-embed-text.gguf ollama:/tmp/nomic-embed-text.gguf

cat > /tmp/Modelfile.nomic << 'EOF'
FROM /tmp/nomic-embed-text.gguf
PARAMETER num_ctx 8192
TEMPLATE """{{ if .System }}{{ .System }}
{{ end }}{{ .Prompt }}"""
SYSTEM "Represent the input text for semantic search."
EOF
docker cp /tmp/Modelfile.nomic ollama:/tmp/Modelfile.nomic
```

#### Step 3: Create model inside container
```bash
docker exec ollama ollama create nomic-embed-text -f /tmp/Modelfile.nomic
```

**Important:** The `ollama create` command MUST run inside the container — the Ollama API (`POST /api/create`) with `modelfile` in the JSON body does NOT work reliably for FROM directives in newer versions (returns `neither 'from' or 'files' was specified`). Use the CLI directly.

#### Step 4: Verify
```bash
docker exec ollama ollama list
# Should show: nomic-embed-text:latest  146 MB  <timestamp>
```

#### Why This Works
- GGUF files are self-contained — no registry pull needed
- `ollama create` parses the GGUF metadata and registers the model in Ollama's local manifest
- The model is then available for embeddings via `http://ollama:11434/api/embed`
- LiteLLM's `ollama/<model-name>` provider can route to it

#### Common GGUF Sources
| Model | HuggingFace URL | Use Case |
|-------|----------------|----------|
| nomic-embed-text v1.5 | `nomic-ai/nomic-embed-text-v1.5-GGUF` | Embeddings (768 dims) |
| deepseek-r1:8b | `deepseek-ai/DeepSeek-R1-Distill-Llama-8B-GGUF` | Local reasoning fallback |
| dolphin3 | `cognitivecomputations/dolphin-3.0-Qwen2.5-7B-GGUF` | Fast utility fallback |

### Affected Services
- `registry.ollama.ai` (Cloudflare edge — `172.64.x.x`)
- Any service behind Cloudflare proxy that resolves to `172.64.x.x`
- `api.telegram.org` (sometimes — Cloudflare, though usually resolves to `149.154.x.x`)

## IPv6 DNS Resolution Causing Connection Failures

### Symptom
Container can resolve a hostname via DNS but TCP connections fail. Direct IP connections to the same port work.

### Root Cause
Docker's internal DNS returns IPv6 addresses (AAAA records) for some hosts. The container's networking stack may not have proper IPv6 routing configured, causing connections to silently timeout.

```bash
# Container resolves IPv6:
docker exec <container> getent hosts registry.ollama.ai
# → 2606:4700:130:436c:6f75:6466:6c61:7265 registry.ollama.ai

# Python tries IPv6 first, hangs:
docker exec <container> python3 -c "
import socket
print(socket.getaddrinfo('registry.ollama.ai', 443))
# Returns both IPv4 and IPv6 — IPv6 attempted first, times out
"
```

### Fix
Force IPv4 in your connection code, or add `network.force_ipv4: true` to application config:

```python
# Force IPv4 resolution
import socket
addr = socket.getaddrinfo('registry.ollama.ai', 443, socket.AF_INET)
ip = addr[0][4][0]  # IPv4 address
```

For Hermes Agent, set in config.yaml:
```yaml
network:
  force_ipv4: false  # Set to true if IPv6 causes issues
```

## Auto-Discovery Script for All Bridge Networks

After Docker Desktop restart or WSL2 reboot, all iptables FORWARD rules are lost. This script auto-discovers all Docker bridge networks and re-adds the rules:

```bash
#!/bin/bash
# fix-docker-forwarding.sh — run with sudo after Docker Desktop restart
set -e
ETH_IFACE="eth0"

ip -o link show | grep -oP 'br-[a-f0-9]+' | sort -u | while read BRIDGE; do
    NET_NAME=""
    while IFS=: read -r NAME ID; do
        if ip link show "$BRIDGE" 2>/dev/null | grep -q "${ID:0:12}"; then
            NET_NAME="$NAME"
            break
        fi
    done < <(docker network ls --format '{{.Name}}:{{.ID}}')

    [ -z "$NET_NAME" ] && NET_NAME="unknown"

    if ip link show "$BRIDGE" &>/dev/null; then
        # Intra-bridge (container ↔ container on same network)
        sudo iptables -C FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT 2>/dev/null || \
            sudo iptables -I FORWARD -i "$BRIDGE" -o "$BRIDGE" -j ACCEPT

        # Outbound (container → internet)
        sudo iptables -C FORWARD -i "$BRIDGE" -o "$ETH_IFACE" -j ACCEPT 2>/dev/null || \
            sudo iptables -I FORWARD -i "$BRIDGE" -o "$ETH_IFACE" -j ACCEPT

        # Return traffic (internet → container)
        sudo iptables -C FORWARD -i "$ETH_IFACE" -o "$BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
            sudo iptables -I FORWARD -i "$ETH_IFACE" -o "$BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi
done
```

Store at `scripts/fix-docker-forwarding.sh` and run with `sudo bash` after every Docker Desktop restart.

## Verification After Fix

```bash
# Test inter-container
docker exec <source> python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('<target>', <port>)); print('OK')"

# Test outbound
docker exec <container> wget -qO- --timeout=5 https://pypi.org/simple/ | head -1

# Test all services
docker compose --profile '*' ps --format '{{.Name}}\t{{.Status}}' | grep -v healthy
```
