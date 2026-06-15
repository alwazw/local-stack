---
name: deep-validation
description: Mandatory 4-step runtime validation pipeline for Docker deployments — log scrutiny, stability observation, port compliance, and completion gates that go beyond docker ps.
source: auto-skill
extracted_at: '2026-06-15T07:36:24.448Z'
---

# Deep Validation Pipeline

## Core Constraint

**No agent may mark a container deployment as complete based solely on `docker ps` uptime or a passing container return code.** The following 4-step validation is mandatory for every deployment, modification, or infrastructure change.

## Step 1: Structural Health Check

Map the full Docker daemon state:

```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
```

**Pass criteria:** All target containers show `Up X minutes (healthy)`. No containers in `Restarting`, `health: starting`, `unhealthy`, or `Created` state.

**Fail actions:**
- `Restarting` → `docker logs <name> --tail 30` to find crash cause
- `unhealthy` → inspect healthcheck: `docker inspect <name> --format '{{json .State.Health}}' | python3 -m json.tool`
- `health: starting` → wait for `start_period` to elapse, then recheck

## Step 2: Exhaustive Log Scrutiny

For **every** container deployed or modified in the current sprint:

```bash
docker logs --tail 200 <container_name> 2>&1 | \
  grep -iE "error|warn|fatal|panic|exception|fail|timeout|crash|refused|denied"
```

### Classification Framework

Every match must be classified into one of three categories:

| Classification | Meaning | Action |
|---|---|---|
| **CLEAN** | No matches found (grep returns empty) | ✅ Container operating normally |
| **ACCEPTABLE** | Matches found but are from known pre-existing conditions | ✅ Document in known-warnings list, no action needed |
| **ACTION REQUIRED** | New errors, crash loops, auth failures, silent exceptions | 🔴 Must investigate and resolve before marking complete |

### Common Acceptable Anomalies (document and move on)

| Container | Typical Acceptable Warning | Reason |
|---|---|---|
| redis | `Memory overcommit must be enabled` | WSL2 kernel limitation |
| traefik | ACME cert errors | Cloudflare API not yet configured |
| openwebui | `CORS_ALLOW_ORIGIN IS SET TO '*'` | Acceptable for local dev |
| authentik-server | Transient `PostgreSQL connection failed` | Normal startup retry, resolves |
| authentik-worker | `CPendingDeprecationWarning` | Upstream Celery deprecation |
| agent-zero | External API HTTP 403 | Rate limits on third-party APIs |
| omniroute | External API timeouts | Non-critical external features |
| grafana | `database is locked (SQLITE_BUSY)` | Transient, auto-resolves on retry |

### Red Flags (always investigate)

- `panic:` or `FATAL:` in any container → crash, not just a warning
- Repeated identical errors in rapid succession → crash loop
- `connection refused` that doesn't resolve → dependency not reachable
- `permission denied` on a file the service needs → ownership issue
- Memory-related errors → potential leak or OOM

## Step 3: Stability Observation

Confirm no background crashes, memory leaks, or restart loops:

```bash
# Snapshot at T+0
docker ps --format "{{.Names}}: {{.Status}}" | sort > /tmp/t0.txt

# Wait 15 seconds (minimum continuous observation window)
sleep 15

# Snapshot at T+15s
docker ps --format "{{.Names}}: {{.Status}}" | sort > /tmp/t15.txt

# Compare
diff /tmp/t0.txt /tmp/t15.txt
```

**Pass criteria:** Empty diff — zero state changes, restarts, or health transitions during the observation window.

**Fail actions:**
- Container restarted → investigate logs for crash cause
- Health state changed (healthy → unhealthy) → check what triggered the transition
- Container disappeared → container crashed and `restart: unless-stopped` hasn't recovered it

## Step 4: Port Binding Compliance

Verify no services are accidentally exposed to the network:

```bash
docker ps --format "{{.Names}}: {{.Ports}}" | grep "0.0.0.0"
```

**Pass criteria:** Only the reverse proxy (traefik 80/443) shows `0.0.0.0`. All other services must be on `127.0.0.1`.

**Fail action:** Update port binding in `docker-compose.yml`:
```yaml
# Before (exposed):
ports:
  - "${PORT_SERVICE}:8080"

# After (locked):
ports:
  - "127.0.0.1:${PORT_SERVICE}:8080"
```

## Completion Gate

A deployment task is complete **ONLY** when all four steps pass:

1. ✅ All containers report `healthy`
2. ✅ Log scrutiny shows no new ACTION REQUIRED items
3. ✅ 15-second stability window shows zero state changes
4. ✅ Port bindings comply with `127.0.0.1` standard (only proxy on `0.0.0.0`)

## Report Template

After completing validation, write a verification report documenting:

```markdown
| # | Container | Log Lines | Anomalies Found | Classification | Verdict |
|---|---|---|---|---|---|
| 1 | postgres  | 200 | 0 | — | ✅ CLEAN |
| 2 | redis     | 200 | 2 | vm.overcommit warning | ✅ ACCEPTABLE |
| 3 | traefik   | 200 | 5 | ACME errors | ✅ ACCEPTABLE |
...
```

Include:
- Total containers checked
- Clean vs acceptable vs action-required counts
- Stability window result (diff output)
- Port compliance result
- Any issues found and resolved during validation
- Pre-existing issues documented with priority for future remediation

## When to Apply

- After deploying any new container
- After modifying any service configuration (env vars, ports, volumes, networks)
- After running `docker compose up -d` with any changes
- After fixing a container that was previously unhealthy
- Before declaring any infrastructure task complete
