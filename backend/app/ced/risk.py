"""
A second opinion on how serious a message is, from the text-chat model
(Groq), independent of whatever model is talking to the user.

Used for voice calls: the live voice model rates nothing we can check, so
each spoken turn's transcript is rated here as well as by the patterns in
safety.py. Only the transcript of that one turn is sent; nothing is stored.
"""
import json

from app.ced import providers, safety
from app.ced.providers import ChatMessage

CLASSIFIER_PROMPT = """\
You rate how serious one message is, said by someone going through a breakup. \
Reply with JSON only: {"risk": "..."} using exactly one of:
"none"           everyday conversation, or doing okay
"distress"       sad, hurt, angry, anxious, lonely, missing an ex
"self_harm"      any sign they might hurt themselves or want to die, even indirect
"in_danger"      someone is hurting, threatening or stalking THEM
"harm_to_others" stalking, monitoring, tracking, harassing or obsessively contacting someone
"violence"       wanting or planning to physically hurt someone
When unsure between two, choose the more serious one.\
"""


def classify(text: str) -> str | None:
    """The model's rating, or None if it couldn't be asked (no key, errors)."""
    if not providers.is_configured():
        return None
    try:
        # A one-word answer: a small budget keeps it from eating into the
        # shared per-minute token limit that text chat needs, and
        # temperature 0 rates the same words the same way every time.
        raw = providers.complete(
            [ChatMessage("system", CLASSIFIER_PROMPT), ChatMessage("user", text[:2000])],
            json_reply=True, max_output_tokens=300, temperature=0,
        )
        risk = json.loads(raw).get("risk")
    except (providers.ProviderRateLimited, providers.ProviderUnavailable, providers.ProviderTimeout,
            providers.ProviderError, json.JSONDecodeError, AttributeError):
        return None
    return risk if risk in safety.RISK_ORDER else None
