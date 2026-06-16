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
        """Call a specific MCP tool on a specific server.
        
        MCPO exposes each tool as a direct POST endpoint:
          POST /{server}/{tool_name}
        NOT as /{server}/tools/call
        """
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.post(
                    f"{self.base_url}/{server}/{tool_name}",
                    json=arguments,
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

    def git_status(self, repo_path: str = ".") -> dict[str, Any]:
        """Get git status via MCP git server."""
        return self.call_tool("git", "git_status", {"repo_path": repo_path})

    def git_log(self, repo_path: str = ".", n: int = 10) -> dict[str, Any]:
        """Get git log via MCP git server."""
        return self.call_tool("git", "git_log", {"repo_path": repo_path, "n": n})

    def git_diff(self, repo_path: str = ".", staged: bool = False) -> dict[str, Any]:
        """Get git diff via MCP git server."""
        return self.call_tool("git", "git_diff", {"repo_path": repo_path, "staged": staged})

    def git_commit(self, repo_path: str = ".", message: str = "") -> dict[str, Any]:
        """Create a git commit via MCP git server."""
        return self.call_tool("git", "git_commit", {"repo_path": repo_path, "message": message})

    def git_add(self, repo_path: str = ".", files: str = ".") -> dict[str, Any]:
        """Stage files via MCP git server."""
        return self.call_tool("git", "git_add", {"repo_path": repo_path, "files": files})

    def git_branch(self, repo_path: str = ".") -> dict[str, Any]:
        """List branches via MCP git server."""
        return self.call_tool("git", "git_branch", {"repo_path": repo_path})

    def git_checkout(self, repo_path: str = ".", branch: str = "") -> dict[str, Any]:
        """Checkout branch via MCP git server."""
        return self.call_tool("git", "git_checkout", {"repo_path": repo_path, "branch": branch})

    def git_create_branch(self, repo_path: str = ".", branch: str = "", from_branch: str = "main") -> dict[str, Any]:
        """Create branch via MCP git server."""
        return self.call_tool("git", "git_create_branch", {"repo_path": repo_path, "branch": branch, "from_branch": from_branch})

    def git_push(self, repo_path: str = ".", remote: str = "origin", branch: str = "") -> dict[str, Any]:
        """Push to remote via MCP git server."""
        return self.call_tool("git", "git_push", {"repo_path": repo_path, "remote": remote, "branch": branch})

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
