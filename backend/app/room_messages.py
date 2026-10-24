"""
Which of Ced's room messages fits a check-in. The rules live only here; the
catalog itself is in the room_messages table (scripts/room_message_data.py).

The check-in's answers, as the app asks them:
- feeling: "heavy" (it feels overwhelming), "missing_them" (thoughts keep
  returning), "getting_through" (one step at a time), "hopeful" (the weight
  feels lighter). Choices, not a scale.
- contact_urge: 1 ("Not at all") to 10 ("Very strong"). HIGHER IS HARDER.
- energy_level: low, medium or high (low only gets low-demand activities).
- hardest_areas: any of feeling_lonely, missing_relationship, wanting_answers,
  resisting_contact, rebuilding_confidence.

Patterns, first match wins (PRIORITY):
1. strong_urge          contact_urge >= STRONG_URGE (7), whatever else was answered
2. heavy_low_energy     feeling heavy or missing_them, and energy low
3. low_energy           energy low (any other feeling)
4. lonely               "feeling_lonely" among the hardest areas (energy medium/high)
5. heavy_some_energy    feeling heavy or missing_them (energy medium/high)
6. lighter_with_energy  feeling hopeful (energy medium/high)
7. general              anything else (getting_through with medium/high energy)

A strong urge comes first because the activities do the same (quick, gentle
movement first), so the message and the cards agree. Low energy comes next so
nothing suggests more than the low-demand activities offered that day.

These describe today's answers gently. They are not a risk assessment, a
diagnosis, or a judgement about readiness to move forward.
"""
from datetime import date
from hashlib import sha256

from app.recommendation_rules import HIGH_URGE
from app.schemas import CheckIn

STRONG_URGE = HIGH_URGE          # 7, shared with the activity recommendations
HARDER_FEELINGS = {"heavy", "missing_them"}

PRIORITY = [
    "strong_urge", "heavy_low_energy", "low_energy", "lonely",
    "heavy_some_energy", "lighter_with_energy", "general",
]
BEFORE_CHECK_IN = "before_check_in"


def pattern_for(check_in: CheckIn) -> str:
    if check_in.contact_urge >= STRONG_URGE:
        return "strong_urge"
    if check_in.energy_level == "low":
        return "heavy_low_energy" if check_in.feeling in HARDER_FEELINGS else "low_energy"
    if "feeling_lonely" in check_in.hardest_areas:
        return "lonely"
    if check_in.feeling in HARDER_FEELINGS:
        return "heavy_some_energy"
    if check_in.feeling == "hopeful":
        return "lighter_with_energy"
    return "general"


def choose(candidates: list[dict], key: str) -> dict | None:
    """The same message for the same key every time (no randomness)."""
    if not candidates:
        return None
    index = int(sha256(key.encode()).hexdigest(), 16) % len(candidates)
    return candidates[index]


def check_in_key(check_in_id: int) -> str:
    return f"check-in:{check_in_id}"


def before_check_in_key(installation_id, local_date: date) -> str:
    """Stable for the whole day, without saving anything before a check-in."""
    return f"before:{installation_id}:{local_date.isoformat()}"
