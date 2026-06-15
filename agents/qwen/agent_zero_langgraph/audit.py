"""Audit trail writer for LangGraph state."""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

AUDIT_DIR = Path(os.environ.get("AUDIT_DIR", str(Path(__file__).resolve().parent.parent)))


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _json_serialize(obj: Any) -> Any:
    """Serialize Pydantic models, UUIDs, datetimes, etc."""
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    if hasattr(obj, "dict"):
        return obj.dict()
    if isinstance(obj, Path):
        return str(obj)
    return str(obj)


def write_execution_graph(state: dict, task_id: str | None = None) -> Path:
    """Write graph execution state to execution-graph.json."""
    data = {
        "task_id": task_id or state.get("task_id", "unknown"),
        "project_name": state.get("project_name", "unknown"),
        "current_node": state.get("current_node", "unknown"),
        "node_history": state.get("node_history", []),
        "final_status": state.get("final_status", "pending"),
        "contract_id": (
            str(state["contract"].contract_id)
            if state.get("contract")
            else None
        ),
        "contract_approved": state.get("contract_approved", False),
        "sandbox_verified": state.get("sandbox_verified", False),
        "errors": state.get("errors", []),
        "timestamp": _now_iso(),
    }
    path = AUDIT_DIR / "execution-graph.json"
    path.write_text(json.dumps(data, indent=2, default=_json_serialize))
    return path


def write_agent_registry(state: dict, task_id: str | None = None) -> Path:
    """Write active sub-agents to agent-registry.json."""
    agents = []

    # PM Agent
    if state.get("pm_manifest"):
        agents.append({
            "agent_id": state["pm_manifest"].get("project_name", "pm"),
            "role": "project_manager",
            "status": "completed",
            "project": state.get("project_name", "unknown"),
            "output_summary": f"{len(state['pm_manifest'].get('features', []))} features",
        })

    # Dev Agents
    for i, result in enumerate(state.get("dev_results", [])):
        builds = result.get("builds", [])
        passed = sum(1 for b in builds if b.get("tests_failed", 1) == 0)
        agents.append({
            "agent_id": result.get("agent_id", f"dev-{i}"),
            "role": "developer",
            "status": result.get("status", "unknown"),
            "project": state.get("project_name", "unknown"),
            "output_summary": f"specialty={result.get('specialty', '?')}, builds: {passed}/{len(builds)} passed",
        })

    # DevOps Agent
    if state.get("devops_manifest"):
        manifest = state["devops_manifest"]
        agents.append({
            "agent_id": "devops",
            "role": "devops",
            "status": "completed",
            "project": state.get("project_name", "unknown"),
            "output_summary": f"deployed to {manifest.get('deploy_target', '?')}, {len(manifest.get('artifacts', []))} artifacts",
        })

    registry = {
        "task_id": task_id or state.get("task_id", "unknown"),
        "active_agents": agents,
        "total_spawned": len(agents),
        "timestamp": _now_iso(),
    }
    path = AUDIT_DIR / "agent-registry.json"
    path.write_text(json.dumps(registry, indent=2, default=_json_serialize))
    return path


def append_deployment_log(state: dict, task_id: str | None = None) -> Path:
    """Append deployment event to deployment-log.jsonl."""
    path = AUDIT_DIR / "deployment-log.jsonl"

    entry = {
        "task_id": task_id or state.get("task_id", "unknown"),
        "project": state.get("project_name", "unknown"),
        "timestamp": _now_iso(),
        "final_status": state.get("final_status", "pending"),
        "sandbox_verified": state.get("sandbox_verified", False),
    }

    if state.get("devops_manifest"):
        entry["deploy_manifest"] = state["devops_manifest"]

    with open(path, "a") as f:
        f.write(json.dumps(entry, default=_json_serialize) + "\n")

    return path


def write_decision_tree(state: dict, task_id: str | None = None) -> Path:
    """Write human-readable decision log."""
    path = AUDIT_DIR / "decision-tree.md"
    contract = state.get("contract")

    lines = [
        f"# Decision Tree — {state.get('project_name', 'unknown')}",
        "",
        f"**Task ID:** `{task_id or state.get('task_id', 'unknown')}`",
        f"**Contract ID:** `{contract.contract_id if contract else 'N/A'}`",
        f"**Executed:** {_now_iso()}",
        f"**Final Status:** {state.get('final_status', 'pending')}",
        "",
        "---",
        "",
        "## Graph Execution Path",
        "",
        "```",
        " → ".join(state.get("node_history", [])),
        "```",
        "",
    ]

    if contract:
        lines.extend([
            "## Scope",
            "",
        ])
        scope = contract.scope
        for key in ("features", "boundaries", "exclusions"):
            items = getattr(scope, key, [])
            if items:
                lines.append(f"### {key.title()}")
                for item in items:
                    lines.append(f"- {item}")
                lines.append("")

    # Sub-Agent Results table
    lines.extend([
        "## Sub-Agent Results",
        "",
        "| Agent | Role | Status | Details |",
        "|-------|------|--------|---------|",
    ])

    if state.get("pm_manifest"):
        manifest = state["pm_manifest"]
        lines.append(
            f"| PM | project_manager | completed | {len(manifest.get('features', []))} features |"
        )

    for result in state.get("dev_results", []):
        builds = result.get("builds", [])
        passed = sum(1 for b in builds if b.get("tests_failed", 1) == 0)
        lines.append(
            f"| `{result.get('agent_id', '?')}` | developer | {result.get('status', '?')} | "
            f"specialty={result.get('specialty', '?')}, builds: {passed}/{len(builds)} passed |"
        )

    if state.get("devops_manifest"):
        manifest = state["devops_manifest"]
        lines.append(
            f"| DevOps | devops | completed | "
            f"deployed to {manifest.get('deploy_target', '?')}, "
            f"{len(manifest.get('artifacts', []))} artifacts |"
        )

    # Errors
    errors = state.get("errors", [])
    if errors:
        lines.extend(["", "## Errors"])
        for e in errors:
            lines.append(f"- {e}")

    # Deploy Manifest
    if state.get("devops_manifest"):
        lines.extend([
            "",
            "## Deploy Manifest",
            "```json",
            json.dumps(state["devops_manifest"], indent=2, default=_json_serialize),
            "```",
        ])

    path.write_text("\n".join(lines) + "\n")
    return path


def write_all_artifacts(state: dict, task_id: str | None = None) -> list[Path]:
    """Write all audit artifacts."""
    return [
        write_execution_graph(state, task_id),
        write_agent_registry(state, task_id),
        append_deployment_log(state, task_id),
        write_decision_tree(state, task_id),
    ]
