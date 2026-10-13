"""
Progress & Insights. Unit tests for the calculations (app/insights.py) plus
API tests against the real database with controlled data.
"""
from datetime import date

from fastapi.testclient import TestClient

from app import insights
from app.main import app

client = TestClient(app)

TODAY = date(2026, 10, 14)  # a Wednesday; week = Oct 12–18, month = Oct 1–31


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def records(check_ins=(), completed=(), moods=()):
    return {
        "check_ins": [{"local_date": d, "contact_urge": u} for d, u in check_ins],
        "completed": [{"completed_on": d, "category": c} for d, c in completed],
        "moods": [{"local_date": d, "mood_change": m, "category": c} for d, m, c in moods],
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
    assert [p.label for p in result.urges] == ["W1", "W2", "W3", "W4", "W5"]
    assert (result.urges[4].start, result.urges[4].end) == (date(2026, 10, 29), date(2026, 10, 31))
    assert [p.value for p in result.urges] == [8, None, None, None, 3]


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
    assert result.takeaway.headline == "Outdoor & movement stood out."
    assert "You completed 3 activities this week." in result.observations


def test_moods_are_counted_as_given_never_scored():
    result = insights.build("week", TODAY, records(moods=[
        (date(2026, 10, 12), "much_better", "outdoor_movement"),
        (date(2026, 10, 13), "a_little_better", "outdoor_movement"),
        (date(2026, 10, 14), "worse", "mindfulness_rest"),
    ]))
    assert [(m.response, m.count) for m in result.moods] == [
        ("worse", 1), ("about_the_same", 0), ("a_little_better", 1), ("much_better", 1),
    ]
    assert "You reported feeling better after 2 of 2 outdoor & movement activities." in result.observations
    # One reflection isn't enough to say anything about mindfulness.
    assert not any("mindfulness" in o for o in result.observations)


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

def complete_activity(installation_id, card_index, local_date, mood="a_little_better"):
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    selection = client.post(
        f"/recommendations/{cards[card_index]['id']}/selection", headers=headers(installation_id)
    ).json()
    saved = client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection["id"], "thought_about_ex": "not_really",
        "mood_change": mood, "local_date": local_date,
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
    complete_activity(installation_id, 0, "2026-10-12")          # mindfulness_rest
    complete_activity(installation_id, 1, "2026-10-13", "much_better")  # outdoor_movement

    # Abandoned, bookmarked and in-progress activities don't count.
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    client.put(f"/bookmarks/{cards[2]['activity']['id']}", headers=headers(installation_id))
    started = client.post(f"/recommendations/{cards[2]['id']}/selection", headers=headers(installation_id)).json()
    client.post(f"/activity-selections/{started['id']}/abandon", headers=headers(installation_id))
    client.post(f"/recommendations/{cards[2]['id']}/selection", headers=headers(installation_id))

    week = get_insights(installation_id)
    assert week["completed"] == 2
    assert {c["category"]: c["count"] for c in week["categories"]} == {
        "outdoor_movement": 1, "mindfulness_rest": 1, "solo_exploration": 0, "social_connection": 0,
    }
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


def test_api_deleting_a_memory_keeps_the_completion(installation_id):
    check_in(installation_id, "2026-10-13", 5)
    memory = complete_activity(installation_id, 0, "2026-10-13")

    assert client.delete(f"/reflections/{memory['id']}", headers=headers(installation_id)).status_code == 204
    assert client.delete(f"/reflections/{memory['id']}", headers=headers(installation_id)).status_code == 404
    assert client.get("/reflections", headers=headers(installation_id)).json() == []

    week = get_insights(installation_id)
    assert week["completed"] == 1                       # still done…
    assert sum(m["count"] for m in week["moods"]) == 0  # …but the deleted answers are gone
    summary = client.get("/progress/summary", headers=headers(installation_id)).json()
    assert summary["activities_completed"] == 1 and summary["memories"] == 0


def test_api_requires_today(installation_id):
    assert client.get("/insights", headers=headers(installation_id)).status_code == 422
