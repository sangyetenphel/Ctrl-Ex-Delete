"""Shared test fixtures."""
import uuid

import psycopg
import pytest

from app.config import settings


@pytest.fixture
def installation_id():
    """A brand-new installation ID, deleted afterwards with all of its rows."""
    test_id = str(uuid.uuid4())
    yield test_id
    with psycopg.connect(settings.database_url) as conn:
        conn.execute("DELETE FROM installations WHERE id = %s", (test_id,))
