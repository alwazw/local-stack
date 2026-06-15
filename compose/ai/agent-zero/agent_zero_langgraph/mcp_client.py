"""
MCP Client — connects sub-agents to MCP tool servers via MCPO bridge.
MCPO exposes MCP servers as OpenAPI-compatible REST endpoints.
"""
from __future__ import annotations

import os
from typing import Any

import httpx


class MCPClient:
    """Client for MCP tool servers via MCPO bridge."""

    def __init__(
        self,
        base_url: str | None = None,
        timeout: float = 30.0,
    ):
        self.base_url = (base_url or os.environ.get("MCP_BASE_URL", "http://mcpo:8000")).rstrip("/")
        self.timeout = timeout

    def list_tools(self) -> dict[str, Any]:
        """List available MCP tools from the bridge."""
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.get(f"{self.base_url}/tools")
                if response.status_code == 404:
                    # MCPO may expose tools under a different path
                    response = client.get(f"{self.base_url}/")
                return {"status": "ok", "tools": response.json()}
        except Exception as e:
            return {"status": "error", "error": f"{type(e).__name__}: {str(e)[:200]}", "tools": []}

    def call_tool(self, server: str, tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        """Call a specific MCP tool on a specific server."""
        payload = {
            "tool": tool_name,
            "arguments": arguments,
        }

        try:
            with httpx.Client(timeout=self.timeout) as client:
                # MCPO exposes each MCP server at /{server_name}/
                response = client.post(
                    f"{self.base_url}/{server}/tools/call",
                    json=payload,
                )
                response.raise_for_status()
                return {"status": "ok", "result": response.json()}
        except httpx.HTTPStatusError as e:
            return {
                "status": "error",
                "error": f"HTTP {e.response.status_code}: {e.response.text[:200]}",
                "result": None,
            }
        except (httpx.ConnectError, httpx.TimeoutException) as e:
            return {
                "status": "unavailable",
                "error": f"MCP service unavailable: {type(e).__name__}",
                "result": None,
            }
        except Exception as e:
            return {
                "status": "error",
                "error": f"{type(e).__name__}: {str(e)[:200]}",
                "result": None,
            }

    def filesystem_read(self, path: str) -> dict[str, Any]:
        """Read a file via MCP filesystem server."""
        return self.call_tool("filesystem", "read_file", {"path": path})

    def filesystem_write(self, path: str, content: str) -> dict[str, Any]:
        """Write a file via MCP filesystem server."""
        return self.call_tool("filesystem", "write_file", {"path": path, "content": content})

    def filesystem_list(self, path: str) -> dict[str, Any]:
        """List directory via MCP filesystem server."""
        return self.call_tool("filesystem", "list_directory", {"path": path})

    def git_status(self, repo_path: str) -> dict[str, Any]:
        """Get git status via MCP git server."""
        return self.call_tool("git", "git_status", {"repo_path": repo_path})

    def git_commit(self, repo_path: str, message: str) -> dict[str, Any]:
        """Create a git commit via MCP git server."""
        return self.call_tool("git", "git_commit", {"repo_path": repo_path, "message": message})

    def is_available(self) -> bool:
        """Check if MCPO bridge is reachable."""
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.get(f"{self.base_url}/")
                return response.status_code in (200, 404)
        except Exception:
            return False


def get_mcp_client() -> MCPClient:
    """Factory: create an MCP client from environment configuration."""
    return MCPClient()
