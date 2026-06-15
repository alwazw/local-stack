"""
Audit trail writer — persists structured artifacts to ~/docker/agents/qwen/.
These files serve as the ground-truth map of the multi-agent stack.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .state import GraphState, NodeStatus, SubAgentRole

AUDIT_DIR = Path(__file__).resolve().parent.parent.parent


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _json_default(obj: Any) -> Any:
    if isinstance(obj, SubAgentRole):
        return obj.value
    if isinstance(obj, NodeStatus):
        return obj.value
    if hasattr(obj, "__dict__"):
        return {k: v for k, v in obj.__dict__.items() if not k.startswith("_")}
    return str(obj)


def write_execution_graph(state: GraphState) -> Path:
    """Write the current graph execution state to execution-graph.json."""
    data = {
        "task_id": state.task_id,
        "project_name": state.project_name,
        "current_node": state.current_node,
        "node_history": state.node_history,
        "final_status": state.final_status.value,
        "contract_id": state.contract.get("contract_id"),
        "contract_approved": state.contract_approved.hermes_signoff,
        "sandbox_verified": state.sandbox_verified,
        "errors": state.errors,
        "timestamp": _now_iso(),
    }
    path = AUDIT_DIR / "execution-graph.json"
    path.write_text(json.dumps(data, indent=2, default=_json_default))
    return path


def write_agent_registry(state: GraphState) -> Path:
    """Write active sub-agents and their roles to agent-registry.json."""
    agents = []
    for r in state.sub_agent_results:
        agents.append({
            "agent_id": r.agent_id,
            "role": r.role.value,
            "status": r.status.value,
            "project": state.project_name,
            "output_summary": _summarize_output(r.output),
            "error": r.error,
        })

    registry = {
        "task_id": state.task_id,
        "active_agents": agents,
        "total_spawned": len(agents),
        "timestamp": _now_iso(),
    }
    path = AUDIT_DIR / "agent-registry.json"
    path.write_text(json.dumps(registry, indent=2, default=_json_default))
    return path


def append_deployment_log(state: GraphState) -> Path:
    """Append a deployment event to deployment-log.jsonl."""
    path = AUDIT_DIR / "deployment-log.jsonl"

    entry = {
        "task_id": state.task_id,
        "project": state.project_name,
        "timestamp": _now_iso(),
        "final_status": state.final_status.value,
        "sandbox_verified": state.sandbox_verified,
    }

    if state.deploy_manifest:
        entry["deploy_manifest"] = state.deploy_manifest

    with open(path, "a") as f:
        f.write(json.dumps(entry, default=_json_default) + "\n")

    return path


def write_decision_tree(state: GraphState) -> Path:
    """Write a human-readable decision log for this contract execution."""
    path = AUDIT_DIR / "decision-tree.md"

    lines = [
        f"# Decision Tree — {state.project_name}",
        f"",
        f"**Task ID:** `{state.task_id}`",
        f"**Contract ID:** `{state.contract.get('contract_id', 'N/A')}`",
        f"**Executed:** {_now_iso()}",
        f"**Final Status:** {state.final_status.value}",
        f"",
        f"---",
        f"",
        f"## Graph Execution Path",
        f"",
        f"```",
        f" → ".join(state.node_history),
        f"```",
        f"",
        f"## Scope",
        f"",
    ]

    scope = state.contract.get("scope", {})
    for key in ("features", "boundaries", "exclusions"):
        items = scope.get(key, [])
        if items:
            lines.append(f"### {key.title()}")
            for item in items:
                lines.append(f"- {item}")
            lines.append("")

    lines.append("## Sub-Agent Results")
    lines.append("")
    lines.append("| Agent | Role | Status | Details |")
    lines.append("|-------|------|--------|---------|")
    for r in state.sub_agent_results:
        summary = _summarize_output(r.output)
        lines.append(f"| `{r.agent_id}` | {r.role.value} | {r.status.value} | {summary} |")

    if state.errors:
        lines.append("")
        lines.append("## Errors")
        for e in state.errors:
            lines.append(f"- {e}")

    if state.deploy_manifest:
        lines.append("")
        lines.append("## Deploy Manifest")
        lines.append(f"```json")
        lines.append(json.dumps(state.deploy_manifest, indent=2, default=_json_default))
        lines.append(f"```")

    path.write_text("\n".join(lines) + "\n")
    return path


def _summarize_output(output: dict[str, Any]) -> str:
    """One-line summary of agent output for tables."""
    parts = []
    if "feature_count" in output:
        parts.append(f"{output['feature_count']} features")
    if "specialty" in output:
        parts.append(f"specialty={output['specialty']}")
    if "sandbox_verified" in output:
        parts.append(f"sandbox={'pass' if output['sandbox_verified'] else 'FAIL'}")
    if "deploy_manifest" in output:
        parts.append(f"deployed to {output['deploy_manifest'].get('deploy_target', '?')}")
    if "builds" in output:
        total = len(output["builds"])
        passed = sum(1 for b in output["builds"] if b.get("build_status") == "passed")
        parts.append(f"builds: {passed}/{total} passed")
    return ", ".join(parts) if parts else "—"


def write_all_artifacts(state: GraphState) -> list[Path]:
    """Write all audit artifacts and return the list of written paths."""
    paths = [
        write_execution_graph(state),
        write_agent_registry(state),
        append_deployment_log(state),
        write_decision_tree(state),
    ]
    return paths
