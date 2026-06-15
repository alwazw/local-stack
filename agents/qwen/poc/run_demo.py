#!/usr/bin/env python3
"""
Agent Zero PoC — CEO Orchestration Graph Demo

Demonstrates the full pipeline:
  1. Build a handshake contract for a sample project
  2. Validate schema and enforce Hermes sign-off gate
  3. Delegate to PM Agent → Dev Agent pool → DevOps Agent
  4. Write structured audit artifacts to ~/docker/agents/qwen/

Run:  python3 run_demo.py
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from agent_zero.audit import write_all_artifacts
from agent_zero.contract import build_contract, validate_contract_schema
from agent_zero.graph import CEOGraph
from agent_zero.state import GraphState, NodeStatus


def print_header(title: str):
    width = 64
    print(f"\n{'═' * width}")
    print(f"  {title}")
    print(f"{'═' * width}")


def print_step(step: str, detail: str = ""):
    print(f"\n  ▸ {step}")
    if detail:
        for line in detail.strip().split("\n"):
            print(f"    {line}")


def main():
    print_header("Agent Zero — CEO Orchestration Graph (PoC)")

    # ── Step 1: Build Contract ──────────────────────────────────────
    print_step("1. Building handshake contract", "Project: 'taskflow' — a full-stack task management app")

    contract = build_contract(
        project="taskflow",
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
        risks=[
            {"severity": "medium", "mitigation": "Use proven drag-and-drop library (dnd-kit)"},
            {"severity": "low", "mitigation": "Standard JWT auth pattern"},
            {"severity": "high", "mitigation": "Health-check with auto-rollback on deploy"},
        ],
        repos=["github.com/org/taskflow-frontend", "github.com/org/taskflow-backend"],
        infra=["production-vm-01"],
        veto_window_hrs=24,
    )

    errors = validate_contract_schema(contract)
    if errors:
        print(f"    ✗ Contract validation FAILED: {errors}")
        sys.exit(1)

    print(f"    ✓ Contract {contract['contract_id'][:8]}... validated")
    print(f"    ✓ {len(contract['scope']['features'])} features, "
          f"{len(contract['risks'])} risks identified")

    # ── Step 2: Initialize Graph State ──────────────────────────────
    print_step("2. Initializing graph state")

    state = GraphState(
        project_name=contract["project"],
        contract=contract,
    )
    print(f"    Task ID: {state.task_id}")
    print(f"    Project: {state.project_name}")

    # ── Step 3: Execute the CEO Graph ───────────────────────────────
    print_step("3. Executing CEO orchestration graph")
    print()

    graph = CEOGraph()
    start = time.perf_counter()
    state = graph.run(state)
    elapsed = time.perf_counter() - start

    # Print execution trace
    for i, node in enumerate(state.node_history):
        marker = "✓" if node not in ("blocked",) else "✗"
        print(f"    [{i + 1}/{len(state.node_history)}] {marker} {node}")

    print(f"\n    Completed in {elapsed * 1000:.1f}ms")

    # ── Step 4: Sub-Agent Results ───────────────────────────────────
    print_step("4. Sub-agent results")

    for r in state.sub_agent_results:
        icon = "✓" if r.status == NodeStatus.COMPLETED else "✗"
        print(f"    {icon} [{r.role.value}] agent-{r.agent_id}")

        if r.role.value == "project_manager":
            fc = r.output.get("feature_count", 0)
            print(f"      └─ Initialized {fc} features, project manifest created")
        elif r.role.value == "developer":
            builds = r.output.get("builds", [])
            passed = sum(1 for b in builds if b["tests_failed"] == 0)
            print(f"      └─ {len(builds)} builds, {passed}/{len(builds)} tests passed, "
                  f"sandbox={'verified' if r.output.get('sandbox_verified') else 'FAILED'}")
        elif r.role.value == "devops":
            dm = r.output.get("deploy_manifest", {})
            print(f"      └─ Deployed to {dm.get('deploy_target', '?')} via {dm.get('auth_method', '?')}")
            hc = dm.get("health_check", {})
            print(f"      └─ Health check: {hc.get('endpoint')} "
                  f"({hc.get('retries', '?')} retries, {hc.get('interval_s', '?')}s interval)")

    # ── Step 5: Deploy Manifest ─────────────────────────────────────
    if state.deploy_manifest:
        print_step("5. Deploy manifest")
        dm = state.deploy_manifest
        print(f"    Target:    {dm['deploy_target']}")
        print(f"    Auth:      {dm['auth_method']}")
        print(f"    Rollback:  {dm['rollback_timeout_s']}s auto-rollback")
        print(f"    Artifacts: {len(dm['artifacts'])} feature builds")
        for a in dm["artifacts"]:
            print(f"      └─ {a['feature']}: {a['build_status']}")

    # ── Step 6: Audit Trail ─────────────────────────────────────────
    print_step("6. Writing audit artifacts")

    paths = write_all_artifacts(state)
    for p in paths:
        print(f"    ✓ {p}")

    # ── Summary ─────────────────────────────────────────────────────
    print_header("Execution Summary")

    status_icon = "✓" if state.final_status == NodeStatus.COMPLETED else "✗"
    print(f"  Status:        {status_icon} {state.final_status.value.upper()}")
    print(f"  Graph Path:    {' → '.join(state.node_history)}")
    print(f"  Agents:        {len(state.sub_agent_results)} spawned")
    print(f"  Sandbox:       {'VERIFIED' if state.sandbox_verified else 'FAILED'}")
    print(f"  Deployed:      {'YES' if state.deploy_manifest else 'NO'}")
    print(f"  Audit Files:   {len(paths)} written to agents/qwen/")

    if state.errors:
        print(f"\n  Errors:")
        for e in state.errors:
            print(f"    ✗ {e}")

    print(f"\n{'═' * 64}\n")

    return 0 if state.final_status == NodeStatus.COMPLETED else 1


if __name__ == "__main__":
    sys.exit(main())
