"""Pydantic models for contract and state validation."""
from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator


class Scope(BaseModel):
    features: list[str] = Field(..., min_length=1, description="List of features to implement")
    boundaries: list[str] = Field(default_factory=list, description="Technical boundaries")
    exclusions: list[str] = Field(default_factory=list, description="Explicit exclusions")


class Risk(BaseModel):
    id: str = Field(default_factory=lambda: f"R{uuid4().hex[:6]}")
    severity: str = Field(..., pattern="^(high|medium|low)$")
    mitigation: str = ""

    @field_validator("severity")
    @classmethod
    def validate_severity(cls, v: str) -> str:
        if v not in ("high", "medium", "low"):
            raise ValueError(f"Severity must be high|medium|low, got {v}")
        return v


class Assets(BaseModel):
    repos: list[str] = Field(default_factory=list)
    secrets: list[str] = Field(default_factory=list)
    infra: list[str] = Field(default_factory=list)


class Approval(BaseModel):
    hermes_signoff: bool = False
    board_veto_window_hrs: int = Field(default=24, ge=1, le=168)


class Contract(BaseModel):
    """Handshake contract between Hermes and Agent Zero."""
    contract_id: UUID = Field(default_factory=uuid4)
    project: str = Field(..., min_length=1, max_length=100)
    scope: Scope
    risks: list[Risk] = Field(default_factory=list)
    assets: Assets = Field(default_factory=Assets)
    approval: Approval = Field(default_factory=Approval)
    created_at: datetime = Field(default_factory=datetime.utcnow)

    def is_approved(self) -> bool:
        """Check if contract is approved (Hermes signoff or veto window expired)."""
        if self.approval.hermes_signoff:
            return True

        from datetime import timedelta
        veto_deadline = self.created_at + timedelta(hours=self.approval.board_veto_window_hrs)
        return datetime.utcnow() >= veto_deadline


class BuildResult(BaseModel):
    feature: str
    build_status: str = "passed"
    tests_run: int = 12
    tests_passed: int = 12
    tests_failed: int = 0
    sandbox: str = ""


class DeployManifest(BaseModel):
    project: str
    contract_id: UUID
    deploy_target: str = "production-vm"
    auth_method: str = "ssh_key"
    rollback_timeout_s: int = 60
    health_check: dict[str, Any] = Field(default_factory=lambda: {
        "endpoint": "/health",
        "interval_s": 10,
        "retries": 3,
    })
    artifacts: list[dict[str, str]] = Field(default_factory=list)
    status: str = "deployed"


class ProjectManifest(BaseModel):
    project_name: str
    contract_id: UUID
    features: list[str]
    directories: dict[str, str]
    status: str = "initialized"
