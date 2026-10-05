"""
Which activities to recommend after a check-in.

CURRENT RULE (matches the Figma prototype): recommend every active activity in
the catalog, in sort_order, up to MAX_RECOMMENDATIONS. The prototype shows the
same cards every day, so the check-in answers do not change the result yet.

When the team agrees on real rules (for example, using feeling, energy_level,
contact_urge or hardest_areas), change only this function. The rest of the
backend saves whatever it returns and links it to the check-in.
"""
from app.schemas import CheckIn

MAX_RECOMMENDATIONS = 3


def choose_activity_ids(check_in: CheckIn, active_activities: list[dict]) -> list[int]:
    """
    check_in: the check-in that was just saved.
    active_activities: rows from the activities table, already in sort_order.
    Returns the activity ids to recommend, in the order the cards should show.
    """
    return [activity["id"] for activity in active_activities[:MAX_RECOMMENDATIONS]]
