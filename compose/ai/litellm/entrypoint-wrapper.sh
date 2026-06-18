#!/bin/sh
# LiteLLM entrypoint wrapper — reads API keys from Docker secrets
# and exports them as environment variables before launching LiteLLM.
set -e

SECRET_DIR="/run/secrets"

# Read secrets directly and export
if [ -f "$SECRET_DIR/openrouter_key_1" ]; then export OPENROUTER_KEY_1="$(cat "$SECRET_DIR/openrouter_key_1" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/openrouter_key_2" ]; then export OPENROUTER_KEY_2="$(cat "$SECRET_DIR/openrouter_key_2" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/openrouter_key_3" ]; then export OPENROUTER_KEY_3="$(cat "$SECRET_DIR/openrouter_key_3" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/nvidia_nim_key_1" ]; then export NVIDIA_NIM_KEY_1="$(cat "$SECRET_DIR/nvidia_nim_key_1" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/gemini_key_1" ]; then export GEMINI_API_KEY_1="$(cat "$SECRET_DIR/gemini_key_1" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/gemini_key_2" ]; then export GEMINI_API_KEY_2="$(cat "$SECRET_DIR/gemini_key_2" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/gemini_key_3" ]; then export GEMINI_API_KEY_3="$(cat "$SECRET_DIR/gemini_key_3" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/grok_key_1" ]; then export GROQ_API_KEY_1="$(cat "$SECRET_DIR/grok_key_1" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/alibaba_key_1" ]; then export ALIBABA_MODELSTUDIO_KEY_1="$(cat "$SECRET_DIR/alibaba_key_1" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/alibaba_key_2" ]; then export ALIBABA_MODELSTUDIO_KEY_2="$(cat "$SECRET_DIR/alibaba_key_2" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/novita_key_1" ]; then export NOVITA_API_KEY_1="$(cat "$SECRET_DIR/novita_key_1" | tr -d '\n\r')"; fi
if [ -f "$SECRET_DIR/litellm_key" ]; then export LITELLM_MASTER_KEY="$(cat "$SECRET_DIR/litellm_key" | tr -d '\n\r')"; fi

echo "[litellm-wrapper] LITELLM_MASTER_KEY is set: $([ -n "$LITELLM_MASTER_KEY" ] && echo 'YES' || echo 'NO')" >&2
echo "[litellm-wrapper] Starting LiteLLM with config /app/config/config.yml" >&2

# Execute the original LiteLLM entrypoint with config flag
exec docker/prod_entrypoint.sh --config /app/config/config.yml --port 4000
