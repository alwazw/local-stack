"""
Sub-agent classes for the Agent Zero hierarchy.
These are lightweight Python classes with role-specific logic —
in production they'd bind to MCP tool servers and LLM endpoints.
"""
from __future__ import annotations

import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

from .state import GraphState, NodeStatus, SubAgentResult, SubAgentRole


class BaseAgent(ABC):
    """Base class for all sub-agents spawned by Agent Zero."""

    role: SubAgentRole

    def __init__(self, agent_id: str | None = None):
        self.agent_id = agent_id or str(uuid.uuid4())[:8]

    @abstractmethod
    def execute(self, state: GraphState) -> SubAgentResult:
        ...

    def __repr__(self) -> str:
        return f"<{self.__class__.__name__} id={self.agent_id}>"


class PMAgent(BaseAgent):
    """
    Project Manager Agent — owns a single project directory.
    Responsibilities:
    - Validate that the project scope matches the contract features
    - Generate a project manifest
    - Track progress and enforce documentation standards
    """

    role = SubAgentRole.PM

    def execute(self, state: GraphState) -> SubAgentResult:
        contract = state.contract
        scope = contract.get("scope", {})
        features = scope.get("features", [])

        manifest = {
            "project_name": state.project_name,
            "contract_id": contract.get("contract_id"),
            "features": features,
            "directories": {
                "frontend": f"projects/{state.project_name}/frontend",
                "backend": f"projects/{state.project_name}/backend",
                "docker": f"projects/{state.project_name}/docker",
                "audit": f"projects/{state.project_name}/.audit",
            },
            "status": "initialized",
        }

        return SubAgentResult(
            agent_id=self.agent_id,
            role=self.role,
            status=NodeStatus.COMPLETED,
            output={"manifest": manifest, "feature_count": len(features)},
        )


class DevAgent(BaseAgent):
    """
    Developer Agent — writes, tests, and debugs code within a sandboxed scope.
    In production: binds to MCP Filesystem + Git servers, runs shell commands.
    PoC: simulates build + test cycle.
    """

    role = SubAgentRole.DEV

    def __init__(self, specialty: str = "fullstack", **kwargs):
        super().__init__(**kwargs)
        self.specialty = specialty

    def execute(self, state: GraphState) -> SubAgentResult:
        features = state.contract.get("scope", {}).get("features", [])
        build_results = []

        for feature in features:
            build_results.append({
                "feature": feature,
                "build_status": "passed",
                "tests_run": 12,
                "tests_passed": 12,
                "tests_failed": 0,
                "sandbox": f"sandbox-{self.agent_id}",
            })

        all_passed = all(b["tests_failed"] == 0 for b in build_results)

        return SubAgentResult(
            agent_id=self.agent_id,
            role=self.role,
            status=NodeStatus.COMPLETED if all_passed else NodeStatus.FAILED,
            output={
                "specialty": self.specialty,
                "builds": build_results,
                "sandbox_verified": all_passed,
            },
        )


class DevOpsAgent(BaseAgent):
    """
    DevOps Agent — manages deployments to the production VM.
    Only activates after sandbox verification passes.
    In production: SSH key-based deployment with health-check rollback.
    PoC: generates a deploy manifest.
    """

    role = SubAgentRole.DEVOPS

    def execute(self, state: GraphState) -> SubAgentResult:
        if not state.sandbox_verified:
            return SubAgentResult(
                agent_id=self.agent_id,
                role=self.role,
                status=NodeStatus.BLOCKED,
                error="Sandbox verification not passed. Deployment aborted.",
            )

        dev_results = [
            r for r in state.sub_agent_results if r.role == SubAgentRole.DEV
        ]
        builds = []
        for r in dev_results:
            builds.extend(r.output.get("builds", []))

        manifest = {
            "project": state.project_name,
            "contract_id": state.contract.get("contract_id"),
            "deploy_target": "production-vm",
            "auth_method": "ssh_key",
            "rollback_timeout_s": 60,
            "health_check": {
                "endpoint": f"/health",
                "interval_s": 10,
                "retries": 3,
            },
            "artifacts": [
                {"feature": b["feature"], "build_status": b["build_status"]}
                for b in builds
            ],
            "status": "deployed",
        }

        return SubAgentResult(
            agent_id=self.agent_id,
            role=self.role,
            status=NodeStatus.COMPLETED,
            output={"deploy_manifest": manifest},
        )
