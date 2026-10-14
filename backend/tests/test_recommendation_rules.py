"""
Unit tests for the recommendation rules. No database needed:
these call choose_activity_ids directly with made-up activity rows.

    pytest tests/test_recommendation_rules.py
"""
from datetime import date, datetime, timezone
from uuid import uuid4

from app.recommendation_rules import MAX_RECOMMENDATIONS, choose_activity_ids
from app.schemas import CheckIn


def make_check_in(**answers) -> CheckIn:
    defaults = {
        "feeling": "getting_through",
        "contact_urge": 3,
        "energy_level": "high",
        "hardest_areas": [],
    }
    return CheckIn(
        id=1,
        installation_id=uuid4(),
        created_at=datetime.now(timezone.utc),
        local_date=date(2026, 10, 13),
        **{**defaults, **answers},
    )


# A small catalog, already in sort_order like the real query returns it.
CATALOG = [
    {"id": 1, "category": "mindfulness_rest", "duration_minutes": 10},
    {"id": 2, "category": "outdoor_movement", "duration_minutes": 20},
    {"id": 3, "category": "solo_exploration", "duration_minutes": 120},
    {"id": 4, "category": "social_connection", "duration_minutes": 15},
    {"id": 5, "category": "social_connection", "duration_minutes": 60},
    {"id": 6, "category": "mindfulness_rest", "duration_minutes": 5},
    {"id": 7, "category": "outdoor_movement", "duration_minutes": 45},
    {"id": 8, "category": "solo_exploration", "duration_minutes": 30},
]


def by_id(ids):
    return [next(a for a in CATALOG if a["id"] == i) for i in ids]


def test_returns_max_recommendations():
    assert len(choose_activity_ids(make_check_in(), CATALOG)) == MAX_RECOMMENDATIONS


def test_low_energy_only_gets_short_activities():
    ids = choose_activity_ids(make_check_in(energy_level="low"), CATALOG)
    assert all(a["duration_minutes"] <= 15 for a in by_id(ids))


def test_low_energy_tops_up_when_too_few_fit():
    catalog = [a for a in CATALOG if a["duration_minutes"] > 15] + [CATALOG[0]]
    ids = choose_activity_ids(make_check_in(energy_level="low"), catalog)
    assert len(ids) == MAX_RECOMMENDATIONS
    assert ids[0] == 1  # the only one that fits comes first


def test_feeling_lonely_puts_social_connection_first():
    ids = choose_activity_ids(make_check_in(hardest_areas=["feeling_lonely"]), CATALOG)
    assert by_id(ids)[0]["category"] == "social_connection"


def test_high_urge_puts_outdoor_movement_first():
    ids = choose_activity_ids(make_check_in(contact_urge=9), CATALOG)
    assert by_id(ids)[0]["category"] == "outdoor_movement"


def test_no_more_than_two_from_one_category():
    ids = choose_activity_ids(
        make_check_in(hardest_areas=["feeling_lonely"], feeling="hopeful"), CATALOG
    )
    categories = [a["category"] for a in by_id(ids)]
    assert max(categories.count(c) for c in categories) <= 2


def test_empty_catalog_returns_nothing():
    assert choose_activity_ids(make_check_in(), []) == []


def test_same_answers_give_same_result():
    check_in = make_check_in(feeling="heavy", hardest_areas=["wanting_answers"])
    assert choose_activity_ids(check_in, CATALOG) == choose_activity_ids(check_in, CATALOG)


def test_recent_activities_go_to_the_back():
    check_in = make_check_in(hardest_areas=["feeling_lonely"])
    first = choose_activity_ids(check_in, CATALOG)
    second = choose_activity_ids(check_in, CATALOG, recent_activity_ids=set(first))
    assert not set(first) & set(second)


def test_recent_activities_come_back_when_nothing_else_fits():
    check_in = make_check_in(energy_level="low")
    short_ids = {a["id"] for a in CATALOG if a["duration_minutes"] <= 15}
    ids = choose_activity_ids(check_in, CATALOG, recent_activity_ids=short_ids)
    assert len(ids) == MAX_RECOMMENDATIONS
    assert set(ids) <= short_ids  # still respects energy, even though all were recent


def test_saved_activities_come_first():
    ids = choose_activity_ids(make_check_in(hardest_areas=["feeling_lonely"]), CATALOG, {3})
    assert ids[0] == 3


def test_at_most_two_saved_activities_first():
    ids = choose_activity_ids(
        make_check_in(hardest_areas=["feeling_lonely"]), CATALOG, {3, 7, 8}
    )
    assert len(set(ids[:2]) & {3, 7, 8}) == 2
    assert by_id(ids)[2]["category"] == "social_connection"  # the check-in still counts


def test_saved_activity_too_long_for_energy_is_not_forced_in():
    ids = choose_activity_ids(make_check_in(energy_level="low"), CATALOG, {3})  # 3 is 120 min
    assert 3 not in ids


def test_saved_activity_still_shows_even_if_recent():
    ids = choose_activity_ids(make_check_in(), CATALOG, {2}, recent_activity_ids={2})
    assert ids[0] == 2
