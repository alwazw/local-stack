"""
Agent Zero REST API — Delegation endpoint for Hermes → Agent Zero.

Endpoints:
  POST /api/v1/tasks          — Submit a contract and start graph execution
  GET  /api/v1/tasks/{id}     — Get task status and state
  POST /api/v1/tasks/{id}/approve — Approve a blocked contract (HITL)
  GET  /api/v1/tasks          — List all active tasks
  GET  /api/v1/health         — Health check
  GET  /api/v1/projects       — List projects in memory
"""
from __future__ import annotations

import json
import os
import threading
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from langgraph.checkpoint.memory import MemorySaver
from pydantic import BaseModel, Field

from .audit import write_all_artifacts
from .graph import build_ceo_graph
from .llm_client import LLMClient
from .mcp_client import MCPClient
from .memory import ProjectMemory
from .models import Approval, Assets, Contract, Risk, Scope
from .ssh_deploy import SSHDeployer

app = FastAPI(
    title="Agent Zero — CEO Orchestration API",
    description="REST API for Hermes → Agent Zero task delegation",
    version="1.0.0",
)

# ── API Key / Auth ─────────────────────────────────────────────────

def _load_api_key() -> str:
    """Load API key from env var or secret file. Called on each request."""
    key = os.environ.get("AGENT_ZERO_API_KEY", "")
    if not key:
        key_file = os.environ.get("AGENT_ZERO_API_KEY_FILE", "/run/secrets/agent_zero_key")
        if os.path.exists(key_file):
            try:
                key = open(key_file).read().strip()
            except Exception:
                pass
    return key


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    api_key = _load_api_key()
    if not api_key:  # No key set = dev mode, allow all
        return await call_next(request)
    public_paths = {"/api/v1/health", "/docs", "/openapi.json", "/redoc"}
    if request.url.path in public_paths:
        return await call_next(request)
    auth = request.headers.get("Authorization", "")
    if auth != f"Bearer {api_key}":
        return JSONResponse(
            status_code=401,
            content={"error": "Invalid or missing API key"},
        )
    return await call_next(request)


# ── In-memory task store ───────────────────────────────────────────
_tasks: dict[str, dict[str, Any]] = {}
_task_lock = threading.Lock()

# Shared services
_checkpointer = MemorySaver()
_compiled_graph = build_ceo_graph().compile(checkpointer=_checkpointer)
_project_memory = ProjectMemory()
_llm_client = LLMClient()
_mcp_client = MCPClient()
_ssh_deployer = SSHDeployer()


# ── Request/Response Models ─────────────────────────────────────────

class TaskSubmitRequest(BaseModel):
    """Request body for submitting a new task/contract."""
    project: str = Field(..., min_length=1, max_length=100)
    features: list[str] = Field(..., min_length=1)
    boundaries: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    risks: list[dict[str, str]] = Field(default_factory=list)
    repos: list[str] = Field(default_factory=list)
    infra: list[str] = Field(default_factory=list)
    veto_window_hrs: int = Field(default=24, ge=1, le=168)
    auto_approve: bool = Field(default=False, description="Auto-approve contract (skip HITL)")
    simulate: bool = Field(default=True, description="Simulate LLM/MCP/SSH calls")


class TaskResponse(BaseModel):
    task_id: str
    project: str
    status: str
    node_history: list[str] = Field(default_factory=list)
    contract_approved: bool = False
    sandbox_verified: bool = False
    final_status: str = "pending"
    errors: list[str] = Field(default_factory=list)
    created_at: str = ""
    completed_at: str | None = None
    agent_count: int = 0
    deploy_manifest: dict[str, Any] | None = None


class ApprovalRequest(BaseModel):
    """Request body for approving a blocked contract."""
    approved: bool = True
    approver: str = "board"


# ── Endpoints ───────────────────────────────────────────────────────

@app.get("/api/v1/health")
def health():
    """Health check — shows service availability."""
    return {
        "status": "ok",
        "services": {
            "llm_available": _llm_client.is_available(),
            "mcp_available": _mcp_client.is_available(),
            "ssh_key_exists": _ssh_deployer.is_available(),
            "memory_dir": str(_project_memory.memory_dir),
        },
        "active_tasks": len(_tasks),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/api/v1/tasks", response_model=TaskResponse)
def submit_task(request: TaskSubmitRequest):
    """Submit a new task contract and execute the CEO graph."""
    task_id = str(uuid.uuid4())[:8]

    # Build contract
    contract = Contract(
        project=request.project,
        scope=Scope(
            features=request.features,
            boundaries=request.boundaries,
            exclusions=request.exclusions,
        ),
        risks=[
            Risk(
                severity=r.get("severity", "medium"),
                mitigation=r.get("mitigation", ""),
            )
            for r in request.risks
        ],
        assets=Assets(repos=request.repos, infra=request.infra),
        approval=Approval(
            hermes_signoff=request.auto_approve,
            board_veto_window_hrs=request.veto_window_hrs,
        ),
    )

    # Store task
    with _task_lock:
        _tasks[task_id] = {
            "task_id": task_id,
            "project": request.project,
            "contract": contract,
            "status": "running",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "simulate": request.simulate,
        }

    # Execute graph
    try:
        state = _execute_graph(task_id, contract, simulate=request.simulate)
        result = _state_to_response(task_id, state)

        # Store project memory
        _project_memory.store_project_context(request.project, {
            "task_id": task_id,
            "final_status": result.final_status,
            "agent_count": result.agent_count,
            "features": request.features,
        })

        return result

    except Exception as e:
        with _task_lock:
            _tasks[task_id]["status"] = "error"
            _tasks[task_id]["error"] = str(e)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/tasks/{task_id}", response_model=TaskResponse)
def get_task(task_id: str):
    """Get the status and state of a task."""
    with _task_lock:
        task = _tasks.get(task_id)

    if not task:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")

    state = task.get("final_state")
    if state:
        return _state_to_response(task_id, state)

    return TaskResponse(
        task_id=task_id,
        project=task["project"],
        status=task["status"],
        created_at=task["created_at"],
    )


@app.post("/api/v1/tasks/{task_id}/approve")
def approve_task(task_id: str, request: ApprovalRequest):
    """Approve a blocked contract (human-in-the-loop)."""
    with _task_lock:
        task = _tasks.get(task_id)

    if not task:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")

    if task["status"] != "blocked":
        raise HTTPException(status_code=400, detail=f"Task {task_id} is not blocked (status: {task['status']})")

    # Update contract approval
    contract = task["contract"]
    contract.approval.hermes_signoff = request.approved

    if request.approved:
        # Re-execute the graph with approved contract
        try:
            state = _execute_graph(task_id, contract, simulate=task.get("simulate", True))
            result = _state_to_response(task_id, state)
            return {"message": "Contract approved and graph re-executed", "task": result}
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
    else:
        with _task_lock:
            _tasks[task_id]["status"] = "rejected"
        return {"message": "Contract rejected", "task_id": task_id}


@app.get("/api/v1/tasks")
def list_tasks():
    """List all tasks."""
    with _task_lock:
        tasks = []
        for task_id, task in _tasks.items():
            state = task.get("final_state", {})
            agent_count = 0
            if state.get("pm_manifest"):
                agent_count += 1
            agent_count += len(state.get("dev_results", []))
            if state.get("devops_manifest"):
                agent_count += 1
            tasks.append({
                "task_id": task_id,
                "project": task["project"],
                "status": task["status"],
                "final_status": state.get("final_status", task["status"]),
                "created_at": task["created_at"],
                "completed_at": task.get("completed_at"),
                "agent_count": agent_count,
            })
    return {"tasks": tasks, "total": len(tasks)}


@app.get("/api/v1/projects")
def list_projects():
    """List all projects in memory."""
    projects = _project_memory.list_projects()
    return {"projects": projects, "total": len(projects)}


@app.get("/api/v1/projects/{project}")
def get_project_memory(project: str):
    """Get memory context for a project."""
    data = _project_memory.get_project_context(project)
    if not data:
        raise HTTPException(status_code=404, detail=f"No memory for project '{project}'")
    return data


# ── Internal Helpers ────────────────────────────────────────────────

def _execute_graph(task_id: str, contract: Contract, simulate: bool = True) -> dict:
    """Execute the CEO graph and store results."""
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

    final_state = None
    for event in _compiled_graph.stream(initial_state, config=config, stream_mode="values"):
        final_state = event

    if final_state is None:
        raise RuntimeError("Graph execution produced no final state")

    # Store final state in task
    with _task_lock:
        _tasks[task_id]["final_state"] = final_state
        _tasks[task_id]["status"] = final_state.get("final_status", "unknown")
        _tasks[task_id]["completed_at"] = datetime.now(timezone.utc).isoformat()

    # Write audit artifacts
    try:
        write_all_artifacts(final_state, task_id)
    except Exception:
        pass  # Audit write failure is non-fatal

    return final_state


def _state_to_response(task_id: str, state: dict) -> TaskResponse:
    """Convert graph state to API response."""
    task = _tasks.get(task_id, {})

    agent_count = 0
    if state.get("pm_manifest"):
        agent_count += 1
    agent_count += len(state.get("dev_results", []))
    if state.get("devops_manifest"):
        agent_count += 1

    return TaskResponse(
        task_id=task_id,
        project=state.get("project_name", "unknown"),
        status=task.get("status", state.get("final_status", "unknown")),
        node_history=state.get("node_history", []),
        contract_approved=state.get("contract_approved", False),
        sandbox_verified=state.get("sandbox_verified", False),
        final_status=state.get("final_status", "unknown"),
        errors=state.get("errors", []),
        created_at=task.get("created_at", ""),
        completed_at=task.get("completed_at"),
        agent_count=agent_count,
        deploy_manifest=state.get("devops_manifest"),
    )
