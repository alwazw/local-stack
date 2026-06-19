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
        2>/dev/null | head -1 | cut -c1-120)
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
