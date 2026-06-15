#!/usr/bin/env python3
"""
Agent Zero — LangGraph CEO Orchestration Demo

Demonstrates the full pipeline using real LangGraph StateGraph:
  1. Build and validate handshake contract (Pydantic)
  2. Execute CEO graph with checkpointing
  3. Delegate to PM → Dev → DevOps agents
  4. Write structured audit artifacts

Run: python3 run_demo.py
"""
from __future__ import annotations

import json
import sys
import time
from datetime import datetime, timedelta
from uuid import uuid4

from langgraph.checkpoint.memory import MemorySaver

from .audit import write_all_artifacts
from .graph import build_ceo_graph
from .models import Approval, Assets, Contract, Risk, Scope


def print_header(title: str):
    width = 70
    print(f"\n{'═' * width}")
    print(f"  {title}")
    print(f"{'═' * width}")


def print_step(step: str, detail: str = ""):
    print(f"\n  ▸ {step}")
    if detail:
        for line in detail.strip().split("\n"):
            print(f"    {line}")


def main():
    print_header("Agent Zero — LangGraph CEO Orchestration (Production)")

    # ── Step 1: Build Contract with Pydantic ────────────────────────
    print_step("1. Building handshake contract (Pydantic validation)", "Project: 'taskflow' — full-stack task management app")

    contract = Contract(
        project="taskflow",
        scope=Scope(
            features=[
                "Kanban board with drag-and-drop",
                "REST API with auth middleware",
                "Docker Compose dev environment",
            ],
            boundaries=[
                "Node.js + React + Tailwind only",
                "PostgreSQL for persistence",
                "Single production VM deployment",
            ],
            exclusions=[
                "No mobile app in this sprint",
                "No real-time WebSocket updates",
            ],
        ),
        risks=[
            Risk(severity="medium", mitigation="Use proven drag-and-drop library (dnd-kit)"),
            Risk(severity="low", mitigation="Standard JWT auth pattern"),
            Risk(severity="high", mitigation="Health-check with auto-rollback on deploy"),
        ],
        assets=Assets(
            repos=["github.com/org/taskflow-frontend", "github.com/org/taskflow-backend"],
            infra=["production-vm-01"],
        ),
        approval=Approval(
            hermes_signoff=True,  # Auto-approve for demo
            board_veto_window_hrs=24,
        ),
    )

    print(f"    ✓ Contract {str(contract.contract_id)[:8]}... validated")
    print(f"    ✓ {len(contract.scope.features)} features, {len(contract.risks)} risks")

    # ── Step 2: Initialize LangGraph ────────────────────────────────
    print_step("2. Initializing LangGraph StateGraph with checkpointing")

    task_id = str(uuid4())[:8]
    graph = build_ceo_graph()
    checkpointer = MemorySaver()
    app = graph.compile(checkpointer=checkpointer)

    print(f"    Task ID: {task_id}")
    print(f"    Project: {contract.project}")
    print(f"    Checkpointing: enabled (MemorySaver)")

    # ── Step 3: Execute Graph ───────────────────────────────────────
    print_step("3. Executing CEO orchestration graph")
    print()

    initial_state = {
        "task_id": task_id,
        "project_name": "",
        "contract": contract,
        "current_node": "",
        "node_history": [],
        "pm_manifest": None,
        "dev_results": [],
        "devops_manifest": None,
        "contract_approved": False,
        "sandbox_verified": False,
        "errors": [],
        "final_status": "pending",
        "messages": [],
    }

    config = {"configurable": {"thread_id": task_id}}

    start = time.perf_counter()

    # Stream execution to show progress
    final_state = None
    for event in app.stream(initial_state, config=config, stream_mode="values"):
        final_state = event
        node = event.get("current_node", "?")
        if node:
            marker = "✓" if node != "blocked" else "✗"
            step_num = len(event.get("node_history", []))
            print(f"    [{step_num}] {marker} {node}")

    elapsed = time.perf_counter() - start
    print(f"\n    Completed in {elapsed * 1000:.1f}ms")

    if final_state is None:
        print("    ✗ Graph execution failed — no final state")
        return 1

    # ── Step 4: Sub-Agent Results ───────────────────────────────────
    print_step("4. Sub-agent results")

    # PM
    if final_state.get("pm_manifest"):
        manifest = final_state["pm_manifest"]
        print(f"    ✓ [project_manager] PM")
        print(f"      └─ Initialized {len(manifest.get('features', []))} features, project manifest created")

    # Dev Agents
    for result in final_state.get("dev_results", []):
        builds = result.get("builds", [])
        passed = sum(1 for b in builds if b.get("tests_failed", 1) == 0)
        sandbox_status = "verified" if result.get("sandbox_verified") else "FAILED"
        print(f"    ✓ [developer] agent-{result.get('agent_id', '?')}")
        print(f"      └─ {len(builds)} builds, {passed}/{len(builds)} tests passed, sandbox={sandbox_status}")

    # DevOps
    if final_state.get("devops_manifest"):
        dm = final_state["devops_manifest"]
        print(f"    ✓ [devops] DevOps")
        print(f"      └─ Deployed to {dm.get('deploy_target', '?')} via {dm.get('auth_method', '?')}")
        hc = dm.get("health_check", {})
        print(f"      └─ Health check: {hc.get('endpoint')} ({hc.get('retries', '?')} retries, {hc.get('interval_s', '?')}s interval)")

    # ── Step 5: Deploy Manifest ─────────────────────────────────────
    if final_state.get("devops_manifest"):
        print_step("5. Deploy manifest")
        dm = final_state["devops_manifest"]
        print(f"    Target:    {dm.get('deploy_target', '?')}")
        print(f"    Auth:      {dm.get('auth_method', '?')}")
        print(f"    Rollback:  {dm.get('rollback_timeout_s', '?')}s auto-rollback")

        artifacts = dm.get("artifacts", [])
        print(f"    Artifacts: {len(artifacts)} feature builds (deduplicated)")
        for a in artifacts:
            print(f"      └─ {a.get('feature', '?')}: {a.get('build_status', '?')}")

    # ── Step 6: Audit Trail ─────────────────────────────────────────
    print_step("6. Writing audit artifacts")

    paths = write_all_artifacts(final_state, task_id)
    for p in paths:
        print(f"    ✓ {p}")

    # ── Step 7: Retrieve Checkpoint History ─────────────────────────
    print_step("7. Checkpoint history (LangGraph MemorySaver)")

    checkpoint_history = list(checkpointer.list(config))
    print(f"    ✓ {len(checkpoint_history)} checkpoints saved")
    for i, cp in enumerate(checkpoint_history[:5], 1):
        print(f"      [{i}] {cp.config.get('configurable', {}).get('checkpoint_ns', 'root')}")

    # ── Summary ─────────────────────────────────────────────────────
    print_header("Execution Summary")

    status = final_state.get("final_status", "unknown")
    status_icon = "✓" if status == "completed" else "✗"

    print(f"  Status:        {status_icon} {status.upper()}")
    print(f"  Graph Path:    {' → '.join(final_state.get('node_history', []))}")

    agent_count = 1 if final_state.get("pm_manifest") else 0
    agent_count += len(final_state.get("dev_results", []))
    agent_count += 1 if final_state.get("devops_manifest") else 0
    print(f"  Agents:        {agent_count} spawned")
    print(f"  Sandbox:       {'VERIFIED' if final_state.get('sandbox_verified') else 'FAILED'}")
    print(f"  Deployed:      {'YES' if final_state.get('devops_manifest') else 'NO'}")
    print(f"  Audit Files:   {len(paths)} written to agents/qwen/")
    print(f"  Checkpoints:   {len(checkpoint_history)} saved in MemorySaver")

    errors = final_state.get("errors", [])
    if errors:
        print(f"\n  Errors:")
        for e in errors:
            print(f"    ✗ {e}")

    print(f"\n{'═' * 70}\n")

    return 0 if status == "completed" else 1


if __name__ == "__main__":
    sys.exit(main())
