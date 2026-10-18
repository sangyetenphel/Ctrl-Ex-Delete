"""'Save for later': bookmarks never select anything, and a saved activity that
suits the next check-in comes back as its last card."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)

CHECK_IN = {
    "feeling": "hopeful",
    "contact_urge": 2,
    "energy_level": "high",
    "hardest_areas": [],
    "local_date": "2026-10-06",
}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


_check_ins_made: dict[str, int] = {}


def check_in_and_list(installation_id: str) -> list[dict]:
    # One check-in per day: each call checks in on the following day.
    days = _check_ins_made[installation_id] = _check_ins_made.get(installation_id, -1) + 1
    local_date = date.fromisoformat(CHECK_IN["local_date"]) + timedelta(days=days)
    client.post("/check-ins", json={**CHECK_IN, "local_date": str(local_date)}, headers=headers(installation_id))
    return client.get("/recommendations/latest", headers=headers(installation_id)).json()[
        "recommendations"
    ]


def test_save_and_remove(installation_id):
    cards = check_in_and_list(installation_id)
    activity_id = cards[2]["activity"]["id"]
    assert cards[2]["is_saved"] is False

    first = client.put(f"/bookmarks/{activity_id}", headers=headers(installation_id))
    again = client.put(f"/bookmarks/{activity_id}", headers=headers(installation_id))
    assert (first.status_code, again.status_code) == (201, 200)  # no duplicates

    saved = client.get("/bookmarks", headers=headers(installation_id)).json()
    assert [b["activity"]["id"] for b in saved] == [activity_id]
    refreshed = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert refreshed["recommendations"][2]["is_saved"] is True

    # Saving is not choosing.
    assert refreshed["recommendations"][2]["status"] is None
    current = client.get("/activity-selections/current", headers=headers(installation_id)).json()
    assert current["selection"] is None

    assert client.delete(f"/bookmarks/{activity_id}", headers=headers(installation_id)).status_code == 204
    assert client.delete(f"/bookmarks/{activity_id}", headers=headers(installation_id)).status_code == 204
    assert client.get("/bookmarks", headers=headers(installation_id)).json() == []


def test_matching_saved_activity_comes_back_last_next_time(installation_id):
    cards = check_in_and_list(installation_id)
    last = cards[-1]["activity"]  # hopeful → Solo Exploration / Social Connection, so it still suits
    client.put(f"/bookmarks/{last['id']}", headers=headers(installation_id))

    next_cards = check_in_and_list(installation_id)
    assert len(next_cards) == 3
    assert next_cards[-1]["activity"]["id"] == last["id"]
    assert next_cards[-1]["is_saved"] is True
    assert not any(c["is_saved"] for c in next_cards[:-1])
    # The others are new: cards shown recently wait a few check-ins to come back.
    shown_before = {c["activity"]["id"] for c in cards}
    assert shown_before.isdisjoint(c["activity"]["id"] for c in next_cards[:-1])


def test_saved_activity_that_does_not_suit_the_check_in_stays_out(installation_id):
    cards = check_in_and_list(installation_id)
    solo = next(c["activity"] for c in cards if c["activity"]["category"] == "solo_exploration")
    client.put(f"/bookmarks/{solo['id']}", headers=headers(installation_id))

    # Heavy, low energy, wanting answers: nothing points to Solo Exploration.
    heavy_day = {**CHECK_IN, "feeling": "heavy", "energy_level": "low",
                 "hardest_areas": ["wanting_answers"], "local_date": "2026-10-07"}
    client.post("/check-ins", json=heavy_day, headers=headers(installation_id))
    body = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert solo["id"] not in {c["activity"]["id"] for c in body["recommendations"]}
    assert not any(c["is_saved"] for c in body["recommendations"])
    assert len(body["recommendations"]) == 3


def test_unknown_activity(installation_id):
    assert client.put("/bookmarks/999999", headers=headers(installation_id)).status_code == 404

def test_saved_activity_waits_after_it_is_completed(installation_id, fake_s3):
    def check_in_on(local_date):
        body = {**CHECK_IN, "local_date": local_date}
        assert client.post("/check-ins", json=body, headers=headers(installation_id)).status_code == 201
        return client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]

    card = check_in_on("2026-10-06")[0]
    client.put(f"/bookmarks/{card['activity']['id']}", headers=headers(installation_id))
    selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()
    assert client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection["id"], "thought_about_ex": "not_really",
        "mood_change": "a_little_better", "local_date": "2026-10-06", "note": "A quiet moment",
        "photo_id": upload_test_photo(client, installation_id, fake_s3[0]),
    }).status_code == 201

    # Completed 2 days ago: not offered yet.
    assert card["activity"]["id"] not in {c["activity"]["id"] for c in check_in_on("2026-10-08")}
    # 3 days later it's offered again, as the last card.
    assert check_in_on("2026-10-09")[-1]["activity"]["id"] == card["activity"]["id"]
