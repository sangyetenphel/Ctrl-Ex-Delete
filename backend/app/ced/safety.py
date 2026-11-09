"""
Backend safety checks for Ced, independent of the model.

1. assess(): patterns on the user's latest message, read clause by clause,
   plus the turn before it when Ced had just asked a safety question. Each
   finding is a Signal:
   - certain: a clear warning sign ("I want to end my life", "he hit me",
     "I'm being stalked", a "no" to "are you safe?"). It guarantees the crisis
     resources and can't be lowered by the model.
   - possible: worth a gentle check but not a verdict ("I'm thinking about
     ending it" might mean the relationship; "he used to hit me" is past;
     "I could kill him lol" is usually venting). The model is told what to
     ask about and decides; if the model can't be reached, the person still
     gets a gentle question and the resources.
   Emotional pain ("she hurt me so much"), self-blame ("I think I hurt her")
   and being a victim ("I've been stalked") are kept apart from danger,
   violence and stalking someone else.
2. The model rates every message too ("risk" in its JSON reply), which
   catches wording the patterns can't. combine() decides: the model may
   raise a rating or re-label it at the same level, never lower a certain one.
3. check_reply(): runs on the model's reply BEFORE the user sees it.
   Therapist claims, diagnoses, medication advice and promised outcomes are
   replaced with a safe fallback.

Voice calls use check_message(), which reports certain findings only.
"""
import re
from dataclasses import dataclass, field
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
    "in_danger": "danger",     # 911 first (the card still has 988)
    "violence": "danger",
}
_SUPPORT_URGENCY = {None: 0, "crisis": 1, "danger": 2}


def more_serious(a: str, b: str) -> str:
    return a if RISK_ORDER.get(a, 0) >= RISK_ORDER.get(b, 0) else b


def more_urgent(a: Support | None, b: Support | None) -> Support | None:
    return a if _SUPPORT_URGENCY[a] >= _SUPPORT_URGENCY[b] else b


def _normalize(text: str) -> str:
    text = text.lower().replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text).strip()


def _any(patterns: list[str], text: str) -> bool:
    return any(re.search(p, text) for p in patterns)


# ── Findings ───────────────────────────────────

@dataclass(frozen=True)
class Signal:
    risk: Risk        # the kind of risk: self_harm, in_danger, violence or harm_to_others
    certain: bool     # clear warning sign (True) or needs a gentle check (False)
    note: str         # which prompt.SAFETY_NOTES entry tells the model about it


@dataclass(frozen=True)
class Assessment:
    signals: tuple[Signal, ...] = field(default_factory=tuple)

    @property
    def certain(self) -> list[Signal]:
        return [s for s in self.signals if s.certain]

    @property
    def floor(self) -> Signal | None:
        """The most serious certain finding (the first one found, on a tie)."""
        best = None
        for s in self.certain:
            if best is None or RISK_ORDER[s.risk] > RISK_ORDER[best.risk]:
                best = s
        return best

    @property
    def certain_support(self) -> Support | None:
        support = None
        for s in self.certain:
            support = more_urgent(support, SUPPORT_FOR_RISK.get(s.risk))
        return support

    @property
    def notes(self) -> list[str]:
        return list(dict.fromkeys(s.note for s in self.signals))

    @property
    def fallback(self) -> Signal | None:
        """What a fixed reply must answer when the model can't be reached, or None."""
        if self.floor and self.floor.risk in SUPPORT_FOR_RISK:
            return self.floor
        for s in self.signals:
            if s.note in FALLBACK_FOR_NOTE:
                return s
        return None


def combine(assessment: Assessment, model_risk: str) -> tuple[str, Support | None]:
    """
    (risk, support) from the patterns and the model's own rating. The model
    can raise a rating or re-label it at the same level (e.g. self_harm for
    a message the patterns read as danger), but can't lower a certain
    finding. Support is the most urgent of the two, so a clear warning sign
    always keeps its resources.
    """
    floor = assessment.floor
    if floor is None or RISK_ORDER.get(model_risk, 0) >= RISK_ORDER[floor.risk]:
        risk = model_risk
    else:
        risk = floor.risk
    return risk, more_urgent(assessment.certain_support, SUPPORT_FOR_RISK.get(risk))


# ── Language helpers ───────────────────────────

# People other than the user, as the subject of a sentence.
_SUBJ = (r"(?:he|she|they|someone|somebody|my ex|my ex-?(?:boyfriend|girlfriend|husband|wife|partner)"
         r"|my (?:boyfriend|girlfriend|bf|gf|husband|wife|partner|fianc[eé]e?|date)|this (?:guy|girl|person))")
# Someone the user might hurt.
_TARGET = (r"(?:him|her|them|my ex|his new \w+|her new \w+|their new \w+|that (?:guy|girl|person|\w+)"
           r"|the (?:guy|girl|person) (?:he|she|they)'?(?:s|re|'s)? (?:with|seeing|dating)|someone|somebody)")
_FIRST_PERSON = re.compile(r"\b(?:i|i'm|im|i've|i'd|i'll|me|myself)\b")
_THIRD_PERSON = re.compile(rf"\b{_SUBJ}\b|\b(?:my|his|her) (?:friend|mom|dad|brother|sister|roommate|cousin)\b")

# "not", "never", "don't want to", "I'd never even"... right before a phrase.
_NEGATION = re.compile(
    r"\b(?:not|never|no longer|don'?t|do not|didn'?t|won'?t|wouldn'?t|isn'?t|ain'?t|nothing like)"
    r"(?: (?:want|wanna|to|ever|even|really|plan|planning|going|gonna|intend|try|trying|would|actually|"
    r"think|thinking|feel|i|i'd|i'll|about|of|on|be|been|anything)){0,3} ?$"
)
# Things that put a sentence in the past.
_PAST = re.compile(r"\b(?:used to|years ago|a year ago|last year|in (?:high school|middle school|college)"
                   r"|when i was (?:younger|little|a kid|a teen|a teenager|in)|as a (?:kid|teen|teenager)"
                   r"|back then|in the past|when we were together|before we broke up)\b")
_PRESENT = re.compile(r"\b(?:again|now|lately|these days|tonight|today|recently|still|this week|right now|anymore)\b")
# Phrases that mention self-harm words but aren't about the user.
_BENIGN = re.compile(r"\bsuicide (?:prevention|awareness|hotline|lifeline|squad|walk)\b|\b988\b"
                     r"|\bkill(?:ing)? myself laughing\b")


def _clauses(text: str) -> list[str]:
    parts = re.split(r"[.!?;\n]+|,\s*(?=but\b)|\s+but\s+|\s+-\s+", text)
    return [p.strip(" ,") for p in parts if p.strip(" ,")]


def _hits(patterns: list[str], clause: str) -> list[re.Match]:
    return [m for p in patterns for m in re.finditer(p, clause)]


def _negated(clause: str, match: re.Match) -> bool:
    return bool(_NEGATION.search(clause[:match.start()]))


def _is_past(clause: str) -> bool:
    return bool(_PAST.search(clause)) and not _PRESENT.search(clause)


def _about_someone_else(clause: str, match: re.Match) -> bool:
    """Said about another person ("I think my ex is suicidal"), not the user:
    the nearest subject before the phrase is someone else."""
    before = clause[:match.start()]
    third = [m.end() for m in _THIRD_PERSON.finditer(before)]
    first = [m.end() for m in _FIRST_PERSON.finditer(_THIRD_PERSON.sub(lambda m: " " * len(m.group()), before))]
    return bool(third) and (not first or third[-1] > first[-1])


# ── Self-harm ──────────────────────────────────

# Clear signs, in the user's own words.
_SELF_HARM = [
    r"\bkill(?:ing)? my ?self\b",
    r"\bkms\b",
    r"\bunalive(?: my ?self)?\b",
    r"\b(?:hurt|harm|cut|cutting|harming|hurting|burn|burning|starve|starving) my ?self\b",
    r"\bself[- ]?harm",
    r"(?<!makes me )(?<!made me )(?<!making me )\b(?:(?:want|going|ready|plan|planning) to|wanna|gonna) die\b(?! (?:of|from|laughing|alone|happy|old|for|when|if|on|in a))",
    r"\bwish i (?:was|were|could be) dead\b",
    r"\bwish i (?:could|would) (?:just )?die\b",
    r"\bend (?:it all|my life|everything)\b|\bending (?:it all|my life|everything)\b",
    r"\btake my (?:own )?life\b",
    r"\b(?:don'?t|do not) (?:want|wanna) to (?:live|be alive|be here any ?more|exist|wake up)\b",
    r"\b(?:don'?t|do not) (?:want|wanna) (?:to )?wake up\b",
    r"\b(?:fall asleep|go to sleep|sleep) and (?:never|not) wake up\b",
    r"\bno (?:reason|point) (?:to|in) (?:live|living|going on|being alive)\b",
    r"\bbetter off (?:dead|without me)\b",
    r"\btired of (?:living|being alive|life)\b",
    r"\b(?:saving|saved|stockpil\w*|hoard\w*|collecting|stashing|stashed)(?: up)?(?: (?:some|all|my|a bunch of|enough))? "
    r"(?:pills|meds|medication|medicine|sleeping pills|tablets)\b",
    r"\b(?:pills|meds|tablets) (?:saved|stashed|ready)\b|\benough (?:pills|meds) to\b",
    r"\b(?:want|going|gonna|plan|planning|thinking about|thinking of|about) to (?:overdose|od)\b|\bthinking (?:about|of) overdosing\b",
    r"\bnot safe (?:with|from|around) (?:myself|me|my (?:own )?(?:thoughts|mind|head))\b",
    r"\b(?:don'?t|do not) (?:feel|trust) (?:safe )?(?:with|around) myself\b",
]
# "suicide"/"suicidal" is clear unless it's about someone else or negated.
_SUICIDE = [r"\bsuicid(?:e|al)\b"]

# Worth a gentle question, not a verdict.
_MAYBE_SELF_HARM = [
    # "ending it" can mean the relationship.
    r"\b(?:want(?:ed)? to|wanna|going to|gonna|thinking (?:about|of)|think about|thought about|ready to|might|"
    r"plan(?:ning)? (?:to|on)|considering|about to|i'?ll|i will|i should|should i|just) (?:just )?(?:end|ending) it\b(?! all)(?! (?:with|off|between))",
    r"\bcan'?t (?:do this|take (?:it|this)) any ?more\b|\bcan'?t (?:go on|keep going)\b|\bcan'?t do this much longer\b",
    r"\b(?:want|wanna|wish i could|just want) to disappear\b|\bwish i could just disappear\b",
    r"\b(?:want|wish) (?:it|everything|it all|the pain) (?:all )?(?:to|would) (?:stop|end)\b",
    r"\b(?:no ?one|nobody) would (?:miss|notice|care)\b",
    r"\bgiving (?:away )?my (?:stuff|things|belongings)(?: away)?\b",
    r"\bwhat'?s the point (?:of|in) (?:anything|any of this|life|living|going on|trying)\b",
    r"\b(?:don'?t|do not) (?:want|wanna) to be here\b",
    r"\bsleep forever\b",
    r"\b(?:i'?m|i am) (?:so )?(?:done|finished) with (?:everything|life|it all)\b",
    r"\boverdos(?:e|ed|ing)\b",
    # Often a figure of speech ("this commute makes me want to die").
    r"\b(?:makes|made|making) me (?:want|wanna) (?:to )?die\b",
]

# Someone else threatening to hurt themselves ("he says he'll kill himself if I leave").
_SOMEONE_ELSE_SELF_HARM = [
    r"\b(?:kill|hurt|harm|cut|end) (?:himself|herself|themselves|themself|his life|her life|their life)\b",
]


def _self_harm(clause: str) -> list[Signal]:
    if _BENIGN.search(clause):
        clause = _BENIGN.sub(" ", clause)
    found: list[Signal] = []
    clear = _hits(_SELF_HARM, clause)
    clear += [m for m in _hits(_SUICIDE, clause) if not _about_someone_else(clause, m)]
    affirmed = [m for m in clear if not _negated(clause, m)]
    if affirmed:
        if _is_past(clause):
            found.append(Signal("self_harm", False, "past_self_harm"))
        else:
            found.append(Signal("self_harm", True, "self_harm"))
    elif clear:
        found.append(Signal("self_harm", False, "denied_self_harm"))
    maybe = [m for m in _hits(_MAYBE_SELF_HARM, clause) if not _negated(clause, m)]
    if maybe and not affirmed:
        found.append(Signal("self_harm", False, "past_self_harm" if _is_past(clause) else "possible_self_harm"))
    others = _hits(_SOMEONE_ELSE_SELF_HARM, clause)
    others += [m for m in _hits(_SUICIDE, clause) if _about_someone_else(clause, m)]
    if others:
        found.append(Signal("self_harm", False, "someone_else_at_risk"))
    return found


# ── The user in danger from someone ────────────

_PHYSICAL = (r"(?:hit|hits|hitting|punched|punches|slapped|slaps|kicked|kicks|choked|chokes|choking|strangled|"
             r"strangles|shoved|shoves|pushed|pushes|grabbed|grabs|beat|beats|beating|raped|rapes|assaulted|"
             r"assaults|sexually assaulted|attacked|attacks|threw (?:something|stuff|things|a \w+) at)")
_DANGER = [
    rf"\b{_SUBJ} (?:just |has |had |keeps |kept |always |still |sometimes |used to |would |)?{_PHYSICAL} me\b(?! (?:away|to\b|at\b|in\b|off|out of|up\b|with\b))",
    rf"\b{_SUBJ} (?:threatened|threatens|is threatening|keeps threatening|has threatened) me\b",
    rf"\b{_SUBJ} (?:threatened|threatens|is threatening|keeps threatening|has threatened) to (?:kill|hurt|beat|shoot|stab|"
    r"post|share|leak|send|release|expose)\b",
    rf"\b{_SUBJ} (?:said|says|told me)(?: that)? (?:he|she|they)(?:'d|'ll| would| will| is going to| was going to) "
    r"(?:kill|hurt|beat|shoot|stab) me\b",
    rf"\b{_SUBJ} (?:posted|leaked|shared|sent out|is sharing|is posting) (?:my|our) (?:nudes|intimate|private) ",
    rf"\bafraid {_SUBJ} (?:will|'ll|might|is going to|could) (?:hurt|kill|find|come after) me\b",
    rf"\bscared {_SUBJ} (?:will|'ll|might|is going to|could) (?:hurt|kill|find|come after) me\b",
    r"\b(?:i'?m|i am) (?:not safe|in danger|scared for my life|afraid for my life)\b"
    r"(?! (?:with|from|around) (?:myself|me|my (?:own )?(?:thoughts|mind|head)))",
    # Stalked, followed, tracked or harassed: the user is the one being watched.
    r"\b(?:i'?m|i am|i'?ve been|i have been|been|being) (?:being )?(?:stalked|followed|tracked|harassed)\b(?! (?:on|back|by (?:a|an|some) (?:account|page|bot)))",
    rf"\b{_SUBJ}(?: is|'s| are| keeps| kept| has been|'s been| have been| won'?t stop| been| started)(?: always)? "
    r"(?:stalking|following|tracking|harassing|watching) me\b(?! (?:on|back))",
    rf"\b{_SUBJ} (?:stalks|follows|tracks|harasses|stalked|tracked|harassed) me\b(?! (?:on|back))",
    rf"\b{_SUBJ} (?:keeps |kept |)(?:showing|shows|showed) up (?:at|outside) my\b",
    r"\b(?:keeps|kept) showing up (?:at|outside) my\b|\bshows up (?:at|outside) my (?:house|home|apartment|place|door|work|job|dorm)\b",
    rf"\b{_SUBJ}(?: is|'s) (?:outside|at|parked outside) my (?:house|home|apartment|place|door|work|job|dorm|window|car)\b",
    rf"\b{_SUBJ} (?:put|installed|hid|is using|has) (?:a |an )?(?:tracker|airtag|tracking app|spyware)\b",
    rf"\b{_SUBJ} (?:won'?t|will not|doesn'?t|does not) let me (?:leave|go)\b",
    rf"\b{_SUBJ} (?:locked|locks|is locking) me (?:in|out)\b",
]
# Hurt that may be physical: only a sign of danger with a physical detail.
_HURT_ME = rf"\b{_SUBJ} (?:physically )?(?:hurt|hurts|hurting|injured) me\b"
_PHYSICAL_DETAIL = re.compile(r"\b(?:physically|bruises?|bruised|bleeding|blood|hospital|black eye|marks on|"
                              r"broke my|sprained|choke|choking)\b")
# Unclear: needs a gentle check.
_MAYBE_DANGER = [
    r"\b(?:i )?(?:don'?t|do not) feel safe\b(?! (?:with|around) myself)",
    rf"\b(?:i'?m|i am) (?:scared|afraid|terrified) (?:of {_SUBJ}|to go home|to leave)\b",
    rf"\b{_SUBJ} (?:still )?(?:has|is tracking|tracks|checks|is checking|can see) my location\b",
]


def _danger(clause: str) -> list[Signal]:
    hits = [m for m in _hits(_DANGER, clause) if not _negated(clause, m)]
    hurt = [m for m in re.finditer(_HURT_ME, clause) if not _negated(clause, m)]
    if hurt and _PHYSICAL_DETAIL.search(clause):
        hits += hurt
    if hits:
        return [Signal("in_danger", False, "past_danger")] if _is_past(clause) else [Signal("in_danger", True, "in_danger")]
    if [m for m in _hits(_MAYBE_DANGER, clause) if not _negated(clause, m)]:
        return [Signal("in_danger", False, "possible_danger")]
    return []


# ── Violence toward someone else ───────────────

_INTENT = (r"(?:i'?m going to|i'?m gonna|im gonna|i will|i'?ll|i'?m about to|i plan to|i'?m planning to|"
           r"going to|gonna|want to|wanna|i want to|ready to)")
_VIOLENCE = [
    rf"\b{_INTENT} (?:kill|stab|shoot|strangle|murder|beat up|run over|attack|physically hurt) {_TARGET}\b",
    rf"\b{_INTENT} (?:beat|punch|hit|slap) {_TARGET}\b",
    r"\b(?:bought|got|have|grabbed|brought|loaded) (?:a |my |the )?(?:gun|knife|weapon)\b.*\b(?:him|her|them|my ex)\b",
]
_MAYBE_VIOLENCE = [
    # Usually venting ("I could kill him lol", "I want to hurt him like he hurt me").
    rf"\bi(?: could|'d| would)? (?:literally |honestly |actually |seriously )?(?:kill|murder|strangle|punch|slap) {_TARGET}\b",
    rf"\b{_INTENT} hurt {_TARGET}\b",
    r"\b(?:wish|hope) (?:he|she|they|my ex) (?:dies|would die|gets hurt|got hurt)\b",
]


def _violence(clause: str) -> list[Signal]:
    if [m for m in _hits(_VIOLENCE, clause) if not _negated(clause, m)]:
        return [Signal("violence", True, "violence")]
    if [m for m in _hits(_MAYBE_VIOLENCE, clause) if not _negated(clause, m)]:
        return [Signal("violence", False, "possible_violence")]
    return []


# ── Stalking, monitoring, revenge (the user doing it) ──

_HARM_TO_OTHERS = [
    r"\bstalk(?:ed|ing)? (?:him|her|them|my ex|his|her|their)\b",
    r"\b(?:i|i'?ve|i have|i'?ve been|i have been|been|i'?m|im|i am|i keep|keep) (?:been )?"
    r"(?:stalking|tracking|monitoring) (?:him|her|them|my ex|his|her|their)\b",
    r"\b(?:need|have|want|got) to (?:know|find out|see) where (?:he|she|they|my ex) (?:is|are|lives?|went|is staying)\b",
    r"\b(?:get|take|getting|taking) revenge\b",
    r"\bget back at (?:him|her|them|my ex)\b",
    r"\bmake (?:him|her|them|my ex) (?:pay|suffer|regret)\b",
    r"\b(?:track|trace|follow|check|checking|look at|looking at|looked at|checked|watch|watching) (?:his|her|their|my ex'?s) "
    r"(?:location|phone|car|find my)\b",
    r"\bhack (?:into )?(?:his|her|their|my ex'?s)\b",
    r"\b(?:get into|log ?into|access|read|go through) (?:his|her|their|my ex'?s) (?:account|phone|email|instagram|messages|texts|dms)\b",
    r"\b(?:leak|post|share|send out|spread) (?:his|her|their|my ex'?s) (?:nudes|private|intimate|photos|pics|secrets)\b",
    r"\b(?:find out|figure out) where (?:he|she|they|my ex) (?:lives?|is living|is staying)\b",
    r"\bfake (?:account|profile|insta|instagram|page) to (?:message|watch|stalk|contact|follow|see|view|look at|check)\b",
    r"\b(?:ruin|destroy) (?:his|her|their|my ex'?s) (?:life|reputation)\b",
    r"\b(?:going to|gonna|will|i'?ll|want to|wanna|thinking (?:about|of)|about to) (?:show up|go|drive|turn up) "
    r"(?:at|to|over to|outside) (?:his|her|their|my ex'?s) (?:place|house|home|apartment|work|job|door|dorm)\b",
]
# Wanting to know where someone is in order to stay safe isn't stalking.
_STAYING_SAFE = re.compile(r"\b(?:avoid|stay away|safe|scared|afraid|so i can leave|so i don'?t run into)\b")


def _harm_to_others(clause: str) -> list[Signal]:
    hits = [m for m in _hits(_HARM_TO_OTHERS, clause) if not _negated(clause, m)]
    if hits and not _STAYING_SAFE.search(clause):
        return [Signal("harm_to_others", True, "harm_to_others")]
    return []


# ── Answers to Ced's safety question ───────────

_ASKS_SAFE = re.compile(r"\b(?:are|do|will|would) you (?:feel(?:ing)? )?safe\b"
                        r"|\bsafe (?:right now|tonight|where you are|at home|now)\b|\byou(?:'re| are) safe\b")
_ASKS_THOUGHTS = re.compile(
    r"\b(?:hurt(?:ing)? yourself|harm(?:ing)? yourself|kill(?:ing)? yourself|end(?:ing)? your life|suicid\w*|"
    r"not wanting to (?:be alive|live|be here)|thoughts of (?:dying|death|not being here)|want to die)\b"
)
_YES = re.compile(r"^(?:yes|yeah|yea|yep|yup|ya|yh|i do|i am|i have|i guess|kind of|kinda|sort of|sorta|a little|"
                  r"a bit|sometimes|maybe|i think so|probably|honestly yes|mhm|uh huh|true|definitely|i mean yes)\b")
_NO = re.compile(r"^(?:no|nope|nah|not really|not exactly|not at all|never|i'?m not|i am not)\b")
_UNSURE = re.compile(r"^(?:i don'?t know|idk|i'?m not sure|not sure|dunno|maybe|kind of|kinda|sort of|i guess|"
                     r"hard to say|i can'?t say|honestly i don'?t know)\b")
_SAFE_NOW = re.compile(r"\b(?:i'?m|i am|i feel|i'?ll be) (?:safe|okay|ok|fine|alright|all right)\b")
_NOT_SAFE = re.compile(r"\b(?:not (?:really |totally |completely )?safe|don'?t (?:feel|think i'?m) safe|unsafe)\b")


def _last_question(text: str) -> str:
    questions = re.findall(r"[^.!?]*\?", text)
    return questions[-1] if questions else ""


def _answer_to_safety_question(question: str, answer: str) -> bool | None:
    """True: the answer suggests they aren't safe. False: reassured. None: not an answer."""
    asks_thoughts, asks_safe = bool(_ASKS_THOUGHTS.search(question)), bool(_ASKS_SAFE.search(question))
    if not (asks_thoughts or asks_safe) or len(answer.split()) > 25:
        return None
    if _NOT_SAFE.search(answer):
        return True
    if asks_thoughts:
        if _NO.search(answer) and not _UNSURE.search(answer):
            return False
        if _YES.search(answer) or _UNSURE.search(answer):
            return True
        return None
    if _SAFE_NOW.search(answer) and not _NOT_SAFE.search(answer):
        return False
    if _UNSURE.search(answer) or _NO.search(answer):
        return True
    if _YES.search(answer):
        return False
    return None


# ── Putting it together ────────────────────────

def _assess_text(text: str) -> list[Signal]:
    signals: list[Signal] = []
    for clause in _clauses(_normalize(text)):
        for check in (_self_harm, _danger, _violence, _harm_to_others):
            signals += check(clause)
    # One certain finding of a kind makes "possible" ones of the same kind moot.
    certain_risks = {s.risk for s in signals if s.certain}
    signals = [s for s in signals if s.certain or s.risk not in certain_risks]
    return list(dict.fromkeys(signals))


def assess(latest: str, previous_ced: str | None = None, earlier_user: list[str] | None = None) -> Assessment:
    """
    Findings for the user's latest message. `previous_ced` is Ced's turn just
    before it (to read a "yes"/"no" to a safety question); `earlier_user` are
    the user's earlier messages, newest first (to tell whether that question
    was about self-harm or about someone else).
    """
    signals = _assess_text(latest)
    if previous_ced:
        answer = _answer_to_safety_question(_last_question(_normalize(previous_ced)), _normalize(latest))
        if answer:
            kind = "self_harm"
            for text in earlier_user or []:
                earlier = [s for s in _assess_text(text) if s.risk in SUPPORT_FOR_RISK]
                if earlier:
                    kind = "in_danger" if earlier[0].risk in ("in_danger", "violence") else "self_harm"
                    break
            signals.insert(0, Signal(kind, True, "unsafe_answer"))
    certain_risks = {s.risk for s in signals if s.certain}
    signals = [s for s in signals if s.certain or s.risk not in certain_risks]
    return Assessment(tuple(dict.fromkeys(signals)))


def check_message(text: str) -> Risk | None:
    """The most serious CERTAIN risk in one message, or None (used by voice calls)."""
    floor = Assessment(tuple(_assess_text(text))).floor
    return floor.risk if floor else None


# ── Fixed replies ──────────────────────────────

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

# For unclear findings when the model can't be reached: a gentle question
# instead of an assumption, with the resources in reach.
FALLBACK_FOR_NOTE: dict[str, list[str]] = {
    "possible_self_harm": [
        "That sounds really heavy, and I'm glad you said it.",
        "Can I ask you gently: are you having any thoughts of hurting yourself or not wanting to be alive?",
        "If you are, you don't have to carry that alone. You can call or text 988 below, any time.",
    ],
    "past_self_harm": [
        "Thank you for trusting me with that.",
        "How are you doing with those thoughts these days? If they're back, you can call or text 988 below, any time.",
    ],
    "denied_self_harm": [
        "Thank you for telling me, and I believe you.",
        "If those thoughts ever do show up, you can call or text 988 below, any time.",
    ],
    "someone_else_at_risk": [
        "That's a lot to carry, and it isn't your job to keep someone safe on your own.",
        "If they might hurt themselves, they can call or text 988, and if they're in immediate danger, call 911.",
    ],
    "possible_danger": [
        "I'm glad you told me. How you feel about your safety matters.",
        "Are you somewhere safe right now? If you're ever in immediate danger, you can call 911.",
    ],
    "past_danger": [
        "I'm so sorry that happened to you. It wasn't okay, and it wasn't your fault.",
        "Are you safe now? If you're ever in danger, you can call 911.",
    ],
}

# The question every self-harm / danger reply must contain.
SAFETY_QUESTION = "Are you safe right now?"

# Asked when an unclear finding got a reply with no question at all.
CHECK_IN_QUESTIONS: dict[str, str] = {
    "possible_self_harm": "Can I ask you gently: are you having any thoughts of hurting yourself or not wanting to be alive?",
    "past_self_harm": "How are you doing with those thoughts these days?",
    "possible_danger": "Are you somewhere safe right now?",
    "past_danger": "Are you safe now?",
}


def asks_about_safety(parts: list[str]) -> bool:
    """Whether a reply asks directly about safety or self-harm."""
    for part in parts:
        for question in re.findall(r"[^.!?]*\?", _normalize(part)):
            if _ASKS_SAFE.search(question) or _ASKS_THOUGHTS.search(question):
                return True
    return False


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
