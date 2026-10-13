"""
Scrapbook photo endpoints. The database is real (like test_api.py), but S3 is
replaced by a small in-memory fake, so these tests never need AWS credentials.
"""
import uuid

import pytest
from fastapi.testclient import TestClient

from app import media
from app.main import app

client = TestClient(app)

def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def start_upload(installation_id: str) -> tuple[int, str]:
    response = client.post("/scrapbook/photos", headers=headers(installation_id))
    assert response.status_code == 201
    body = response.json()
    return body["id"], body["upload_url"].removeprefix("https://s3.example/put/")


def test_scrapbook_needs_s3_settings(installation_id):
    # No fake_s3 here, and the test .env has no AWS settings.
    if media.is_configured():
        pytest.skip("AWS settings are present in .env")
    response = client.post("/scrapbook/photos", headers=headers(installation_id))
    assert response.status_code == 503


def test_photo_upload_flow(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    photo_id, key = start_upload(installation_id)

    # The S3 key must not reveal who the photo belongs to.
    assert installation_id not in key
    assert key.startswith("scrapbook/") and key.endswith(".jpg")

    # Can't be completed (or used in a memory) until the file is really in S3.
    early = client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    assert early.status_code == 409

    uploaded[key] = 250_000
    done = client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    assert done.status_code == 200
    assert done.json()["id"] == photo_id
    assert done.json()["image_url"] == f"https://s3.example/get/{key}"


def test_deleting_a_photo_keeps_its_memory(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 1000
    client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    check_in = {"feeling": "hopeful", "contact_urge": 2, "energy_level": "high",
                "hardest_areas": [], "local_date": "2026-10-05"}
    client.post("/check-ins", json=check_in, headers=headers(installation_id))
    card = client.get("/recommendations/latest", headers=headers(installation_id)).json()[
        "recommendations"][0]
    selection = client.post(
        f"/recommendations/{card['id']}/selection", headers=headers(installation_id)
    ).json()
    memory = client.post(
        "/reflections",
        json={"activity_selection_id": selection["id"], "photo_id": photo_id, "note": "kept",
              "thought_about_ex": "not_really", "mood_change": "much_better",
              "local_date": "2026-10-05"},
        headers=headers(installation_id),
    ).json()

    gone = client.delete(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id))
    assert gone.status_code == 204
    assert deleted == [key]

    [after] = client.get("/reflections", headers=headers(installation_id)).json()
    assert after["id"] == memory["id"]
    assert after["note"] == "kept"
    assert after["photo_id"] is None and after["image_url"] is None


def test_too_large_photo_is_removed(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 6 * 1024 * 1024

    response = client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    assert response.status_code == 413
    assert deleted == [key]
    again = client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    assert again.status_code == 404


def test_cannot_touch_another_installations_photo(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 1000

    stranger = headers(str(uuid.uuid4()))
    assert client.post(f"/scrapbook/photos/{photo_id}/complete", headers=stranger).status_code == 404
    assert client.delete(f"/scrapbook/photos/{photo_id}", headers=stranger).status_code == 404
    assert deleted == []
