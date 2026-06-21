#!/usr/bin/env bash
# ============================================================================
# stack-troubleshooter.sh — Self-diagnosing, self-healing Docker stack monitor
# ============================================================================
# A living document of known failure modes and automated fixes for the AEF3
# Docker Compose stack on WSL2.
#
# Usage:
#   ./scripts/stack-troubleshooter.sh              # Full diagnostic + auto-heal
#   ./scripts/stack-troubleshooter.sh --diagnose    # Diagnostic only (no fixes)
#   ./scripts/stack-troubleshooter.sh --heal        # Apply known fixes only
#   ./scripts/stack-troubleshooter.sh --status      # Quick status check
#   ./scripts/stack-troubleshooter.sh --service X   # Deep-dive on one service
#
# Known failure modes (add new ones as they're discovered):
#   1. WSL2 bridge-nf-call-iptables kills Docker custom bridge networking
#   2. Cloudflared QUIC protocol fails on WSL2 (use --protocol http2)
#   3. Missing depends_on causes startup race conditions (authentik, plane)
#   4. Loki has no healthcheck → promtail starts before loki is ready
#   5. Postgres "starting up" race when healthcheck passes too early
#   6. Gitea install page healthcheck false positives (benign)
#   7. Hermes-agent Telegram API unreachable (ISP-level, not Docker)
# ============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
PROJECT_ROOT="/mnt/d/docker"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
LOG_DIR="$PROJECT_ROOT/docs/troubleshooter-logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
ISSUES_FOUND=0
ISSUES_FIXED=0
WARNINGS=0

# ── Helpers ────────────────────────────────────────────────────────────────
log_ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
log_warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; ((WARNINGS++)) || true; }
log_fail()  { echo -e "  ${RED}✗${NC} $*"; ((ISSUES_FOUND++)) || true; }
log_fix()   { echo -e "  ${CYAN}→${NC} $*"; ((ISSUES_FIXED++)) || true; }
log_info()  { echo -e "  ${CYAN}ℹ${NC} $*"; }
log_section() { echo -e "\n${BOLD}━━━ $* ━━━${NC}"; }

needs_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if sudo -n true 2>/dev/null; then
      return 0
    else
      log_warn "sudo access needed for network fixes but not available"
      return 1
    fi
  fi
  return 0
}

# ── Parse arguments ────────────────────────────────────────────────────────
MODE="full"
TARGET_SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diagnose) MODE="diagnose"; shift ;;
    --heal)     MODE="heal"; shift ;;
    --status)   MODE="status"; shift ;;
    --service)  MODE="service"; TARGET_SERVICE="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--diagnose|--heal|--status|--service NAME]"
      echo ""
      echo "Modes:"
      echo "  (default)    Full diagnostic + auto-heal"
      echo "  --diagnose   Diagnostic only (no fixes applied)"
      echo "  --heal       Apply known fixes only"
      echo "  --status     Quick health status check"
      echo "  --service X  Deep-dive diagnostic on a specific service"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR" 2>/dev/null || true

echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║    AEF3 Stack Troubleshooter — $TIMESTAMP    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "  Mode: ${CYAN}$MODE${NC}"

# ============================================================================
# CHECK 1: Docker Bridge Networking (WSL2 iptables)
# ============================================================================
# FAILURE MODE: WSL2 sets bridge-nf-call-iptables=1, routing L2 bridge traffic
# through iptables FORWARD chain. Docker only creates rules for docker0, not
# custom bridges. Result: ALL inter-container traffic silently dropped.
# SYMPTOMS: postgres connection refused/timeout, loki unreachable, QUIC failures
# FIX: Add physdev-is-bridged ACCEPT + RELATED,ESTABLISHED + outbound ACCEPT
# ============================================================================
check_docker_networking() {
  log_section "CHECK 1: Docker Bridge Networking (WSL2)"

  # Check bridge-nf-call-iptables
  local bridge_nf
  bridge_nf=$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo "0")

  if [[ "$bridge_nf" != "1" ]]; then
    log_ok "bridge-nf-call-iptables is OFF"
    return
  fi

  log_warn "bridge-nf-call-iptables is ON — checking FORWARD rules"

  # Check FORWARD policy
  local forward_policy
  forward_policy=$(sudo iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "ACCEPT")

  if [[ "$forward_policy" != "DROP" ]]; then
    log_ok "FORWARD chain policy is $forward_policy"
    return
  fi

  # Check if same-bridge rule exists
  if sudo iptables -C FORWARD -m physdev --physdev-is-bridged -j ACCEPT 2>/dev/null; then
    log_ok "Same-bridge ACCEPT rule exists"
  else
    log_fail "Same-bridge ACCEPT rule MISSING — inter-container traffic is being dropped!"
    if [[ "$MODE" != "diagnose" ]]; then
      sudo iptables -I FORWARD 1 -m physdev --physdev-is-bridged -j ACCEPT
      log_fix "Added same-bridge ACCEPT rule"
    fi
  fi

  # Check RELATED,ESTABLISHED rule
  if sudo iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    log_ok "RELATED,ESTABLISHED ACCEPT rule exists"
  else
    log_fail "RELATED,ESTABLISHED rule MISSING — return traffic blocked"
    if [[ "$MODE" != "diagnose" ]]; then
      sudo iptables -I FORWARD 2 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
      log_fix "Added RELATED,ESTABLISHED ACCEPT rule"
    fi
  fi

  # Check outbound rule
  local outbound_iface
  outbound_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
  if [[ -n "$outbound_iface" ]]; then
    if sudo iptables -C FORWARD -o "$outbound_iface" -j ACCEPT 2>/dev/null; then
      log_ok "Outbound ACCEPT rule for $outbound_iface exists"
    else
      log_fail "Outbound ACCEPT rule for $outbound_iface MISSING — containers can't reach internet"
      if [[ "$MODE" != "diagnose" ]]; then
        sudo iptables -I FORWARD 3 -o "$outbound_iface" -j ACCEPT
        log_fix "Added outbound ACCEPT rule for $outbound_iface"
      fi
    fi
  fi

  # Quick connectivity validation
  log_info "Validating inter-container connectivity..."
  local test_result
  test_result=$(docker exec postgres pg_isready -h localhost 2>&1 || echo "FAIL")
  if echo "$test_result" | grep -q "accepting"; then
    log_ok "Postgres self-connect: OK"
  else
    log_fail "Postgres self-connect: FAILED"
  fi

  # Test cross-container on database network
  if docker ps --format '{{.Names}}' | grep -q "n8n"; then
    local n8n_pg
    n8n_pg=$(docker exec n8n node -e "
      const net=require('net');
      const s=new net.Socket();
      s.setTimeout(3000);
      s.connect(5432,'postgres',()=>{console.log('OK');s.destroy()});
      s.on('error',(e)=>console.log('FAIL'));
      s.on('timeout',()=>{console.log('TIMEOUT');s.destroy()})
    " 2>&1)
    if [[ "$n8n_pg" == "OK" ]]; then
      log_ok "Cross-container (n8n→postgres): OK"
    else
      log_fail "Cross-container (n8n→postgres): $n8n_pg"
    fi
  fi
}

# ============================================================================
# CHECK 2: Container Health Status
# ============================================================================
check_container_health() {
  log_section "CHECK 2: Container Health Status"

  local unhealthy_count=0
  local restarting_count=0
  local high_restart_count=0

  while IFS= read -r name; do
    local state health restarts
    state=$(docker inspect --format='{{.State.State}}' "$name" 2>/dev/null || echo "unknown")
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-hc{{end}}' "$name" 2>/dev/null || echo "unknown")
    restarts=$(docker inspect --format='{{.RestartCount}}' "$name" 2>/dev/null || echo "0")

    if [[ "$state" == "restarting" ]]; then
      log_fail "$name: STUCK IN RESTART LOOP"
      ((restarting_count++)) || true
    elif [[ "$health" == "unhealthy" ]]; then
      log_fail "$name: UNHEALTHY (restarts: $restarts)"
      ((unhealthy_count++)) || true
    elif [[ "$restarts" -gt 3 ]]; then
      log_warn "$name: High restart count ($restarts)"
      ((high_restart_count++)) || true
    elif [[ "$health" == "healthy" ]]; then
      log_ok "$name"
    elif [[ "$state" == "exited" ]]; then
      local exit_code
      exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$name" 2>/dev/null || echo "?")
      if [[ "$exit_code" == "0" ]]; then
        log_ok "$name: exited cleanly (one-shot)"
      else
        log_fail "$name: exited with code $exit_code"
      fi
    else
      log_ok "$name (no healthcheck, running)"
    fi
  done < <(docker ps -a --format '{{.Names}}' | sort)

  if [[ $unhealthy_count -eq 0 && $restarting_count -eq 0 && $high_restart_count -eq 0 ]]; then
    log_ok "All containers healthy"
  else
    log_fail "Unhealthy: $unhealthy_count | Restarting: $restarting_count | High restarts: $high_restart_count"
  fi
}

# ============================================================================
# CHECK 3: Service Dependency Validation
# ============================================================================
# FAILURE MODE: Services start before their dependencies are ready.
# Known gaps:
#   - authentik-server missing depends_on for postgres/redis (FIXED in compose)
#   - promtail using simple depends_on for loki (FIXED: loki now has healthcheck)
#   - plane-worker simple depends_on plane-api (no condition)
# ============================================================================
check_dependencies() {
  log_section "CHECK 3: Service Dependencies"

  # Check if postgres is ready before dependent services
  local pg_ready
  pg_ready=$(docker exec postgres pg_isready 2>&1 || echo "FAIL")
  if echo "$pg_ready" | grep -q "accepting"; then
    log_ok "Postgres: accepting connections"
  else
    log_fail "Postgres: NOT accepting connections"
    log_info "Dependent services (authentik, n8n, plane, gitea) will fail until postgres is ready"
  fi

  # Check redis
  local redis_ok
  redis_ok=$(docker exec redis redis-cli ping 2>&1 || echo "FAIL")
  if echo "$redis_ok" | grep -q "PONG"; then
    log_ok "Redis: responding"
  else
    log_warn "Redis: not responding (may need auth)"
  fi

  # Check known dependency gaps in compose files
  local auth_server_compose="$PROJECT_ROOT/compose/security/authentik-server/docker-compose.yml"
  if [[ -f "$auth_server_compose" ]]; then
    if grep -q "depends_on" "$auth_server_compose"; then
      log_ok "authentik-server: has depends_on"
    else
      log_warn "authentik-server: MISSING depends_on for postgres/redis"
    fi
  fi

  local loki_compose="$PROJECT_ROOT/compose/monitoring/loki/docker-compose.yml"
  if [[ -f "$loki_compose" ]]; then
    if grep -q "healthcheck" "$loki_compose"; then
      log_ok "loki: has healthcheck defined"
    else
      log_warn "loki: NO healthcheck — promtail may start before loki is ready"
    fi
  fi
}

# ============================================================================
# CHECK 4: Cloudflared Tunnel
# ============================================================================
# FAILURE MODE: QUIC (UDP) doesn't work through Docker networking on WSL2.
# Cloudflared fails to establish tunnel connections.
# FIX: Add --protocol http2 to cloudflared command in compose file
# ============================================================================
check_cloudflared() {
  log_section "CHECK 4: Cloudflared Tunnel"

  if ! docker ps --format '{{.Names}}' | grep -q "cloudflared"; then
    log_warn "cloudflared container not running"
    return
  fi

  # Check if tunnel is connected
  local recent_logs
  recent_logs=$(docker logs --tail 30 cloudflared 2>&1)

  if echo "$recent_logs" | grep -qi "Registered tunnel connection"; then
    log_ok "Tunnel: connected to Cloudflare edge"
  elif echo "$recent_logs" | grep -qi "hard_fail=true"; then
    log_fail "Tunnel: HARD FAIL — cannot connect to any edge"
  elif echo "$recent_logs" | grep -qi "quic.*timeout\|quic.*failed"; then
    log_warn "Tunnel: QUIC connections failing (expected on WSL2)"
    # Check if HTTP/2 fallback is working
    if echo "$recent_logs" | grep -qi "http2\|http/2.*pass\|proceed.*http2"; then
      log_ok "Tunnel: HTTP/2 fallback is working"
    else
      log_fail "Tunnel: QUIC failing AND no HTTP/2 fallback"
      # Check compose file for --protocol http2
      local cf_compose="$PROJECT_ROOT/compose/network/cloudflared/docker-compose.yml"
      if [[ -f "$cf_compose" ]] && ! grep -q "protocol http2" "$cf_compose"; then
        log_info "FIX: Add '--protocol http2' to cloudflared command in compose file"
        if [[ "$MODE" != "diagnose" ]]; then
          sed -i 's/tunnel --no-autoupdate run/tunnel --no-autoupdate --protocol http2 run/' "$cf_compose"
          log_fix "Added --protocol http2 to cloudflared compose file"
          log_info "Run: docker compose up -d cloudflared"
        fi
      fi
    fi
  elif echo "$recent_logs" | grep -qi "TCP Connectivity.*PASS\|http/2 connection successful"; then
    log_ok "Tunnel: HTTP/2 connections successful"
  else
    log_info "Tunnel: status unclear — check logs"
  fi
}

# ============================================================================
# CHECK 5: Log Error Scan
# ============================================================================
check_log_errors() {
  log_section "CHECK 5: Recent Log Errors (last 5 minutes)"

  local error_services=()

  while IFS= read -r name; do
    local errs
    errs=$(docker logs --since 5m "$name" 2>&1 | grep -ciE \
      "(fatal|panic|error|exception|crash|oom|killed|failed|refused|timeout)" \
      2>/dev/null || true)
    errs=$(echo "$errs" | tr -d '[:space:]')
    errs=${errs:-0}

    if [[ "$errs" -gt 5 ]]; then
      # Get the most common error pattern
      local top_error
      top_error=$(docker logs --since 5m "$name" 2>&1 | grep -iE \
        "(fatal|panic|error|exception|crash|oom|killed|failed|refused|timeout)" \
        2>/dev/null | head -1 | cut -c1-120 || true)
      log_warn "$name: $errs error lines — sample: $top_error"
      error_services+=("$name")
    fi
  done < <(docker ps --format '{{.Names}}')

  if [[ ${#error_services[@]} -eq 0 ]]; then
    log_ok "No significant errors in last 5 minutes"
  else
    log_info "Services with errors: ${error_services[*]}"
    log_info "Known benign errors: gitea (install template), hermes-agent (Telegram ISP block), grafana (plugin permissions)"
  fi
}

# ============================================================================
# CHECK 6: Resource Usage
# ============================================================================
check_resources() {
  log_section "CHECK 6: Resource Usage"

  local high_mem=()
  local high_cpu=()

  while IFS= read -r line; do
    local name cpu mem_pct
    name=$(echo "$line" | awk '{print $1}')
    cpu=$(echo "$line" | awk '{gsub(/%/,""); print $2}')
    mem_pct=$(echo "$line" | awk '{gsub(/%/,""); print $NF}')

    if [[ -n "$cpu" ]] && (( $(echo "$cpu > 100" | bc -l 2>/dev/null || echo 0) )); then
      high_cpu+=("$name (${cpu}%)")
    fi
    if [[ -n "$mem_pct" ]] && (( $(echo "$mem_pct > 10" | bc -l 2>/dev/null || echo 0) )); then
      high_mem+=("$name (${mem_pct}%)")
    fi
  done < <(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemPerc}}" 2>/dev/null)

  if [[ ${#high_cpu[@]} -gt 0 ]]; then
    log_warn "High CPU: ${high_cpu[*]}"
  else
    log_ok "CPU usage normal"
  fi

  if [[ ${#high_mem[@]} -gt 0 ]]; then
    log_warn "High memory: ${high_mem[*]}"
  else
    log_ok "Memory usage normal"
  fi

  # Check WSL2 total memory
  local total_mem used_mem
  total_mem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  used_mem=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  local avail_pct=$(( used_mem * 100 / total_mem ))
  log_info "WSL2 memory: ${avail_pct}% available ($(( used_mem / 1024 ))MB / $(( total_mem / 1024 ))MB)"
}

# ============================================================================
# CHECK 7: Auto-heal Unhealthy Containers
# ============================================================================
auto_heal() {
  log_section "CHECK 7: Auto-Heal"

  if [[ "$MODE" == "diagnose" || "$MODE" == "status" ]]; then
    log_info "Skipping auto-heal in $MODE mode"
    return
  fi

  # Restart unhealthy containers
  while IFS= read -r name; do
    local health
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}ok{{end}}' "$name" 2>/dev/null || echo "ok")

    if [[ "$health" == "unhealthy" ]]; then
      log_info "Restarting unhealthy container: $name"
      docker restart "$name" 2>&1
      log_fix "Restarted $name"
    fi
  done < <(docker ps --format '{{.Names}}')

  # Check if networking fix resolved issues (wait 10s for containers to stabilize)
  log_info "Waiting 10s for containers to stabilize..."
  sleep 10

  # Re-check health
  local still_unhealthy=0
  while IFS= read -r name; do
    local health
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}ok{{end}}' "$name" 2>/dev/null || echo "ok")
    if [[ "$health" == "unhealthy" ]]; then
      log_fail "$name: STILL unhealthy after restart"
      ((still_unhealthy++)) || true
    fi
  done < <(docker ps --format '{{.Names}}')

  if [[ $still_unhealthy -eq 0 ]]; then
    log_ok "All containers recovered"
  else
    log_fail "$still_unhealthy container(s) still unhealthy — manual intervention needed"
  fi
}

# ============================================================================
# CHECK 8: Port Conflict Detection (Host + Internal Network)
# ============================================================================
# FAILURE MODE 1 (Host): Two services bind the same host port.
#   SYMPTOM: "port already allocated" on docker compose up.
#   FIX: Ensure unique host ports in .env.
# FAILURE MODE 2 (Internal): Two containers on the same Docker network expose
#   the same internal port. Docker DNS resolves by container name so this is
#   usually benign, but causes confusion in Traefik auto-discovery and makes
#   the architecture harder to reason about.
#   FIX: Remove unnecessary network attachments; ensure all Traefik-routed
#   services have explicit loadbalancer.server.port labels.
# ============================================================================
check_port_conflicts() {
  log_section "CHECK 8: Port Conflicts (Host + Internal)"

  # ── Part A: Host port conflicts ──
  log_info "Checking host port bindings..."
  local -A host_port_map
  local host_conflicts=0

  while IFS= read -r line; do
    local name ports
    name=$(echo "$line" | cut -d: -f1 | xargs)
    ports=$(echo "$line" | cut -d: -f2-)

    while read -r binding; do
      if [[ "$binding" =~ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)-\> ]]; then
        local host_port="${BASH_REMATCH[2]}"
        if [[ -n "${host_port_map[$host_port]:-}" ]]; then
          log_fail "HOST CONFLICT: Port $host_port used by ${host_port_map[$host_port]} and $name"
          ((host_conflicts++)) || true
        else
          host_port_map[$host_port]="$name"
        fi
      fi
    done < <(echo "$ports" | tr ',' '\n' | xargs)
  done < <(docker ps --format '{{.Names}}: {{.Ports}}')

  if [[ $host_conflicts -eq 0 ]]; then
    log_ok "Host ports: No conflicts (${#host_port_map[@]} unique ports in use)"
  else
    log_fail "Host ports: $host_conflicts conflict(s) — check .env for duplicates"
  fi

  # Check for unbound ports (services exposing to all interfaces)
  local unbound=0
  while IFS= read -r line; do
    if echo "$line" | grep -qP '0\.0\.0\.0:[0-9]+->'; then
      local name=$(echo "$line" | cut -d: -f1 | xargs)
      if [[ "$name" != "traefik" && "$name" != "homepage" ]]; then
        log_warn "$name: port exposed to 0.0.0.0 (all interfaces)"
        ((unbound++)) || true
      fi
    fi
  done < <(docker ps --format '{{.Names}}: {{.Ports}}')

  if [[ $unbound -eq 0 ]]; then
    log_ok "Bind addresses: All non-public ports bound to 127.0.0.1"
  fi

  # ── Part B: Internal network port conflicts ──
  log_info "Checking internal network port overlaps..."
  local internal_conflicts=0
  local -a conflict_lines=()

  # Build network:port → container mapping
  local tmpfile
  tmpfile=$(mktemp)
  local all_names
  all_names=$(docker ps --format '{{.Names}}' | sort)
  
  for name in $all_names; do
    local networks ports_json internal_ports
    networks=$(docker inspect "$name" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || true)
    ports_json=$(docker inspect "$name" --format='{{json .NetworkSettings.Ports}}' 2>/dev/null || true)
    internal_ports=$(echo "$ports_json" | grep -oP '"(\d+)/tcp"' 2>/dev/null | sed 's/"//g; s/\/tcp//g' | sort -un || true)
    for net in $networks; do
      for port in $internal_ports; do
        echo "$net:$port:$name" >> "$tmpfile"
      done
    done
  done

  # Find conflicts (same network:port with >1 container)
  local awk_output
  awk_output=$(awk -F: '{key=$1":"$2; containers[key]=containers[key] " " $3; count[key]++} END {for (k in count) if (count[k]>1) print k " →" containers[k] " (" count[k] ")"}' "$tmpfile" 2>/dev/null | sort || true)
  
  if [[ -n "$awk_output" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      log_warn "INTERNAL: $line"
      ((internal_conflicts++)) || true
    done <<< "$awk_output"
  fi

  rm -f "$tmpfile"

  if [[ $internal_conflicts -eq 0 ]]; then
    log_ok "Internal ports: No network conflicts"
  else
    log_info "Internal ports: $internal_conflicts overlap(s) detected"
    log_info "These are usually benign (Docker DNS resolves by container name)"
    log_info "Ensure all Traefik-routed services have explicit loadbalancer.server.port labels"
  fi

  # ── Part C: Missing Traefik port labels ──
  log_info "Checking Traefik label completeness..."
  local missing_labels=0
  while IFS= read -r name; do
    local has_traefik has_port_label
    has_traefik=$(docker inspect "$name" --format='{{index .Config.Labels "traefik.enable"}}' 2>/dev/null)
    if [[ "$has_traefik" == "true" ]]; then
      # Skip traefik itself — it uses api@internal service
      if [[ "$name" == "traefik" ]]; then continue; fi
      has_port_label=$(docker inspect "$name" --format='{{json .Config.Labels}}' 2>/dev/null | grep -c "loadbalancer.server.port" || true)
      if [[ "$has_port_label" -eq 0 ]]; then
        log_warn "$name: Traefik enabled but missing loadbalancer.server.port label"
        ((missing_labels++)) || true
      fi
    fi
  done < <(docker ps --format '{{.Names}}')

  if [[ $missing_labels -eq 0 ]]; then
    log_ok "Traefik labels: All routed services have explicit port labels"
  else
    log_fail "Traefik labels: $missing_labels service(s) missing loadbalancer.server.port"
    log_info "Fix: Add traefik.http.services.<name>.loadbalancer.server.port=<port> label"
  fi
}

# ============================================================================
# CHECK 9: .env Compliance Validation
# ============================================================================
# FAILURE MODE: Ports hardcoded in compose files instead of using variables.
# SYMPTOMS: Changing ports requires editing multiple files instead of .env.
# REQUIREMENTS:
#   1. All ports in compose files must use ${PORT_*:-default} syntax
#   2. All PORT_* variables must be defined in .env.example
#   3. .env.example ports must be sorted by port number
#   4. No duplicate port values in .env.example
# ============================================================================
check_env_compliance() {
  log_section "CHECK 9: .env Compliance"

  local env_file="$PROJECT_ROOT/.env"
  local env_example="$PROJECT_ROOT/.env.example"
  local issues=0

  # Check if .env exists
  if [[ ! -f "$env_file" ]]; then
    log_fail ".env file not found — run: cp .env.example .env"
    return
  fi

  # Extract PORT_* variables from .env
  local -A env_ports
  while IFS='=' read -r var val; do
    if [[ "$var" =~ ^PORT_ ]]; then
      env_ports[$var]="$val"
    fi
  done < <(grep -E '^PORT_' "$env_file")

  # Check for duplicate port values
  local -A port_values
  for var in "${!env_ports[@]}"; do
    local port="${env_ports[$var]}"
    if [[ -n "${port_values[$port]:-}" ]]; then
      log_fail "DUPLICATE PORT: $var and ${port_values[$port]} both use port $port"
      ((issues++)) || true
    else
      port_values[$port]="$var"
    fi
  done

  # Check if ports are sorted in .env.example
  if [[ -f "$env_example" ]]; then
    local prev_port=0
    local sorted=true
    while IFS='=' read -r var val; do
      if [[ "$var" =~ ^PORT_ && "$val" =~ ^[0-9]+$ ]]; then
        if [[ $val -lt $prev_port ]]; then
          sorted=false
          break
        fi
        prev_port=$val
      fi
    done < <(grep -E '^PORT_' "$env_example")

    if $sorted; then
      log_ok "Ports in .env.example are sorted numerically"
    else
      log_warn "Ports in .env.example are NOT sorted by port number"
    fi
  fi

  # Scan compose files for hardcoded ports
  local hardcoded=0
  while IFS= read -r file; do
    # Look for port mappings that don't use ${VAR} syntax
    if grep -qE '^\s*-\s*"(127\.0\.0\.1|0\.0\.0\.0):[0-9]+:' "$file"; then
      local service=$(basename "$(dirname "$file")")
      log_warn "$service: hardcoded port in $file"
      ((hardcoded++)) || true
    fi
  done < <(find "$PROJECT_ROOT/compose" -name 'docker-compose.yml' -not -path '*/data/*' 2>/dev/null)

  if [[ $hardcoded -eq 0 ]]; then
    log_ok "All compose files use \${PORT_*:-default} variable syntax"
  else
    log_fail "$hardcoded compose file(s) have hardcoded ports"
    log_info "Fix: Replace hardcoded ports with \${PORT_SERVICE:-default} syntax"
  fi

  # Check for variable syntax consistency (${VAR:-default} not ${VAR-default})
  local bad_syntax=0
  while IFS= read -r file; do
    if grep -qE '\$\{[A-Z_]+-[0-9]+' "$file" && ! grep -qE '\$\{[A-Z_]+:-[0-9]+' "$file"; then
      local service=$(basename "$(dirname "$file")")
      log_warn "$service: uses \${VAR-default} instead of \${VAR:-default}"
      ((bad_syntax++)) || true
    fi
  done < <(find "$PROJECT_ROOT/compose" -name 'docker-compose.yml' -not -path '*/data/*' 2>/dev/null)

  if [[ $bad_syntax -eq 0 ]]; then
    log_ok "All compose files use consistent \${VAR:-default} syntax"
  fi

  # Summary
  local total_ports=${#env_ports[@]}
  log_info "Total port variables in .env: $total_ports"

  if [[ $issues -eq 0 && $hardcoded -eq 0 ]]; then
    log_ok ".env compliance: PASS"
  else
    log_fail ".env compliance: FAIL ($issues issues, $hardcoded hardcoded ports)"
  fi
}

# ============================================================================
# CHECK 10: Network Diagnostics
# ============================================================================
# FAILURE MODE: Docker bridge networking broken on WSL2.
# SYMPTOMS: Containers can't reach each other or the internet.
# ROOT CAUSE: WSL2 kernel sets bridge-nf-call-iptables=1, but Docker only
# creates iptables rules for docker0, not custom bridges.
# FIX: Run fix-docker-networking.sh or apply rules manually.
# ============================================================================
check_network_diagnostics() {
  log_section "CHECK 10: Network Diagnostics"

  # Check if we're on WSL2
  if ! grep -qi microsoft /proc/version 2>/dev/null; then
    log_info "Not running on WSL2 — skipping WSL2-specific checks"
    return
  fi

  log_info "WSL2 environment detected"

  # Check bridge-nf-call-iptables
  local bridge_nf
  bridge_nf=$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo "0")

  if [[ "$bridge_nf" == "1" ]]; then
    log_warn "bridge-nf-call-iptables is ON (WSL2 default)"
    log_info "This causes Docker bridge traffic to go through iptables FORWARD chain"
  else
    log_ok "bridge-nf-call-iptables is OFF"
  fi

  # Check iptables FORWARD policy
  local forward_policy
  forward_policy=$(sudo iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "UNKNOWN")

  log_info "iptables FORWARD policy: $forward_policy"

  # Check if fix-docker-networking.sh exists and is executable
  local fix_script="$PROJECT_ROOT/scripts/fix-docker-networking.sh"
  if [[ -x "$fix_script" ]]; then
    log_ok "fix-docker-networking.sh exists and is executable"

    # Check if the script has been run (look for our custom rules)
    if sudo iptables -C FORWARD -m physdev --physdev-is-bridged -j ACCEPT 2>/dev/null; then
      log_ok "Same-bridge ACCEPT rule: PRESENT"
    else
      log_fail "Same-bridge ACCEPT rule: MISSING"
      log_info "Run: sudo bash $fix_script"
    fi

    if sudo iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
      log_ok "RELATED,ESTABLISHED rule: PRESENT"
    else
      log_fail "RELATED,ESTABLISHED rule: MISSING"
    fi

    # Check outbound rule
    local outbound_iface
    outbound_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    if [[ -n "$outbound_iface" ]]; then
      if sudo iptables -C FORWARD -o "$outbound_iface" -j ACCEPT 2>/dev/null; then
        log_ok "Outbound ACCEPT rule ($outbound_iface): PRESENT"
      else
        log_fail "Outbound ACCEPT rule ($outbound_iface): MISSING"
      fi
    fi
  else
    log_fail "fix-docker-networking.sh not found or not executable"
    log_info "Create it at: $fix_script"
  fi

  # Test inter-container connectivity
  log_info "Testing container-to-container connectivity..."

  # Pick two containers on the same network to test
  local test_result
  test_result=$(docker exec postgres pg_isready -h localhost 2>&1 || echo "FAIL")
  if echo "$test_result" | grep -q "accepting"; then
    log_ok "postgres self-connect: OK"
  else
    log_fail "postgres self-connect: FAILED"
  fi

  # Test container-to-internet
  test_result=$(docker exec postgres timeout 3 bash -c "echo > /dev/tcp/8.8.8.8/53" 2>&1 && echo "OK" || echo "FAIL")
  if [[ "$test_result" == "OK" ]]; then
    log_ok "Container outbound internet: OK"
  else
    log_fail "Container outbound internet: FAILED"
    log_info "Containers cannot reach external services"
  fi

  # Check MASQUERADE rules for Docker networks
  local masq_count
  masq_count=$(sudo iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -c "MASQUERADE.*172\." || echo "0")
  log_info "MASQUERADE rules for Docker networks: $masq_count"

  if [[ $masq_count -lt 3 ]]; then
    log_warn "Low MASQUERADE rule count — some networks may not have NAT rules"
  fi
}

# ============================================================================
# Deep-dive: Single Service Diagnostic
# ============================================================================
diagnose_service() {
  local svc="$1"
  log_section "Deep-Dive: $svc"

  if ! docker ps -a --format '{{.Names}}' | grep -q "^${svc}$"; then
    log_fail "Container '$svc' not found"
    return
  fi

  # State
  log_info "State:"
  docker inspect --format='  State: {{.State.State}} | Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} | Restarts: {{.RestartCount}} | OOM: {{.State.OOMKilled}} | Started: {{.State.StartedAt}}' "$svc"

  # Networks
  log_info "Networks:"
  docker inspect --format='{{range $k, $v := .NetworkSettings.Networks}}  {{$k}}: {{$v.IPAddress}}{{"\n"}}{{end}}' "$svc"

  # Resource usage
  log_info "Resources:"
  docker stats --no-stream --format '  CPU: {{.CPUPerc}} | MEM: {{.MemUsage}} ({{.MemPerc}})' "$svc" 2>/dev/null

  # Recent logs
  log_info "Last 20 log lines:"
  docker logs --tail 20 "$svc" 2>&1 | sed 's/^/  /'

  # Error scan
  log_info "Error scan (last 30 min):"
  local errs
  errs=$(docker logs --since 30m "$svc" 2>&1 | grep -ciE \
    "(fatal|panic|error|exception|crash|oom|killed|failed|refused|timeout)" \
    2>/dev/null || echo 0)
  if [[ "$errs" -gt 0 ]]; then
    log_warn "$errs error-like lines found:"
    docker logs --since 30m "$svc" 2>&1 | grep -iE \
      "(fatal|panic|error|exception|crash|oom|killed|failed|refused|timeout)" \
      2>/dev/null | tail -5 | sed 's/^/  /'
  else
    log_ok "No errors in last 30 minutes"
  fi

  # Healthcheck config
  local hc
  hc=$(docker inspect --format='{{json .Config.Healthcheck}}' "$svc" 2>/dev/null)
  if [[ "$hc" != "null" && -n "$hc" ]]; then
    log_info "Healthcheck config: $hc"
  fi
}

# ============================================================================
# Quick Status
# ============================================================================
quick_status() {
  log_section "Quick Status"

  local total running unhealthy
  total=$(docker ps -a --format '{{.Names}}' | wc -l)
  running=$(docker ps --format '{{.Names}}' | wc -l)
  unhealthy=$(docker ps --format '{{.Names}}' | while read -r n; do
    docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$n" 2>/dev/null
  done | grep -c "unhealthy" 2>/dev/null || true)
  unhealthy=${unhealthy:-0}

  echo -e "  Total containers: ${BOLD}$total${NC} | Running: ${GREEN}$running${NC} | Unhealthy: ${RED}$unhealthy${NC}"

  # Quick networking check
  if sudo iptables -C FORWARD -m physdev --physdev-is-bridged -j ACCEPT 2>/dev/null; then
    echo -e "  Docker networking: ${GREEN}OK${NC} (bridge rules present)"
  else
    echo -e "  Docker networking: ${RED}BROKEN${NC} (bridge rules missing)"
  fi
}

# ============================================================================
# Main Execution
# ============================================================================
case "$MODE" in
  status)
    quick_status
    ;;
  service)
    diagnose_service "$TARGET_SERVICE"
    ;;
  diagnose)
    check_docker_networking
    check_container_health
    check_dependencies
    check_cloudflared
    check_log_errors
    check_resources
    check_port_conflicts
    check_env_compliance
    check_network_diagnostics
    ;;
  heal)
    check_docker_networking
    auto_heal
    check_container_health
    ;;
  full)
    check_docker_networking
    check_container_health
    check_dependencies
    check_cloudflared
    check_log_errors
    check_resources
    check_port_conflicts
    check_env_compliance
    check_network_diagnostics
    auto_heal
    ;;
esac

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                   SUMMARY                           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "  Issues found:  ${RED}${ISSUES_FOUND}${NC}"
echo -e "  Issues fixed:  ${GREEN}${ISSUES_FIXED}${NC}"
echo -e "  Warnings:      ${YELLOW}${WARNINGS}${NC}"
echo ""

if [[ $ISSUES_FOUND -gt $ISSUES_FIXED ]]; then
  echo -e "  ${YELLOW}Some issues require manual intervention.${NC}"
  echo -e "  Run with ${CYAN}--service <name>${NC} for deep-dive on a specific container."
fi

exit $ISSUES_FOUND
