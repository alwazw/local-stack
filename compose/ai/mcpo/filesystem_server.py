#!/usr/bin/env python3
"""
Filesystem MCP Server — stdio-based MCP server for file operations.
Restricted to /workspace directory (mounted from host projects/).
Uses the mcp Python SDK already available in the MCPO container.
"""
import json
import os
import shutil
import stat
import time
from datetime import datetime, timezone
from pathlib import Path

from mcp.server.fastmcp import FastMCP

WORKSPACE = os.environ.get("FILESYSTEM_WORKSPACE", "/workspace")

mcp = FastMCP("filesystem")


def _safe_path(path: str) -> Path:
    """Resolve path and ensure it's within the workspace boundary."""
    resolved = Path(WORKSPACE, path).resolve()
    workspace_resolved = Path(WORKSPACE).resolve()
    if not str(resolved).startswith(str(workspace_resolved)):
        raise PermissionError(f"Path '{path}' is outside workspace '{WORKSPACE}'")
    return resolved


@mcp.tool()
def read_file(path: str) -> str:
    """Read the contents of a file.

    Args:
        path: Relative path within the workspace (e.g., 'my-project/README.md')
    """
    resolved = _safe_path(path)
    if not resolved.exists():
        return f"Error: File not found: {path}"
    if not resolved.is_file():
        return f"Error: Not a file: {path}"
    try:
        return resolved.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return f"Error: Binary file, cannot read as text: {path}"


@mcp.tool()
def write_file(path: str, content: str) -> str:
    """Write content to a file, creating parent directories if needed.

    Args:
        path: Relative path within the workspace (e.g., 'my-project/src/main.py')
        content: The text content to write
    """
    resolved = _safe_path(path)
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(content, encoding="utf-8")
    return f"Written {len(content)} bytes to {path}"


@mcp.tool()
def list_directory(path: str = "") -> str:
    """List files and directories at the given path.

    Args:
        path: Relative path within the workspace (empty string for root)
    """
    resolved = _safe_path(path)
    if not resolved.exists():
        return f"Error: Directory not found: {path}"
    if not resolved.is_dir():
        return f"Error: Not a directory: {path}"

    entries = []
    for item in sorted(resolved.iterdir()):
        prefix = "[DIR] " if item.is_dir() else "      "
        size = item.stat().st_size if item.is_file() else 0
        entries.append(f"{prefix}{item.name}" + (f" ({size} bytes)" if item.is_file() else ""))

    return "\n".join(entries) if entries else "(empty directory)"


@mcp.tool()
def search_files(pattern: str, path: str = "") -> str:
    """Search for files matching a glob pattern.

    Args:
        pattern: Glob pattern to match (e.g., '*.py', '**/*.json')
        path: Relative directory to search within (empty for workspace root)
    """
    resolved = _safe_path(path)
    if not resolved.exists():
        return f"Error: Directory not found: {path}"
    matches = sorted(str(p.relative_to(resolved)) for p in resolved.glob(pattern))
    if not matches:
        return f"No files matching '{pattern}' in {path or 'workspace root'}"
    return "\n".join(matches)


@mcp.tool()
def move_file(source: str, destination: str) -> str:
    """Move or rename a file or directory.

    Args:
        source: Relative source path within the workspace
        destination: Relative destination path within the workspace
    """
    src = _safe_path(source)
    dst = _safe_path(destination)
    if not src.exists():
        return f"Error: Source not found: {source}"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dst))
    return f"Moved {source} → {destination}"


@mcp.tool()
def get_file_info(path: str) -> str:
    """Get metadata about a file or directory (size, permissions, timestamps).

    Args:
        path: Relative path within the workspace
    """
    resolved = _safe_path(path)
    if not resolved.exists():
        return f"Error: Path not found: {path}"

    st = resolved.stat()
    info = {
        "path": path,
        "type": "directory" if resolved.is_dir() else "file",
        "size": st.st_size,
        "permissions": stat.filemode(st.st_mode),
        "modified": datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat(),
        "created": datetime.fromtimestamp(st.st_ctime, tz=timezone.utc).isoformat(),
    }
    return json.dumps(info, indent=2)


if __name__ == "__main__":
    mcp.run()
