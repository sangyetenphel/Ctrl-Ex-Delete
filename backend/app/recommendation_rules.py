"""
Which activities to recommend after a check-in: at most MAX_RECOMMENDATIONS
unique cards, chosen from today's answers first.

How it works:
1. Energy filter: an activity is suitable only if its energy demand (its
   stored energy_level: physical, cognitive, social and preparation demand,
   separate from its duration) is allowed for today's check-in energy
   (ALLOWED_DEMAND). Nothing above today's allowance is ever added just to
   fill the deck, so a day can get fewer than three cards.
2. Score each suitable activity, using what the user said in the check-in:
   how they feel and what feels hardest pick the category; an activity whose
   demand matches today's energy gets a small bonus (so a fuller day leans
   towards fuller activities); and a strong urge to contact them puts quick,
   gentle movement first. Movement is the activity's involves_movement flag:
   sitting outside is Outdoor & Movement but not movement, and a strong urge
   never adds points to strenuous (high-demand) activities.
3. Skip repeats: activities shown in the last REPEAT_WINDOW check-ins, or
   completed recently, go to the back of the line, so the user sees fresh
   cards day to day. They only come back when there aren't enough fresh ones.
4. The first cards come only from today's check-in: the highest scores, with
   at most MAX_PER_CATEGORY cards from one category. Saved activities are
   never picked here, so "Save for later" can't push today's answers aside.
5. The last card may be ONE saved activity ("Save for later"), but only if it
   fits today's energy and today's answers point to it (see
   matches_check_in). Otherwise it's the next regular recommendation.
   A saved activity completed in the last SAVED_COMPLETED_HIDE_DAYS days isn't
   offered (storage.py leaves it out of the saved set).

The catalog has 25 activities per category, but that balance isn't a quota:
which categories come up depends only on the answers.
Ties keep catalog order (sort_order), so results are predictable and testable.
The rest of the backend saves whatever this returns and links it to the check-in.
"""
from app.schemas import CheckIn

MAX_RECOMMENDATIONS = 3
MAX_PER_CATEGORY = 2
# A saved activity completed within this many days isn't offered again yet.
SAVED_COMPLETED_HIDE_DAYS = 3
# A saved activity needs at least this many "need" points (from how the user
# feels, what feels hardest, or a strong urge) to earn the last card.
SAVED_MATCH_MIN_POINTS = 1

# Activities recommended in this many recent check-ins are shown only if needed.
REPEAT_WINDOW = 5
# Activities completed within this many days are shown only if needed.
RECENTLY_COMPLETED_DAYS = 7

# Check-in energy -> the activity energy levels it allows. The check-in and
# the catalog use the same three words, so this is the whole mapping.
ALLOWED_DEMAND = {
    "low": {"low"},
    "medium": {"low", "medium"},
    "high": {"low", "medium", "high"},
}
# Bonus when an activity's demand equals today's energy (outside a strong urge).
ENERGY_MATCH_POINTS = 1

# At or above this urge level, favour something quick, and quick gentle
# movement most: movement, at most QUICK_MINUTES long, not high demand.
HIGH_URGE = 7
QUICK_MINUTES = 20
QUICK_POINTS = 1
GENTLE_MOVEMENT_POINTS = 2

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
    """Whether today's check-in energy allows this activity's demand."""
    return activity["energy_level"] in ALLOWED_DEMAND[energy_level]


def is_quick_gentle_movement(activity: dict) -> bool:
    return (
        activity["involves_movement"]
        and activity["duration_minutes"] <= QUICK_MINUTES
        and activity["energy_level"] != "high"
    )


def need_points(activity: dict, check_in: CheckIn) -> int:
    """How strongly today's answers point to this activity."""
    category = activity["category"]
    points = FEELING_WEIGHTS[check_in.feeling].get(category, 0)
    for area in check_in.hardest_areas:
        points += HARDEST_AREA_WEIGHTS[area].get(category, 0)
    if check_in.contact_urge >= HIGH_URGE and is_quick_gentle_movement(activity):
        points += GENTLE_MOVEMENT_POINTS
    return points


def score(activity: dict, check_in: CheckIn) -> int:
    points = need_points(activity, check_in)
    if check_in.contact_urge >= HIGH_URGE:
        # A strong urge needs something quick right now.
        if activity["duration_minutes"] <= QUICK_MINUTES:
            points += QUICK_POINTS
    elif activity["energy_level"] == check_in.energy_level:
        points += ENERGY_MATCH_POINTS
    return points


def matches_check_in(activity: dict, check_in: CheckIn) -> bool:
    """
    Whether a saved activity really suits today. Being saved isn't enough:
    it must fit today's energy, and today's answers must point to it.
    """
    return (
        fits_energy(activity, check_in.energy_level)
        and need_points(activity, check_in) >= SAVED_MATCH_MIN_POINTS
    )


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
    Returns up to MAX_RECOMMENDATIONS unique activity ids, in card order.
    """
    def best_first(activities: list[dict]) -> list[dict]:
        # sorted() is stable, so equal scores stay in catalog order.
        return sorted(activities, key=lambda a: score(a, check_in), reverse=True)

    fitting = [a for a in active_activities if fits_energy(a, check_in.energy_level)]

    # Regular cards: everything suitable that isn't saved. Fresh ones first,
    # then recent ones, each group best score first.
    regular = [a for a in fitting if a["id"] not in saved_activity_ids]
    ranked = best_first([a for a in regular if a["id"] not in recent_activity_ids])
    ranked += best_first([a for a in regular if a["id"] in recent_activity_ids])

    chosen: list[dict] = []
    per_category: dict[str, int] = {}

    def add(activity: dict) -> None:
        chosen.append(activity)
        per_category[activity["category"]] = per_category.get(activity["category"], 0) + 1

    def fill_up_to(size: int) -> None:
        # Best scores first while keeping variety; if the variety rule leaves
        # gaps, fill them with the next best suitable activities.
        for keep_variety in (True, False):
            for activity in ranked:
                if len(chosen) >= size:
                    return
                if activity in chosen:
                    continue
                if keep_variety and per_category.get(activity["category"], 0) >= MAX_PER_CATEGORY:
                    continue
                add(activity)

    # 1. Every card but the last comes from today's check-in only.
    fill_up_to(MAX_RECOMMENDATIONS - 1)

    # 2. The last card: one saved activity, if it really suits today.
    saved_matches = best_first(
        [a for a in fitting if a["id"] in saved_activity_ids and matches_check_in(a, check_in)]
    )
    saved_pick = next(
        (a for a in saved_matches if per_category.get(a["category"], 0) < MAX_PER_CATEGORY),
        None,
    )
    if saved_pick is not None:
        add(saved_pick)  # always last: the regular cards are already chosen
    else:
        fill_up_to(MAX_RECOMMENDATIONS)

    return [activity["id"] for activity in chosen]
