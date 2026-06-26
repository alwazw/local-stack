# Audit Trail & Traceability Record

**Date:** 2026-06-15
**Session:** Production VM Configuration (vm2) + Hermes Cron Fix
**Operator:** Qwen (Architecture)
**Reference:** `agents/main-system-gap-analysis.md` §4 — Current Sprint

---

## Intentional Rationale

Two critical fixes were needed:
1. **Hermes cron job broken** — `--deliver log` is not a valid delivery target in Hermes (valid targets: `origin`, `local`, `telegram`, `discord`, `signal`). The watchdog cron had 0 successful deliveries and was spamming error logs.
2. **Production VM configured** — Ubuntu Server 26.04 WSL VM (`vm2`) created with SSH authentication for `alwazw@vm2`. The SSH deployment pipeline needed environment variable wiring to point to this real target.

---

## Tasks Undertaken

### 1. Fixed Hermes Cron Delivery Target
- **Problem:** Cron job `agent-zero-watchdog` used `--deliver log` — not a valid option. Every run logged: `⚠ Delivery failed: no delivery target resolved for deliver=log`
- **Fix:** Deleted broken cron job (`ca1c069c0156`), recreated with `--deliver local`
- **SKILL.md updated:** Fixed both the cron command example and the options description in `.qwen/skills/auto-skill-multi-agent-architecture/SKILL.md`

### 2. Configured Production VM SSH Target (vm2)
- **Problem:** SSH deployer used hardcoded `deploy` user with no deploy host env var — all deployments were simulated
- **Fix:**
  - Added `SSH_DEPLOY_HOST=vm2`, `SSH_DEPLOY_USER=alwazw`, `SSH_DEPLOY_PORT=22` to `.env` and `.env.example`
  - Updated `compose/ai/agent-zero/docker-compose.yml` to pass these env vars to agent-zero container
  - Updated `SSHDeployer.__init__()` to read `SSH_DEPLOY_HOST` from environment (defaults to `vm2`)
  - Updated `deploy()` and `simulate_deploy()` to use `self.ssh_host` when no host is passed
- **Gap analysis updated:** Added vm2 milestone entry and updated next steps

---

## Verification Results

| Check | Result |
| :--- | :--- |
| Hermes cron job | ✅ Recreated with `--deliver local`, no delivery errors |
| Cron job status | ✅ `agent-zero-watchdog` active, 26/999 repeats consumed |
| SSH env vars in .env | ✅ `SSH_DEPLOY_HOST=vm2`, `SSH_DEPLOY_USER=alwazw`, `SSH_DEPLOY_PORT=22` |
| docker-compose.yml | ✅ Environment variables wired with defaults |
| SSHDeployer module | ✅ Reads `SSH_DEPLOY_HOST` from env, defaults to `vm2` |
| Gap analysis | ✅ vm2 milestone added, next steps updated |
| SKILL.md | ✅ Cron command and options corrected |

---

## Files Modified

| File | Change |
| :--- | :--- |
| `.env` | Added SSH deployment env vars |
| `.env.example` | Added SSH deployment env vars |
| `compose/ai/agent-zero/docker-compose.yml` | Added `SSH_DEPLOY_HOST`, `SSH_DEPLOY_USER`, `SSH_DEPLOY_PORT` env vars |
| `agents/qwen/agent_zero_langgraph/ssh_deploy.py` | Added `ssh_host` param, read from env, default to `vm2` |
| `compose/ai/agent-zero/agent_zero_langgraph/ssh_deploy.py` | Synced from source |
| `.qwen/skills/auto-skill-multi-agent-architecture/SKILL.md` | Fixed `--deliver log` → `--deliver local` |
| `agents/main-system-gap-analysis.md` | Added vm2 milestone, updated next steps |

---

## Container Operations

| Operation | Result |
| :--- | :--- |
| `hermes cron delete ca1c069c0156` | ✅ Removed broken job |
| `hermes cron create ... --deliver local` | ✅ Created job `8503d29473b2` |
| `docker restart hermes-agent agent-zero` | ✅ Both containers restarted |
| `docker network reconnect hermes-agent` | ✅ Network routing refreshed |

---

## Items Deferred

- **Real SSH deployment to vm2** — Infrastructure is ready, but DevOps agent hasn't yet deployed real code to vm2. Next step is to trigger a test deployment with `simulate=false`.

---

## Follow-up: ai-ml Network Broken — Workaround Applied

The `ai-ml` Docker bridge network stopped allowing inter-container traffic (hermes-agent ↔ agent-zero, openwebui ↔ litellm). This is a known WSL2/Docker Desktop networking regression that can happen after container restarts.

**Root cause:** The `ai-ml` bridge network (`br-1813ea894891`) stopped forwarding packets between containers on the same subnet (172.21.0.0/16). DNS resolution works, but TCP connections time out. Likely caused by Docker Desktop's WSL2 backend losing iptables state or bridge forwarding rules after container restarts.

**Fix applied:**
- Created new Docker bridge network `agent-communication`
- Connected both `hermes-agent` and `agent-zero` to the new network
- Verified inter-container connectivity restored: `curl http://agent-zero:8080/api/v1/health` succeeds from hermes-agent
- Updated `docker-compose.yml` (both root and subdirectory) to include `agent-communication` network for both services
- Added `agent-communication` as external network definition

**Permanent fix (if issue recurs):** Restarting the Docker Desktop service or recreating the affected network typically resolves this WSL2 networking issue.
