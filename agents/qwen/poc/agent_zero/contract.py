"""
Handshake Contract Validator — enforces scope sign-off before execution.
Agent Zero blocks until Hermes approves the contract.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from .state import ContractApproval, GraphState, NodeStatus


REQUIRED_FIELDS = ["project", "scope", "risks", "assets", "approval"]
SCOPE_FIELDS = ["features", "boundaries", "exclusions"]


def build_contract(
    project: str,
    features: list[str],
    boundaries: list[str],
    exclusions: list[str],
    risks: list[dict[str, str]],
    repos: list[str] | None = None,
    secrets: list[str] | None = None,
    infra: list[str] | None = None,
    veto_window_hrs: int = 24,
) -> dict[str, Any]:
    """Build a new handshake contract from raw project parameters."""
    return {
        "contract_id": str(uuid.uuid4()),
        "project": project,
        "scope": {
            "features": features,
            "boundaries": boundaries,
            "exclusions": exclusions,
        },
        "risks": [
            {"id": r.get("id", f"R{i}"), "severity": r.get("severity", "medium"), "mitigation": r.get("mitigation", "")}
            for i, r in enumerate(risks, 1)
        ],
        "assets": {
            "repos": repos or [],
            "secrets": secrets or [],
            "infra": infra or [],
        },
        "approval": {
            "hermes_signoff": False,
            "board_veto_window_hrs": veto_window_hrs,
        },
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


class ContractValidationError(Exception):
    pass


def validate_contract_schema(contract: dict[str, Any]) -> list[str]:
    """Validate the contract structure. Returns list of errors (empty = valid)."""
    errors: list[str] = []

    for f in REQUIRED_FIELDS:
        if f not in contract:
            errors.append(f"Missing required field: {f}")

    if "scope" in contract:
        scope = contract["scope"]
        if not isinstance(scope, dict):
            errors.append("'scope' must be a dict")
        else:
            for sf in SCOPE_FIELDS:
                if sf not in scope:
                    errors.append(f"Missing scope field: {sf}")
            if not scope.get("features"):
                errors.append("'scope.features' must not be empty")

    if "risks" in contract:
        if not isinstance(contract["risks"], list):
            errors.append("'risks' must be a list")
        else:
            for i, r in enumerate(contract["risks"]):
                if "severity" not in r or r["severity"] not in ("high", "medium", "low"):
                    errors.append(f"Risk {i}: severity must be high|medium|low")

    if "approval" in contract:
        approval = contract["approval"]
        if not isinstance(approval, dict):
            errors.append("'approval' must be a dict")
        elif "hermes_signoff" not in approval:
            errors.append("Missing 'approval.hermes_signoff'")

    return errors


def check_approval_gate(state: GraphState) -> GraphState:
    """
    Conditional edge: blocks execution unless hermes_signoff is True.
    If board_veto_window_hrs has elapsed without veto, auto-approves.
    """
    errors = validate_contract_schema(state.contract)
    if errors:
        state.errors.extend(errors)
        state.final_status = NodeStatus.BLOCKED
        return state

    approval = state.contract["approval"]

    if approval.get("hermes_signoff"):
        state.contract_approved = ContractApproval(
            hermes_signoff=True,
            board_veto_expires_at=None,
            board_vetoed=False,
        )
        return state

    veto_window_hrs = approval.get("board_veto_window_hrs", 24)
    created_at_str = state.contract.get("created_at")

    if created_at_str:
        created_at = datetime.fromisoformat(created_at_str)
        veto_deadline = created_at + timedelta(hours=veto_window_hrs)
        now = datetime.now(timezone.utc)

        if now >= veto_deadline:
            state.contract_approved = ContractApproval(
                hermes_signoff=True,
                board_veto_expires_at=veto_deadline.isoformat(),
                board_vetoed=False,
            )
            return state

    state.contract_approved = ContractApproval(
        hermes_signoff=False,
        board_veto_expires_at=(
            datetime.fromisoformat(created_at_str) + timedelta(hours=veto_window_hrs)
        ).isoformat()
        if created_at_str
        else None,
        board_vetoed=False,
    )
    state.final_status = NodeStatus.BLOCKED
    return state


def simulate_hermes_signoff(state: GraphState) -> GraphState:
    """Simulate Hermes approving the contract (for PoC purposes)."""
    state.contract["approval"]["hermes_signoff"] = True
    return state
