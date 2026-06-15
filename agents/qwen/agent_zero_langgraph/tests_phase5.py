#!/usr/bin/env python3
"""
Phase 5 Integration Tests — LLM, MCP, SSH, Memory, API
"""
import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))


class TestLLMClient:
    """Test LLM client integration with LiteLLM."""

    def test_llm_client_initialization(self):
        from agent_zero_langgraph.llm_client import LLMClient
        
        client = LLMClient()
        assert client is not None
        assert client.base_url is not None

    def test_llm_client_availability_check(self):
        from agent_zero_langgraph.llm_client import LLMClient
        
        client = LLMClient()
        # Should not raise an exception
        try:
            result = client.is_available()
            assert isinstance(result, bool)
        except Exception:
            pytest.skip("LiteLLM not available")

    def test_llm_client_code_generation_simulation(self):
        from agent_zero_langgraph.llm_client import LLMClient
        
        client = LLMClient()
        
        # Test with a mock endpoint that will fail gracefully
        client.base_url = "http://localhost:9999"  # Non-existent
        result = client.generate_code("test feature", "test context")
        
        assert result["status"] == "unavailable"
        assert "error" in result


class TestMCPClient:
    """Test MCP client integration."""

    def test_mcp_client_initialization(self):
        from agent_zero_langgraph.mcp_client import MCPClient
        
        client = MCPClient()
        assert client is not None
        assert client.base_url is not None

    def test_mcp_client_availability_check(self):
        from agent_zero_langgraph.mcp_client import MCPClient
        
        client = MCPClient()
        try:
            result = client.is_available()
            assert isinstance(result, bool)
        except Exception:
            pytest.skip("MCPO not available")

    def test_mcp_client_tool_list(self):
        from agent_zero_langgraph.mcp_client import MCPClient
        
        client = MCPClient()
        try:
            result = client.list_tools()
            assert "status" in result
        except Exception:
            pytest.skip("MCPO not available")


class TestSSHDeployer:
    """Test SSH deployment module."""

    def test_ssh_deployer_initialization(self):
        from agent_zero_langgraph.ssh_deploy import SSHDeployer
        
        deployer = SSHDeployer()
        assert deployer is not None

    def test_ssh_deployer_key_check(self):
        from agent_zero_langgraph.ssh_deploy import SSHDeployer
        
        deployer = SSHDeployer()
        # Should return bool without exception
        result = deployer.is_available()
        assert isinstance(result, bool)

    def test_ssh_deployer_simulate_deploy(self):
        from agent_zero_langgraph.ssh_deploy import SSHDeployer
        
        deployer = SSHDeployer()
        
        artifacts = [
            {"feature": "Feature A", "build_status": "passed"},
            {"feature": "Feature B", "build_status": "passed"},
        ]
        
        result = deployer.simulate_deploy("test-host", artifacts)
        
        assert result.success is True
        assert result.health_ok is True
        assert result.rolled_back is False
        assert result.target == "test-host"
        assert "Feature A" in result.output
        assert "Feature B" in result.output

    def test_ssh_deployer_with_custom_key_path(self):
        from agent_zero_langgraph.ssh_deploy import SSHDeployer
        
        # Test with non-existent key
        deployer = SSHDeployer(ssh_key_path="/tmp/nonexistent_key")
        assert deployer.is_available() is False


class TestProjectMemory:
    """Test project memory module."""

    def test_memory_initialization(self):
        from agent_zero_langgraph.memory import ProjectMemory
        
        with tempfile.TemporaryDirectory() as tmpdir:
            memory = ProjectMemory(memory_dir=tmpdir)
            assert memory is not None
            assert Path(tmpdir).exists()

    def test_memory_store_and_retrieve(self):
        from agent_zero_langgraph.memory import ProjectMemory
        
        with tempfile.TemporaryDirectory() as tmpdir:
            memory = ProjectMemory(memory_dir=tmpdir)
            
            context = {
                "task_id": "test-001",
                "final_status": "completed",
                "features": ["Feature A", "Feature B"],
            }
            
            memory.store_project_context("test-project", context)
            
            retrieved = memory.get_project_context("test-project")
            assert retrieved is not None
            assert "executions" in retrieved
            assert len(retrieved["executions"]) == 1
            assert retrieved["executions"][0]["context"]["task_id"] == "test-001"

    def test_memory_store_knowledge(self):
        from agent_zero_langgraph.memory import ProjectMemory
        
        with tempfile.TemporaryDirectory() as tmpdir:
            memory = ProjectMemory(memory_dir=tmpdir)
            
            memory.store_knowledge("test-project", "tech_stack", "Node.js + React")
            
            knowledge = memory.get_knowledge("test-project", "tech_stack")
            assert len(knowledge) == 1
            assert knowledge[0]["value"] == "Node.js + React"

    def test_memory_list_projects(self):
        from agent_zero_langgraph.memory import ProjectMemory
        
        with tempfile.TemporaryDirectory() as tmpdir:
            memory = ProjectMemory(memory_dir=tmpdir)
            
            memory.store_project_context("project-a", {"status": "ok"})
            memory.store_project_context("project-b", {"status": "ok"})
            
            projects = memory.list_projects()
            assert "project-a" in projects
            assert "project-b" in projects

    def test_memory_search(self):
        from agent_zero_langgraph.memory import ProjectMemory
        
        with tempfile.TemporaryDirectory() as tmpdir:
            memory = ProjectMemory(memory_dir=tmpdir)
            
            memory.store_knowledge("project-a", "database", "PostgreSQL")
            memory.store_knowledge("project-b", "database", "MongoDB")
            
            results = memory.search_across_projects("PostgreSQL")
            assert len(results) > 0
            assert any(r["project"] == "project-a" for r in results)


class TestAPIEndpoints:
    """Test FastAPI endpoints."""

    @pytest.fixture
    def client(self):
        from fastapi.testclient import TestClient
        from agent_zero_langgraph.api import app
        
        return TestClient(app)

    def test_health_endpoint(self, client):
        response = client.get("/api/v1/health")
        assert response.status_code == 200
        
        data = response.json()
        assert "status" in data
        assert data["status"] == "ok"
        assert "services" in data
        assert "timestamp" in data

    def test_list_tasks_empty(self, client):
        response = client.get("/api/v1/tasks")
        assert response.status_code == 200
        
        data = response.json()
        assert "tasks" in data
        assert isinstance(data["tasks"], list)

    def test_list_projects_empty(self, client):
        response = client.get("/api/v1/projects")
        assert response.status_code == 200
        
        data = response.json()
        assert "projects" in data
        assert isinstance(data["projects"], list)

    def test_submit_task_with_auto_approve(self, client):
        task_request = {
            "project": "test-project",
            "features": ["Feature A", "Feature B"],
            "boundaries": ["TypeScript only"],
            "exclusions": ["No mobile"],
            "risks": [
                {"severity": "low", "mitigation": "test"}
            ],
            "repos": ["repo1"],
            "infra": ["vm1"],
            "veto_window_hrs": 24,
            "auto_approve": True,
            "simulate": True,
        }
        
        response = client.post("/api/v1/tasks", json=task_request)
        assert response.status_code == 200
        
        data = response.json()
        assert "task_id" in data
        assert data["project"] == "test-project"
        assert data["contract_approved"] is True
        assert data["sandbox_verified"] is True
        assert data["final_status"] == "completed"
        assert data["agent_count"] >= 3  # PM + Dev agents + DevOps

    def test_get_nonexistent_task(self, client):
        response = client.get("/api/v1/tasks/nonexistent")
        assert response.status_code == 404

    def test_approve_nonexistent_task(self, client):
        response = client.post(
            "/api/v1/tasks/nonexistent/approve",
            json={"approved": True, "approver": "board"}
        )
        assert response.status_code == 404


class TestIntegration:
    """Integration tests for the full pipeline with Phase 5 components."""

    def test_full_pipeline_with_memory(self):
        from agent_zero_langgraph.graph import build_ceo_graph
        from agent_zero_langgraph.models import Contract, Scope, Approval, Assets, Risk
        from agent_zero_langgraph.memory import ProjectMemory
        from langgraph.checkpoint.memory import MemorySaver
        from datetime import datetime
        
        with tempfile.TemporaryDirectory() as tmpdir:
            memory = ProjectMemory(memory_dir=tmpdir)
            
            contract = Contract(
                project="integration-test",
                scope=Scope(
                    features=["Feature X"],
                    boundaries=["Test boundary"],
                    exclusions=["No mobile"],
                ),
                risks=[Risk(severity="low", mitigation="test")],
                assets=Assets(repos=["repo1"], infra=["vm1"]),
                approval=Approval(hermes_signoff=True, board_veto_window_hrs=24),
                created_at=datetime.now(),
            )
            
            graph = build_ceo_graph()
            checkpointer = MemorySaver()
            app = graph.compile(checkpointer=checkpointer)
            
            initial_state = {
                "task_id": "int-test-001",
                "project_name": "",
                "contract": contract,
                "current_node": "",
                "node_history": [],
                "pm_manifest": None,
                "dev_results": [],
                "devops_manifest": None,
                "contract_approved": False,
                "sandbox_verified": False,
                "simulate": True,
                "errors": [],
                "final_status": "pending",
                "messages": [],
            }
            
            config = {"configurable": {"thread_id": "int-test-001"}}
            
            final_state = None
            for event in app.stream(initial_state, config=config, stream_mode="values"):
                final_state = event
            
            assert final_state is not None
            assert final_state["final_status"] == "completed"
            
            # Store in memory
            memory.store_project_context("integration-test", {
                "task_id": "int-test-001",
                "final_status": final_state["final_status"],
                "features": ["Feature X"],
            })
            
            # Verify memory
            retrieved = memory.get_project_context("integration-test")
            assert retrieved is not None
            assert len(retrieved["executions"]) == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
