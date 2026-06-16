"""
Hindsight Vector Memory — cross-project context retention for Hermes.
Configures and manages the vector memory backend for long-term project knowledge.
Primary backend: Qdrant via REST API. Fallback: JSON file storage.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import httpx
    HAS_HTTPX = True
except ImportError:
    HAS_HTTPX = False

logger = logging.getLogger(__name__)

# Qdrant configuration
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant:6333")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "project_memory")
# Dummy vector dimension — we use payload-based search, not semantic similarity
VECTOR_DIM = 4

# Simple hash-to-float for deterministic dummy vectors
def _hash_vector(key: str, dim: int = VECTOR_DIM) -> list[float]:
    """Generate a deterministic dummy vector from a string key."""
    h = hashlib.md5(key.encode()).hexdigest()
    return [int(h[i:i+8], 16) / 0xFFFFFFFF for i in range(0, dim * 8, 8)]


class _QdrantClient:
    """Thin wrapper around Qdrant REST API. No qdrant-client library required."""

    def __init__(self, base_url: str, collection: str):
        self.base_url = base_url.rstrip("/")
        self.collection = collection
        self._client: httpx.Client | None = None

    def _get_client(self) -> httpx.Client | None:
        if not HAS_HTTPX:
            return None
        if self._client is None:
            self._client = httpx.Client(base_url=self.base_url, timeout=5.0)
        return self._client

    def _request(self, method: str, path: str, **kwargs) -> dict | None:
        client = self._get_client()
        if client is None:
            return None
        try:
            resp = client.request(method, path, **kwargs)
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            logger.debug("Qdrant request failed: %s", e)
            return None

    def ensure_collection(self) -> bool:
        """Create the collection if it does not exist."""
        # Check if collection exists
        result = self._request("GET", f"/collections/{self.collection}")
        if result and result.get("result", {}).get("status") == "green":
            return True

        # Create collection
        body = {
            "vectors": {"size": VECTOR_DIM, "distance": "Cosine"},
        }
        result = self._request("PUT", f"/collections/{self.collection}", json=body)
        return result is not None and result.get("result", False) is True

    def upsert(self, point_id: str, vector: list[float], payload: dict[str, Any]) -> bool:
        """Upsert a single point."""
        body = {
            "points": [
                {
                    "id": point_id,
                    "vector": vector,
                    "payload": payload,
                }
            ]
        }
        result = self._request("PUT", f"/collections/{self.collection}/points", json=body)
        return result is not None and result.get("result", {}).get("status") == "completed"

    def retrieve(self, point_id: str) -> dict | None:
        """Retrieve a single point by ID."""
        body = {"ids": [point_id], "with_payload": True, "with_vector": False}
        result = self._request("POST", f"/collections/{self.collection}/points/scroll", json=body)
        if result and result.get("result", {}).get("points"):
            return result["result"]["points"][0]
        return None

    def scroll_by_project(self, project: str, limit: int = 100) -> list[dict]:
        """Scroll points matching project_name in payload."""
        body = {
            "limit": limit,
            "with_payload": True,
            "filter": {
                "must": [
                    {"key": "project_name", "match": {"value": project}}
                ]
            },
        }
        result = self._request("POST", f"/collections/{self.collection}/points/scroll", json=body)
        if result:
            return result.get("result", {}).get("points", [])
        return []

    def scroll_all(self, limit: int = 1000) -> list[dict]:
        """Scroll all points (for listing projects and searching)."""
        body = {"limit": limit, "with_payload": True}
        result = self._request("POST", f"/collections/{self.collection}/points/scroll", json=body)
        if result:
            return result.get("result", {}).get("points", [])
        return []

    def delete(self, point_id: str) -> bool:
        """Delete a single point."""
        body = {"points": [point_id]}
        result = self._request("POST", f"/collections/{self.collection}/points/delete", json=body)
        return result is not None

    def count(self) -> int:
        """Count points in collection."""
        result = self._request("GET", f"/collections/{self.collection}/points/count")
        if result:
            return result.get("result", {}).get("count", 0)
        return 0


class _JsonBackend:
    """Fallback JSON file-based storage matching original behavior."""

    def __init__(self, memory_dir: Path):
        self.memory_dir = memory_dir
        self.memory_dir.mkdir(parents=True, exist_ok=True)

    def store_project_context(self, project: str, context: dict[str, Any]) -> Path:
        project_file = self.memory_dir / f"{project}.json"
        if project_file.exists():
            data = json.loads(project_file.read_text())
        else:
            data = {"project": project, "executions": [], "knowledge": []}

        entry = {"timestamp": datetime.now(timezone.utc).isoformat(), "context": context}
        data["executions"].append(entry)
        data["executions"] = data["executions"][-100:]

        project_file.write_text(json.dumps(data, indent=2))
        return project_file

    def store_knowledge(self, project: str, key: str, value: Any) -> Path:
        project_file = self.memory_dir / f"{project}.json"
        if project_file.exists():
            data = json.loads(project_file.read_text())
        else:
            data = {"project": project, "executions": [], "knowledge": []}

        existing = [k for k in data["knowledge"] if k["key"] == key]
        if existing:
            existing[0]["value"] = value
            existing[0]["updated_at"] = datetime.now(timezone.utc).isoformat()
        else:
            data["knowledge"].append({
                "key": key, "value": value,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            })

        project_file.write_text(json.dumps(data, indent=2))
        return project_file

    def get_project_context(self, project: str) -> dict[str, Any] | None:
        project_file = self.memory_dir / f"{project}.json"
        if not project_file.exists():
            return None
        return json.loads(project_file.read_text())

    def get_recent_executions(self, project: str, limit: int = 10) -> list[dict[str, Any]]:
        data = self.get_project_context(project)
        if not data:
            return []
        return data.get("executions", [])[-limit:]

    def get_knowledge(self, project: str, key: str | None = None) -> list[dict[str, Any]]:
        data = self.get_project_context(project)
        if not data:
            return []
        knowledge = data.get("knowledge", [])
        if key:
            return [k for k in knowledge if k["key"] == key]
        return knowledge

    def list_projects(self) -> list[str]:
        return [f.stem for f in self.memory_dir.glob("*.json")]

    def search_across_projects(self, query: str) -> list[dict[str, Any]]:
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
                        "project": project, "type": "execution",
                        "timestamp": e.get("timestamp"), "context": e.get("context"),
                    })
        return results


class ProjectMemory:
    """
    Manages project-level memory for cross-project context retention.
    Primary: Qdrant via REST API. Fallback: JSON files.
    """

    def __init__(self, memory_dir: str | None = None):
        self.memory_dir = Path(memory_dir or os.environ.get("MEMORY_DIR", "/app/data/memory"))
        self.json_backend = _JsonBackend(self.memory_dir)

        # Initialize Qdrant backend
        self._qdrant: _QdrantClient | None = None
        self._qdrant_available = False
        self._init_qdrant()

    def _init_qdrant(self):
        """Attempt to connect to Qdrant; fall back silently."""
        if not HAS_HTTPX:
            logger.info("httpx not available, using JSON fallback")
            return
        try:
            self._qdrant = _QdrantClient(QDRANT_URL, QDRANT_COLLECTION)
            if self._qdrant.ensure_collection():
                self._qdrant_available = True
                logger.info("Qdrant memory backend ready at %s", QDRANT_URL)
            else:
                logger.warning("Could not create Qdrant collection, using JSON fallback")
                self._qdrant = None
        except Exception as e:
            logger.warning("Qdrant unavailable (%s), using JSON fallback", e)
            self._qdrant = None

    def _qdrant_point_id(self, project: str, entry_type: str, key_or_ts: str) -> str:
        """Generate a unique point ID for Qdrant."""
        return f"{project}__{entry_type}__{key_or_ts}"

    # ------------------------------------------------------------------
    # Public API — delegates to Qdrant or JSON
    # ------------------------------------------------------------------

    def store_project_context(self, project: str, context: dict[str, Any]) -> dict[str, Any]:
        """Store a project's execution context for future reference."""
        ts = datetime.now(timezone.utc).isoformat()

        if self._qdrant_available and self._qdrant:
            payload = {
                "project_name": project,
                "entry_type": "execution",
                "context": context,
                "timestamp": ts,
            }
            point_id = self._qdrant_point_id(project, "execution", ts)
            vector = _hash_vector(point_id)
            self._qdrant.upsert(point_id, vector, payload)
            # Also persist to JSON for compatibility
            self.json_backend.store_project_context(project, context)
            return {"status": "ok", "project": project, "backend": "qdrant+json", "timestamp": ts}

        result = self.json_backend.store_project_context(project, context)
        return {"status": "ok", "project": project, "backend": "json", "file": str(result)}

    def store_knowledge(self, project: str, key: str, value: Any) -> dict[str, Any]:
        """Store a persistent knowledge entry for a project."""
        ts = datetime.now(timezone.utc).isoformat()

        if self._qdrant_available and self._qdrant:
            payload = {
                "project_name": project,
                "entry_type": "knowledge",
                "knowledge_key": key,
                "value": value,
                "timestamp": ts,
            }
            point_id = self._qdrant_point_id(project, "knowledge", key)
            vector = _hash_vector(point_id)
            self._qdrant.upsert(point_id, vector, payload)
            # Also persist to JSON for compatibility
            self.json_backend.store_knowledge(project, key, value)
            return {"status": "ok", "project": project, "key": key, "backend": "qdrant+json", "timestamp": ts}

        result = self.json_backend.store_knowledge(project, key, value)
        return {"status": "ok", "project": project, "key": key, "backend": "json", "file": str(result)}

    def get_project_context(self, project: str) -> dict[str, Any] | None:
        """Retrieve the full context for a project."""
        if self._qdrant_available and self._qdrant:
            points = self._qdrant.scroll_by_project(project)
            if not points:
                # Fallback to JSON
                return self.json_backend.get_project_context(project)

            executions = []
            knowledge = []
            for p in points:
                pl = p.get("payload", {})
                if pl.get("entry_type") == "execution":
                    executions.append({
                        "timestamp": pl.get("timestamp"),
                        "context": pl.get("context", {}),
                    })
                elif pl.get("entry_type") == "knowledge":
                    knowledge.append({
                        "key": pl.get("knowledge_key"),
                        "value": pl.get("value"),
                        "created_at": pl.get("timestamp"),
                        "updated_at": pl.get("timestamp"),
                    })

            executions.sort(key=lambda x: x.get("timestamp", ""))
            return {"project": project, "executions": executions, "knowledge": knowledge}

        return self.json_backend.get_project_context(project)

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
        if self._qdrant_available and self._qdrant:
            points = self._qdrant.scroll_all()
            projects = set()
            for p in points:
                pl = p.get("payload", {})
                if "project_name" in pl:
                    projects.add(pl["project_name"])
            # Merge with JSON projects
            projects.update(self.json_backend.list_projects())
            return sorted(projects)

        return self.json_backend.list_projects()

    def search_across_projects(self, query: str) -> list[dict[str, Any]]:
        """Simple keyword search across all project knowledge entries."""
        # Search is done in-memory after retrieving all data
        # (Qdrant payload filtering is exact-match; keyword search needs text scan)
        results = []
        query_lower = query.lower()

        # Search Qdrant data
        if self._qdrant_available and self._qdrant:
            points = self._qdrant.scroll_all()
            for p in points:
                pl = p.get("payload", {})
                project = pl.get("project_name", "unknown")
                if pl.get("entry_type") == "knowledge":
                    entry = {
                        "key": pl.get("knowledge_key"),
                        "value": pl.get("value"),
                    }
                    if query_lower in json.dumps(entry).lower():
                        results.append({"project": project, **entry})
                elif pl.get("entry_type") == "execution":
                    ctx = pl.get("context", {})
                    if query_lower in json.dumps(ctx).lower():
                        results.append({
                            "project": project, "type": "execution",
                            "timestamp": pl.get("timestamp"), "context": ctx,
                        })
        else:
            # Pure JSON fallback
            return self.json_backend.search_across_projects(query)

        # Deduplicate by checking if we already have this entry
        seen = set()
        deduped = []
        for r in results:
            key = json.dumps(r, sort_keys=True, default=str)
            if key not in seen:
                seen.add(key)
                deduped.append(r)

        return deduped

    def generate_context_prompt(self, project: str) -> str:
        """Generate a context prompt from project memory for LLM injection."""
        data = self.get_project_context(project)
        if not data:
            return f"No prior context available for project '{project}'."

        lines = [f"Project: {project}"]

        knowledge = data.get("knowledge", [])
        if knowledge:
            lines.append("\nKnown facts:")
            for k in knowledge[-10:]:
                lines.append(f"  - {k['key']}: {k['value']}")

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
