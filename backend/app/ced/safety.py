"""
Backend safety checks for Ced, independent of the model.

1. check_message(): runs on the user's latest message BEFORE any AI call.
   Crisis, danger and harassment messages get a fixed, human-written reply,
   and the model is never asked. Crisis replies also open the app's
   "Connect with human support" sheet.
2. check_reply(): runs on the model's reply BEFORE the user sees it. Replies
   that claim to be a therapist, diagnose someone or give medication advice
   are replaced with a safe fallback.

These are deliberately simple, high-precision patterns: they can't catch
everything, which is why the system prompt (app/ced/prompt.py) also covers
these topics. Keep the replies short, warm and honest about what Ced is.
"""
import re
from dataclasses import dataclass
from typing import Literal

Kind = Literal["crisis", "danger", "boundary"]


@dataclass(frozen=True)
class SafetyResult:
    kind: Kind
    reply: str
    show_support: bool


def _normalize(text: str) -> str:
    text = text.lower().replace("’", "'").replace("‘", "'")
    return re.sub(r"\s+", " ", text)


def _any(patterns: list[str], text: str) -> bool:
    return any(re.search(p, text) for p in patterns)


# ── Before the model ───────────────────────────

# Thoughts of suicide or self-harm.
_CRISIS = [
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
_DANGER = [
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

# Harassment, revenge, surveillance, sharing private images.
_HARASSMENT = [
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

CRISIS_REPLY = (
    "I'm really glad you told me, and I'm so sorry it's this heavy right now. "
    "You deserve support from a real person tonight. Please call or text 988 "
    "(the Suicide & Crisis Lifeline in the US) or chat at 988lifeline.org. If "
    "you might act on these thoughts or you're in danger, call 911 now. Is "
    "there someone you trust who could be with you while you reach out?"
)

DANGER_REPLY = (
    "Your safety comes first. If you're in danger right now, please call 911. "
    "The National Domestic Violence Hotline (1-800-799-7233, or text START to "
    "88788) is free, confidential and available 24/7, and 988 is there if "
    "you're struggling. You don't have to handle this alone."
)

VIOLENCE_REPLY = (
    "It sounds like a lot of pain and anger is building up, and those feelings "
    "make sense after being hurt. I can't help with hurting anyone, and I don't "
    "want you to carry the consequences of that. If you feel you might act on "
    "it, please call 988 or 911 now. Would it help to step away and talk about "
    "what's underneath the anger?"
)

BOUNDARY_REPLY = (
    "I can hear how much this hurts, and wanting them to feel some of it is a "
    "very human reaction. I can't help with getting back at them, tracking "
    "them, or sharing anything private, because it tends to hurt you most in "
    "the end. What's the feeling that's loudest for you right now?"
)


def check_message(text: str) -> SafetyResult | None:
    """A fixed reply for messages the model must not handle, else None."""
    t = _normalize(text)
    if _any(_CRISIS, t):
        return SafetyResult("crisis", CRISIS_REPLY, show_support=True)
    if _any(_DANGER, t):
        return SafetyResult("danger", DANGER_REPLY, show_support=True)
    if _any(_VIOLENCE, t) and not _any(_NOT_VIOLENCE, t):
        return SafetyResult("crisis", VIOLENCE_REPLY, show_support=True)
    if _any(_HARASSMENT, t):
        return SafetyResult("boundary", BOUNDARY_REPLY, show_support=False)
    return None


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
