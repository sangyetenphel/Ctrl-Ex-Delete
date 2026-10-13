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

NEW_PHOTO = {"caption": "Evening walk", "local_date": "2026-10-04"}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def start_upload(installation_id: str) -> tuple[int, str]:
    response = client.post("/scrapbook/photos", json=NEW_PHOTO, headers=headers(installation_id))
    assert response.status_code == 201
    body = response.json()
    return body["id"], body["upload_url"].removeprefix("https://s3.example/put/")


def test_scrapbook_needs_s3_settings(installation_id):
    # No fake_s3 here, and the test .env has no AWS settings.
    if media.is_configured():
        pytest.skip("AWS settings are present in .env")
    response = client.get("/scrapbook/photos", headers=headers(installation_id))
    assert response.status_code == 503


def test_photo_upload_flow(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    photo_id, key = start_upload(installation_id)

    # The S3 key must not reveal who the photo belongs to.
    assert installation_id not in key
    assert key.startswith("scrapbook/") and key.endswith(".jpg")

    # Not listed (and can't be completed) until the file is really in S3.
    assert client.get("/scrapbook/photos", headers=headers(installation_id)).json() == []
    early = client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    assert early.status_code == 409

    uploaded[key] = 250_000
    done = client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    assert done.status_code == 200
    assert done.json()["caption"] == "Evening walk"
    assert done.json()["image_url"] == f"https://s3.example/get/{key}"

    listed = client.get("/scrapbook/photos", headers=headers(installation_id)).json()
    assert [p["id"] for p in listed] == [photo_id]

    gone = client.delete(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id))
    assert gone.status_code == 204
    assert deleted == [key]
    assert client.get("/scrapbook/photos", headers=headers(installation_id)).json() == []


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
    assert client.get("/scrapbook/photos", headers=stranger).json() == []
    assert deleted == []
