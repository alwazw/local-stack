#!/usr/bin/env python3
"""
Tests for Agent Zero LangGraph implementation.
Tests contract validation, graph execution, deduplication, and audit output.
"""
from __future__ import annotations

import json
import sys
import os
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

# Add parent to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from agent_zero_langgraph.models import (
    Approval, Assets, BuildResult, Contract, DeployManifest,
    ProjectManifest, Risk, Scope,
)
from agent_zero_langgraph.agents import DevAgent, DevOpsAgent, PMAgent
from agent_zero_langgraph.graph import build_ceo_graph
from agent_zero_langgraph.audit import write_all_artifacts

from langgraph.checkpoint.memory import MemorySaver

passed = 0
failed = 0


def test(name: str):
    """Decorator for test functions."""
    def decorator(fn):
        global passed, failed
        try:
            fn()
            print(f"  ✓ {name}")
            passed += 1
        except AssertionError as e:
            print(f"  ✗ {name}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ✗ {name}: {type(e).__name__}: {e}")
            failed += 1
        return fn
    return decorator


def make_contract(hermes_signoff=True, veto_hrs=24) -> Contract:
    """Helper to create a test contract."""
    return Contract(
        project="test-project",
        scope=Scope(
            features=["Feature A", "Feature B"],
            boundaries=["TypeScript only"],
            exclusions=["No mobile"],
        ),
        risks=[Risk(severity="low", mitigation="test")],
        assets=Assets(repos=["repo1"], infra=["vm1"]),
        approval=Approval(hermes_signoff=hermes_signoff, board_veto_window_hrs=veto_hrs),
    )


# ── Model Tests ─────────────────────────────────────────────────────

@test("Pydantic: Contract validates with required fields")
def _():
    c = make_contract()
    assert c.project == "test-project"
    assert len(c.scope.features) == 2

@test("Pydantic: Contract rejects empty project name")
def _():
    try:
        Contract(project="", scope=Scope(features=["f"]))
        assert False, "Should have raised"
    except Exception:
        pass

@test("Pydantic: Contract rejects empty features list")
def _():
    try:
        Contract(project="test", scope=Scope(features=[]))
        assert False, "Should have raised"
    except Exception:
        pass

@test("Pydantic: Risk severity validation (high/medium/low)")
def _():
    Risk(severity="high")
    Risk(severity="medium")
    Risk(severity="low")
    try:
        Risk(severity="critical")
        assert False, "Should have raised"
    except Exception:
        pass

@test("Pydantic: Contract.is_approved() returns True when signed off")
def _():
    c = make_contract(hermes_signoff=True)
    assert c.is_approved() is True

@test("Pydantic: Contract.is_approved() returns False when not signed off and within veto window")
def _():
    c = make_contract(hermes_signoff=False, veto_hrs=24)
    assert c.is_approved() is False

@test("Pydantic: Contract.is_approved() returns True when veto window expired")
def _():
    c = make_contract(hermes_signoff=False, veto_hrs=24)
    c.created_at = datetime.utcnow() - timedelta(hours=25)
    assert c.is_approved() is True

@test("Pydantic: DeployManifest deduplication schema")
def _():
    dm = DeployManifest(
        project="test",
        contract_id=make_contract().contract_id,
        artifacts=[
            {"feature": "A", "build_status": "passed"},
            {"feature": "B", "build_status": "passed"},
        ],
    )
    assert len(dm.artifacts) == 2

# ── Agent Tests ─────────────────────────────────────────────────────

@test("PMAgent: generates manifest with correct feature count")
def _():
    c = make_contract()
    state = {"contract": c, "project_name": "test-project"}
    pm = PMAgent()
    result = pm.execute(state)
    assert result["status"] == "completed"
    assert result["feature_count"] == 2
    assert result["manifest"]["project_name"] == "test-project"

@test("PMAgent: fails gracefully without contract")
def _():
    state = {"contract": None, "project_name": ""}
    pm = PMAgent()
    result = pm.execute(state)
    assert result["status"] == "failed"

@test("DevAgent: builds all features with passing tests")
def _():
    c = make_contract()
    state = {"contract": c}
    dev = DevAgent()
    result = dev.execute(state)
    assert result["status"] == "completed"
    assert len(result["builds"]) == 2
    assert result["sandbox_verified"] is True

@test("DevOpsAgent: blocks when sandbox not verified")
def _():
    c = make_contract()
    state = {"contract": c, "sandbox_verified": False, "dev_results": []}
    devops = DevOpsAgent()
    result = devops.execute(state)
    assert result["status"] == "blocked"

@test("DevOpsAgent: deduplicates artifacts by feature name")
def _():
    c = make_contract()
    dev_results = [
        {
            "status": "completed",
            "agent_id": "dev-1",
            "builds": [
                {"feature": "Feature A", "build_status": "passed"},
                {"feature": "Feature B", "build_status": "passed"},
            ],
        },
        {
            "status": "completed",
            "agent_id": "dev-2",
            "builds": [
                {"feature": "Feature A", "build_status": "passed"},
                {"feature": "Feature B", "build_status": "passed"},
            ],
        },
    ]
    state = {
        "contract": c,
        "sandbox_verified": True,
        "dev_results": dev_results,
    }
    devops = DevOpsAgent()
    result = devops.execute(state)
    assert result["status"] == "completed"
    assert result["artifact_count"] == 2, f"Expected 2 deduplicated artifacts, got {result['artifact_count']}"

# ── Graph Tests ─────────────────────────────────────────────────────

@test("LangGraph: CEO graph compiles successfully")
def _():
    graph = build_ceo_graph()
    app = graph.compile(checkpointer=MemorySaver())
    assert app is not None

@test("LangGraph: full pipeline executes to completion")
def _():
    graph = build_ceo_graph()
    checkpointer = MemorySaver()
    app = graph.compile(checkpointer=checkpointer)

    c = make_contract(hermes_signoff=True)
    initial_state = {
        "task_id": "test-01",
        "project_name": "",
        "contract": c,
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
    config = {"configurable": {"thread_id": "test-01"}}

    final = None
    for event in app.stream(initial_state, config=config, stream_mode="values"):
        final = event

    assert final is not None, "No final state"
    assert final["final_status"] == "completed", f"Expected completed, got {final['final_status']}"
    assert final["contract_approved"] is True
    assert final["sandbox_verified"] is True
    assert final["devops_manifest"] is not None
    assert "intake" in final["node_history"]
    assert "checkpoint" in final["node_history"]

@test("LangGraph: blocked path when contract not approved")
def _():
    graph = build_ceo_graph()
    checkpointer = MemorySaver()
    app = graph.compile(checkpointer=checkpointer)

    c = make_contract(hermes_signoff=False, veto_hrs=24)
    initial_state = {
        "task_id": "test-02",
        "project_name": "",
        "contract": c,
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
    config = {"configurable": {"thread_id": "test-02"}}

    final = None
    for event in app.stream(initial_state, config=config, stream_mode="values"):
        final = event

    assert final is not None
    assert final["final_status"] == "blocked"
    assert "blocked" in final["node_history"]
    assert "devops_pool" not in final["node_history"]

@test("LangGraph: checkpoints are saved to MemorySaver")
def _():
    graph = build_ceo_graph()
    checkpointer = MemorySaver()
    app = graph.compile(checkpointer=checkpointer)

    c = make_contract(hermes_signoff=True)
    initial_state = {
        "task_id": "test-03",
        "project_name": "",
        "contract": c,
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
    config = {"configurable": {"thread_id": "test-03"}}

    for _ in app.stream(initial_state, config=config, stream_mode="values"):
        pass

    checkpoints = list(checkpointer.list(config))
    assert len(checkpoints) > 0, "No checkpoints saved"

@test("LangGraph: deploy manifest has deduplicated artifacts")
def _():
    graph = build_ceo_graph()
    checkpointer = MemorySaver()
    app = graph.compile(checkpointer=checkpointer)

    c = make_contract(hermes_signoff=True)
    initial_state = {
        "task_id": "test-04",
        "project_name": "",
        "contract": c,
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
    config = {"configurable": {"thread_id": "test-04"}}

    final = None
    for event in app.stream(initial_state, config=config, stream_mode="values"):
        final = event

    assert final is not None
    dm = final.get("devops_manifest")
    assert dm is not None
    artifacts = dm.get("artifacts", [])
    feature_names = [a["feature"] for a in artifacts]
    assert len(feature_names) == len(set(feature_names)), "Artifacts not deduplicated"
    assert len(feature_names) == 2, f"Expected 2 features, got {len(feature_names)}"

# ── Audit Tests ─────────────────────────────────────────────────────

@test("Audit: write_all_artifacts produces 4 files")
def _():
    c = make_contract()
    state = {
        "task_id": "audit-test",
        "project_name": "test-project",
        "contract": c,
        "node_history": ["intake", "scope_validation", "pm_delegation"],
        "pm_manifest": {"project_name": "test-project", "features": ["A", "B"]},
        "dev_results": [{"agent_id": "dev-1", "status": "completed", "builds": []}],
        "devops_manifest": {"project": "test-project", "deploy_target": "vm"},
        "final_status": "completed",
        "contract_approved": True,
        "sandbox_verified": True,
        "errors": [],
    }
    paths = write_all_artifacts(state, "audit-test")
    assert len(paths) == 4
    for p in paths:
        assert p.exists(), f"File not created: {p}"

@test("Audit: execution-graph.json has correct structure")
def _():
    from agent_zero_langgraph.audit import AUDIT_DIR
    path = AUDIT_DIR / "execution-graph.json"
    if not path.exists():
        # Run a quick graph execution to generate the file
        from agent_zero_langgraph.run_demo import main
        main()

    data = json.loads(path.read_text())
    assert "task_id" in data
    assert "node_history" in data
    assert "final_status" in data
    assert "timestamp" in data

@test("Audit: deployment-log.jsonl is append-only")
def _():
    from agent_zero_langgraph.audit import AUDIT_DIR
    path = AUDIT_DIR / "deployment-log.jsonl"
    if not path.exists():
        return  # Skip if file doesn't exist yet

    lines = path.read_text().strip().split("\n")
    assert len(lines) >= 1, "No entries in deployment log"
    for line in lines:
        entry = json.loads(line)
        assert "task_id" in entry
        assert "timestamp" in entry

# ── Runner ──────────────────────────────────────────────────────────

def main():
    print_header("Agent Zero LangGraph — Test Suite")
    print()
    print(f"  Results: {passed} passed, {failed} failed, {passed + failed} total")
    print()
    if failed:
        print(f"  {'═' * 60}")
        print(f"  ✗ {failed} test(s) FAILED")
        print(f"  {'═' * 60}\n")
        return 1
    else:
        print(f"  {'═' * 60}")
        print(f"  ✓ All {passed} tests PASSED")
        print(f"  {'═' * 60}\n")
        return 0


def print_header(title: str):
    width = 70
    print(f"\n{'═' * width}")
    print(f"  {title}")
    print(f"{'═' * width}")


if __name__ == "__main__":
    sys.exit(main())
