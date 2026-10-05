from datetime import date, datetime
from uuid import uuid4

from app.recommendations import reason_for, recommend
from app.schemas import Activity, CheckIn


def make_check_in(**overrides) -> CheckIn:
    data = dict(
        id=1, installation_id=uuid4(), created_at=datetime.now(),
        feeling="getting_through", contact_urge=3, energy_level="medium",
        hardest_areas=[], local_date=date.today(),
    )
    data.update(overrides)
    return CheckIn(**data)


def make_activity(id, category, minutes) -> Activity:
    return Activity(
        id=id, slug=f"a{id}", title=f"A{id}", category=category,
        category_label="", duration_minutes=minutes, instructions="",
        why_it_fits="", sort_order=id,
    )


# The three activities currently seeded in Neon, plus a few extras.
CATALOG = [
    make_activity(1, "mindfulness_rest", 10),
    make_activity(2, "outdoor_movement", 20),
    make_activity(3, "solo_exploration", 120),
    make_activity(4, "mindfulness_rest", 5),
    make_activity(5, "outdoor_movement", 10),
    make_activity(6, "solo_exploration", 30),
    make_activity(7, "social_connection", 10),
]


def test_lonely_leads_with_social_connection():
    check_in = make_check_in(hardest_areas=["feeling_lonely"])
    assert recommend(check_in, CATALOG, set())[0].category == "social_connection"


def test_hopeful_vs_missing_them_get_different_orders():
    hopeful = make_check_in(feeling="hopeful", contact_urge=5,
                            hardest_areas=["missing_relationship"])
    missing = make_check_in(feeling="missing_them", contact_urge=5,
                            hardest_areas=["missing_relationship"])
    a = [x.id for x in recommend(hopeful, CATALOG, set())]
    b = [x.id for x in recommend(missing, CATALOG, set())]
    assert a != b


def test_high_urge_leads_with_movement():
    check_in = make_check_in(contact_urge=9, hardest_areas=["resisting_contact"])
    assert recommend(check_in, CATALOG, set())[0].category == "outdoor_movement"


def test_low_energy_only_gets_short_activities():
    picks = recommend(make_check_in(energy_level="low"), CATALOG, set())
    assert picks and all(a.duration_minutes <= 15 for a in picks)


def test_excluded_ids_are_skipped():
    picks = recommend(make_check_in(energy_level="high"), CATALOG, {1, 2})
    assert {1, 2}.isdisjoint(a.id for a in picks)


def test_reason_mentions_low_energy():
    check_in = make_check_in(energy_level="low")
    assert "low-energy" in reason_for(check_in, CATALOG[0])