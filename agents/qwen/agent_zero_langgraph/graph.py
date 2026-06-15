"""
Agent Zero CEO Orchestration Graph — LangGraph StateGraph implementation.

Graph topology:
    [Intake] → [Scope Validation] → (approved?) → [PM Delegation]
                                                  → [Dev Pool]
                                                  → [Result Aggregation] → (sandbox ok?) → [DevOps Pool]
                                                                                         → [Checkpoint]
                                                                                          → [Blocked]
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

from langgraph.graph import END, START, StateGraph
from langgraph.checkpoint.memory import MemorySaver
from langgraph.types import interrupt, Command

from .agents import DevAgent, DevOpsAgent, PMAgent
from .models import Contract
from .state import GraphState


def intake_node(state: GraphState) -> dict[str, Any]:
    """Parse contract and set project name."""
    contract = state.get("contract")
    if contract is None:
        return {
            "project_name": "unknown",
            "errors": ["No contract provided"],
            "final_status": "failed",
        }

    return {
        "project_name": contract.project,
        "current_node": "intake",
        "node_history": ["intake"],
        "simulate": state.get("simulate", True),
    }


def scope_validation_node(state: GraphState) -> dict[str, Any]:
    """
    Validate contract and check approval gate.
    If not approved, use interrupt() for human-in-the-loop approval.
    """
    contract = state.get("contract")
    if contract is None:
        return {
            "contract_approved": False,
            "errors": ["No contract to validate"],
            "final_status": "blocked",
        }

    # Check if already approved
    if contract.is_approved():
        return {
            "contract_approved": True,
            "current_node": "scope_validation",
            "node_history": state.get("node_history", []) + ["scope_validation"],
        }

    # Check veto window expiration
    veto_deadline = contract.created_at + timedelta(hours=contract.approval.board_veto_window_hrs)
    if datetime.utcnow() >= veto_deadline:
        return {
            "contract_approved": True,
            "current_node": "scope_validation",
            "node_history": state.get("node_history", []) + ["scope_validation"],
        }

    # Not approved — use interrupt() for human-in-the-loop
    # This pauses execution and waits for resume via Command(resume={...})
    try:
        approval_result = interrupt({
            "type": "contract_approval",
            "contract_id": str(contract.contract_id),
            "project": contract.project,
            "features": contract.scope.features,
            "veto_deadline": veto_deadline.isoformat(),
            "message": f"Contract {contract.contract_id} requires approval. "
                       f"Veto window expires at {veto_deadline.isoformat()}.",
        })

        # Resumed with approval decision
        if approval_result and approval_result.get("approved"):
            contract.approval.hermes_signoff = True
            return {
                "contract_approved": True,
                "current_node": "scope_validation",
                "node_history": state.get("node_history", []) + ["scope_validation"],
            }
        else:
            return {
                "contract_approved": False,
                "current_node": "scope_validation",
                "node_history": state.get("node_history", []) + ["scope_validation"],
            }

    except Exception:
        # interrupt() not available (e.g., no checkpointer) — fall back to blocked
        return {
            "contract_approved": False,
            "current_node": "scope_validation",
            "node_history": state.get("node_history", []) + ["scope_validation"],
            "messages": [
                {
                    "role": "system",
                    "content": f"Contract {contract.contract_id} requires Hermes sign-off. "
                    f"Veto window expires at {veto_deadline.isoformat()}. "
                    f"Approve to proceed.",
                }
            ],
        }


def route_after_validation(state: GraphState) -> str:
    """Conditional edge: route based on contract approval."""
    if state.get("contract_approved", False):
        return "pm_delegation"
    return "blocked"


def pm_delegation_node(state: GraphState) -> dict[str, Any]:
    """Spawn PM Agent and generate project manifest."""
    pm = PMAgent()
    result = pm.execute(state)

    return {
        "pm_manifest": result.get("manifest"),
        "current_node": "pm_delegation",
        "node_history": state.get("node_history", []) + ["pm_delegation"],
    }


def dev_pool_node(state: GraphState) -> dict[str, Any]:
    """Spawn Dev Agent pool — one agent per feature (max 3)."""
    contract = state.get("contract")
    if contract is None:
        return {
            "dev_results": [],
            "sandbox_verified": False,
            "errors": ["No contract for dev pool"],
        }

    feature_count = len(contract.scope.features)
    agent_count = min(feature_count, 3)
    dev_agents = [DevAgent(specialty="fullstack") for _ in range(agent_count)]

    results = []
    for dev in dev_agents:
        result = dev.execute(state)
        results.append(result)

    return {
        "dev_results": results,
        "current_node": "dev_pool",
        "node_history": state.get("node_history", []) + ["dev_pool"],
    }


def result_aggregation_node(state: GraphState) -> dict[str, Any]:
    """Aggregate Dev agent results and verify sandbox."""
    dev_results = state.get("dev_results", [])

    if not dev_results:
        return {
            "sandbox_verified": False,
            "errors": ["No dev results to aggregate"],
        }

    all_passed = all(r.get("status") == "completed" for r in dev_results)
    errors = []

    if not all_passed:
        errors = ["Sandbox verification failed: one or more Dev agents reported failures"]

    return {
        "sandbox_verified": all_passed,
        "errors": state.get("errors", []) + errors,
        "current_node": "result_aggregation",
        "node_history": state.get("node_history", []) + ["result_aggregation"],
    }


def route_after_aggregation(state: GraphState) -> str:
    """Conditional edge: route to DevOps if sandbox verified, else checkpoint."""
    if state.get("sandbox_verified", False):
        return "devops_pool"
    return "checkpoint"


def devops_pool_node(state: GraphState) -> dict[str, Any]:
    """Spawn DevOps Agent and generate deploy manifest."""
    devops = DevOpsAgent()
    result = devops.execute(state)

    updates: dict[str, Any] = {
        "current_node": "devops_pool",
        "node_history": state.get("node_history", []) + ["devops_pool"],
    }

    if result.get("status") == "completed":
        updates["devops_manifest"] = result.get("manifest")
    else:
        updates["errors"] = state.get("errors", []) + [result.get("error", "DevOps failed")]

    return updates


def checkpoint_node(state: GraphState) -> dict[str, Any]:
    """Final checkpoint — determine overall status."""
    errors = state.get("errors", [])
    has_manifest = state.get("devops_manifest") is not None

    if not errors and has_manifest:
        final_status = "completed"
    elif errors:
        final_status = "failed"
    else:
        final_status = "completed"  # Sandbox-only run

    return {
        "final_status": final_status,
        "current_node": "checkpoint",
        "node_history": state.get("node_history", []) + ["checkpoint"],
    }


def blocked_node(state: GraphState) -> dict[str, Any]:
    """Terminal node when contract is not approved."""
    return {
        "final_status": "blocked",
        "current_node": "blocked",
        "node_history": state.get("node_history", []) + ["blocked"],
    }


def build_ceo_graph() -> StateGraph:
    """Build and compile the Agent Zero CEO orchestration graph."""

    # Create the state graph
    graph = StateGraph(GraphState)

    # Add nodes
    graph.add_node("intake", intake_node)
    graph.add_node("scope_validation", scope_validation_node)
    graph.add_node("pm_delegation", pm_delegation_node)
    graph.add_node("dev_pool", dev_pool_node)
    graph.add_node("result_aggregation", result_aggregation_node)
    graph.add_node("devops_pool", devops_pool_node)
    graph.add_node("checkpoint", checkpoint_node)
    graph.add_node("blocked", blocked_node)

    # Add edges
    graph.add_edge(START, "intake")
    graph.add_edge("intake", "scope_validation")

    # Conditional edge: approved → pm_delegation, else → blocked
    graph.add_conditional_edges(
        "scope_validation",
        route_after_validation,
        {
            "pm_delegation": "pm_delegation",
            "blocked": "blocked",
        },
    )

    graph.add_edge("pm_delegation", "dev_pool")
    graph.add_edge("dev_pool", "result_aggregation")

    # Conditional edge: sandbox ok → devops_pool, else → checkpoint
    graph.add_conditional_edges(
        "result_aggregation",
        route_after_aggregation,
        {
            "devops_pool": "devops_pool",
            "checkpoint": "checkpoint",
        },
    )

    graph.add_edge("devops_pool", "checkpoint")
    graph.add_edge("checkpoint", END)
    graph.add_edge("blocked", END)

    return graph
