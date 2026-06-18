# 🔍 Missed Opportunities — Free Models Not in LiteLLM Config
**Generated:** 2026-06-18 07:46 UTC
**Total missed free models:** 84

These models are available at zero cost from your configured providers
but are NOT currently in your `config.yml` model_list.

## Top Free Models by Context Length

| Model | Provider | Context | Tier | Suggested Role |
|-------|----------|---------|------|----------------|
| `openrouter/owl-alpha` | openrouter | 1,048,756 | T3-FREE | long-context |
| `google/lyria-3-pro-preview` | openrouter | 1,048,576 | T3-FREE | long-context |
| `google/lyria-3-clip-preview` | openrouter | 1,048,576 | T3-FREE | long-context |
| `qwen/qwen3-coder:free` | openrouter | 1,048,576 | T3-FREE | long-context |
| `gemini/gemini-2.0-flash` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-2.0-flash-001` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-2.0-flash-lite-001` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-2.0-flash-lite` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-flash-latest` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-flash-lite-latest` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-2.5-flash-lite` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-3-flash-preview` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-3.1-flash-lite-preview` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-3.1-flash-lite` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-3.5-flash` | gemini | 1,048,576 | T3-FREE | utility |
| `gemini/gemini-robotics-er-1.5-preview` | gemini | 1,048,576 | T3-FREE | long-context |
| `nvidia/nemotron-3-ultra-550b-a55b:free` | openrouter | 1,000,000 | T1-ULTRA | long-context |
| `nvidia/nemotron-3-super-120b-a12b:free` | openrouter | 1,000,000 | T3-FREE | long-context |
| `nex-agi/nex-n2-pro:free` | openrouter | 262,144 | T3-FREE | long-context |
| `poolside/laguna-xs.2:free` | openrouter | 262,144 | T3-FREE | long-context |
| `poolside/laguna-m.1:free` | openrouter | 262,144 | T3-FREE | long-context |
| `google/gemma-4-26b-a4b-it:free` | openrouter | 262,144 | T3-FREE | long-context |
| `google/gemma-4-31b-it:free` | openrouter | 262,144 | T3-FREE | long-context |
| `qwen/qwen3-next-80b-a3b-instruct:free` | openrouter | 262,144 | T3-FREE | long-context |
| `cohere/north-mini-code:free` | openrouter | 256,000 | T3-FREE | long-context |
| `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` | openrouter | 256,000 | T3-FREE | long-context |
| `nvidia/nemotron-3-nano-30b-a3b:free` | openrouter | 256,000 | T3-FREE | long-context |
| `openrouter/free` | openrouter | 200,000 | T3-FREE | long-context |
| `openai/gpt-oss-120b:free` | openrouter | 131,072 | T3-FREE | long-context |
| `openai/gpt-oss-20b:free` | openrouter | 131,072 | T3-FREE | long-context |
| `meta-llama/llama-3.3-70b-instruct:free` | openrouter | 131,072 | T1-ULTRA | reasoning |
| `meta-llama/llama-3.2-3b-instruct:free` | openrouter | 131,072 | T3-FREE | long-context |
| `nousresearch/hermes-3-llama-3.1-405b:free` | openrouter | 131,072 | T1-ULTRA | reasoning |
| `openai/qwen3.7-plus-2026-05-26` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.7-plus` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.5-plus-2026-04-20` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.5-omni-plus-realtime-2026-03-15` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.5-omni-plus-realtime` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.5-omni-plus-2026-03-15` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.5-omni-plus` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.6-plus-2026-04-02` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.6-plus` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen3.5-plus-2026-02-15` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen-image-plus-2026-01-09` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen-plus-character` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/z-image-turbo` | alibaba | 131,072 | T3-FREE | utility |
| `openai/qwen3-vl-plus-2025-12-19` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen-image-edit-plus-2025-12-15` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen-plus-2025-12-01` | alibaba | 131,072 | T3-FREE | long-context |
| `openai/qwen-image-edit-plus` | alibaba | 131,072 | T3-FREE | long-context |

## Recommended Additions to config.yml

```yaml
# Suggested free model additions for LiteLLM config.yml
# - openrouter/owl-alpha  (ctx=1048756, tier=T3-FREE)
# - google/lyria-3-pro-preview  (ctx=1048576, tier=T3-FREE)
# - google/lyria-3-clip-preview  (ctx=1048576, tier=T3-FREE)
# - qwen/qwen3-coder:free  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-2.0-flash  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-2.0-flash-001  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-2.0-flash-lite-001  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-2.0-flash-lite  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-flash-latest  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-flash-lite-latest  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-2.5-flash-lite  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-3-flash-preview  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-3.1-flash-lite-preview  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-3.1-flash-lite  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-3.5-flash  (ctx=1048576, tier=T3-FREE)
# - gemini/gemini-robotics-er-1.5-preview  (ctx=1048576, tier=T3-FREE)
# - nvidia/nemotron-3-ultra-550b-a55b:free  (ctx=1000000, tier=T1-ULTRA)
# - nvidia/nemotron-3-super-120b-a12b:free  (ctx=1000000, tier=T3-FREE)
# - nex-agi/nex-n2-pro:free  (ctx=262144, tier=T3-FREE)
# - poolside/laguna-xs.2:free  (ctx=262144, tier=T3-FREE)
```