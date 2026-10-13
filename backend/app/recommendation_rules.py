"""
Which activities to recommend after a check-in.

CURRENT RULE (matches the Figma prototype): recommend every active activity in
the catalog, in sort_order, up to MAX_RECOMMENDATIONS, with the user's saved
("Save for later") activities moved to the front. The prototype shows the
same cards every day, so the check-in answers do not change the result yet.

When the team agrees on real rules (for example, using feeling, energy_level,
contact_urge or hardest_areas), change only this function. The rest of the
backend saves whatever it returns and links it to the check-in.
"""
from app.schemas import CheckIn

MAX_RECOMMENDATIONS = 3


def choose_activity_ids(
    check_in: CheckIn, active_activities: list[dict], saved_activity_ids: set[int]
) -> list[int]:
    """
    check_in: the check-in that was just saved.
    active_activities: rows from the activities table, already in sort_order.
    saved_activity_ids: activities the user bookmarked with "Save for later".
    Returns the activity ids to recommend, in the order the cards should show.

    Saved activities come first. Each group keeps the base order, so when
    mood-based ordering is added to the base order, it still applies among
    the saved activities and among the rest.
    """
    base_order = active_activities  # mood-based ordering goes here later
    saved = [a["id"] for a in base_order if a["id"] in saved_activity_ids]
    others = [a["id"] for a in base_order if a["id"] not in saved_activity_ids]
    return (saved + others)[:MAX_RECOMMENDATIONS]
