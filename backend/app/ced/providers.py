"""
The AI provider behind Ced. Only this file knows which company and SDK is
used; switching provider means adding a class here and setting AI_PROVIDER.
The app only ever talks to POST /ced/messages.

Message text is passed through and returned, never logged.
"""
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
    def complete(self, messages: list[ChatMessage]) -> str: ...


class GroqProvider:
    """Groq's chat completions through the official SDK."""

    def __init__(self, api_key: str, model: str):
        import groq  # imported here so the API starts even if it's missing

        self._groq = groq
        # One quick retry for dropped connections; never loops on limits.
        self._client = groq.Groq(api_key=api_key, timeout=settings.ai_timeout_seconds, max_retries=1)
        self._model = model

    def complete(self, messages: list[ChatMessage]) -> str:
        g = self._groq
        try:
            response = self._client.chat.completions.create(
                model=self._model,
                messages=[{"role": m.role, "content": m.content} for m in messages],
                max_completion_tokens=settings.ai_max_output_tokens,
                temperature=0.7,
                # gpt-oss reasons before answering. Keep it short, and don't
                # send the reasoning back: only the final answer is used.
                reasoning_effort="low",
                include_reasoning=False,
            )
        except g.RateLimitError as error:
            retry_after = error.response.headers.get("retry-after") if error.response else None
            raise ProviderRateLimited(int(float(retry_after)) if retry_after else None) from None
        except (g.AuthenticationError, g.PermissionDeniedError):
            raise ProviderUnavailable() from None
        except g.APITimeoutError:
            raise ProviderTimeout() from None
        except g.APIError as error:
            raise ProviderError(type(error).__name__) from None

        text = (response.choices[0].message.content or "").strip() if response.choices else ""
        if not text:
            raise ProviderError("empty reply")
        return text


@cache
def _provider() -> ChatProvider:
    if settings.ai_provider == "groq":
        if not settings.groq_api_key:
            raise ProviderUnavailable()
        return GroqProvider(settings.groq_api_key, settings.ai_model)
    raise ProviderUnavailable()


def is_configured() -> bool:
    return settings.ai_provider == "groq" and bool(settings.groq_api_key)


def complete(messages: list[ChatMessage]) -> str:
    return _provider().complete(messages)
