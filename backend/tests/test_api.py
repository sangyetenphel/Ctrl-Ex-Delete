"""
End-to-end API tests. They use the real database in DATABASE_URL, so run
`python -m scripts.migrate` first. Every test uses a brand-new random
installation ID and deletes it afterwards (which also deletes its check-ins,
recommendations and selections), so other data is never touched.

    pytest
"""
import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

CHECK_IN = {
    "feeling": "missing_them",
    "contact_urge": 4,
    "energy_level": "medium",
    "hardest_areas": ["feeling_lonely", "resisting_contact"],
    "local_date": "2026-10-04",
}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_check_in_is_saved(installation_id):
    response = client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
    assert response.status_code == 201
    saved = response.json()
    assert saved["installation_id"] == installation_id
    assert saved["feeling"] == "missing_them"

    listed = client.get("/check-ins", headers=headers(installation_id)).json()
    assert [c["id"] for c in listed] == [saved["id"]]


def test_check_in_requires_valid_installation_id():
    assert client.post("/check-ins", json=CHECK_IN).status_code == 422
    bad = client.post("/check-ins", json=CHECK_IN, headers={"X-Installation-ID": "nope"})
    assert bad.status_code == 422


def test_check_in_rejects_bad_values(installation_id):
    bad = {**CHECK_IN, "contact_urge": 11}
    response = client.post("/check-ins", json=bad, headers=headers(installation_id))
    assert response.status_code == 422


def test_no_check_in_means_no_recommendations(installation_id):
    response = client.get("/recommendations/latest", headers=headers(installation_id))
    assert response.status_code == 200
    assert response.json() == {
        "check_in_id": None,
        "check_in_local_date": None,
        "recommendations": [],
    }


def test_recommendations_follow_latest_check_in(installation_id):
    first = client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id)).json()
    earlier = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    second = client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id)).json()

    body = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert body["check_in_id"] == second["id"] != first["id"]
    assert [r["position"] for r in body["recommendations"]] == [1, 2, 3]
    first_card = body["recommendations"][0]
    # Resisting contact + missing them makes outdoor movement the best fit.
    assert first_card["activity"]["category"] == "outdoor_movement"
    assert first_card["selected_at"] is None
    # Medium energy: nothing longer than 45 minutes.
    assert all(r["activity"]["duration_minutes"] <= 45 for r in body["recommendations"])
    # Same answers again still gives new cards: recent ones wait their turn.
    shown_before = {r["activity"]["id"] for r in earlier["recommendations"]}
    assert shown_before.isdisjoint(r["activity"]["id"] for r in body["recommendations"])


def test_select_recommendation(installation_id):
    client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
    body = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    recommendation = body["recommendations"][1]

    url = f"/recommendations/{recommendation['id']}/selection"
    created = client.post(url, headers=headers(installation_id))
    assert created.status_code == 201
    assert created.json()["activity_id"] == recommendation["activity"]["id"]
    assert created.json()["check_in_id"] == body["check_in_id"]
    assert created.json()["status"] == "in_progress"

    # Tapping again doesn't create a second row.
    again = client.post(url, headers=headers(installation_id))
    assert again.status_code == 200
    assert again.json()["id"] == created.json()["id"]

    refreshed = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert refreshed["recommendations"][1]["selected_at"] is not None


def test_cannot_select_another_installations_recommendation(installation_id):
    client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
    body = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    recommendation_id = body["recommendations"][0]["id"]

    stranger = str(uuid.uuid4())
    response = client.post(
        f"/recommendations/{recommendation_id}/selection", headers=headers(stranger)
    )
    assert response.status_code == 404
