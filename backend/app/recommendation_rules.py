"""
Which activities to recommend after a check-in.

How it works:
1. Energy filter: drop activities that are too long for today's energy.
   If that leaves fewer than MAX_RECOMMENDATIONS, the shortest of the rest are
   added after them.
2. Saved first: activities the user bookmarked with "Save for later" (and that
   fit today's energy) come first, at most MAX_SAVED_FIRST of them, so the
   rest of the deck still responds to today's check-in. A saved activity
   completed in the last SAVED_COMPLETED_HIDE_DAYS days isn't moved to the
   front (storage.py leaves it out of the saved set).
3. Score each activity by category, using what the user said in the check-in:
   how they feel, what feels hardest, and how strong the urge to contact is.
4. Skip repeats: activities shown in the last REPEAT_WINDOW check-ins, or
   completed recently, go to the back of the line, so the user sees fresh
   cards day to day. They only come back when there aren't enough fresh ones.
5. Pick the highest scores, with at most MAX_PER_CATEGORY cards from one
   category, so the deck has some variety to swipe through.

Ties keep catalog order (sort_order), so results are predictable and testable.
The rest of the backend saves whatever this returns and links it to the check-in.
"""
from app.schemas import CheckIn

MAX_RECOMMENDATIONS = 3
MAX_PER_CATEGORY = 2
MAX_SAVED_FIRST = 2
# A saved activity completed within this many days isn't moved to the front.
SAVED_COMPLETED_HIDE_DAYS = 3

# Activities recommended in this many recent check-ins are shown only if needed.
REPEAT_WINDOW = 5
# Activities completed within this many days are shown only if needed.
RECENTLY_COMPLETED_DAYS = 7

# Longest activity (in minutes) that fits each energy level. None means no limit.
MAX_MINUTES_FOR_ENERGY = {"low": 15, "medium": 45, "high": None}

# At or above this urge level, favour quick activities that get the user moving.
HIGH_URGE = 7

# How much each answer pushes each category up.
FEELING_WEIGHTS = {
    "heavy": {"mindfulness_rest": 2},
    "getting_through": {"outdoor_movement": 1},
    "missing_them": {"outdoor_movement": 2, "mindfulness_rest": 1},
    "hopeful": {"solo_exploration": 1, "social_connection": 1},
}

HARDEST_AREA_WEIGHTS = {
    "feeling_lonely": {"social_connection": 3, "outdoor_movement": 1},
    "missing_relationship": {"solo_exploration": 2, "mindfulness_rest": 1},
    "wanting_answers": {"mindfulness_rest": 2, "outdoor_movement": 1},
    "resisting_contact": {"outdoor_movement": 3, "solo_exploration": 1},
    "rebuilding_confidence": {"solo_exploration": 3, "social_connection": 1},
}


def fits_energy(activity: dict, energy_level: str) -> bool:
    limit = MAX_MINUTES_FOR_ENERGY[energy_level]
    return limit is None or activity["duration_minutes"] <= limit


def score(activity: dict, check_in: CheckIn) -> int:
    category = activity["category"]
    points = FEELING_WEIGHTS[check_in.feeling].get(category, 0)
    for area in check_in.hardest_areas:
        points += HARDEST_AREA_WEIGHTS[area].get(category, 0)

    if check_in.contact_urge >= HIGH_URGE:
        if category == "outdoor_movement":
            points += 2
        if activity["duration_minutes"] <= 20:
            points += 1
    return points


def choose_activity_ids(
    check_in: CheckIn,
    active_activities: list[dict],
    saved_activity_ids: set[int] = frozenset(),
    recent_activity_ids: set[int] = frozenset(),
) -> list[int]:
    """
    check_in: the check-in that was just saved.
    active_activities: rows from the activities table, already in sort_order.
    saved_activity_ids: activities the user bookmarked with "Save for later".
    recent_activity_ids: activities shown in the last REPEAT_WINDOW check-ins
        or completed in the last RECENTLY_COMPLETED_DAYS days.
    Returns the activity ids to recommend, in the order the cards should show.
    """
    def best_first(activities: list[dict]) -> list[dict]:
        # sorted() is stable, so equal scores stay in catalog order.
        return sorted(activities, key=lambda a: score(a, check_in), reverse=True)

    fitting = [a for a in active_activities if fits_energy(a, check_in.energy_level)]

    saved = best_first([a for a in fitting if a["id"] in saved_activity_ids])
    saved = saved[:MAX_SAVED_FIRST]
    others = [a for a in fitting if a not in saved]
    # Fresh activities first, then recent ones, each group best score first.
    ranked = best_first([a for a in others if a["id"] not in recent_activity_ids])
    ranked += best_first([a for a in others if a["id"] in recent_activity_ids])

    if len(fitting) < MAX_RECOMMENDATIONS:
        # Not enough fit today's energy: add the shortest of the rest, after them.
        too_long = sorted(
            (a for a in active_activities if a not in fitting),
            key=lambda a: a["duration_minutes"],
        )
        ranked += best_first(too_long[: MAX_RECOMMENDATIONS - len(fitting)])

    chosen: list[dict] = saved[:MAX_RECOMMENDATIONS]
    per_category: dict[str, int] = {}
    for activity in chosen:
        per_category[activity["category"]] = per_category.get(activity["category"], 0) + 1

    for activity in ranked:
        if len(chosen) == MAX_RECOMMENDATIONS:
            break
        category = activity["category"]
        if per_category.get(category, 0) >= MAX_PER_CATEGORY:
            continue
        chosen.append(activity)
        per_category[category] = per_category.get(category, 0) + 1

    # If the variety rule left gaps, fill them with the next best activities.
    for activity in ranked:
        if len(chosen) == MAX_RECOMMENDATIONS:
            break
        if activity not in chosen:
            chosen.append(activity)

    return [activity["id"] for activity in chosen]