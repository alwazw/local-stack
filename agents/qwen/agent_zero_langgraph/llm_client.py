"""
LLM Client — connects sub-agents to LiteLLM proxy for real code generation.
Uses httpx for async HTTP calls to the OpenAI-compatible LiteLLM endpoint.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import httpx


class LLMClient:
    """Client for the LiteLLM proxy (OpenAI-compatible API)."""

    def __init__(
        self,
        base_url: str | None = None,
        api_key: str | None = None,
        model: str | None = None,
        timeout: float = 120.0,
    ):
        self.base_url = (base_url or os.environ.get("LLM_BASE_URL", "http://litellm:4000")).rstrip("/")
        self.model = model or os.environ.get("LLM_MODEL", "ollama/llama3.1:8b")
        self.timeout = timeout

        # Resolve API key: direct value > file path > env var
        if api_key:
            self.api_key = api_key
        else:
            key_file = os.environ.get("LITELLM_MASTER_KEY_FILE")
            if key_file and Path(key_file).exists():
                self.api_key = Path(key_file).read_text().strip()
            else:
                self.api_key = os.environ.get("LITELLM_MASTER_KEY", "")

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    def chat(
        self,
        messages: list[dict[str, str]],
        temperature: float = 0.3,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> dict[str, Any]:
        """Send a chat completion request to LiteLLM."""
        payload = {
            "model": model or self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

        with httpx.Client(timeout=self.timeout) as client:
            response = client.post(
                f"{self.base_url}/v1/chat/completions",
                headers=self._headers(),
                json=payload,
            )
            response.raise_for_status()
            return response.json()

    def generate_code(
        self,
        feature: str,
        context: str = "",
        language: str = "typescript",
    ) -> dict[str, Any]:
        """Generate code for a specific feature with project context."""
        system_prompt = (
            f"You are a senior {language} developer. "
            f"Generate clean, production-ready code for the described feature. "
            f"Include brief comments explaining key logic. "
            f"Return ONLY the code, no markdown fences."
        )
        user_prompt = f"Feature: {feature}\n\nContext:\n{context}\n\nGenerate the implementation."

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        try:
            result = self.chat(messages, temperature=0.2, max_tokens=4096)
            content = result["choices"][0]["message"]["content"]
            return {
                "status": "generated",
                "code": content,
                "model": result.get("model", self.model),
                "tokens_used": result.get("usage", {}).get("total_tokens", 0),
            }
        except httpx.HTTPStatusError as e:
            return {
                "status": "error",
                "error": f"HTTP {e.response.status_code}: {e.response.text[:200]}",
                "code": "",
                "tokens_used": 0,
            }
        except (httpx.ConnectError, httpx.TimeoutException) as e:
            return {
                "status": "unavailable",
                "error": f"LLM service unavailable: {type(e).__name__}",
                "code": "",
                "tokens_used": 0,
            }
        except Exception as e:
            return {
                "status": "error",
                "error": f"{type(e).__name__}: {str(e)[:200]}",
                "code": "",
                "tokens_used": 0,
            }

    def review_code(self, code: str, criteria: str = "correctness and security") -> dict[str, Any]:
        """Use LLM to review generated code."""
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a code reviewer. Analyze the provided code for "
                    f"{criteria}. Return a JSON object with keys: "
                    "approved (bool), issues (list of strings), summary (string)."
                ),
            },
            {"role": "user", "content": f"Review this code:\n\n{code}"},
        ]

        try:
            result = self.chat(messages, temperature=0.1, max_tokens=1024)
            content = result["choices"][0]["message"]["content"]
            return {
                "status": "reviewed",
                "review": content,
                "tokens_used": result.get("usage", {}).get("total_tokens", 0),
            }
        except Exception as e:
            return {
                "status": "error",
                "review": "",
                "error": f"{type(e).__name__}: {str(e)[:200]}",
                "tokens_used": 0,
            }

    def is_available(self) -> bool:
        """Quick health check against the LLM endpoint."""
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.get(
                    f"{self.base_url}/health",
                    headers=self._headers(),
                )
                # Any non-timeout response means the service is reachable
                return response.status_code < 500
        except Exception:
            return False


def get_llm_client() -> LLMClient:
    """Factory: create an LLM client from environment configuration."""
    return LLMClient()
