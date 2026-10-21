"""
Progress & Insights. Unit tests for the calculations (app/insights.py) plus
API tests against the real database with controlled data.
"""
from datetime import date

import pytest

from fastapi.testclient import TestClient

from app import insights
from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)

TODAY = date(2026, 10, 14)  # a Wednesday; week = Oct 12–18, month = Oct 1–31


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


# What storage reads from activity_categories (migration 011), in display order.
CATEGORIES = [
    {"category": "outdoor_movement", "label": "Outdoor & Movement"},
    {"category": "mindfulness_rest", "label": "Mindfulness & Rest"},
    {"category": "solo_exploration", "label": "Solo Exploration"},
    {"category": "social_connection", "label": "Social Connection"},
]


def records(check_ins=(), completed=(), moods=(), journey_started_on=None):
    return {
        "journey_started_on": journey_started_on,
        "check_ins": [{"local_date": d, "contact_urge": u} for d, u in check_ins],
        "completed": [{"completed_on": d, "category": c} for d, c in completed],
        "moods": [{"local_date": d, "mood_change": m, "category": c} for d, m, c in moods],
        "categories": CATEGORIES,
    }


# ── Calculations ─────────────────────────────

def test_period_bounds():
    assert insights.period_bounds("week", TODAY) == (date(2026, 10, 12), date(2026, 10, 18))
    assert insights.period_bounds("month", TODAY) == (date(2026, 10, 1), date(2026, 10, 31))
    assert insights.period_bounds("week", date(2026, 10, 12))[0] == date(2026, 10, 12)  # Monday
    assert insights.period_bounds("month", date(2028, 2, 10))[1] == date(2028, 2, 29)


def test_empty_state_invents_nothing():
    result = insights.build("week", TODAY, records())
    assert result.has_data is False
    assert [p.value for p in result.urges] == [None] * 7
    assert [p.label for p in result.urges] == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    assert all(m.count == 0 for m in result.moods)
    assert [p.value for p in result.mood_points] == [None] * 7  # gaps, not zeros
    assert all(p.answers == [] for p in result.mood_points)
    assert all(c.count == 0 and c.percent == 0 for c in result.categories)
    assert result.observations == []
    assert result.takeaway.headline == "Your patterns will appear here."


def test_urges_average_per_day_and_gaps_stay_empty():
    result = insights.build("week", TODAY, records(check_ins=[
        (date(2026, 10, 12), 7), (date(2026, 10, 12), 4), (date(2026, 10, 14), 2),
    ]))
    values = [p.value for p in result.urges]
    assert values == [6, None, 2, None, None, None, None]  # (7+4)/2 = 5.5 → 6
    assert result.urges[0].check_ins == 2
    assert result.check_in_days == 2


def test_month_has_one_bar_per_week_of_the_month():
    result = insights.build("month", TODAY, records(check_ins=[(date(2026, 10, 3), 8), (date(2026, 10, 30), 3)]))
    assert [p.label for p in result.urges] == ["Oct 1", "Oct 8", "Oct 15", "Oct 22", "Oct 29"]
    assert (result.urges[4].start, result.urges[4].end) == (date(2026, 10, 29), date(2026, 10, 31))
    assert [p.value for p in result.urges] == [8, None, None, None, 3]


def test_month_starts_at_the_first_check_in():
    # Started on Oct 18: no empty weeks before it, and the first bar starts that day.
    result = insights.build("month", date(2026, 10, 25), records(
        check_ins=[(date(2026, 10, 18), 6), (date(2026, 10, 23), 4)],
        journey_started_on=date(2026, 10, 18),
    ))
    assert [p.label for p in result.urges] == ["Oct 18", "Oct 22", "Oct 29"]
    assert (result.urges[0].start, result.urges[0].end) == (date(2026, 10, 18), date(2026, 10, 21))
    assert [p.value for p in result.urges] == [6, 4, None]
    assert [p.label for p in result.mood_points] == ["Oct 18", "Oct 22", "Oct 29"]


def test_month_keeps_every_week_for_someone_who_started_earlier():
    result = insights.build("month", TODAY, records(journey_started_on=date(2026, 9, 20)))
    assert [p.label for p in result.urges] == ["Oct 1", "Oct 8", "Oct 15", "Oct 22", "Oct 29"]


def test_week_view_is_never_trimmed():
    result = insights.build("week", TODAY, records(journey_started_on=date(2026, 10, 14)))
    assert [p.label for p in result.urges] == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def test_categories_count_completed_only_with_percentages():
    result = insights.build("week", TODAY, records(completed=[
        (date(2026, 10, 12), "outdoor_movement"),
        (date(2026, 10, 13), "outdoor_movement"),
        (date(2026, 10, 14), "mindfulness_rest"),
    ]))
    shares = {c.category: (c.count, c.percent) for c in result.categories}
    assert shares == {
        "outdoor_movement": (2, 67),
        "mindfulness_rest": (1, 33),
        "solo_exploration": (0, 0),
        "social_connection": (0, 0),
    }
    assert result.takeaway.headline == "Outdoor & Movement stood out."
    assert "You completed 3 activities this week." in result.observations


def test_mood_answers_are_still_counted_as_given():
    result = insights.build("week", TODAY, records(moods=[
        (date(2026, 10, 12), "much_better", "outdoor_movement"),
        (date(2026, 10, 13), "a_little_better", "outdoor_movement"),
        (date(2026, 10, 14), "worse", "mindfulness_rest"),
    ]))
    assert [(m.response, m.count) for m in result.moods] == [
        ("worse", 1), ("about_the_same", 0), ("a_little_better", 1), ("much_better", 1),
    ]
    assert "You reported feeling better after 2 of 2 Outdoor & Movement activities." in result.observations
    # One reflection isn't enough to say anything about Mindfulness & Rest.
    assert not any("Mindfulness & Rest" in o for o in result.observations)


def test_mood_scores_are_fixed():
    assert insights.MOOD_SCORES == {
        "worse": 2, "about_the_same": 5, "a_little_better": 7, "much_better": 9,
    }


def test_mood_chart_averages_each_day_and_leaves_gaps():
    result = insights.build("week", TODAY, records(moods=[
        (date(2026, 10, 12), "much_better", "outdoor_movement"),      # Mon: 9
        (date(2026, 10, 14), "worse", "mindfulness_rest"),            # Wed: (2 + 7) / 2
        (date(2026, 10, 14), "a_little_better", "solo_exploration"),
        (date(2026, 10, 18), "about_the_same", "social_connection"),  # Sun: 5
    ]))
    points = result.mood_points
    assert [p.label for p in points] == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    assert [p.value for p in points] == [9, None, 4.5, None, None, None, 5]
    assert points[2].answers == ["worse", "a_little_better"]
    assert points[1].answers == []


def test_mood_chart_skips_unknown_answers_instead_of_guessing():
    result = insights.build("week", TODAY, records(moods=[
        (date(2026, 10, 13), "great", "outdoor_movement"),     # not one of the four answers
        (date(2026, 10, 15), "great", "outdoor_movement"),
        (date(2026, 10, 15), "much_better", "outdoor_movement"),
    ]))
    assert [p.value for p in result.mood_points] == [None, None, None, 9, None, None, None]


def test_mood_chart_only_uses_this_weeks_days():
    # Sunday Oct 11 belongs to last week and Monday Oct 19 to next week.
    result = insights.build("week", TODAY, records(moods=[
        (date(2026, 10, 11), "worse", "outdoor_movement"),
        (date(2026, 10, 19), "worse", "outdoor_movement"),
        (date(2026, 10, 12), "much_better", "outdoor_movement"),
    ]))
    assert [p.value for p in result.mood_points] == [9, None, None, None, None, None, None]


def test_mood_chart_month_view_averages_each_week():
    result = insights.build("month", TODAY, records(moods=[
        (date(2026, 10, 2), "worse", "outdoor_movement"),
        (date(2026, 10, 5), "much_better", "outdoor_movement"),
    ]))
    assert result.mood_points[0].label == "Oct 1"
    assert result.mood_points[0].value == 5.5
    assert all(p.value is None for p in result.mood_points[1:])


def test_urge_chart_ignores_mood_answers_and_the_other_way_round():
    result = insights.build("week", TODAY, records(
        check_ins=[(date(2026, 10, 12), 8)],
        moods=[(date(2026, 10, 13), "much_better", "outdoor_movement")],
    ))
    assert [p.value for p in result.urges][:2] == [8, None]
    assert [p.value for p in result.mood_points][:2] == [None, 9]


def test_urge_trend_needs_enough_days_and_a_real_change():
    two_days = records(check_ins=[(date(2026, 10, 12), 9), (date(2026, 10, 13), 2)])
    assert not any("urge" in o for o in insights.build("week", TODAY, two_days).observations)

    lower = records(check_ins=[(date(2026, 10, 12), 8), (date(2026, 10, 13), 7), (date(2026, 10, 14), 4), (date(2026, 10, 15), 3)])
    result = insights.build("week", TODAY, lower)
    assert any("was lower in your later check-ins" in o for o in result.observations)
    assert result.takeaway.headline == "Urges eased a little."

    steady = records(check_ins=[(date(2026, 10, 12), 5), (date(2026, 10, 13), 5), (date(2026, 10, 14), 5)])
    assert any("stayed fairly steady" in o for o in insights.build("week", TODAY, steady).observations)


def test_check_ins_only_takeaway():
    result = insights.build("week", TODAY, records(check_ins=[(date(2026, 10, 13), 5)]))
    assert result.has_data is True
    assert result.takeaway.headline == "You kept checking in."
    assert result.observations == ["You checked in on 1 day this week."]


# ── API with real records ────────────────────

UPLOADED: dict = {}  # replaced by fake_s3's dict for each test


@pytest.fixture(autouse=True)
def _photos_upload_to_fake_s3(fake_s3):
    # Share fake_s3's own dict: its fake "S3" reads the uploads from it.
    global UPLOADED
    UPLOADED = fake_s3[0]
    yield


def complete_activity(installation_id, card_index, local_date, mood="a_little_better"):
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    selection = client.post(
        f"/recommendations/{cards[card_index]['id']}/selection", headers=headers(installation_id)
    ).json()
    saved = client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection["id"], "thought_about_ex": "not_really",
        "mood_change": mood, "local_date": local_date, "note": "A quiet moment",
        "photo_id": upload_test_photo(client, installation_id, UPLOADED),
    })
    assert saved.status_code == 201
    return saved.json()


def check_in(installation_id, local_date, urge):
    body = {"feeling": "hopeful", "contact_urge": urge, "energy_level": "medium",
            "hardest_areas": [], "local_date": local_date}
    assert client.post("/check-ins", json=body, headers=headers(installation_id)).status_code == 201


def get_insights(installation_id, period="week", today="2026-10-14"):
    response = client.get(f"/insights?period={period}&today={today}", headers=headers(installation_id))
    assert response.status_code == 200
    return response.json()


def test_api_new_user_gets_the_empty_state(installation_id):
    body = get_insights(installation_id)
    assert body["has_data"] is False and body["completed"] == 0
    assert body["start"] == "2026-10-12" and body["end"] == "2026-10-18"


def test_api_counts_only_completed_activities_once(installation_id):
    check_in(installation_id, "2026-10-12", 8)
    first_two = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][:2]
    complete_activity(installation_id, 0, "2026-10-12")
    complete_activity(installation_id, 1, "2026-10-13", "much_better")
 
    # Abandoned, bookmarked and in-progress activities don't count.
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    client.put(f"/bookmarks/{cards[2]['activity']['id']}", headers=headers(installation_id))
    started = client.post(f"/recommendations/{cards[2]['id']}/selection", headers=headers(installation_id)).json()
    client.post(f"/activity-selections/{started['id']}/abandon", headers=headers(installation_id))
    client.post(f"/recommendations/{cards[2]['id']}/selection", headers=headers(installation_id))
 
    week = get_insights(installation_id)
    assert week["completed"] == 2
    expected = {"outdoor_movement": 0, "mindfulness_rest": 0, "solo_exploration": 0, "social_connection": 0}
    for card in first_two:
        expected[card["activity"]["category"]] += 1
    assert {c["category"]: c["count"] for c in week["categories"]} == expected
    assert {m["response"]: m["count"] for m in week["moods"]} == {
        "worse": 0, "about_the_same": 0, "a_little_better": 1, "much_better": 1,
    }
    assert week["urges"][0]["value"] == 8 and week["urges"][1]["value"] is None



def test_api_week_and_month_use_their_own_boundaries(installation_id):
    check_in(installation_id, "2026-10-02", 9)   # earlier this month, not this week
    check_in(installation_id, "2026-10-13", 3)
    check_in(installation_id, "2026-09-30", 5)   # last month: in neither

    week = get_insights(installation_id, "week")
    month = get_insights(installation_id, "month")
    assert week["check_in_days"] == 1
    assert month["check_in_days"] == 2
    assert [p["value"] for p in month["urges"]][:2] == [9, 3]


def test_api_month_starts_at_the_first_check_in(installation_id):
    check_in(installation_id, "2026-10-13", 4)
    month = get_insights(installation_id, "month")
    assert [p["label"] for p in month["urges"]] == ["Oct 13", "Oct 15", "Oct 22", "Oct 29"]
    assert (month["urges"][0]["start"], month["urges"][0]["end"]) == ("2026-10-13", "2026-10-14")
    assert month["urges"][0]["value"] == 4


def test_api_deleting_a_memory_keeps_the_completion(installation_id):
    check_in(installation_id, "2026-10-13", 5)
    memory = complete_activity(installation_id, 0, "2026-10-13")

    assert client.delete(f"/reflections/{memory['id']}", headers=headers(installation_id)).status_code == 204
    assert client.delete(f"/reflections/{memory['id']}", headers=headers(installation_id)).status_code == 404
    assert client.get("/reflections", headers=headers(installation_id)).json() == []

    week = get_insights(installation_id)
    assert week["completed"] == 1                       # still done…
    assert sum(m["count"] for m in week["moods"]) == 0  # …but the deleted answers are gone
    assert all(p["value"] is None for p in week["mood_points"])
    summary = client.get("/progress/summary", headers=headers(installation_id)).json()
    assert summary["activities_completed"] == 1 and summary["memories"] == 0


def test_api_requires_today(installation_id):
    assert client.get("/insights", headers=headers(installation_id)).status_code == 422


def test_api_mood_chart_uses_the_completion_day_and_averages(installation_id):
    # Chosen after Monday's check-in, but completed (reflection saved) on Tuesday.
    check_in(installation_id, "2026-10-12", 6)
    complete_activity(installation_id, 0, "2026-10-13", "worse")
    complete_activity(installation_id, 1, "2026-10-13", "much_better")
    complete_activity(installation_id, 2, "2026-10-15", "about_the_same")

    week = get_insights(installation_id)
    assert [p["value"] for p in week["mood_points"]] == [None, 5.5, None, 5, None, None, None]
    assert week["mood_points"][1]["answers"] == ["worse", "much_better"]
    # The urge chart still shows only the check-in.
    assert [p["value"] for p in week["urges"]] == [6, None, None, None, None, None, None]

    # The next week starts on Monday Oct 19 with no answers yet.
    next_week = get_insights(installation_id, today="2026-10-19")
    assert next_week["start"] == "2026-10-19"
    assert all(p["value"] is None for p in next_week["mood_points"])
