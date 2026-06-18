#!/bin/sh
# OpenWebUI entrypoint wrapper — reads LiteLLM key from Docker secret
# and sets OPENAI_API_KEYS with both LiteLLM and Hermes agent keys.
set -e

LITELLM_KEY=""
if [ -f /run/secrets/litellm_key ]; then
    LITELLM_KEY="$(cat /run/secrets/litellm_key | tr -d '\n\r')"
fi

HERMES_KEY="${HERMES_API_KEY:-no-key}"

# OpenWebUI supports multiple OpenAI endpoints separated by semicolons
export OPENAI_API_BASE_URLS="http://litellm:4000/v1;http://host.docker.internal:8642/v1"
export OPENAI_API_KEYS="${LITELLM_KEY};${HERMES_KEY}"

echo "[openwebui-wrapper] Configured LiteLLM + Hermes agent endpoints" >&2

exec "$@"
