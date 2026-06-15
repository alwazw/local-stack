#!/usr/bin/env python3
"""
Agent Zero API Server — uvicorn runner for the FastAPI delegation API.
Run as a background process alongside the main Agent Zero container.
"""
from __future__ import annotations

import os
import sys

# Ensure the module is importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    import uvicorn
    from agent_zero_langgraph.api import app

    host = os.environ.get("API_HOST", "0.0.0.0")
    port = int(os.environ.get("API_PORT", "8080"))

    print(f"Starting Agent Zero API server on {host}:{port}")
    uvicorn.run(app, host=host, port=port, log_level="info")


if __name__ == "__main__":
    main()
