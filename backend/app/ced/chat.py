"""
One turn of a conversation with Ced.

Privacy: the conversation arrives with the request, is sent to the provider,
and is gone when the request ends. Nothing is stored or logged. Only the
latest turns are sent (MAX_TURNS / MAX_CONTEXT_CHARS), and nothing else from
the app (check-ins, scrapbook, reflections) is ever included.
"""
from uuid import UUID

from app.ced import limits, prompt, providers, safety
from app.ced.providers import ChatMessage
from app.schemas import CedChatRequest, CedChatResponse

MAX_TURNS = 12              # the latest messages the model sees
MAX_CONTEXT_CHARS = 6_000   # about 1.5k tokens, well inside the free tier's per-minute budget


class InvalidConversation(ValueError):
    pass


def _context(request: CedChatRequest) -> list[ChatMessage]:
    """The latest turns that fit the budget, oldest first."""
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
    return [ChatMessage("system", system), *kept]


def respond(installation_id: UUID, request: CedChatRequest) -> CedChatResponse:
    latest = request.messages[-1]
    if latest.role != "user":
        raise InvalidConversation("The last message must be from the user.")

    # Safety first: these never reach the model, and never count against limits.
    flagged = safety.check_message(latest.content)
    if flagged:
        return CedChatResponse(reply=flagged.reply, kind=flagged.kind, show_support=flagged.show_support)

    if not providers.is_configured():
        raise providers.ProviderUnavailable()
    limits.take(installation_id)

    reply = providers.complete(_context(request))
    return CedChatResponse(reply=safety.check_reply(reply), kind="ai", show_support=False)
