"""
One turn of a conversation with Ced.

Privacy: the conversation arrives with the request, is sent to the provider,
and is gone when the request ends. Nothing is stored or logged. Only the
latest turns are sent (MAX_TURNS / MAX_CONTEXT_CHARS), and nothing else from
the app (check-ins, scrapbook, reflections) is ever included.

Safety, in order:
1. safety.assess() reads the latest message (and Ced's turn before it, for
   answers to a safety question). Clear warning signs are "certain"; unclear
   ones ("I'm thinking about ending it") need a gentle check.
2. The model writes the reply AND rates the message itself ("risk"), which
   catches indirect wording. Findings are passed to it as notes: a hint for
   its own rating, never an order to copy.
3. safety.combine(): the model may raise a rating, never lower a certain
   one, and certain findings always keep their crisis resources.
   Self-harm and danger replies always include a direct safety question;
   unclear findings always get at least one gentle question.
4. safety.check_reply() screens what the model wrote.
If the model can't be used (no key, limits, provider or database errors),
messages with a safety finding still get a human-written reply and the
resources; ordinary messages get a friendly error.
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


def _assess(request: CedChatRequest) -> safety.Assessment:
    """The safety findings for the latest message, read with the turn before it."""
    *earlier, latest = request.messages
    previous_ced = earlier[-1].content if earlier and earlier[-1].role == "assistant" else None
    earlier_user = [t.content for t in reversed(earlier[-MAX_TURNS:]) if t.role == "user"]
    return safety.assess(latest.content, previous_ced, earlier_user)


def _context(request: CedChatRequest, assessment: safety.Assessment) -> list[ChatMessage]:
    """Ced's instructions plus the latest turns that fit the budget, oldest first."""
    kept: list[ChatMessage] = []
    total = 0
    for turn in reversed(request.messages[-MAX_TURNS:]):
        if kept and total + len(turn.content) > MAX_CONTEXT_CHARS:
            break
        # Ced's earlier turns go back in the JSON shape it must answer in, one
        # item per bubble (the app joins bubbles with a blank line). As plain
        # text the model copies them and answers in plain text, which Groq's
        # JSON mode rejects (most second replies failed that way).
        content = (json.dumps({"messages": [b.strip() for b in turn.content.split("\n\n") if b.strip()]},
                              ensure_ascii=False)
                   if turn.role == "assistant" else turn.content)
        kept.append(ChatMessage(turn.role, content))
        total += len(turn.content)
    kept.reverse()

    system = prompt.SYSTEM_PROMPT
    # Only describe the first message as the unsent one while it's still in view.
    if request.mode == "unsent_message" and len(kept) == len(request.messages):
        system += "\n\n" + prompt.UNSENT_MESSAGE_CONTEXT
    notes = [prompt.SAFETY_NOTES[n] for n in assessment.notes if n in prompt.SAFETY_NOTES]
    if notes:
        system += "\n\n" + "\n\n".join(notes) + "\n\n" + prompt.RISK_HINT
    return [ChatMessage("system", system), *kept]


def _parse(raw: str) -> tuple[list[str], str]:
    """
    (bubbles, risk) from the model's JSON. Plain text still works, rated
    "none". JSON without any message is a failed reply, never shown as is.
    """
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return [raw], "none"
    if isinstance(data, str) and data.strip():
        return [data], "none"
    messages = data.get("messages") if isinstance(data, dict) else None
    parts = [m for m in messages if isinstance(m, str) and m.strip()] if isinstance(messages, list) else []
    if not parts:
        raise providers.ProviderError("no messages in the reply")
    risk = data.get("risk")
    return parts, risk if risk in safety.RISK_ORDER else "none"


def _response(parts: list[str], risk: str, support: safety.Support | None, source: str) -> CedChatResponse:
    return CedChatResponse(messages=bubbles.split(parts), risk=risk, support=support, source=source)


def _fallback(assessment: safety.Assessment) -> CedChatResponse:
    """A human-written reply with the resources, for when the model can't answer."""
    signal = assessment.fallback
    if signal.certain:
        parts, support = safety.FALLBACK_REPLIES[signal.risk], assessment.certain_support
    else:
        # Unclear: a gentle question rather than an assumption, resources in reach.
        parts, support = safety.FALLBACK_FOR_NOTE[signal.note], safety.SUPPORT_FOR_RISK.get(signal.risk)
    return _response(list(parts), signal.risk, support, "fallback")


def respond(installation_id: UUID, request: CedChatRequest) -> CedChatResponse:
    latest = request.messages[-1]
    if latest.role != "user":
        raise InvalidConversation("The last message must be from the user.")

    assessment = _assess(request)
    # Safety findings are always answered, even without a key, past the
    # limits, or when the provider or the database fails. Ordinary messages
    # get the usual errors.
    needs_answer = assessment.fallback is not None

    if not providers.is_configured():
        if needs_answer:
            return _fallback(assessment)
        raise providers.ProviderUnavailable()
    try:
        limits.take(installation_id)
        parts, model_risk = _parse(providers.complete(_context(request, assessment), json_reply=True))
    except Exception:
        if needs_answer:
            return _fallback(assessment)
        raise

    risk, support = safety.combine(assessment, model_risk)

    # Anything that crosses a boundary is replaced with a safe reply.
    checked = safety.check_reply(" ".join(parts))
    if checked != " ".join(parts):
        parts = list(safety.FALLBACK_REPLIES[risk]) if risk in safety.FALLBACK_REPLIES else [checked]

    if risk in NEEDS_SAFETY_QUESTION:
        # Self-harm and danger replies must ask directly about safety right now.
        if not safety.asks_about_safety(parts):
            parts.append(safety.SAFETY_QUESTION)
    else:
        # Unclear findings are never treated as settled without a question.
        check_in = next((safety.CHECK_IN_QUESTIONS[n] for n in assessment.notes if n in safety.CHECK_IN_QUESTIONS), None)
        if check_in and not any("?" in p for p in parts):
            parts.append(check_in)

    return _response(parts, risk, support, "ai")
