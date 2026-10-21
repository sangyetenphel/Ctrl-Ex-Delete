"""
Unit tests for the recommendation rules. No database needed:
these call choose_activity_ids directly with made-up activity rows.

    pytest tests/test_recommendation_rules.py
"""
from datetime import date, datetime, timezone
from uuid import uuid4

from app.recommendation_rules import (
    FEELING_REASONS,
    HARDEST_AREA_REASONS,
    MAX_RECOMMENDATIONS,
    choose_activity_ids,
    reason,
    reasons,
)
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


def activity(id, category, minutes, energy, moves=False):
    return {"id": id, "category": category, "duration_minutes": minutes,
            "energy_level": energy, "involves_movement": moves}


# A small catalog, already in sort_order like the real query returns it.
CATALOG = [
    activity(1, "mindfulness_rest", 10, "low"),
    activity(2, "outdoor_movement", 20, "medium", moves=True),   # e.g. a brisk walk
    activity(3, "solo_exploration", 120, "high"),
    activity(4, "social_connection", 15, "low"),
    activity(5, "social_connection", 60, "high"),
    activity(6, "mindfulness_rest", 5, "low"),
    activity(7, "outdoor_movement", 45, "medium", moves=True),
    activity(8, "solo_exploration", 30, "medium"),
]
LOW_DEMAND = {a["id"] for a in CATALOG if a["energy_level"] == "low"}


def by_id(ids):
    return [next(a for a in CATALOG if a["id"] == i) for i in ids]


def test_returns_max_recommendations():
    assert len(choose_activity_ids(make_check_in(), CATALOG)) == MAX_RECOMMENDATIONS


def test_energy_allows_demand_levels():
    for energy, allowed in (("low", {"low"}), ("medium", {"low", "medium"}),
                            ("high", {"low", "medium", "high"})):
        for check_in_kwargs in ({}, {"hardest_areas": ["feeling_lonely"]}, {"contact_urge": 9}):
            ids = choose_activity_ids(make_check_in(energy_level=energy, **check_in_kwargs), CATALOG)
            assert {a["energy_level"] for a in by_id(ids)} <= allowed


def test_too_few_suitable_activities_gives_a_shorter_deck():
    # Only one activity fits low energy: nothing above it is added to fill up.
    catalog = [a for a in CATALOG if a["energy_level"] != "low"] + [CATALOG[0]]
    assert choose_activity_ids(make_check_in(energy_level="low"), catalog) == [1]


def test_energy_is_demand_not_duration():
    long_and_quiet = activity(20, "mindfulness_rest", 45, "low")        # a long, restful session
    short_and_demanding = activity(21, "social_connection", 5, "high")  # brief, but socially hard
    catalog = [long_and_quiet, short_and_demanding]
    low = choose_activity_ids(make_check_in(energy_level="low", hardest_areas=["feeling_lonely"]), catalog)
    assert low == [20]
    high = choose_activity_ids(make_check_in(energy_level="high", hardest_areas=["feeling_lonely"]), catalog)
    assert high == [21, 20]


def test_feeling_lonely_puts_social_connection_first():
    ids = choose_activity_ids(make_check_in(hardest_areas=["feeling_lonely"]), CATALOG)
    assert by_id(ids)[0]["category"] == "social_connection"


def test_high_urge_puts_quick_movement_first():
    ids = choose_activity_ids(make_check_in(contact_urge=9), CATALOG)
    first = by_id(ids)[0]
    assert first["involves_movement"] and first["duration_minutes"] <= 20


def test_strong_urge_prefers_movement_over_sitting_outside():
    sit_outside = activity(30, "outdoor_movement", 5, "low")               # outdoors, but not movement
    gentle_walk = activity(31, "outdoor_movement", 10, "low", moves=True)
    calm_corner = activity(32, "mindfulness_rest", 5, "low")
    catalog = [sit_outside, calm_corner, gentle_walk]                      # the walk is last in catalog order
    ids = choose_activity_ids(make_check_in(energy_level="low", contact_urge=9), catalog)
    assert ids[0] == 31


def test_strong_urge_never_boosts_strenuous_exercise():
    hard_sprint = activity(40, "outdoor_movement", 15, "high", moves=True)
    gentle_walk = activity(41, "outdoor_movement", 15, "medium", moves=True)
    ids = choose_activity_ids(make_check_in(energy_level="high", contact_urge=9), [hard_sprint, gentle_walk])
    assert ids[0] == 41  # the gentle one wins, though the strenuous one comes first in catalog order
    # And with low energy the strenuous one isn't eligible at all.
    assert choose_activity_ids(make_check_in(energy_level="low", contact_urge=10), [hard_sprint]) == []


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
    ids = choose_activity_ids(check_in, CATALOG, recent_activity_ids=LOW_DEMAND)
    assert len(ids) == MAX_RECOMMENDATIONS
    assert set(ids) <= LOW_DEMAND  # still respects energy, even though all were recent


# ── Saved activities ("Save for later") ─────────────────────────────────

def test_no_saved_activities_gives_three_regular_cards():
    ids = choose_activity_ids(make_check_in(hardest_areas=["feeling_lonely"]), CATALOG, set())
    assert len(ids) == len(set(ids)) == MAX_RECOMMENDATIONS


def test_matching_saved_activity_comes_last():
    # Lonely → Social Connection. Saved #5 (Social Connection, 60 min) suits a high-energy day.
    check_in = make_check_in(hardest_areas=["feeling_lonely"])
    without = choose_activity_ids(check_in, CATALOG)
    ids = choose_activity_ids(check_in, CATALOG, {5})
    assert ids[-1] == 5 and 5 not in ids[:-1]
    assert ids[:2] == [i for i in without if i != 5][:2]  # first two: today's check-in only


def test_saved_activity_is_never_first_even_if_it_is_the_best_fit():
    check_in = make_check_in(hardest_areas=["feeling_lonely"])
    best = choose_activity_ids(check_in, CATALOG)[0]
    ids = choose_activity_ids(check_in, CATALOG, {best})
    assert ids[0] != best and ids[-1] == best


def test_at_most_one_saved_activity():
    check_in = make_check_in(hardest_areas=["feeling_lonely"], feeling="hopeful")
    saved = {3, 4, 5, 8}
    ids = choose_activity_ids(check_in, CATALOG, saved)
    assert len(set(ids) & saved) == 1
    assert ids[-1] in saved


def test_saved_activity_that_does_not_match_the_check_in_is_left_out():
    # Heavy + wanting answers point to Mindfulness & Rest / Outdoor & Movement, never Solo Exploration.
    check_in = make_check_in(feeling="heavy", hardest_areas=["wanting_answers"])
    ids = choose_activity_ids(check_in, CATALOG, {8})  # 8 = Solo Exploration, 30 min
    assert 8 not in ids
    assert ids == choose_activity_ids(check_in, CATALOG)  # a regular card instead


def test_saved_activity_above_todays_energy_is_not_forced_in():
    check_in = make_check_in(energy_level="low", hardest_areas=["rebuilding_confidence"])
    ids = choose_activity_ids(check_in, CATALOG, {3})  # 3 is Solo Exploration but high demand
    assert 3 not in ids


def test_saved_activity_still_shows_even_if_recent():
    # Saved #2 (Outdoor & Movement) suits "getting through"; recently shown doesn't stop it.
    ids = choose_activity_ids(make_check_in(), CATALOG, {2}, recent_activity_ids={2})
    assert ids[-1] == 2


def test_strong_urge_keeps_quick_movement_first_with_saved_activities():
    check_in = make_check_in(contact_urge=9, hardest_areas=["feeling_lonely"])
    ids = choose_activity_ids(check_in, CATALOG, {5})
    first = by_id(ids)[0]
    assert first["involves_movement"] and first["duration_minutes"] <= 20
    assert ids[-1] == 5


def test_saved_activity_respects_variety():
    # The first two are already both Social Connection, so a saved Social Connection can't be third.
    check_in = make_check_in(hardest_areas=["feeling_lonely"], feeling="hopeful", energy_level="low")
    catalog = CATALOG + [
        activity(9, "social_connection", 5, "low"),
        activity(10, "social_connection", 10, "low"),
    ]
    ids = choose_activity_ids(check_in, catalog, {10})
    assert [a["category"] for a in by_id_in(catalog, ids[:2])] == ["social_connection"] * 2
    assert 10 not in ids  # a third Social Connection would break the variety rule
    assert len(ids) == 3 and by_id_in(catalog, ids)[2]["category"] != "social_connection"


def test_limited_activities_saved_still_comes_after_every_regular_card():
    # Low energy: only the low-demand #1 and #6 (Mindfulness & Rest) and #4 (Social Connection) fit.
    check_in = make_check_in(energy_level="low", hardest_areas=["feeling_lonely"])
    ids = choose_activity_ids(check_in, CATALOG, {4})
    assert ids[-1] == 4
    assert set(ids[:-1]) == {1, 6}


def test_never_more_than_three_and_never_duplicates():
    for saved in (set(), {1}, {2, 4}, {1, 2, 3, 4, 5, 6, 7, 8}):
        for answers in ({}, {"energy_level": "low"}, {"contact_urge": 10},
                        {"hardest_areas": ["feeling_lonely", "resisting_contact"]}):
            ids = choose_activity_ids(make_check_in(**answers), CATALOG, saved, {1, 2})
            assert len(ids) <= MAX_RECOMMENDATIONS
            assert len(ids) == len(set(ids))
            assert len(set(ids) & saved) <= 1


def by_id_in(catalog, ids):
    return [next(a for a in catalog if a["id"] == i) for i in ids]


# ── Energy picks how demanding the activities are ───────────────────────

def test_medium_energy_leans_towards_medium_demand():
    ids = choose_activity_ids(make_check_in(energy_level="medium"), CATALOG)
    activities = by_id(ids)
    assert all(a["energy_level"] in ("low", "medium") for a in activities)
    assert activities[0]["energy_level"] == "medium"


def test_high_energy_leans_towards_fuller_activities():
    high = by_id(choose_activity_ids(make_check_in(energy_level="high"), CATALOG))
    medium = by_id(choose_activity_ids(make_check_in(energy_level="medium"), CATALOG))
    assert sum(a["energy_level"] == "high" for a in high) >= 2
    assert not any(a["energy_level"] == "high" for a in medium)


def test_energy_changes_the_result_for_the_same_feelings():
    answers = {"feeling": "hopeful", "hardest_areas": ["rebuilding_confidence"]}
    results = {
        level: choose_activity_ids(make_check_in(energy_level=level, **answers), CATALOG)
        for level in ("low", "medium", "high")
    }
    assert results["low"] != results["medium"] != results["high"] != results["low"]


def test_strong_urge_still_wins_over_high_energy():
    ids = choose_activity_ids(make_check_in(energy_level="high", contact_urge=9), CATALOG)
    first = by_id(ids)[0]
    assert first["involves_movement"] and first["energy_level"] != "high"
    assert first["duration_minutes"] <= 20


def test_what_feels_hardest_still_picks_the_category_on_high_energy():
    # Lonely: a Social Connection activity beats activities from other categories.
    ids = choose_activity_ids(
        make_check_in(energy_level="high", hardest_areas=["feeling_lonely"]), CATALOG
    )
    assert by_id(ids)[0]["category"] == "social_connection"


def test_every_answer_can_change_the_cards():
    base = {"feeling": "getting_through", "contact_urge": 3, "energy_level": "medium",
            "hardest_areas": []}
    baseline = choose_activity_ids(make_check_in(**base), CATALOG)
    for change in ({"feeling": "heavy"}, {"contact_urge": 9}, {"energy_level": "low"},
                   {"energy_level": "high"}, {"hardest_areas": ["feeling_lonely"]}):
        assert choose_activity_ids(make_check_in(**{**base, **change}), CATALOG) != baseline, change


# ── Reasons ("Why this fits today") ─────────────

def test_reason_names_the_hardest_area_that_picked_the_card():
    check_in = make_check_in(hardest_areas=["resisting_contact"])
    text = reason(activity(2, "outdoor_movement", 20, "medium", moves=True), check_in)
    assert text.startswith("You said not reaching out is one of the hardest parts right now")
    assert "getting outside or moving a little" in text


def test_reason_uses_the_feeling_when_no_hardest_area_points_to_it():
    check_in = make_check_in(feeling="heavy", hardest_areas=["feeling_lonely"])
    text = reason(activity(1, "mindfulness_rest", 10, "low"), check_in)
    assert text == "Today feels heavy, so something calm and quiet might help."


def test_reason_prefers_the_answer_with_more_points():
    # feeling_lonely gives social_connection 3 points, hopeful gives it 1.
    check_in = make_check_in(feeling="hopeful", hardest_areas=["feeling_lonely"])
    text = reason(activity(4, "social_connection", 15, "low"), check_in)
    assert text.startswith("You said feeling lonely")


def test_strong_urge_reason_only_for_quick_gentle_movement():
    check_in = make_check_in(contact_urge=9)
    walk = activity(2, "outdoor_movement", 20, "medium", moves=True)
    long_walk = activity(7, "outdoor_movement", 45, "medium", moves=True)
    assert reason(walk, check_in).startswith("Your urge to reach out is strong today")
    assert not (reason(long_walk, check_in) or "").startswith("Your urge")


def test_reason_falls_back_to_energy_then_nothing():
    check_in = make_check_in(feeling="getting_through", energy_level="medium")
    solo = activity(8, "solo_exploration", 30, "medium")   # no answer points to it
    assert reason(solo, check_in) == "It fits the medium energy you have today."
    assert reason(activity(3, "solo_exploration", 120, "high"), check_in) is None


def test_reason_never_mentions_an_answer_the_user_did_not_give():
    for feeling in ("heavy", "getting_through", "missing_them", "hopeful"):
        for area in ("feeling_lonely", "missing_relationship", "wanting_answers",
                     "resisting_contact", "rebuilding_confidence"):
            check_in = make_check_in(feeling=feeling, hardest_areas=[area], contact_urge=2)
            for a in CATALOG:
                text = reason(a, check_in) or ""
                assert "urge" not in text
                other_areas = set(HARDEST_AREA_REASONS) - {area}
                assert not any(HARDEST_AREA_REASONS[o] in text for o in other_areas)
                other_feelings = set(FEELING_REASONS) - {feeling}
                assert not any(FEELING_REASONS[o] in text for o in other_feelings)


def test_second_card_of_a_kind_gets_a_different_true_reason():
    check_in = make_check_in(feeling="heavy", hardest_areas=["wanting_answers"])
    first = reason(activity(1, "mindfulness_rest", 10, "low"), check_in)
    second = reason(activity(6, "mindfulness_rest", 5, "low"), check_in, already_used={first})
    assert first != second
    assert {first, second} == set(reasons(activity(1, "mindfulness_rest", 10, "low"), check_in))
    # With only one true thing to say, it is repeated rather than invented.
    only = make_check_in(feeling="getting_through")
    walk = activity(2, "outdoor_movement", 20, "medium", moves=True)
    text = reason(walk, only)
    assert reason(walk, only, already_used={text}) == text
