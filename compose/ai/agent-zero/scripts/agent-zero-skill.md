---
name: agent-zero-delegation
description: "Delegate build tasks to Agent Zero (CEO orchestrator) via REST API. Submit contracts, poll status, approve pending tasks, and retrieve results."
version: 1.0.0
author: Qwen (Architecture)
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [agent-zero, delegation, multi-agent, build, orchestration, api]
---

# Agent Zero Delegation

Agent Zero is the CEO orchestrator that manages PM, Dev, and DevOps sub-agents via LangGraph. You (Hermes) act as the PM layer — decomposing user requests into contracts and delegating execution to Agent Zero.

## Architecture

```
User → Hermes (PM: decompose, delegate, report)
         ↓ POST /api/v1/tasks
       Agent Zero (CEO: spawn PM, Dev, DevOps agents)
         ↓ LangGraph execution
       Results (deploy manifest, audit trail)
```

## API Reference

Base URL: `http://agent-zero:8080`

### Health Check

```bash
curl -s http://agent-zero:8080/api/v1/health
```

Returns service availability (LLM, MCP, SSH) and active task count.

### Submit a Task

```bash
curl -s -X POST http://agent-zero:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "project": "my-project",
    "features": ["user authentication", "REST API endpoints"],
    "boundaries": ["Python/FastAPI only", "PostgreSQL database"],
    "exclusions": ["no frontend", "no CI/CD"],
    "risks": [{"severity": "medium", "mitigation": "use existing auth patterns"}],
    "repos": [],
    "infra": [],
    "veto_window_hrs": 24,
    "auto_approve": true,
    "simulate": false
  }'
```

**Key fields:**
- `project`: Project name (used for memory and workspace isolation)
- `features`: List of features to build
- `boundaries`: Technical constraints
- `exclusions`: What NOT to build
- `auto_approve`: Set `true` to skip HITL approval (for trusted tasks)
- `simulate`: Set `false` for real LLM code generation; `true` for dry-run

### Check Task Status

```bash
curl -s http://agent-zero:8080/api/v1/tasks/{task_id}
```

Returns task state, node history, agent count, and deploy manifest.

### List All Tasks

```bash
curl -s http://agent-zero:8080/api/v1/tasks
```

### Approve a Pending Task (HITL)

```bash
curl -s -X POST http://agent-zero:8080/api/v1/tasks/{task_id}/approve \
  -H "Content-Type: application/json" \
  -d '{"approved": true, "approver": "hermes"}'
```

### List Projects in Memory

```bash
curl -s http://agent-zero:8080/api/v1/projects
```

## Delegation Workflow

1. **Decompose**: Break the user's request into a project name, feature list, boundaries, and exclusions.
2. **Submit**: POST the contract to Agent Zero. Use `simulate: true` first for validation, then `simulate: false` for real execution.
3. **Monitor**: Check task status via GET. The watchdog cron runs every 5 minutes.
4. **Approve**: If a task is blocked on HITL, review the contract and approve if acceptable.
5. **Report**: When the task completes, summarize the deploy manifest for the user.

## When to Delegate

Delegate to Agent Zero when:
- User asks to build a project with multiple features
- User needs code generated, tested, and committed
- User requests deployment to a production VM

Handle directly (don't delegate) when:
- Simple questions or single-file edits
- Quick research or web searches
- Configuration changes to the current stack

## Example: Full Delegation

```bash
# 1. Submit task
RESULT=$(curl -s -X POST http://agent-zero:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{"project":"todo-api","features":["CRUD endpoints","JWT auth","PostgreSQL schema"],"auto_approve":true,"simulate":false}')
TASK_ID=$(echo $RESULT | python3 -c "import sys,json; print(json.load(sys.stdin)['task_id'])")
echo "Submitted task: $TASK_ID"

# 2. Poll until complete
while true; do
  STATUS=$(curl -s http://agent-zero:8080/api/v1/tasks/$TASK_ID | python3 -c "import sys,json; print(json.load(sys.stdin)['final_status'])")
  echo "Status: $STATUS"
  if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then break; fi
  sleep 10
done

# 3. Get final result
curl -s http://agent-zero:8080/api/v1/tasks/$TASK_ID | python3 -m json.tool
```

## Watchdog

A cron job (`agent-zero-watchdog`) runs every 5 minutes and reports Agent Zero status. It uses the script at `~/.hermes/scripts/hermes_delegate.sh`.
