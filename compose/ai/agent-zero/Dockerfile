FROM frdel/agent-zero:latest

# Install pip and system dependencies
RUN python3 -m ensurepip --upgrade || apt-get update && apt-get install -y python3-pip openssh-client

# Install Python dependencies
RUN python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
    typing_extensions>=4.15.0 && \
    python3 -m pip install --no-cache-dir --break-system-packages \
    langgraph>=0.2.0 \
    langchain-core>=0.3.0 \
    pydantic>=2.0.0 \
    httpx>=0.27.0 \
    fastapi>=0.115.0 \
    uvicorn[standard]>=0.32.0 \
    paramiko>=3.5.0

# Copy Agent Zero LangGraph orchestration module
COPY agent_zero_langgraph/ /app/agent_zero_langgraph/

# Copy and configure entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create projects and audit directories for workspace isolation
RUN mkdir -p /app/projects /app/audit

WORKDIR /app

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/exe/initialize.sh", "${BRANCH}"]
