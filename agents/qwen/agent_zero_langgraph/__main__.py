#!/usr/bin/env python3
"""Entry point for running the LangGraph demo."""
import sys
import os

# Add parent to path so the module can be imported
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from agent_zero_langgraph.run_demo import main

if __name__ == "__main__":
    sys.exit(main())

