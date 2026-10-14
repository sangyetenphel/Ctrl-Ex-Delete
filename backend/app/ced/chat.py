"""
One turn of a conversation with Ced.

Privacy: the conversation arrives with the request, is sent to the provider,
and is gone when the request ends. Nothing is stored or logged. Only the
latest turns are sent (MAX_TURNS / MAX_CONTEXT_CHARS), and nothing else from
the app (check-ins, scrapbook, reflections) is ever included.

Safety, in order:
1. safety.check_message() looks for clear warning signs in the latest message.
2. The model writes the reply AND rates the message itself ("risk"), which
   catches indirect wording. A pattern hit is passed to the model as a note.
3. The more serious of the two ratings decides whether crisis resources are
   shown. Self-harm and danger replies always include a direct safety question.
4. safety.check_reply() screens what the model wrote.
If the model can't be used, crisis messages still get a human-written reply
and the resources; other messages get a friendly error.
"""
import json
from uuid import UUID

from app.ced import bubbles, limits, prompt, providers, safety
from app.ced.providers import ChatMessage
from app.schemas import CedChatRequest, CedChatResponse

MAX_TURNS = 12              # the latest messages the model sees
MAX_CONTEXT_CHARS = 6_000   # about 1.5k tokens, well inside the free tier's per-minute budget

# Ratings that need a direct "are you safe right now?" in the reply.
NEEDS_SAFETY_QUESTION = {"self_harm", "in_danger"}


class InvalidConversation(ValueError):
    pass


def _context(request: CedChatRequest, flagged: str | None) -> list[ChatMessage]:
    """Ced's instructions plus the latest turns that fit the budget, oldest first."""
    kept: list[ChatMessage] = []
    total = 0
    for turn in reversed(request.messages[-MAX_TURNS:]):
        if kept and total + len(turn.content) > MAX_CONTEXT_CHARS:
            break
        kept.append(ChatMessage(turn.role, turn.content))
        total += len(turn.content)
    kept.reverse()

    system = prompt.SYSTEM_PROMPT
    # Only describe the first message as the unsent one while it's still in view.
    if request.mode == "unsent_message" and len(kept) == len(request.messages):
        system += "\n\n" + prompt.UNSENT_MESSAGE_CONTEXT
    if flagged in prompt.SAFETY_NOTES:
        system += "\n\n" + prompt.SAFETY_NOTES[flagged]
    return [ChatMessage("system", system), *kept]


def _parse(raw: str) -> tuple[list[str], str]:
    """(bubbles, risk) from the model's JSON. Plain text still works, rated "none"."""
    try:
        data = json.loads(raw)
        parts = [m for m in data.get("messages", []) if isinstance(m, str) and m.strip()]
        risk = data.get("risk")
        if parts:
            return parts, risk if risk in safety.RISK_ORDER else "none"
    except (json.JSONDecodeError, AttributeError):
        pass
    return [raw], "none"


def _response(parts: list[str], risk: str, source: str) -> CedChatResponse:
    return CedChatResponse(
        messages=bubbles.split(parts),
        risk=risk,
        support=safety.SUPPORT_FOR_RISK.get(risk),
        source=source,
    )


def _fallback(flagged: str) -> CedChatResponse:
    return _response(list(safety.FALLBACK_REPLIES[flagged]), flagged, "fallback")


def respond(installation_id: UUID, request: CedChatRequest) -> CedChatResponse:
    latest = request.messages[-1]
    if latest.role != "user":
        raise InvalidConversation("The last message must be from the user.")

    flagged = safety.check_message(latest.content)
    is_crisis = flagged in safety.SUPPORT_FOR_RISK

    # Crisis messages are always answered, even without a key, past the
    # limits, or when the provider fails.
    if not providers.is_configured():
        if is_crisis:
            return _fallback(flagged)
        raise providers.ProviderUnavailable()
    try:
        limits.take(installation_id)
        raw = providers.complete(_context(request, flagged), json_reply=True)
    except (limits.LimitReached, providers.ProviderRateLimited, providers.ProviderUnavailable,
            providers.ProviderTimeout, providers.ProviderError):
        if is_crisis:
            return _fallback(flagged)
        raise

    parts, model_risk = _parse(raw)
    risk = safety.more_serious(flagged or "none", model_risk)

    # Anything that crosses a boundary is replaced with a safe reply.
    checked = safety.check_reply(" ".join(parts))
    if checked != " ".join(parts):
        parts = list(safety.FALLBACK_REPLIES[risk]) if risk in safety.FALLBACK_REPLIES else [checked]

    # Self-harm and danger replies must ask directly about safety right now.
    if risk in NEEDS_SAFETY_QUESTION and not any("safe" in p.lower() and "?" in p for p in parts):
        parts.append(safety.SAFETY_QUESTION)

    return _response(parts, risk, "ai")
