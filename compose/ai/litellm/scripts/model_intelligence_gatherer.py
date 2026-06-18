#!/usr/bin/env python3
"""
Model Intelligence Gatherer for LiteLLM Gateway
=================================================
Aggregates model data from all configured inference providers:
- OpenRouter (free tiers + paid models with rate/caps)
- Google Gemini (free tier limits per key)
- Groq (free tier limits)
- Novita AI (free tiers)
- Nvidia NIM (free tier)
- Alibaba ModelStudio (free quotas)

Classifies models into tiers:
  T1 - ULTRA:  Best reasoning, largest context (code gen, complex planning)
  T2 - FAST:   Quick inference, moderate context (utility, extraction)
  T3 - FREE:   Zero-cost models with decent capability
  T4 - LOCAL:  Ollama models (no API cost, hardware-bound)

Outputs:
  - models_intelligence_report.md  (human-readable)
  - models_intelligence.json       (machine-readable for n8n/LiteLLM)
  - missed_opportunities.md        (models not yet in config.yml)
  - litellm_model_suggestions.yml  (ready to merge into config.yml)
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LITELLM_CONFIG_DIR = Path("/mnt/d/docker/compose/ai/litellm/config")
REPORT_DIR = LITELLM_CONFIG_DIR / "intelligence_reports"
OUTPUT_DIR = REPORT_DIR / datetime.now(timezone.utc).strftime("%Y-%m-%d")

# Provider API keys (read from environment — same as litellm container)
PROVIDER_KEYS = {
    "openrouter": [
        os.environ.get("OPENROUTER_KEY_1", ""),
        os.environ.get("OPENROUTER_KEY_2", ""),
        os.environ.get("OPENROUTER_KEY_3", ""),
    ],
    "gemini": [
        os.environ.get("GEMINI_API_KEY_1", ""),
        os.environ.get("GEMINI_API_KEY_2", ""),
        os.environ.get("GEMINI_API_KEY_3", ""),
    ],
    "groq": [
        os.environ.get("GROQ_API_KEY_1", ""), # Corrected to GROQ_API_KEY_1
        os.environ.get("GROQ_API_KEY_2", ""), # Corrected to GROQ_API_KEY_2
    ],
    "novita": [
        os.environ.get("NOVITA_API_KEY_1", ""),
    ],
    "nvidia_nim": [
        os.environ.get("NVIDIA_NIM_KEY_1", ""),
    ],
    "alibaba": [
        os.environ.get("ALIBABA_MODELSTUDIO_KEY_1", ""),
        os.environ.get("ALIBABA_MODELSTUDIO_KEY_2", ""),
    ],
}

# Free tier rate limits (requests per minute) — approximate
FREE_TIER_LIMITS = {
    "openrouter":        {"rpm": 10,  "tpm": 30_000,   "note": "Free model tier, per-key"},
    "gemini":            {"rpm": 15,  "tpm": 1_000_000, "note": "Free tier per API key"},
    "groq":              {"rpm": 30,  "tpm": 12_000,   "note": "Free tier per key"},
    "novita":            {"rpm": 20,  "tpm": 50_000,   "note": "Free tier per key"},
    "nvidia_nim":        {"rpm": 40,  "tpm": 1_000_000,"note": "Free tier per key"},
    "alibaba":           {"rpm": 20,  "tpm": 60_000,   "note": "Free tier per workspace"},
}

# ---------------------------------------------------------------------------
# Provider fetchers
# ---------------------------------------------------------------------------

def _get_json(url: str, headers: dict | None = None, timeout: int = 15) -> dict | None:
    """Make a GET request and return parsed JSON, or None on failure."""
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as e:
        print(f"  [WARN] {url}: {e}", file=sys.stderr)
        return None


def fetch_openRouter_models() -> list[dict]:
    """Fetch all models from OpenRouter API, including free ones."""
    print("[INFO] Fetching OpenRouter models...")
    data = _get_json("https://openrouter.ai/api/v1/models")
    if not data:
        return []
    models = []
    for m in data.get("data", []):
        prompt_price = float(m.get("pricing", {}).get("prompt", "0") or "0")
        completion_price = float(m.get("pricing", {}).get("completion", "0") or "0")
        is_free = prompt_price == 0 and completion_price == 0
        ctx = m.get("context_length", 0)
        if isinstance(ctx, str):
            try:
                ctx = int(ctx)
            except ValueError:
                ctx = 0
        models.append({
            "provider": "openrouter",
            "model_id": m["id"],
            "name": m["id"].split("/")[-1] if "/" in m["id"] else m["id"],
            "context_length": ctx,
            "is_free": is_free,
            "prompt_price": prompt_price,
            "completion_price": completion_price,
            "description": (m.get("description") or "")[:200],
            "architectures": m.get("architecture", {}).get("modality", "text"),
        })
    print(f"[INFO] OpenRouter: {len(models)} total, {sum(1 for m in models if m['is_free'])} free")
    return models


def fetch_gemini_models() -> list[dict]:
    """Fetch available Gemini models from Google AI Studio API."""
    print("[INFO] Fetching Gemini models...")
    key = next((k for k in PROVIDER_KEYS["gemini"] if k), None)
    if not key:
        print("[WARN] Skipping Gemini: No API key found. Ensure GEMINI_API_KEY_1/2/3 are set.")
        return []
    data = _get_json(
        f"https://generativelanguage.googleapis.com/v1beta/models?key={key}"
    )
    if not data:
        return []
    models = []
    for m in data.get("models", []):
        name = m.get("name", "").replace("models/", "")
        if "gemini" not in name.lower():
            continue
        ctx = int(m.get("inputTokenLimit", 0) or 0)
        models.append({
            "provider": "gemini",
            "model_id": f"gemini/{name}",
            "name": name,
            "context_length": ctx,
            "is_free": "flash" in name.lower() or "1.5" in name.lower(),
            "prompt_price": 0.0 if "flash" in name.lower() else 0.001,
            "completion_price": 0.0 if "flash" in name.lower() else 0.003,
            "description": m.get("displayName", name),
            "architectures": "text",
        })
    print(f"[INFO] Gemini: {len(models)} models")
    return models


def fetch_groq_models() -> list[dict]:
    """Fetch available models from Groq API."""
    print("[INFO] Fetching Groq models...")
    key = next((k for k in PROVIDER_KEYS["groq"] if k), None)
    if not key:
        print("[WARN] Skipping Groq: No API key found. Ensure GROQ_API_KEY_1/2 are set (even if key file is grok_key.txt).")
        return []
    data = _get_json(
        "https://api.groq.com/openai/v1/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    if not data:
        return []
    models = []
    known_free_models = {
        "llama-3.3-70b-versatile", "llama-3.1-8b-instant",
        "llama3-70b-8192", "llama3-8b-8192",
        "gemma2-9b-it", "mixtral-8x7b-32768",
    }
    for m in data.get("data", []):
        mid = m.get("id", "")
        is_free = mid in known_free_models
        # Groq doesn't expose context in API, use known values
        ctx_map = {
            "llama-3.3-70b-versatile": 131072, "llama-3.1-8b-instant": 131072,
            "llama3-70b-8192": 8192, "llama3-8b-8192": 8192,
            "gemma2-9b-it": 8192, "mixtral-8x7b-32768": 32768,
        }
        models.append({
            "provider": "groq",
            "model_id": f"groq/{mid}",
            "name": mid,
            "context_length": ctx_map.get(mid, 32768),
            "is_free": is_free,
            "prompt_price": 0.0 if is_free else 0.0001,
            "completion_price": 0.0 if is_free else 0.0002,
            "description": f"Groq hosted {mid}",
            "architectures": "text",
        })
    print(f"[INFO] Groq: {len(models)} models")
    return models


def fetch_novita_models() -> list[dict]:
    """Fetch available models from Novita AI API."""
    print("[INFO] Fetching Novita models...")
    key = next((k for k in PROVIDER_KEYS["novita"] if k), None)
    if not key:
        print("[WARN] Skipping Novita: No API key found. Ensure NOVITA_API_KEY_1 is set.")
        return []
    data = _get_json(
        "https://api.novita.ai/v3/openai/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    if not data:
        return []
    models = []
    known_free = {"meta-llama/llama-3.1-8b-instruct", "meta-llama/llama-3-8b-instruct"}
    for m in data.get("data", []):
        mid = m.get("id", "")
        ctx = m.get("context_length", 0) or m.get("max_context_length", 0) or 0
        is_free = mid in known_free
        models.append({
            "provider": "novita",
            "model_id": f"novita/{mid}",
            "name": mid,
            "context_length": int(ctx),
            "is_free": is_free,
            "prompt_price": 0.0 if is_free else 0.00008,
            "completion_price": 0.0 if is_free else 0.00008,
            "description": f"Novita hosted {mid}",
            "architectures": "text",
        })
    print(f"[INFO] Novita: {len(models)} models")
    return models


def fetch_nvidia_models() -> list[dict]:
    """Fetch available models from Nvidia NIM API."""
    print("[INFO] Fetching Nvidia NIM models...")
    key = next((k for k in PROVIDER_KEYS["nvidia_nim"] if k), None)
    if not key:
        print("[WARN] Skipping Nvidia NIM: No API key found. Ensure NVIDIA_NIM_KEY_1 is set.")
        return []
    data = _get_json(
        "https://integrate.api.nvidia.com/v1/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    if not data:
        return []
    models = []
    known_free_tier = {"nvidia/nemotron-4-340b-instruct", "meta/llama-3.1-8b-instruct"}
    for m in data.get("data", []):
        mid = m.get("id", "")
        ctx = m.get("context_length", 0) or 0
        is_free = mid in known_free_tier
        models.append({
            "provider": "nvidia_nim",
            "model_id": f"nvidia_nim/{mid}",
            "name": mid,
            "context_length": int(ctx),
            "is_free": is_free,
            "prompt_price": 0.0 if is_free else 0.0002,
            "completion_price": 0.0 if is_free else 0.0004,
            "description": f"Nvidia NIM hosted {mid}",
            "architectures": "text",
        })
    print(f"[INFO] Nvidia NIM: {len(models)} models")
    return models


def fetch_alibaba_models() -> list[dict]:
    """Fetch available models from Alibaba ModelStudio API."""
    print("[INFO] Fetching Alibaba ModelStudio models...")
    key = next((k for k in PROVIDER_KEYS["alibaba"] if k), None)
    if not key:
        print("[WARN] Skipping Alibaba: No API key found. Ensure ALIBABA_MODELSTUDIO_KEY_1/2 are set.")
        return []
    # Alibaba uses OpenAI-compatible endpoint
    data = _get_json(
        "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    if not data:
        # Try the workspace-specific endpoint
        ws_key = os.environ.get("ALIBABA_MODELSTUDIO_KEY_1", "")
        if not ws_key:
            print("[WARN] No Alibaba workspace key for retry.")
            return []
        data = _get_json(
            "https://ws-3dpemgx0bzu13nbz.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models",
            headers={"Authorization": f"Bearer {ws_key}"},
        )
    if not data:
        return []
    models = []
    known_free = {"qwen-plus", "qwen-turbo", "qwen3-plus", "qwen3-turbo"}
    for m in data.get("data", []):
        mid = m.get("id", "")
        ctx = m.get("context_length", 0) or 131072
        is_free = any(f in mid.lower() for f in ["free", "plus", "turbo"])
        models.append({
            "provider": "alibaba",
            "model_id": f"openai/{mid}",
            "name": mid,
            "context_length": int(ctx),
            "is_free": is_free,
            "prompt_price": 0.0 if is_free else 0.0004,
            "completion_price": 0.0 if is_free else 0.0008,
            "description": f"Alibaba ModelStudio {mid}",
            "architectures": "text",
        })
    print(f"[INFO] Alibaba: {len(models)} models")
    return models


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

def classify_model(model: dict) -> str:
    """Classify a model into a tier based on capability signals."""
    name = model["name"].lower()
    ctx = model.get("context_length", 0)
    is_free = model.get("is_free", False)

    # T1 - ULTRA: Best reasoning, large context
    ultra_signals = ["opus", "o1", "o3", "405b", "70b", "ultra", "max", "2.5-pro", "2.5-pro"]
    if any(s in name for s in ultra_signals) and ctx >= 32768:
        return "T1-ULTRA"

    # T4 - LOCAL: Ollama models
    if model["provider"] == "ollama":
        return "T4-LOCAL"

    # T3 - FREE: Zero cost
    if is_free:
        return "T3-FREE"

    # T2 - FAST: Everything else (paid but fast)
    return "T2-FAST"


def classify_role(model: dict) -> str:
    """Classify model's best role in the agent stack."""
    name = model["name"].lower()
    ctx = model.get("context_length", 0)

    if any(s in name for s in ["o1", "o3", "opus", "2.5-pro", "405b", "70b"]):
        return "reasoning"
    if any(s in name for s in ["flash", "8b", "turbo", "instant", "lite"]):
        return "utility"
    if any(s in name for s in ["embed", "nomic", "bge", "e5"]):
        return "embedding"
    if ctx >= 100000:
        return "long-context"
    return "general"


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def generate_reports(all_models: list[dict], output_dir: Path) -> None:
    """Generate all output reports."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Classify all models
    for m in all_models:
        m["tier"] = classify_model(m)
        m["role"] = classify_role(m)

    # ---- JSON report ----
    json_report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_models": len(all_models),
        "free_models": sum(1 for m in all_models if m.get("is_free")),
        "by_provider": {},
        "by_tier": {},
        "models": all_models,
    }
    for m in all_models:
        prov = m["provider"]
        tier = m["tier"]
        json_report["by_provider"].setdefault(prov, []).append(m["model_id"])
        json_report["by_tier"].setdefault(tier, []).append(m["model_id"])

    with open(output_dir / "models_intelligence.json", "w") as f:
        json.dump(json_report, f, indent=2)
    print(f"[INFO] JSON report: {output_dir / 'models_intelligence.json'}")

    # ---- Markdown report ----
    md_lines = [
        "# 🧠 Model Intelligence Report",
        f"**Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"**Total Models:** {len(all_models)}",
        f"**Free Models:** {json_report['free_models']}",
        "",
        "## Summary by Provider",
        "",
        "| Provider | Total | Free | Paid |",
        "|----------|-------|------|------|",
    ]
    for prov, models in sorted(json_report["by_provider"].items()):
        free = sum(1 for m in all_models if m["provider"] == prov and m.get("is_free"))
        md_lines.append(f"| {prov} | {len(models)} | {free} | {len(models) - free} |")

    md_lines += [
        "",
        "## Models by Tier",
        "",
    ]
    for tier in ["T1-ULTRA", "T2-FAST", "T3-FREE", "T4-LOCAL"]:
        tier_models = [m for m in all_models if m.get("tier") == tier]
        if not tier_models:
            continue
        md_lines += [
            f"### {tier} ({len(tier_models)} models)",
            "",
            "| Model | Provider | Context | Role | RPM | Notes |",
            "|-------|----------|---------|------|-----|-------|",
        ]
        for m in sorted(tier_models, key=lambda x: -x.get("context_length", 0)):
            rpm = FREE_TIER_LIMITS.get(m["provider"], {}).get("rpm", "?")
            ctx = f"{m['context_length']:,}" if m['context_length'] else "?"
            md_lines.append(
                f"| `{m['model_id']}` | {m['provider']} | {ctx} | {m.get('role', '?')} | {rpm} | "
                f"{'FREE' if m.get('is_free') else 'paid'} |"
            )
        md_lines.append("")

    with open(output_dir / "models_intelligence_report.md", "w") as f:
        f.write("\n".join(md_lines))
    print(f"[INFO] Markdown report: {output_dir / 'models_intelligence_report.md'}")

    # ---- Missed opportunities ----
    # Models that are free but NOT currently in the LiteLLM config
    currently_configured = {
        "openrouter/openrouter/owl-alpha",
        "nvidia_nim/nemotron-3-ultra",
        "gemini/gemini-2.5-pro",
        "gemini/gemini-2.5-flash",
        "openai/qwen3.5-plus",
        "groq/llama-3.3-70b-versatile",
        "groq/llama-3.1-8b-instant",
        "openrouter/google/gemini-2.5-flash:free",
        "ollama/deepseek-r1:8b",
        "ollama/dolphin3",
        "ollama/nomic-embed-text",
    }

    missed = [m for m in all_models if m["model_id"] not in currently_configured and m.get("is_free")]
    missed.sort(key=lambda x: -x.get("context_length", 0))

    opp_lines = [
        "# 🔍 Missed Opportunities — Free Models Not in LiteLLM Config",
        f"**Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"**Total missed free models:** {len(missed)}",
        "",
        "These models are available at zero cost from your configured providers",
        "but are NOT currently in your `config.yml` model_list.",
        "",
        "## Top Free Models by Context Length",
        "",
        "| Model | Provider | Context | Tier | Suggested Role |",
        "|-------|----------|---------|------|----------------|",
    ]
    for m in missed[:50]:
        ctx = f"{m['context_length']:,}" if m['context_length'] else "?"
        opp_lines.append(
            f"| `{m['model_id']}` | {m['provider']} | {ctx} | {m.get('tier', '?')} | {m.get('role', '?')} |"
        )

    opp_lines += [
        "",
        "## Recommended Additions to config.yml",
        "",
        "```yaml",
        "# Suggested free model additions for LiteLLM config.yml",
    ]
    for m in missed[:20]:
        opp_lines.append(f"# - {m['model_id']}  (ctx={m['context_length']}, tier={m.get('tier', '?')})")
    opp_lines.append("```")

    with open(output_dir / "missed_opportunities.md", "w") as f:
        f.write("\n".join(opp_lines))
    print(f"[INFO] Opportunities report: {output_dir / 'missed_opportunities.md'}")

    # ---- LiteLLM config suggestions ----
    sugg_lines = [
        "# Suggested LiteLLM model additions",
        f"# Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "# Add these under model_list: in config.yml",
        "",
    ]
    for m in missed[:30]:
        ctx = m.get("context_length", 4096)
        rpm = FREE_TIER_LIMITS.get(m["provider"], {}).get("rpm", 10)
        tpm = FREE_TIER_LIMITS.get(m["provider"], {}).get("tpm", 30000)
        sugg_lines += [
            f"  # {m['model_id']} — {m.get('role', 'general')}, ctx={ctx}, free",
            f'  - model_name: {m["model_id"].split("/")[-1]}',
            f"    litellm_params:",
            f'      model: {m["model_id"]}',
        ]
        if m["provider"] == "openrouter":
            sugg_lines += [
                f"      api_base: https://openrouter.ai/api/v1",
                f'      api_key: "os.environ/OPENROUTER_KEY_1"',
            ]
        elif m["provider"] == "gemini":
            sugg_lines += [f'      api_key: "os.environ/GEMINI_API_KEY_1"']
        elif m["provider"] == "groq":
            sugg_lines += [f'      api_key: "os.environ/GROQ_API_KEY_1"']
        elif m["provider"] == "novita":
            sugg_lines += [
                f"      api_base: https://api.novita.ai/v3/openai",
                f'      api_key: "os.environ/NOVITA_API_KEY_1"',
            ]
        elif m["provider"] == "nvidia_nim":
            sugg_lines += [
                f"      api_base: https://integrate.api.nvidia.com/v1",
                f'      api_key: "os.environ/NVIDIA_NIM_KEY_1"',
            ]
        elif m["provider"] == "alibaba":
            sugg_lines += [
                f"      api_base: https://ws-3dpemgx0bzu13nbz.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
                f'      api_key: "os.environ/ALIBABA_MODELSTUDIO_KEY_1"',
            ]
        sugg_lines += [
            f"      rpm: {rpm}",
            f"      tpm: {tpm}",
            f"      order: 3",
            "",
        ]

    with open(output_dir / "litellm_model_suggestions.yml", "w") as f:
        f.write("\n".join(sugg_lines))
    print(f"[INFO] Config suggestions: {output_dir / 'litellm_model_suggestions.yml'}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("🧠 Model Intelligence Gatherer for LiteLLM Gateway")
    print("=" * 60)

    all_models: list[dict] = []

    # Fetch from all providers
    fetchers = [
        fetch_openRouter_models,
        fetch_gemini_models,
        fetch_groq_models,
        fetch_novita_models,
        fetch_nvidia_models,
        fetch_alibaba_models,
    ]
    for fetcher in fetchers:
        try:
            models = fetcher()
            all_models.extend(models)
        except Exception as e:
            print(f"[ERROR] {fetcher.__name__}: {e}", file=sys.stderr)
        time.sleep(0.5)  # Rate limit between provider calls

    if not all_models:
        print("[ERROR] No models fetched from any provider. Check API keys.", file=sys.stderr)
        sys.exit(1)

    print(f"\n[INFO] Total models collected: {len(all_models)}")
    print(f"[INFO] Free models: {sum(1 for m in all_models if m.get('is_free'))}")

    # Generate reports
    generate_reports(all_models, OUTPUT_DIR)

    print(f"\n✅ All reports saved to: {OUTPUT_DIR}")
    print("   - models_intelligence_report.md")
    print("   - models_intelligence.json")
    print("   - missed_opportunities.md")
    print("   - litellm_model_suggestions.yml")


if __name__ == "__main__":
    main()
