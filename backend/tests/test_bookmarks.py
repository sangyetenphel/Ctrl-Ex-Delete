"""'Save for later': bookmarks never select anything and come first next time."""
from fastapi.testclient import TestClient

from app.main import app

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


def check_in_and_list(installation_id: str) -> list[dict]:
    client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
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


def test_saved_activities_come_first_next_time(installation_id):
    cards = check_in_and_list(installation_id)
    last = cards[-1]["activity"]
    client.put(f"/bookmarks/{last['id']}", headers=headers(installation_id))

    next_cards = check_in_and_list(installation_id)
    assert next_cards[0]["activity"]["id"] == last["id"]
    assert next_cards[0]["is_saved"] is True
    # The others keep their usual order behind it.
    assert [c["activity"]["id"] for c in next_cards[1:]] == [c["activity"]["id"] for c in cards[:-1]]


def test_unknown_activity(installation_id):
    assert client.put("/bookmarks/999999", headers=headers(installation_id)).status_code == 404
