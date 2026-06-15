"""LangGraph state schema using TypedDict."""
from __future__ import annotations

from typing import Annotated, Any, TypedDict

from langgraph.graph import END
from langgraph.graph.message import add_messages

from .models import Contract, DeployManifest


class GraphState(TypedDict):
    """State that flows through the LangGraph StateGraph."""

    # Core identifiers
    task_id: str
    project_name: str
    contract: Contract | None

    # Execution tracking
    current_node: str
    node_history: list[str]

    # Sub-agent outputs
    pm_manifest: dict[str, Any] | None
    dev_results: list[dict[str, Any]]
    devops_manifest: DeployManifest | None

    # Gates and flags
    contract_approved: bool
    sandbox_verified: bool
    simulate: bool  # True = simulation mode, False = real LLM/MCP/SSH

    # Error tracking
    errors: list[str]
    final_status: str  # "pending" | "completed" | "failed" | "blocked"

    # Messages for human-in-the-loop
    messages: Annotated[list, add_messages]
