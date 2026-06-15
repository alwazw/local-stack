"""
Hindsight Vector Memory — cross-project context retention for Hermes.
Configures and manages the vector memory backend for long-term project knowledge.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class ProjectMemory:
    """
    Manages project-level memory for cross-project context retention.
    Uses JSON files as a lightweight vector store (upgradeable to SQLite/Qdrant).
    """

    def __init__(self, memory_dir: str | None = None):
        self.memory_dir = Path(memory_dir or os.environ.get("MEMORY_DIR", "/app/data/memory"))
        self.memory_dir.mkdir(parents=True, exist_ok=True)

    def store_project_context(self, project: str, context: dict[str, Any]) -> Path:
        """Store a project's execution context for future reference."""
        project_file = self.memory_dir / f"{project}.json"

        # Load existing memory or create new
        if project_file.exists():
            data = json.loads(project_file.read_text())
        else:
            data = {"project": project, "executions": [], "knowledge": []}

        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "context": context,
        }
        data["executions"].append(entry)

        # Keep last 100 executions per project
        data["executions"] = data["executions"][-100:]

        project_file.write_text(json.dumps(data, indent=2))
        return project_file

    def store_knowledge(self, project: str, key: str, value: Any) -> Path:
        """Store a persistent knowledge entry for a project."""
        project_file = self.memory_dir / f"{project}.json"

        if project_file.exists():
            data = json.loads(project_file.read_text())
        else:
            data = {"project": project, "executions": [], "knowledge": []}

        # Upsert knowledge entry
        existing = [k for k in data["knowledge"] if k["key"] == key]
        if existing:
            existing[0]["value"] = value
            existing[0]["updated_at"] = datetime.now(timezone.utc).isoformat()
        else:
            data["knowledge"].append({
                "key": key,
                "value": value,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            })

        project_file.write_text(json.dumps(data, indent=2))
        return project_file

    def get_project_context(self, project: str) -> dict[str, Any] | None:
        """Retrieve the full context for a project."""
        project_file = self.memory_dir / f"{project}.json"
        if not project_file.exists():
            return None
        return json.loads(project_file.read_text())

    def get_recent_executions(self, project: str, limit: int = 10) -> list[dict[str, Any]]:
        """Get recent execution contexts for a project."""
        data = self.get_project_context(project)
        if not data:
            return []
        return data.get("executions", [])[-limit:]

    def get_knowledge(self, project: str, key: str | None = None) -> list[dict[str, Any]]:
        """Get knowledge entries for a project, optionally filtered by key."""
        data = self.get_project_context(project)
        if not data:
            return []
        knowledge = data.get("knowledge", [])
        if key:
            return [k for k in knowledge if k["key"] == key]
        return knowledge

    def list_projects(self) -> list[str]:
        """List all projects with stored memory."""
        return [
            f.stem for f in self.memory_dir.glob("*.json")
        ]

    def search_across_projects(self, query: str) -> list[dict[str, Any]]:
        """Simple keyword search across all project knowledge entries."""
        results = []
        query_lower = query.lower()

        for project in self.list_projects():
            data = self.get_project_context(project)
            if not data:
                continue

            for k in data.get("knowledge", []):
                if query_lower in json.dumps(k).lower():
                    results.append({"project": project, **k})

            for e in data.get("executions", [])[-10:]:
                if query_lower in json.dumps(e.get("context", {})).lower():
                    results.append({
                        "project": project,
                        "type": "execution",
                        "timestamp": e.get("timestamp"),
                        "context": e.get("context"),
                    })

        return results

    def generate_context_prompt(self, project: str) -> str:
        """Generate a context prompt from project memory for LLM injection."""
        data = self.get_project_context(project)
        if not data:
            return f"No prior context available for project '{project}'."

        lines = [f"Project: {project}"]

        # Recent knowledge
        knowledge = data.get("knowledge", [])
        if knowledge:
            lines.append("\nKnown facts:")
            for k in knowledge[-10:]:
                lines.append(f"  - {k['key']}: {k['value']}")

        # Recent executions
        executions = data.get("executions", [])[-5:]
        if executions:
            lines.append(f"\nRecent executions: {len(executions)}")
            for e in executions[-3:]:
                ctx = e.get("context", {})
                lines.append(f"  - {e.get('timestamp', '?')}: status={ctx.get('final_status', '?')}")

        return "\n".join(lines)


def get_project_memory() -> ProjectMemory:
    """Factory: create a ProjectMemory instance from environment configuration."""
    return ProjectMemory()
