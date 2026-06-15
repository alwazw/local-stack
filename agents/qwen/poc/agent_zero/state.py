"""
State definitions for the Agent Zero orchestration graph.
Mirrors LangGraph's TypedDict-based state model.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class NodeStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    BLOCKED = "blocked"


class SubAgentRole(Enum):
    PM = "project_manager"
    DEV = "developer"
    DEVOPS = "devops"


@dataclass
class ContractApproval:
    hermes_signoff: bool = False
    board_veto_expires_at: str | None = None
    board_vetoed: bool = False


@dataclass
class SubAgentResult:
    agent_id: str
    role: SubAgentRole
    status: NodeStatus
    output: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


@dataclass
class GraphState:
    """The single state object that flows through every node in the graph."""

    task_id: str = field(default_factory=lambda: str(uuid.uuid4())[:8])
    project_name: str = ""
    contract: dict[str, Any] = field(default_factory=dict)
    contract_approved: ContractApproval = field(default_factory=ContractApproval)
    current_node: str = "intake"
    node_history: list[str] = field(default_factory=list)
    sub_agent_results: list[SubAgentResult] = field(default_factory=list)
    sandbox_verified: bool = False
    deploy_manifest: dict[str, Any] | None = None
    errors: list[str] = field(default_factory=list)
    final_status: NodeStatus = NodeStatus.PENDING
