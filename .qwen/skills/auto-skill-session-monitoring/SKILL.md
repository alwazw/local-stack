---
name: session-monitoring
description: Self-monitoring pattern for long-running AI assistant sessions — cron-based health checks, container status monitoring, and automated escalation
source: auto-skill
extracted_at: '2026-06-15T21:41:12.610Z'
---

# Session Self-Monitoring

**Purpose:** When the user steps away from a long-running session, set up automated health checks that verify the session is still alive and containers are healthy. Fires every 10 minutes via the built-in cron scheduler.

## Setup

### 1. Create a Wake Check Script

```bash
cat > /tmp/qwen_wake_check.sh << 'SCRIPT'
#!/bin/bash
# Self-monitoring script — checks if Qwen process is alive and containers are healthy

# Check Qwen process
PID=$(pgrep -f "qwen.*code" 2>/dev/null | head -1)
if [ -z "$PID" ]; then
    echo "⚠ Qwen process not found — may need restart"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "qwen" || echo "⚠ No qwen docker container found"
else
    echo "✅ Qwen alive (PID: $PID)"
fi

# Check container health
echo "=== Container Status ==="
docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || echo "Compose not available"

# Check for recent errors
echo "=== Recent Errors ==="
docker compose logs --tail 5 2>/dev/null | grep -i "err\|fail\|panic" || echo "No recent errors"
SCRIPT
chmod +x /tmp/qwen_wake_check.sh
```

### 2. Schedule Cron Job

```
# Every 10 minutes, run the wake check and report findings
cron_create("*/10 * * * *", 
    "SELF-MONITOR CHECK: Run `/tmp/qwen_wake_check.sh` via shell command. Report: 1) Is the Qwen session alive? 2) Are any Docker containers unhealthy or down? 3) Any new errors in logs? Keep it brief — one line per finding. If everything is fine, just say 'All clear'. If you find issues, escalate with specifics.",
    recurring=True)
```

### 3. Response Protocol

When the cron fires, respond with this format:

```
**1) Qwen session:** ✅ Alive  (or ⚠ if not found)

**2) Containers:** 🟢 31/31 up, 26 healthy, 0 unhealthy, 0 down.
(or escalate with specifics: "⚠ hermes restart loop — investigating...")

**3) Errors:** None.  (or escalate with specific error lines)

All clear — stable state.
```

## Escalation Thresholds

| Condition | Response |
|-----------|----------|
| All containers healthy | "All clear" |
| 1-2 containers unhealthy | Report status, investigate if persistent |
| Container crash loop (Restarting) | Investigate immediately — check logs |
| Qwen process not found | Report — may need session restart |
| New errors in logs | Report with specific error lines |
| Container DOWN (not just unhealthy) | Escalate with container name and status |

## Cron Job Lifetime

- Cron jobs are session-only (not written to disk)
- Auto-expire after 3 days
- Cancel with `cron_delete("<job_id>")` if user returns before expiry

## Additional Monitoring Tasks

Beyond health checks, the cron can also run periodic maintenance:

```
# Check disk space
cron_create("0 */4 * * *", "Run `df -h /` and report if root filesystem is >80% full")

# Check container resource usage
cron_create("0 */6 * * *", "Run `docker stats --no-stream` and report any container using >80% memory")
```

## When User Returns

When the user sends a new message:
1. Cancel the cron: `cron_delete("<job_id>")`
2. Report a summary: "While you were away, I ran X health checks over Y hours. All clear — no issues found." (or report any issues that were detected and handled)
