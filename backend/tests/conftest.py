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
