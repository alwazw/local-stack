#!/bin/sh
# Start the Agent Zero LangGraph API server in the background
python3 -m agent_zero_langgraph.api_server &
API_PID=$!
echo "API server started (PID $API_PID)"

# Execute the original CMD
exec "$@"
