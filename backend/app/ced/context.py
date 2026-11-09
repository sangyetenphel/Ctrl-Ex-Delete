"""
Context-aware Ced: a short summary of THIS installation's journey for the
model, from structured data only (storage.get_ced_context, one query):
today's check-in, today's suggested activities, a few recently completed ones
with how the user felt afterwards, and a little progress.

Never included: reflection notes, photos, names, the installation ID, or any
past conversation. Built per text message and once per voice call; never
stored or logged (a failure logs only the error type, and Ced carries on
without context). The summary is facts, not instructions: the prompt says
how to use it, and safety notes always come after it and override it.
"""
import logging
from datetime import date
from uuid import UUID

from app import storage

logger = logging.getLogger("ced")

MAX_CHARS = 1200   # about 300 tokens: small next to Ced's instructions

_FEELING = {
    "heavy": "heavy, like it's overwhelming",
    "getting_through": "getting through it, one step at a time",
    "missing_them": "missing their ex, with thoughts that keep returning",
    "hopeful": "hopeful, like the weight is a little lighter",
}
_ENERGY = {"low": "low", "medium": "medium", "high": "high"}
_HARDEST = {
    "feeling_lonely": "feeling lonely",
    "missing_relationship": "missing the relationship",
    "wanting_answers": "wanting answers",
    "resisting_contact": "resisting the urge to make contact",
    "rebuilding_confidence": "rebuilding confidence",
}
_CATEGORY = {
    "outdoor_movement": "outdoor & movement",
    "mindfulness_rest": "mindfulness & rest",
    "solo_exploration": "solo exploration",
    "social_connection": "social connection",
}
_MOOD_AFTER = {
    "worse": "felt worse afterwards",
    "about_the_same": "felt about the same afterwards",
    "a_little_better": "felt a little better afterwards",
    "much_better": "felt much better afterwards",
}
_EX_AFTER = {
    "not_really": "barely thought about their ex",
    "a_little": "thought about their ex a little",
    "a_lot": "thought about their ex a lot",
}


def _urge(level: int) -> str:
    if level >= 7:
        return "strong"
    if level >= 4:
        return "moderate"
    return "low"


def _day(value) -> date | None:
    if value is None or isinstance(value, date):
        return value
    return date.fromisoformat(str(value)[:10])


def _when(day: date | None, today: date | None) -> str:
    if day is None:
        return "recently"
    if today is not None:
        days = (today - day).days
        if days == 0:
            return "today"
        if days == 1:
            return "yesterday"
        if 1 < days < 7:
            return f"{days} days ago"
    return f"on {day:%b} {day.day}"


def render(data: dict | None, today: date | None) -> str | None:
    """The summary block, or None when there's nothing worth saying (a new user)."""
    if not data:
        return None
    lines: list[str] = []
    check_in = data.get("check_in")
    if check_in:
        day = _day(check_in.get("local_date"))
        is_today = today is not None and day == today
        when = "Today" if is_today else f"Their most recent check-in ({_when(day, today)}, maybe not how they feel now)"
        parts = [f"feeling {_FEELING.get(check_in.get('feeling'), 'unsure')}",
                 f"{_ENERGY.get(check_in.get('energy_level'), 'unknown')} energy",
                 f"a {_urge(int(check_in.get('contact_urge') or 0))} urge to contact their ex"]
        hardest = [_HARDEST[a] for a in check_in.get("hardest_areas") or [] if a in _HARDEST]
        if hardest:
            parts.append("hardest right now: " + ", ".join(hardest))
        lines.append(f"- {when} they checked in: " + "; ".join(parts) + ".")
        suggested = data.get("suggested") or []
        if is_today and suggested:
            items = [f"\"{s['title']}\" ({_CATEGORY.get(s['category'], s['category'])}, "
                     f"{s['duration_minutes']} min{': ' + s['why_it_fits'] if s.get('why_it_fits') else ''})"
                     for s in suggested]
            lines.append("- Today's suggested activities in the app: " + "; ".join(items) + ".")
    else:
        lines.append("- They haven't checked in yet today.")
    completed = data.get("completed") or []
    if completed:
        items = []
        for c in completed:
            after = [_MOOD_AFTER[c["mood_change"]]] if c.get("mood_change") in _MOOD_AFTER else []
            if c.get("thought_about_ex") in _EX_AFTER:
                after.append(_EX_AFTER[c["thought_about_ex"]])
            items.append(f"\"{c['title']}\" {_when(_day(c.get('completed_on')), today)}"
                         + (f" ({', '.join(after)})" if after else ""))
        lines.append("- Recently completed activities: " + "; ".join(items) + ".")
    started = _day(data.get("journey_started_on"))
    progress = []
    if started and today and today >= started:
        progress.append(f"day {(today - started).days + 1} of their journey")
    if data.get("check_ins"):
        progress.append(f"{data['check_ins']} check-in{'s' if data['check_ins'] != 1 else ''}")
    progress.append(f"{data.get('activities_completed') or 0} activities completed in all")
    if data.get("moved_forward_on"):
        progress.append("they've chosen to start moving forward")
    if data.get("check_ins") or data.get("activities_completed"):
        lines.append("- Progress: " + ", ".join(progress) + ".")
    if not check_in and not completed:
        return None   # a brand-new user: nothing to personalise yet
    text = "\n".join(lines)
    return text if len(text) <= MAX_CHARS else text[:MAX_CHARS - 1].rsplit(" ", 1)[0] + "…"


def load(installation_id: UUID, today: date | None) -> str | None:
    """This installation's summary, or None (nothing yet, or the database failed: Ced works without it)."""
    try:
        return render(storage.get_ced_context(installation_id, today), today)
    except Exception as error:  # noqa: BLE001 — personalisation must never break Ced
        logger.warning("Ced context unavailable: %s", type(error).__name__)
        return None
