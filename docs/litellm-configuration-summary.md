# LiteLLM Gateway Configuration Summary

**Date:** 2026-06-18  
**Status:** ✅ FULLY OPERATIONAL

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    LiteLLM Gateway                          │
│                   http://localhost:4000                      │
│  Master Key: sk-5331c075c076ee7a8a7014204f6e95e749acda2d5e │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Hermes Agent │    │ Agent-Zero   │    │  OpenWebUI   │
│  :8642       │    │  :8501/:8081 │    │  :3000       │
│              │    │              │    │              │
│ Telegram: ✅ │    │ Web UI: ✅   │    │ Web UI: ✅   │
│ API: ✅      │    │ API: ✅      │    │ API: ✅      │
└──────────────┘    └──────────────┘    └──────────────┘
```

## Model Pools Configuration

### 1. Main Model Pool: `openai/morpheus-main-model`
**Purpose:** High-quality reasoning, complex tasks, code generation

**Fallback Chain (Priority Order):**
1. OpenRouter (OWL-Alpha) - 3 keys, 20 RPM each
2. Nvidia NIM (Nemotron-3-Ultra) - 40 RPM
3. Google Gemini 2.5 Pro - 3 keys, 5 RPM each
4. Groq (Llama-3.3-70B-Versatile) - 30 RPM
5. Ollama (DeepSeek-R1:8B) - Local fallback

**Test Results:**
```bash
✅ Direct LiteLLM: "MAIN_POOL_OK"
✅ Via Hermes: "HERMES_E2E_OK"
✅ Via Gemini Alias: "HERMES_ALIAS_OK"
```

### 2. Utility Model Pool: `openai/morpheus-utility-model`
**Purpose:** Fast responses, embeddings, simple tasks

**Fallback Chain (Priority Order):**
1. Google Gemini 2.5 Flash - 3 keys, 30 RPM each
2. Alibaba Qwen 3.5 Plus - 2 keys, 20 RPM each
3. OpenRouter (Gemini 2.5 Flash Free) - 3 keys, 10 RPM each
4. Ollama (Phi-3:Mini) - Local fallback

**Test Results:**
```bash
✅ Direct LiteLLM: "UTILITY_POOL_OK"
✅ Via Hermes: "HERMES_UTILITY_OK"
```

### 3. Embedding Model Pool: `openai/morpheus-embedding-model`
**Purpose:** Text embeddings for RAG and semantic search

**Configuration:**
- Ollama (Nomic-Embed-Text) - Local only

### 4. Tier2 Aliases
**Purpose:** Alternative access paths to main pools

- `openai/morpheus-main-tier2` → `openai/morpheus-main-model`
- `openai/morpheus-utility-tier2` → `openai/morpheus-utility-model`

### 5. Free/OpenRouter Pools
**Purpose:** Cost-free alternatives with rate limits

- `openai/morpheus-omni-free` → OpenRouter free models
- `openai/morpheus-openrouter-free` → OpenRouter free models

### 6. Local Fallback
**Purpose:** Offline operation when cloud APIs unavailable

- `openai/morpheus-local-fallback` → Ollama models

## Provider-Specific Aliases

| Alias | Maps To |
|-------|---------|
| `gemini-2.5-pro` | `openai/morpheus-main-model` |
| `gemini-2.5-flash` | `openai/morpheus-utility-model` |
| `google/gemini-2.5-flash` | `openai/morpheus-utility-model` |
| `anthropic/claude-opus-4.7` | `openai/morpheus-main-model` |
| `nousresearch/hermes-3-llama-3.1-405b:free` | `openai/morpheus-main-model` |
| `openrouter/google/gemini-2.5-flash:free` | `openai/morpheus-utility-model` |

## API Keys Configuration

### Environment Variables (docker-compose.yml)
```yaml
LITELLM_MASTER_KEY: "sk-5331c076ee7a8a7014204f6e95e749acda2d5e13597ed23ed33fbf37cabc"
OPENROUTER_KEY_1: "sk-or-v1-..."
OPENROUTER_KEY_2: "sk-or-v1-..."
OPENROUTER_KEY_3: "sk-or-v1-..."
NVIDIA_NIM_KEY_1: "nvapi-..."
GEMINI_API_KEY_1: "AIza..."
GEMINI_API_KEY_2: "AIza..."
GEMINI_API_KEY_3: "AIza..."
GROQ_API_KEY_1: "gsk_..."
ALIBABA_MODELSTUDIO_KEY_1: "sk-..."
ALIBABA_MODELSTUDIO_KEY_2: "sk-..."
NOVITA_API_KEY_1: "sk-..."
```

## Service Configurations

### Hermes Agent
**File:** `/mnt/d/docker/compose/ai/hermes/docker-compose.yml`

**Environment:**
```yaml
OPENAI_API_KEY: "sk-5331c076ee7a8a7014204f6e95e749acda2d5e13597ed23ed33fbf37cabc"
OPENAI_BASE_URL: "http://litellm:4000/v1"
```

**Config (config.yaml):**
```yaml
model:
  default: "openai/morpheus-main-model"
  provider: "openai-api"
fallback_providers:
  - provider: "openai-api"
    model: "openai/morpheus-utility-model"
```

**Auxiliary Models:**
- vision: `openai/morpheus-main-model`
- web_extract: `openai/morpheus-utility-model`
- compression: `openai/morpheus-utility-model`
- skills_hub: `openai/morpheus-utility-model`
- title_generation: `openai/morpheus-utility-model`
- triage_specifier: `openai/morpheus-utility-model`
- kanban_decomposer: `openai/morpheus-main-model`
- profile_describer: `openai/morpheus-utility-model`
- curator: `openai/morpheus-utility-model`
- monitor: `openai/morpheus-utility-model`

**Gateway State:**
```json
{
  "gateway_state": "running",
  "platforms": {
    "api_server": {"state": "connected"},
    "telegram": {"state": "connected"}
  }
}
```

### Agent-Zero
**File:** `/mnt/d/docker/compose/ai/agent-zero/docker-compose.yml`

**Environment:**
```yaml
LLM_PROVIDER: "openai"
LLM_BASE_URL: "http://litellm:4000"
LLM_MODEL: "openai/morpheus-main-model"
LLM_UTILITY_MODEL: "openai/morpheus-utility-model"
LLM_EMBEDDING_MODEL: "openai/morpheus-embedding-model"
LITELLM_MASTER_KEY_FILE: "/run/secrets/litellm_key"
```

**Status:**
- Web UI: ✅ http://localhost:8501
- API: ✅ http://localhost:8081 (requires API key from secrets/agent_zero_key)

### OpenWebUI
**File:** `/mnt/d/docker/compose/ai/openwebui/docker-compose.yml`

**Environment:**
```yaml
OPENAI_API_BASE_URLS: "http://litellm:4000/v1;http://host.docker.internal:8642/v1"
OPENAI_API_KEYS: "<litellm_key>;<hermes_api_key>"
ENABLE_OLLAMA_API: "true"
```

**Status:**
- Web UI: ✅ http://localhost:3000

## Database Configuration

**PostgreSQL Database:** `litellm`

**Virtual Key Entry:**
```sql
token: "d6c09a612cfd0c60d25d4d3799b74602104fdb0824fa825a554e38a73e5a11be"
key_alias: "hermes-master-key"
user_id: "hermes-system"
models: [
  "openai/morpheus-main-model",
  "openai/morpheus-utility-model",
  "openai/morpheus-embedding-model",
  "gemini-2.5-pro",
  "gemini-2.5-flash",
  "openai/morpheus-main-tier2",
  "openai/morpheus-utility-tier2",
  "openai/morpheus-omni-free",
  "openai/morpheus-openrouter-free",
  "openai/morpheus-local-fallback"
]
```

## Testing Commands

### Test LiteLLM Directly
```bash
# Main model
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-5331c076ee7a8a7014204f6e95e749acda2d5e13597ed23ed33fbf37cabc" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/morpheus-main-model","messages":[{"role":"user","content":"Say hello"}]}'

# Utility model
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-5331c076ee7a8a7014204f6e95e749acda2d5e13597ed23ed33fbf37cabc" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/morpheus-utility-model","messages":[{"role":"user","content":"Say hello"}]}'

# List all models
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer sk-5331c076ee7a8a7014204f6e95e749acda2d5e13597ed23ed33fbf37cabc"
```

### Test Hermes Agent
```bash
curl -X POST http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer your-super-secret-key-here" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/morpheus-main-model","messages":[{"role":"user","content":"Say hello"}]}'
```

### Test Agent-Zero
- Web UI: http://localhost:8501
- API: http://localhost:8081 (requires API key)

### Test OpenWebUI
- Web UI: http://localhost:3000

## Telegram Integration

**Bot:** @Hermes_Morpheus1_bot  
**Status:** ✅ Connected  
**Home Channel:** 6779511356

**Configuration:**
```yaml
telegram:
  token: "8895059618:AAGm_tF7-qaZVE3fAM6HzPw67M3_-8ox-y0"
```

## Troubleshooting

### Common Issues

1. **Authentication Error (401)**
   - Check API key in Authorization header
   - Verify master key matches environment variable
   - Check database virtual key entry

2. **Model Not Found**
   - List available models: `curl http://localhost:4000/v1/models`
   - Check config.yml model_list section
   - Verify model aliases are defined

3. **Provider API Key Invalid**
   - Check environment variables in docker-compose.yml
   - Verify API keys are loaded in container: `docker exec litellm env | grep KEY`
   - Check provider dashboard for key status

4. **Telegram Not Connecting**
   - Check gateway_state.json for connection status
   - Verify bot token is correct
   - Check iptables FORWARD rules for outbound traffic

5. **Slow Response Times**
   - Check provider rate limits (RPM/TPM)
   - Monitor cooldown_time (60s) and fallback behavior
   - Consider increasing num_retries (currently 3)

## Performance Metrics

### Rate Limits by Provider
| Provider | Models | RPM | TPM |
|----------|--------|-----|-----|
| OpenRouter | OWL-Alpha, Gemini Flash Free | 20-30 | 30K-1M |
| Nvidia NIM | Nemotron-3-Ultra | 40 | 1M |
| Google Gemini | 2.5 Pro, 2.5 Flash | 5-30 | 250K-1M |
| Groq | Llama-3.3-70B, Llama-3.1-8B | 30 | 6K-12K |
| Alibaba | Qwen 3.5 Plus | 20 | 60K |
| Ollama | DeepSeek-R1, Phi-3, Nomic-Embed | 1000 | 500K |

### Fallback Behavior
- **num_retries:** 3 (per priority level)
- **cooldown_time:** 60 seconds
- **allowed_fails:** 1 (before cooldown)
- **routing_strategy:** usage-based-routing

## Next Steps

1. **Monitor Usage:** Track token consumption and costs
2. **Optimize Routing:** Adjust priority orders based on performance
3. **Add More Providers:** Consider adding Anthropic, Mistral, etc.
4. **Implement Caching:** Enable response caching for repeated queries
5. **Set Up Alerts:** Monitor for provider failures and rate limits

## Files Reference

- **LiteLLM Config:** `/mnt/d/docker/compose/ai/litellm/config/config.yml`
- **LiteLLM Compose:** `/mnt/d/docker/compose/ai/litellm/docker-compose.yml`
- **Hermes Config:** `/mnt/d/docker/compose/ai/hermes/config/config.yaml`
- **Hermes Compose:** `/mnt/d/docker/compose/ai/hermes/docker-compose.yml`
- **Agent-Zero Compose:** `/mnt/d/docker/compose/ai/agent-zero/docker-compose.yml`
- **OpenWebUI Compose:** `/mnt/d/docker/compose/ai/openwebui/docker-compose.yml`
- **API Keys:** `/mnt/d/docker/secrets/external_llm_keys/*.txt`
- **Master Key:** `/mnt/d/docker/secrets/litellm_key`
