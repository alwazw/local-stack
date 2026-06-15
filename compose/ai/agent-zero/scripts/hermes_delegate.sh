#!/bin/bash
# Agent Zero Delegation Poll — Hermes cron script
# Checks Agent Zero API health, lists active tasks, and reports status.
# Output is injected into Hermes agent prompt for decision-making.

AGENT_ZERO_URL="http://agent-zero:8080"

# Health check
HEALTH=$(curl -sf "${AGENT_ZERO_URL}/api/v1/health" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "AGENT ZERO STATUS: UNREACHABLE"
    echo "Agent Zero API at ${AGENT_ZERO_URL} is not responding."
    echo "Action needed: investigate container health."
    exit 0
fi

# Parse health response
STATUS=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null)
ACTIVE=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('active_tasks',0))" 2>/dev/null)
LLM=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['services'].get('llm_available',False))" 2>/dev/null)
MCP=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['services'].get('mcp_available',False))" 2>/dev/null)
SSH=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['services'].get('ssh_key_exists',False))" 2>/dev/null)

echo "=== AGENT ZERO STATUS REPORT ==="
echo "Status: ${STATUS}"
echo "Active tasks: ${ACTIVE}"
echo "LLM available: ${LLM}"
echo "MCP available: ${MCP}"
echo "SSH key: ${SSH}"

# List active tasks
TASKS=$(curl -sf "${AGENT_ZERO_URL}/api/v1/tasks" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TASKS" ]; then
    echo "Tasks: Unable to retrieve task list"
else
    TASK_COUNT=$(echo "$TASKS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('tasks',[])))" 2>/dev/null)
    echo "Task list entries: ${TASK_COUNT}"

    # Print each task summary
    echo "$TASKS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tasks = data.get('tasks', [])
if not tasks:
    print('No active tasks.')
else:
    for t in tasks:
        tid = t.get('task_id', '?')
        proj = t.get('project', '?')
        st = t.get('status', '?')
        final = t.get('final_status', 'pending')
        created = t.get('created_at', '?')
        completed = t.get('completed_at', 'N/A')
        agents = t.get('agent_count', 0)
        print(f'  Task {tid}: project={proj}, status={st}, final={final}, agents={agents}, created={created}, completed={completed}')
" 2>/dev/null
fi

echo ""
echo "=== END REPORT ==="
echo "If there are completed tasks, review their results and report to the user."
echo "If no active tasks, you may submit new tasks from your planning queue."
