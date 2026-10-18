"""Shared test fixtures."""
import uuid

import psycopg
import pytest

from app import media
from app.config import settings


@pytest.fixture
def installation_id():
    """A brand-new installation ID, deleted afterwards with all of its rows."""
    test_id = str(uuid.uuid4())
    yield test_id
    with psycopg.connect(settings.database_url) as conn:
        conn.execute("DELETE FROM installations WHERE id = %s", (test_id,))


@pytest.fixture
def other_installation_id():
    """A second brand-new installation, for checking that data stays separate."""
    test_id = str(uuid.uuid4())
    yield test_id
    with psycopg.connect(settings.database_url) as conn:
        conn.execute("DELETE FROM installations WHERE id = %s", (test_id,))


def upload_test_photo(client, installation_id: str, uploaded: dict) -> int:
    """
    Uploads a photo through the real flow (POST /scrapbook/photos, then
    /complete) with S3 faked by `fake_s3`, and returns its id. Reflections
    need one, like the app.
    """
    headers = {"X-Installation-ID": installation_id}
    ticket = client.post("/scrapbook/photos", headers=headers).json()
    uploaded[ticket["upload_url"].removeprefix("https://s3.example/put/")] = 1000
    done = client.post(f"/scrapbook/photos/{ticket['id']}/complete", headers=headers)
    assert done.status_code == 200
    return ticket["id"]


@pytest.fixture
def fake_s3(monkeypatch):
    """
    Replaces S3 with an in-memory fake. Put a size in `uploaded[key]` to
    "upload" a file; deleted keys are appended to `deleted`.
    """
    uploaded: dict[str, int] = {}
    deleted: list[str] = []
    monkeypatch.setattr(media, "is_configured", lambda: True)
    monkeypatch.setattr(media, "upload_url", lambda key: f"https://s3.example/put/{key}")
    monkeypatch.setattr(media, "download_url", lambda key: f"https://s3.example/get/{key}")
    monkeypatch.setattr(media, "object_size", lambda key: uploaded.get(key))
    monkeypatch.setattr(media, "delete", deleted.append)
    return uploaded, deleted
