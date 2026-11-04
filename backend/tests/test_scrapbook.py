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


def _memory_with_photo(installation_id, uploaded):
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 1000
    client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))
    check_in = {"feeling": "hopeful", "contact_urge": 2, "energy_level": "high",
                "hardest_areas": [], "local_date": "2026-10-05"}
    client.post("/check-ins", json=check_in, headers=headers(installation_id))
    card = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()
    memory = client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection["id"], "photo_id": photo_id, "note": "A quiet moment",
        "thought_about_ex": "a_lot", "mood_change": "about_the_same", "local_date": "2026-10-05",
    }).json()
    return memory, photo_id, key


def test_deleting_a_memory_deletes_its_photo_file(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    memory, photo_id, key = _memory_with_photo(installation_id, uploaded)

    assert client.delete(f"/reflections/{memory['id']}", headers=headers(installation_id)).status_code == 204
    assert deleted == [key]
    # The photo row went with it.
    assert client.delete(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id)).status_code == 404


def test_old_unused_uploads_are_cleaned_up(installation_id, fake_s3):
    import psycopg

    from app.config import settings

    uploaded, deleted = fake_s3
    orphan_id, orphan_key = start_upload(installation_id)            # never used in a memory
    memory, used_id, used_key = _memory_with_photo(installation_id, uploaded)
    with psycopg.connect(settings.database_url) as conn:
        conn.execute("UPDATE scrapbook_photos SET created_at = now() - interval '2 days' WHERE installation_id = %s",
                     (installation_id,))
        legacy = conn.execute(
            "INSERT INTO scrapbook_photos (installation_id, object_key, created_at) "
            "VALUES (%s, %s, now() - interval '2 days') RETURNING id",
            (installation_id, f"installations/{installation_id}/legacy.jpg"),
        ).fetchone()[0]

    start_upload(installation_id)   # the next upload tidies up
    assert deleted == [orphan_key]  # not the used photo, not the legacy key
    with psycopg.connect(settings.database_url) as conn:
        ids = {r[0] for r in conn.execute("SELECT id FROM scrapbook_photos WHERE installation_id = %s", (installation_id,))}
    assert orphan_id not in ids and used_id in ids and legacy in ids


def photo_row_exists(photo_id: int) -> bool:
    import psycopg

    from app.config import settings
    with psycopg.connect(settings.database_url) as conn:
        return conn.execute("SELECT 1 FROM scrapbook_photos WHERE id = %s", (photo_id,)).fetchone() is not None


def test_deleting_a_photo_removes_its_row_before_its_file(installation_id, fake_s3, monkeypatch):
    uploaded, _ = fake_s3
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 1000
    assert client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id)).status_code == 200
    seen = {}

    def delete_file(deleted_key):
        seen[deleted_key] = photo_row_exists(photo_id)      # is the row still there when the file goes?

    monkeypatch.setattr(media, "delete", delete_file)
    assert client.delete(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id)).status_code == 204
    assert seen == {key: False}


def test_a_failed_file_delete_still_deletes_the_photo(installation_id, fake_s3, monkeypatch, caplog):
    uploaded, _ = fake_s3
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 1000
    client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id))

    def s3_down(_key):
        raise ConnectionError(f"S3 unreachable for {_key}")

    monkeypatch.setattr(media, "delete", s3_down)
    with caplog.at_level("WARNING", logger="ced"):
        assert client.delete(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id)).status_code == 204
    assert not photo_row_exists(photo_id)
    assert client.get(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id)).status_code == 404
    assert "ConnectionError" in caplog.text and key not in caplog.text   # the type only, never the key


def test_a_too_large_photo_loses_its_row_before_its_file(installation_id, fake_s3, monkeypatch):
    uploaded, _ = fake_s3
    photo_id, key = start_upload(installation_id)
    uploaded[key] = 6 * 1024 * 1024
    seen = {}
    monkeypatch.setattr(media, "delete", lambda deleted_key: seen.setdefault(deleted_key, photo_row_exists(photo_id)))
    assert client.post(f"/scrapbook/photos/{photo_id}/complete", headers=headers(installation_id)).status_code == 413
    assert seen == {key: False}
