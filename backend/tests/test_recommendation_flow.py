"""
End-to-end checks that check-in answers really shape the activity cards,
using the real activity catalog in the database (run `python -m scripts.migrate`
first). Like test_api.py, every test uses brand-new installation IDs that are
deleted afterwards.

    pytest tests/test_recommendation_flow.py
"""
import psycopg
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)

LOW_ENERGY_DAY = {
    "feeling": "heavy",
    "contact_urge": 3,
    "energy_level": "low",
    "hardest_areas": ["wanting_answers"],
    "local_date": "2026-10-15",
}
HIGH_ENERGY_DAY = {
    "feeling": "hopeful",
    "contact_urge": 2,
    "energy_level": "high",
    "hardest_areas": ["rebuilding_confidence"],
    "local_date": "2026-10-15",
}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def check_in_and_get_cards(installation_id: str, answers: dict) -> dict:
    saved = client.post("/check-ins", json=answers, headers=headers(installation_id))
    assert saved.status_code == 201, saved.text
    latest = client.get("/recommendations/latest", headers=headers(installation_id))
    assert latest.status_code == 200
    body = latest.json()
    assert body["check_in_id"] == saved.json()["id"]
    return body


def demands(body: dict) -> list[str]:
    return [r["activity"]["energy_level"] for r in body["recommendations"]]


def categories(body: dict) -> list[str]:
    return [r["activity"]["category"] for r in body["recommendations"]]


def test_low_and_high_energy_days_get_different_activities(installation_id, other_installation_id):
    low = check_in_and_get_cards(installation_id, LOW_ENERGY_DAY)
    high = check_in_and_get_cards(other_installation_id, HIGH_ENERGY_DAY)

    assert len(low["recommendations"]) == len(high["recommendations"]) == 3
    # Low energy: only low-demand activities, led by Mindfulness & Rest (heavy + wanting answers).
    assert set(demands(low)) == {"low"}
    assert categories(low)[0] == "mindfulness_rest"
    # High energy and rebuilding confidence: fuller activities, led by Solo Exploration.
    assert demands(high).count("high") >= 2
    assert categories(high)[0] == "solo_exploration"
    assert not {r["activity"]["id"] for r in low["recommendations"]} & {
        r["activity"]["id"] for r in high["recommendations"]
    }


def test_medium_energy_sits_between_low_and_high(installation_id, other_installation_id):
    medium = check_in_and_get_cards(installation_id, {**HIGH_ENERGY_DAY, "energy_level": "medium"})
    low = check_in_and_get_cards(other_installation_id, {**HIGH_ENERGY_DAY, "energy_level": "low"})

    assert set(demands(medium)) <= {"low", "medium"} and "medium" in demands(medium)
    assert set(demands(low)) == {"low"}
    # Same feelings, so the same kind of activities, just a different demand.
    assert categories(medium)[0] == categories(low)[0] == "solo_exploration"


def test_strong_urge_puts_quick_movement_first_even_with_high_energy(installation_id):
    body = check_in_and_get_cards(installation_id, {**HIGH_ENERGY_DAY, "contact_urge": 9,
                                                    "hardest_areas": ["resisting_contact"]})
    first = body["recommendations"][0]["activity"]
    assert first["category"] == "outdoor_movement"
    assert first["duration_minutes"] <= 20 and first["energy_level"] != "high"
    # Real movement, not one of the sit-and-notice outdoor activities.
    assert first["slug"] not in {"notice_nature_outside", "green_courtyard", "watch_the_sky", "watch_wildlife"}


def test_cards_follow_the_newest_answers(installation_id):
    check_in_and_get_cards(installation_id, {**HIGH_ENERGY_DAY, "local_date": "2026-10-14"})
    body = check_in_and_get_cards(installation_id, LOW_ENERGY_DAY)  # the next day

    assert body["check_in"]["energy_level"] == "low"
    assert body["check_in"]["feeling"] == "heavy"
    assert set(demands(body)) == {"low"}


def test_each_installation_only_sees_its_own_cards(installation_id, other_installation_id):
    mine = check_in_and_get_cards(installation_id, LOW_ENERGY_DAY)
    theirs = check_in_and_get_cards(other_installation_id, HIGH_ENERGY_DAY)

    again = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert again["check_in_id"] == mine["check_in_id"] != theirs["check_in_id"]
    assert again["check_in"]["energy_level"] == "low"
    assert {r["id"] for r in again["recommendations"]} == {r["id"] for r in mine["recommendations"]}


def test_invalid_answers_are_rejected_without_saving(installation_id):
    for bad in ({"energy_level": "very_high"}, {"contact_urge": 0}, {"hardest_areas": ["boredom"]},
                {"feeling": None}):
        response = client.post("/check-ins", json={**LOW_ENERGY_DAY, **bad}, headers=headers(installation_id))
        assert response.status_code == 422, bad
    latest = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert latest["check_in_id"] is None and latest["recommendations"] == []


def test_card_text_never_assumes_the_users_answers():
    # "Why this fits today" is the same for everyone who gets the card, so it
    # must describe the activity, not claim how this user feels.
    with psycopg.connect(settings.database_url) as conn:
        rows = conn.execute(
            """
            SELECT slug FROM activities
            WHERE is_active AND (why_it_fits ILIKE '%your energy is%'
                                 OR why_it_fits ILIKE '%urge to reach out is%')
            """
        ).fetchall()
    assert rows == []


def test_cards_carry_a_reason_from_todays_answers(installation_id):
    body = check_in_and_get_cards(installation_id, {
        "feeling": "missing_them",
        "contact_urge": 3,
        "energy_level": "medium",
        "hardest_areas": ["resisting_contact"],
        "local_date": "2026-10-15",
    })
    reasons = [r["reason"] for r in body["recommendations"]]
    assert reasons and all(reasons)
    assert any("not reaching out" in r or "missing them" in r for r in reasons)
    # Loading the cards again shows the same saved text.
    again = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert [r["reason"] for r in again["recommendations"]] == reasons
