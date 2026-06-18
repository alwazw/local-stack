---
name: litellm-proxy-config
description: LiteLLM proxy gateway with multi-provider model fallback pools — entrypoint wrapper, PostgreSQL backend, API key rotation, provider prefixes, and config.yml pitfalls
source: auto-skill
extracted_at: '2026-06-18T06:30:00.000Z'
---

# LiteLLM Proxy Gateway Configuration

## Architecture

```
┌────────────────────────────────────────────────────────┐
│  LiteLLM Proxy (port 4000)                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Router: usage-based-routing                      │  │
│  │ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ │  │
│  │ │ OpenRouter│ │ Nvidia  │ │ Gemini  │ │ Groq   │ │  │
│  │ │ ×3 keys  │ │ ×1 key  │ │ ×3 keys │ │ ×1 key │ │  │
│  │ └─────────┘ └─────────┘ └─────────┘ └────────┘ │  │
│  │ ┌─────────┐ ┌─────────┐                        │  │
│  │ │ Alibaba │ │ Ollama  │ (local fallback)        │  │
│  │ │ ×2 keys │ │ local   │                        │  │
│  │ └─────────┘ └─────────┘                        │  │
│  └──────────────────────────────────────────────────┘  │
│  PostgreSQL backend (Prisma ORM)                       │
└────────────────────────────────────────────────────────┘
```

## Critical: The `--config` Flag

The `main-latest` image does NOT automatically load `/app/config/config.yml`. You MUST pass `--config` explicitly via an entrypoint wrapper.

### Entrypoint Wrapper Script

```sh
#!/bin/sh
# entrypoint-wrapper.sh — loads API keys from secrets, launches LiteLLM with config
set -e

SECRET_DIR="/run/secrets"

load_secret() {
    local var_name="$1"
    local file_name="$2"
    local file_path="${SECRET_DIR}/${file_name}"
    if [ -f "$file_path" ]; then
        export "$var_name"="$(cat "$file_path" | tr -d '\n\r')"
    fi
}

# Load all provider API keys from Docker secrets
load_secret "OPENROUTER_KEY_1" "openrouter_key_1"
load_secret "OPENROUTER_KEY_2" "openrouter_key_2"
load_secret "OPENROUTER_KEY_3" "openrouter_key_3"
load_secret "NVIDIA_NIM_KEY_1" "nvidia_nim_key_1"
load_secret "GEMINI_API_KEY_1" "gemini_key_1"
# ... more keys ...

# Load LiteLLM master key
load_secret "LITELLM_MASTER_KEY" "litellm_key"

echo "[litellm-wrapper] Loaded $(env | grep -c '_KEY\|_API_KEY') API key(s)" >&2

# CRITICAL: pass --config flag to prod_entrypoint.sh
exec docker/prod_entrypoint.sh --config /app/config/config.yml --port 4000
```

### Docker Compose Configuration

```yaml
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    entrypoint: ["/entrypoint-wrapper.sh"]
    environment:
      OLLAMA_API_BASE: "http://ollama:11434"
      DATABASE_URL: "postgresql://user:password%3D@postgres:5432/litellm"
      STORE_MODEL_IN_DB: "False"
      DEBUG: 1
    volumes:
      - ./config:/app/config
      - ./entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro
    secrets:
      - litellm_key
      - openrouter_key_1
      # ... all key secrets ...
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/routes', timeout=5)"]
```

## Critical: PostgreSQL Backend Required

LiteLLM uses **Prisma ORM** which requires PostgreSQL. SQLite does NOT work — Prisma's schema validation rejects `sqlite://` URLs with:

```
Error: the URL must start with the protocol `postgresql://` or `postgres://`
```

### Setup Steps

1. **Create database:**
   ```bash
   docker exec postgres psql -U <user> -d <existing_db> -c "CREATE DATABASE litellm;"
   ```

2. **Connect postgres to shared network:**
   ```bash
   docker network connect ai-ml postgres
   ```

3. **URL-encode special characters in password:**
   - `=` → `%3D`
   - `@` → `%40`
   - `#` → `%23`
   - `/` → `%2F`

   Example: `mPfIVznCZRhSmutj3KBPOLIHT85dJS0Tg15ZbpzoVWg=` → `...%3D@...`

4. **DATABASE_URL format:**
   ```
   postgresql://<user>:<url_encoded_password>@<hostname>:5432/<database>
   ```

### Why Not SQLite?

LiteLLM's `main-latest` image ships with Prisma ORM (not SQLAlchemy). Prisma schema hardcodes `provider = "postgresql"`. The image silently continues startup when migration fails, but the proxy never opens port 4000 — it hangs in `Waiting for application startup`.

## config.yml — Model Fallback Pools

### Model Name Convention

Use `openai/<pool-name>` as the `model_name` so downstream agents (Hermes, Agent Zero) use OpenAI-compatible API format:

```yaml
model_list:
  # Pool 1: High-intelligence models
  - model_name: openai/morpheus-main-model
    litellm_params:
      model: openrouter/openrouter/owl-alpha
      api_base: https://openrouter.ai/api/v1
      api_key: "os.environ/OPENROUTER_KEY_1"
      rpm: 20
      order: 1

  # Pool 2: Fast utility models
  - model_name: openai/morpheus-utility-model
    litellm_params:
      model: gemini/gemini-2.5-flash
      api_key: "os.environ/GEMINI_API_KEY_1"
      rpm: 30
      order: 1
```

### Provider Prefix Rules

LiteLLM requires the model string to start with a recognized provider prefix:

| Provider | Correct Prefix | Wrong Prefix | Notes |
|----------|---------------|-------------|-------|
| Nvidia NIM | `nvidia_nim/<model>` | `nvidia/<model>` | Must include `_nim` |
| Alibaba/DashScope | `openai/<model>` + `api_base` | `dashscope/<model>` | DashScope provider not supported; use OpenAI-compatible mode |
| OpenRouter | `openrouter/<full-model-path>` | — | Full path includes org: `openrouter/openrouter/owl-alpha` |
| Google Gemini | `gemini/<model>` | `google/<model>` | Direct Google AI Studio, not Vertex |
| Groq | `groq/<model>` | — | — |
| Ollama (local) | `ollama/<model>` | — | Needs `api_base: http://ollama:11434` |
| Novita AI | `openai/<model>` + `api_base` | `novita/<model>` | Use OpenAI-compatible mode with `https://api.novita.ai/v3/openai` |

### Model Name Gotchas

- `gemini/gemini-3.1-flash-lite` does NOT exist — use `gemini/gemini-2.5-flash` or `gemini/gemini-2.5-flash-lite-preview-06-17`
- Always verify model names against the provider's actual API before adding to config.yml — LiteLLM silently skips invalid models
- Ollama model names must match exactly what `ollama list` returns (e.g., `ollama/deepseek-r1:8b`, `ollama/dolphin3`)

### Alibaba Workspace-Specific Endpoints

Alibaba Cloud Model Studio uses workspace-specific API endpoints (not the global `dashscope.aliyuncs.com`). Use the OpenAI-compatible endpoint:

```yaml
  - model_name: openai/morpheus-utility-model
    litellm_params:
      model: openai/qwen3.5-plus
      api_base: https://ws-<workspace_id>.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1
      api_key: "os.environ/ALIBABA_MODELSTUDIO_KEY_1"
      rpm: 20
      tpm: 60000
      order: 2
```

The workspace ID and API host are found in the Alibaba workspace settings.

### Router Settings

```yaml
router_settings:
  routing_strategy: usage-based-routing
  num_retries: 3
  cooldown_time: 60
  allowed_fails: 1
  optional_pre_call_checks:
    - enforce_model_rate_limits

  model_group_alias:
    # Handle typos and alternate names
    "gemini-2.5-pro": "openai/morpheus-main-model"
    "gemini-2.5-flash": "openai/morpheus-utility-model"

  fallbacks:
    - "openai/morpheus-main-model": ["openai/morpheus-utility-model"]

litellm_settings:
  drop_params: true       # Strip unsupported params before upstream calls
  set_verbose: false      # Enable only for debugging
```

## Master Key Authentication

LiteLLM supports two authentication methods that can conflict:

### Method 1: Environment Variable (Master Key)
Set `LITELLM_MASTER_KEY` in docker-compose.yml:
```yaml
environment:
  LITELLM_MASTER_KEY: "sk-your-master-key"
```

This key is **automatically valid** for all API calls without database lookup.

### Method 2: Virtual Keys (Database)
Create virtual keys in PostgreSQL with hashed tokens:
```sql
INSERT INTO "LiteLLM_VerificationToken" (
  token, key_alias, user_id, models, permissions,
  created_at, updated_at, spend, expires, blocked
) VALUES (
  '<sha256_hash_of_key>',  -- NOT the plaintext key!
  'my-virtual-key',
  'my-user',
  ARRAY['openai/morpheus-main-model', 'openai/morpheus-utility-model'],
  '{}'::jsonb,
  NOW(), NOW(), 0,
  NOW() + interval '365 days',
  false
);
```

### Critical: Hash vs Plaintext

LiteLLM stores **SHA-256 hashes** of API keys in the database, not plaintext. When you send a request with `Authorization: Bearer sk-abc123`, LiteLLM:
1. Computes `SHA-256("sk-abc123")`
2. Looks up the hash in `LiteLLM_VerificationToken.token`
3. Validates the request

**Common mistake:** Inserting the plaintext key into the database:
```sql
-- WRONG: This will fail authentication
INSERT INTO "LiteLLM_VerificationToken" (token, ...) VALUES ('sk-abc123', ...);

-- CORRECT: Insert the SHA-256 hash
INSERT INTO "LiteLLM_VerificationToken" (token, ...) VALUES ('<hash>', ...);
```

**Generate the hash:**
```bash
python3 -c "import hashlib; print(hashlib.sha256(b'sk-abc123').hexdigest())"
```

### Authentication Priority

1. **Master key** (environment variable) is checked first
2. **Virtual keys** (database) are checked second
3. If both exist, master key takes precedence

### Troubleshooting 401 Errors

**Error:** `Authentication Error, Invalid proxy server token passed`

**Check 1:** Is the master key set?
```bash
docker exec litellm env | grep LITELLM_MASTER_KEY
```

**Check 2:** What's the expected hash?
```bash
# From the error message, find "Key Hash (Token) =..."
# This is the SHA-256 hash LiteLLM computed from your request key
```

**Check 3:** Does the database have this hash?
```bash
docker exec postgres psql -U <user> -d litellm -c \
  "SELECT key_alias FROM \"LiteLLM_VerificationToken\" WHERE token = '<hash_from_error>';"
```

**Check 4:** Is the key in the allowed models list?
```bash
docker exec postgres psql -U <user> -d litellm -c \
  "SELECT models FROM \"LiteLLM_VerificationToken\" WHERE key_alias = 'my-key';"
```

## API Keys: Environment Variables vs Docker Secrets

### The Problem with Secrets-Only Approach

The entrypoint wrapper `load_secret()` function using `export` does NOT reliably pass variables to child processes started by `exec docker/prod_entrypoint.sh`. Specifically:

- Variables ARE visible in PID 1's `/proc/1/environ`
- Variables are NOT visible in shell sessions (`docker exec litellm env`)
- LiteLLM's Python process may or may not see them depending on when they're read

### Working Approach: Direct Environment Variables

Put API keys directly in docker-compose.yml `environment:` section:

```yaml
services:
  litellm:
    environment:
      LITELLM_MASTER_KEY: "sk-your-master-key"
      OPENROUTER_KEY_1: "sk-or-v1-..."
      OPENROUTER_KEY_2: "sk-or-v1-..."
      NVIDIA_NIM_KEY_1: "nvapi-..."
      GEMINI_API_KEY_1: "AIza..."
      GEMINI_API_KEY_2: "AIza..."
      GROQ_API_KEY_1: "gsk_..."
      ALIBABA_MODELSTUDIO_KEY_1: "sk-ws-..."
      NOVITA_API_KEY_1: "sk_..."
```

Then reference them in config.yml using the `os.environ/` pattern:

```yaml
- model_name: openai/morpheus-main-model
  litellm_params:
    model: openrouter/openrouter/owl-alpha
    api_key: "os.environ/OPENROUTER_KEY_1"
```

### Trade-off

Direct env vars means keys are visible in `docker inspect` and process environment. For production, use Docker Compose `${VARIABLE}` substitution from a `.env` file (gitignored) instead of hardcoding.

## Silent Config Failures

If ANY model entry in config.yml has an unrecognized provider prefix, LiteLLM **silently skips it** during router initialization. The proxy starts but the model is missing from `/v1/models`.

### Diagnosis

```bash
# Check which models loaded successfully
curl -s http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_KEY" | python3 -m json.tool

# Check logs for provider errors
docker logs litellm 2>&1 | grep -i "error\|BadRequest"
```

### Validation Script (run inside container)

```python
import yaml
with open('/app/config/config.yml') as f:
    config = yaml.safe_load(f)

for i, m in enumerate(config.get('model_list', [])):
    model = m.get('litellm_params', {}).get('model', 'MISSING')
    provider = model.split('/')[0] if '/' in model else 'UNKNOWN'
    print(f'  [{i+1}] {model} (provider: {provider})')
```

## `external: true` Secrets Conflict with `include`

When using Docker Compose `include:` directive, you CANNOT have `external: true` secrets in the included files. The root file defines secrets with `file:` paths, but included files with `external: true` expect Docker Swarm secrets (which don't exist when Swarm is inactive).

### Error
```
Container litellm unsupported external secret litellm_key
```

### Fix
Remove the entire `secrets:` block from ALL included compose files. Keep secrets definitions ONLY in the root `docker-compose.yml`:

```yaml
# Root docker-compose.yml — ONLY place secrets are defined
secrets:
  litellm_key:
    file: ./secrets/litellm_key.txt
  openrouter_key_1:
    file: ./secrets/external_llm_keys/openrouter_key_1.txt
  # ... all secrets here ...

# Included file — references secrets but doesn't define them
services:
  litellm:
    secrets:
      - litellm_key
      - openrouter_key_1
    # NO top-level secrets: block here!
```

## Health Check Strategy

Use `/routes` (unauthenticated) or `/health/liveliness` (also unauthenticated):

```yaml
healthcheck:
  test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/routes', timeout=5)"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 30s
```

**Do NOT use `/health`** — it requires the master key in newer LiteLLM versions.

## API Usage

```bash
# List models
curl -s http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Chat completion
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "openai/morpheus-main-model",
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# Model info
curl -s http://localhost:4000/model/info \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

## Startup Time

LiteLLM takes 60-90 seconds to start with PostgreSQL:
1. Prisma migration deploy (~30s)
2. Schema diff and baseline (~15s)
3. Application startup and model loading (~15s)
4. Health watchdog initialization (~5s)

Port 4000 only opens AFTER all steps complete. Check `docker logs litellm` for "Application startup complete" and "Uvicorn running on http://0.0.0.0:4000".
