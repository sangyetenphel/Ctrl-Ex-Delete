"""
The AI provider behind Ced. Only this file knows which company and SDK is
used; switching provider means adding a class here and setting AI_PROVIDER.
The app only ever talks to POST /ced/messages.

Message text is passed through and returned, never logged.
"""
import math
from dataclasses import dataclass
from functools import cache
from typing import Protocol

from app.config import settings


class ProviderUnavailable(Exception):
    """Not configured, or the key was rejected (the API answers 503)."""


class ProviderRateLimited(Exception):
    """The provider's own limit was hit (the API answers 429)."""

    def __init__(self, retry_after: int | None):
        super().__init__("rate limited")
        self.retry_after = retry_after


class ProviderTimeout(Exception):
    """No answer in time (the API answers 504)."""


class ProviderError(Exception):
    """Anything else that went wrong upstream (the API answers 502)."""


@dataclass(frozen=True)
class ChatMessage:
    role: str      # "system", "user" or "assistant"
    content: str


class ChatProvider(Protocol):
    def complete(self, messages: list[ChatMessage], json_reply: bool = False,
                 max_output_tokens: int | None = None, temperature: float = 0.7) -> str: ...


class GroqProvider:
    """Groq's chat completions through the official SDK."""

    def __init__(self, api_key: str, model: str):
        import groq  # imported here so the API starts even if it's missing
        import httpx

        self._groq = groq
        # No SDK retries: on a 429 it would quietly wait out Retry-After (up to
        # 60 s) while the app waits too. complete() retries once by itself.
        self._client = groq.Groq(api_key=api_key, max_retries=0,
                                 timeout=httpx.Timeout(settings.ai_timeout_seconds, connect=5))
        self._model = model

    def complete(self, messages: list[ChatMessage], json_reply: bool = False,
                 max_output_tokens: int | None = None, temperature: float = 0.7) -> str:
        g = self._groq
        extra = {"response_format": {"type": "json_object"}} if json_reply else {}
        request = dict(
            model=self._model,
            messages=[{"role": m.role, "content": m.content} for m in messages],
            max_completion_tokens=max_output_tokens or settings.ai_max_output_tokens,
            temperature=temperature,
            # gpt-oss reasons before answering. Keep it short, and don't
            # send the reasoning back: only the final answer is used.
            reasoning_effort="low",
            include_reasoning=False,
            **extra,
        )
        # One immediate second try for failures that pass on their own: a
        # dropped connection, a 5xx, or a reply Groq rejected as invalid JSON
        # ("json_validate_failed", about 1 in 8 replies with gpt-oss, answered
        # in under a second). Limits and timeouts are never retried, so the
        # app always hears back well within its own timeout.
        for attempt in range(2):
            try:
                response = self._client.chat.completions.create(**request)
                break
            except g.RateLimitError as error:
                raise ProviderRateLimited(_retry_after(error.response)) from None
            except (g.AuthenticationError, g.PermissionDeniedError):
                raise ProviderUnavailable() from None
            except g.APITimeoutError:
                raise ProviderTimeout() from None
            except (g.APIConnectionError, g.InternalServerError) as error:
                if attempt:
                    raise ProviderError(type(error).__name__) from None
            except g.BadRequestError as error:
                if attempt or _error_code(error) != "json_validate_failed":
                    raise ProviderError(type(error).__name__) from None
            except g.APIError as error:
                raise ProviderError(type(error).__name__) from None

        text = (response.choices[0].message.content or "").strip() if response.choices else ""
        if not text:
            raise ProviderError("empty reply")
        return text


def _error_code(error) -> str | None:
    """Groq's error code, e.g. "json_validate_failed" (the body never holds user text we log)."""
    body = error.body if isinstance(error.body, dict) else {}
    inner = body.get("error", body)
    return inner.get("code") if isinstance(inner, dict) else None


def _retry_after(response) -> int | None:
    """Whole seconds from a Retry-After header; None if missing or not a number (it can be a date)."""
    value = response.headers.get("retry-after") if response is not None else None
    try:
        return max(1, math.ceil(float(value))) if value else None
    except ValueError:
        return None


@cache
def _provider() -> ChatProvider:
    if settings.ai_provider == "groq":
        if not settings.groq_api_key:
            raise ProviderUnavailable()
        return GroqProvider(settings.groq_api_key, settings.ai_model)
    raise ProviderUnavailable()


def is_configured() -> bool:
    return settings.ai_provider == "groq" and bool(settings.groq_api_key)


def complete(messages: list[ChatMessage], json_reply: bool = False,
             max_output_tokens: int | None = None, temperature: float = 0.7) -> str:
    return _provider().complete(messages, json_reply=json_reply,
                                max_output_tokens=max_output_tokens, temperature=temperature)
