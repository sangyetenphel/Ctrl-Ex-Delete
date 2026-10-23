"""
Backend safety checks for Ced, independent of the model.

1. check_message(): fast, high-precision patterns on the user's latest
   message. A hit tells the model what was found (prompt.SAFETY_NOTES) and
   guarantees the crisis resources are shown, whatever the model says.
2. The model also rates every message ("risk" in its JSON reply), which
   catches indirect wording the patterns can't. chat.py combines both,
   taking the more serious of the two.
3. check_reply(): runs on the model's reply BEFORE the user sees it.
   Therapist claims, diagnoses, medication advice and promised outcomes are
   replaced with a safe fallback.

If the model can't be used (no key, limits, errors), crisis messages still
get a short, human-written reply (FALLBACK_REPLIES) plus the resources.
"""
import re
from typing import Literal

# How serious the latest message is, least to most.
Risk = Literal["none", "distress", "harm_to_others", "self_harm", "in_danger", "violence"]
RISK_ORDER: dict[str, int] = {
    "none": 0, "distress": 1, "harm_to_others": 2, "self_harm": 3, "in_danger": 3, "violence": 3,
}

# Which crisis resources the app shows under Ced's reply.
Support = Literal["crisis", "danger"]
SUPPORT_FOR_RISK: dict[str, Support] = {
    "self_harm": "crisis",     # 988 first, 911 if in immediate danger
    "in_danger": "danger",     # 911 first
    "violence": "danger",
}


def more_serious(a: str, b: str) -> str:
    return a if RISK_ORDER.get(a, 0) >= RISK_ORDER.get(b, 0) else b


def _normalize(text: str) -> str:
    text = text.lower().replace("\u2019", "'").replace("\u2018", "'")
    return re.sub(r"\s+", " ", text)


def _any(patterns: list[str], text: str) -> bool:
    return any(re.search(p, text) for p in patterns)


# ── Before the model ───────────────────────────

# Thoughts of suicide or self-harm.
_SELF_HARM = [
    r"\bsuicid",
    r"\bkill(ing)? my ?self\b",
    r"\b(hurt|harm|cut|cutting|harming|hurting) my ?self\b",
    r"\bself[- ]?harm",
    r"\b(want|wanna|going|ready) to die\b",
    r"\bwish i (was|were) dead\b",
    r"\bend (it all|my life|everything)\b",
    r"\btake my (own )?life\b",
    r"\b(don'?t|do not) want to (live|be alive|be here anymore|exist)\b",
    r"\bno (reason|point) (to|in) (live|living|going on)\b",
    r"\bbetter off (dead|without me)\b",
    r"\boverdose\b",
    r"\bkms\b",
]

# The user may be in danger from someone else.
_IN_DANGER = [
    r"\b(he|she|they|my ex) (hit|hits|choked|chokes|strangled|threatened|threatens|is stalking|keeps stalking|stalks|hurt|hurts|raped) me\b",
    r"\bafraid (he|she|they|my ex) (will|'ll|might|is going to) (hurt|kill) me\b",
    r"\b(i'?m|i am) (not safe|in danger|scared for my life)\b",
]

# Violence toward someone else.
_VIOLENCE = [
    r"\b(kill|stab|shoot|strangle|beat up|attack|hurt) (him|her|them|my ex|his new|her new)\b",
    r"\b(want|going|gonna) to (kill|hurt|attack) (him|her|them|my ex|someone)\b",
]
_NOT_VIOLENCE = [
    r"\b(don'?t|do not|never) want to hurt (him|her|them|my ex)\b",
    r"\bhurt (his|her|their) feelings\b",
]

# Stalking, monitoring, revenge, harassment, sharing private images.
_HARM_TO_OTHERS = [
    r"\bstalk(ed|ing)? (him|her|them|my ex)\b",
    r"\b(i|i've|i have|been) (been )?stalk(ed|ing)\b",
    r"\b(need|have|want) to (know|find out|see) where (he|she|they|my ex) (is|are|lives?|went)\b",
    r"\b(get|take|getting|taking) revenge\b",
    r"\bget back at (him|her|them|my ex)\b",
    r"\bmake (him|her|them|my ex) (pay|suffer|regret)\b",
    r"\b(track|trace|follow) (his|her|their|my ex'?s) (location|phone|car)\b",
    r"\bhack (into )?(his|her|their|my ex'?s)\b",
    r"\b(get into|log ?into|access) (his|her|their|my ex'?s) (account|phone|email|instagram|messages)\b",
    r"\b(leak|post|share|send out|spread) (his|her|their|my ex'?s) (nudes|private|intimate|photos|pics|secrets)\b",
    r"\b(find out|figure out) where (he|she|they|my ex) (lives?|is living|is staying)\b",
    r"\bfake (account|profile) to (message|watch|stalk|contact|follow)\b",
    r"\b(ruin|destroy) (his|her|their|my ex'?s) (life|reputation)\b",
]


def check_message(text: str) -> Risk | None:
    """The risk the patterns see in the user's message, or None."""
    t = _normalize(text)
    if _any(_SELF_HARM, t):
        return "self_harm"
    if _any(_IN_DANGER, t):
        return "in_danger"
    if _any(_VIOLENCE, t) and not _any(_NOT_VIOLENCE, t):
        return "violence"
    if _any(_HARM_TO_OTHERS, t):
        return "harm_to_others"
    return None


# Human-written replies for when the model can't be used. Short bubbles: the
# crisis resources are shown by the app right under them.
FALLBACK_REPLIES: dict[str, list[str]] = {
    "self_harm": [
        "I'm really sorry you're hurting this much. Thank you for telling me.",
        "Are you safe right now?",
        "Please reach out to someone today. You can call or text 988 below, and if "
        "you might act on these thoughts, call 911 now.",
    ],
    "in_danger": [
        "That sounds frightening, and your safety comes first.",
        "Are you somewhere safe right now? If you're in immediate danger, please call 911.",
    ],
    "violence": [
        "I can hear how much pain and anger you're carrying right now.",
        "I can't help with hurting anyone. Please step away from the situation, and "
        "if anyone is in immediate danger, call 911.",
    ],
    "harm_to_others": [
        "It makes sense that not knowing feels unbearable right now.",
        "I can't help with finding or following them, though, and checking keeps the "
        "hurt going. What's one thing that could help you feel a little steadier tonight?",
    ],
}

# The question every self-harm / danger reply must contain.
SAFETY_QUESTION = "Are you safe right now?"


# ── After the model ────────────────────────────

_UNSAFE_REPLY = [
    # Claiming to be a professional.
    r"\b(i'?m|i am) (a|your) (licensed |certified |trained )?(therapist|counsel+or|psychologist|psychiatrist|doctor|clinician)\b",
    r"\bas (a|your) (therapist|counsel+or|psychologist|psychiatrist|doctor)\b",
    # Diagnosing the user or their ex.
    r"\b(you|he|she|they|your ex) (have|has|probably have|probably has|might have|may have|clearly ha(ve|s)) "
    r"(bpd|borderline|npd|narcissistic personality|bipolar|ptsd|c-ptsd|ocd|adhd|clinical depression|"
    r"major depression|an? (anxiety|personality|attachment) disorder)\b",
    r"\b(he|she|they|your ex) (is|are|sounds like|seems like) (a )?(narcissist|sociopath|psychopath)\b",
    r"\byou('re| are) (clinically )?(depressed|bipolar)\b",
    # Medication advice.
    r"\b(take|taking|try|trying|use|using|increase|decrease|stop taking|start taking) (some |your |an |a )?"
    r"(medication|meds|antidepressants?|ssris?|sertraline|zoloft|prozac|fluoxetine|xanax|benzos?|sleeping pills|melatonin)\b",
    # Promised outcomes.
    r"\byou('ll| will) (definitely|certainly) (be fine|get over|recover|heal)\b",
    r"\bi promise (you('ll| will)|it will)\b",
]

FALLBACK_REPLY = (
    "I want to be careful here: I'm an AI companion for reflection, not a "
    "therapist or doctor, so I can't speak to diagnoses or treatment. A "
    "licensed professional can help with that. What I can do is listen. What "
    "feels hardest about this right now?"
)


def check_reply(text: str) -> str:
    """The model's reply, or a safe fallback if it crosses a boundary."""
    return FALLBACK_REPLY if _any(_UNSAFE_REPLY, _normalize(text)) else text
