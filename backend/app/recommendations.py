"""Activity recommendation rules.

No database code lives here on purpose: it takes a check-in and a list of
activities and returns picks in order.

The weights below are placeholders to review with the team (and the psych
professor). Changing the category set only means editing these dictionaries.
"""
from typing import get_args

from app.schemas import Activity, Category, CheckIn

CATEGORIES: tuple[Category, ...] = get_args(Category)

# How much each answer pushes each category up. Every category starts at 1.0.
FEELING_WEIGHTS: dict[str, dict[Category, float]] = {
    "heavy": {"mindfulness_rest": 2.0},
    "getting_through": {"mindfulness_rest": 1.0, "social_connection": 0.5},
    "missing_them": {"outdoor_movement": 1.5, "mindfulness_rest": 0.5},
    "hopeful": {"solo_exploration": 1.5, "social_connection": 1.0},
}

AREA_WEIGHTS: dict[str, dict[Category, float]] = {
    "feeling_lonely": {"social_connection": 2.0},
    "missing_relationship": {"outdoor_movement": 1.0, "mindfulness_rest": 1.0},
    "wanting_answers": {"mindfulness_rest": 1.5},
    "resisting_contact": {"outdoor_movement": 2.0},
    "rebuilding_confidence": {"solo_exploration": 2.0},
}

# No effort column in the table, so duration stands in for it.
# None = no limit.
MAX_MINUTES = {"low": 15, "medium": 45, "high": None}

# Short, check-in-aware text to replace the fixed why_it_fits.
CATEGORY_REASON: dict[Category, str] = {
    "mindfulness_rest": "A quiet reset can take some weight off today.",
    "outdoor_movement": "Moving your body helps break up looping thoughts.",
    "solo_exploration": "Time out on your own builds comfort with your own company.",
    "social_connection": "Reaching out to people who care about you eases the lonely stretches.",
}


def category_weights(check_in: CheckIn) -> dict[Category, float]:
    weights: dict[Category, float] = {c: 1.0 for c in CATEGORIES}

    for category, boost in FEELING_WEIGHTS[check_in.feeling].items():
        weights[category] += boost

    for area in check_in.hardest_areas:
        for category, boost in AREA_WEIGHTS[area].items():
            weights[category] += boost

    if check_in.contact_urge >= 7:
        weights["outdoor_movement"] += 2.0
    elif check_in.contact_urge >= 4:
        weights["outdoor_movement"] += 1.0

    return weights


def recommend(
    check_in: CheckIn,
    activities: list[Activity],
    excluded_ids: set[int],
    limit: int = 3,
) -> list[Activity]:
    """Round-robin across categories, highest weight first, so the list is
    varied but led by what fits best. Position 1 = index 0."""
    weights = category_weights(check_in)
    max_minutes = MAX_MINUTES[check_in.energy_level]

    candidates = [
        a for a in activities
        if a.id not in excluded_ids
        and (max_minutes is None or a.duration_minutes <= max_minutes)
    ]
    order = sorted(CATEGORIES, key=lambda c: weights[c], reverse=True)
    queues = {
        c: sorted((a for a in candidates if a.category == c), key=lambda a: a.sort_order)
        for c in order
    }

    picks: list[Activity] = []
    while len(picks) < limit and any(queues.values()):
        for c in order:
            if queues[c] and len(picks) < limit:
                picks.append(queues[c].pop(0))
    return picks


def reason_for(check_in: CheckIn, activity: Activity) -> str:
    parts = [CATEGORY_REASON[activity.category]]
    if check_in.contact_urge >= 7 and activity.category == "outdoor_movement":
        parts.append("Your urge to reach out is high, and getting away from your phone helps you ride it out.")
    if check_in.energy_level == "low":
        parts.append(f"It only takes about {activity.duration_minutes} minutes, so it fits a low-energy day.")
    return " ".join(parts)