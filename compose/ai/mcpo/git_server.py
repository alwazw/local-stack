"""
Git MCP Server — provides git operations via MCPO bridge.
All paths are resolved relative to GIT_WORKSPACE env var.
"""
import os
import subprocess
from pathlib import Path
from mcp.server.fastmcp import FastMCP

# Configuration
WORKSPACE = Path(os.environ.get("GIT_WORKSPACE", "/workspace"))

# Fix dubious ownership: container runs as root but workspace is owned by different UID
subprocess.run(["git", "config", "--global", "--add", "safe.directory", str(WORKSPACE)], check=False)

# Set default git identity for commits
subprocess.run(["git", "config", "--global", "user.email", "agent-zero@wazzan.us"], check=False)
subprocess.run(["git", "config", "--global", "user.name", "Agent Zero"], check=False)

# Server
mcp = FastMCP("git", instructions="Git operations for project repositories.")


def _safe_path(path: str) -> Path:
    """Resolve and validate a path within the workspace."""
    resolved = (WORKSPACE / path).resolve()
    if not str(resolved).startswith(str(WORKSPACE.resolve())):
        raise ValueError(f"Path traversal detected: {path}")
    if not (resolved / ".git").exists():
        raise ValueError(f"Not a git repository: {resolved}")
    return resolved


def _git(cwd: Path, *args: str) -> str:
    """Run a git command and return stdout."""
    result = subprocess.run(
        ["git"] + list(args),
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


@mcp.tool()
def git_status(repo_path: str = ".") -> str:
    """Get the git status of a repository."""
    repo = _safe_path(repo_path)
    return _git(repo, "status", "--short")


@mcp.tool()
def git_log(repo_path: str = ".", n: int = 10) -> str:
    """Get the git log (last N commits)."""
    repo = _safe_path(repo_path)
    return _git(repo, "log", f"-{n}", "--oneline")


@mcp.tool()
def git_diff(repo_path: str = ".", staged: bool = False) -> str:
    """Get the git diff (optionally staged only)."""
    repo = _safe_path(repo_path)
    args = ["diff"]
    if staged:
        args.append("--staged")
    return _git(repo, *args) or "(no changes)"


@mcp.tool()
def git_commit(repo_path: str = ".", message: str = "") -> str:
    """Create a git commit with the given message."""
    if not message:
        raise ValueError("Commit message is required")
    repo = _safe_path(repo_path)
    return _git(repo, "commit", "-m", message)


@mcp.tool()
def git_add(repo_path: str = ".", files: str = ".") -> str:
    """Stage files for commit."""
    repo = _safe_path(repo_path)
    return _git(repo, "add", files) or "Files staged"


@mcp.tool()
def git_branch(repo_path: str = ".") -> str:
    """List git branches."""
    repo = _safe_path(repo_path)
    return _git(repo, "branch", "-a")


@mcp.tool()
def git_checkout(repo_path: str = ".", branch: str = "") -> str:
    """Checkout a branch."""
    if not branch:
        raise ValueError("Branch name is required")
    repo = _safe_path(repo_path)
    return _git(repo, "checkout", branch)


@mcp.tool()
def git_create_branch(repo_path: str = ".", branch: str = "", from_branch: str = "main") -> str:
    """Create and checkout a new branch."""
    if not branch:
        raise ValueError("Branch name is required")
    repo = _safe_path(repo_path)
    _git(repo, "checkout", "-b", branch, from_branch)
    return f"Created and checked out branch '{branch}'"


@mcp.tool()
def git_push(repo_path: str = ".", remote: str = "origin", branch: str = "") -> str:
    """Push to remote."""
    repo = _safe_path(repo_path)
    if not branch:
        branch = _git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    return _git(repo, "push", remote, branch) or "Pushed successfully"


if __name__ == "__main__":
    mcp.run()
