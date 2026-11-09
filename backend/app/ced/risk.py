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
You rate how serious one spoken message is, said by someone going through a \
breakup. Sometimes you also get the companion's question just before it: then \
rate the answer in that context ("not really" to "are you safe?" is serious). \
Reply with JSON only: {"risk": "..."} using exactly one of:
"none"           everyday conversation, or doing okay
"distress"       sad, hurt, angry, anxious, lonely, missing an ex; emotional hurt \
("she hurt me so much"), venting ("I could kill him lol"), self-blame ("I think I \
hurt her"), ordinary injuries ("I hurt myself at the gym"); stalking, threats to \
share private images, controlling behaviour or past abuse with no immediate \
physical threat (still serious)
"self_harm"      any sign they might hurt themselves or want to die, even indirect \
("I can't do this anymore", "no one would miss me", giving belongings away), \
unless it's clearly about something else or a figure of speech about something \
ordinary ("this commute makes me want to die")
"in_danger"      THEY may be in physical danger from someone now: it's happening, \
just happened, or they fear it's about to (hurt, threatened with violence, can't \
leave, the person is outside)
"harm_to_others" THEY are stalking, monitoring, tracking, harassing or obsessively contacting someone
"violence"       they want or plan to physically hurt someone and seem to mean it
When unsure between self_harm and a milder rating, choose self_harm.\
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
