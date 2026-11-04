"""
The installation marker in GET /check-ins/today, which the app uses to notice
that its installation was reset on the server, and the one-command
./ced-reset wrapper. Local database only (it resets test installations).
"""
import os
import subprocess
import uuid
from pathlib import Path
from urllib.parse import urlparse

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from scripts import reset_installation as ri
from tests.conftest import upload_test_photo

client = TestClient(app)
ROOT = Path(__file__).resolve().parents[2]

pytestmark = pytest.mark.skipif(
    urlparse(settings.database_url).hostname not in (None, "", "localhost", "127.0.0.1", "::1"),
    reason="resets test installations: runs only against a local test database",
)


def marker(installation_id: str) -> dict:
    body = client.get("/check-ins/today", params={"local_date": "2026-10-02"},
                      headers={"X-Installation-ID": installation_id}).json()
    return body["installation"]


def check_in(installation_id: str, day: str = "2026-10-02") -> None:
    response = client.post("/check-ins", headers={"X-Installation-ID": installation_id}, json={
        "feeling": "hopeful", "contact_urge": 2, "energy_level": "low", "hardest_areas": [], "local_date": day})
    assert response.status_code in (200, 201)


def reset(installation_id: str) -> dict:
    with psycopg.connect(settings.database_url, autocommit=True) as conn:
        return ri.execute_reset(conn, installation_id)


def test_marker_before_and_after_the_first_write(installation_id):
    assert marker(installation_id) == {"exists": False, "created_at": None}   # GET creates nothing
    assert marker(installation_id) == {"exists": False, "created_at": None}
    check_in(installation_id)
    first = marker(installation_id)
    assert first["exists"] is True and first["created_at"]
    assert marker(installation_id) == first                                   # stable


def test_a_reset_changes_only_that_installations_marker(installation_id, other_installation_id):
    check_in(installation_id)
    check_in(other_installation_id)
    a_before, b_before = marker(installation_id), marker(other_installation_id)

    reset(installation_id)
    assert marker(installation_id) == {"exists": False, "created_at": None}
    assert marker(other_installation_id) == b_before

    check_in(installation_id)                       # the phone starts again: a new record
    a_after = marker(installation_id)
    assert a_after["exists"] and a_after["created_at"] != a_before["created_at"]
    assert marker(other_installation_id) == b_before

    status = client.get("/check-ins/today", params={"local_date": "2026-10-02"},
                        headers={"X-Installation-ID": installation_id}).json()
    assert status["has_any_check_in"] is True       # only the new day-1 check-in
    summary = client.get("/progress/summary", headers={"X-Installation-ID": installation_id}).json()
    assert summary["journey_started_on"] == "2026-10-02"


def test_repeating_a_reset_is_safe(installation_id, other_installation_id, fake_s3):
    uploaded, _ = fake_s3
    check_in(installation_id)
    check_in(other_installation_id)
    upload_test_photo(client, installation_id, uploaded)
    b_before = marker(other_installation_id)
    reset(installation_id)
    with pytest.raises(ri.Refused, match="No installation"):    # nothing left to reset
        reset(installation_id)
    check_in(installation_id)
    reset(installation_id)                                       # and again after it came back
    assert marker(installation_id)["exists"] is False
    assert marker(other_installation_id) == b_before


def test_ced_reset_command_end_to_end(installation_id, other_installation_id, fake_s3):
    """The real ./ced-reset against this local database: summary, the typed
    confirmation, reset, verification; B untouched; no private data printed."""
    uploaded, _ = fake_s3
    check_in(installation_id)
    check_in(other_installation_id)
    upload_test_photo(client, installation_id, uploaded)
    b_before = marker(other_installation_id)
    env = {**os.environ, "CED_ENV_FILE": os.environ.get("CED_ENV_FILE", ".env")}

    dry = subprocess.run([str(ROOT / "ced-reset"), installation_id, "--dry-run"],
                         capture_output=True, text=True, env=env, timeout=120)
    assert dry.returncode == 0 and "Dry run: nothing was changed" in dry.stdout
    assert marker(installation_id)["exists"] is True

    cancelled = subprocess.run([str(ROOT / "ced-reset"), f'"{installation_id.upper()}"\n'],
                               input="not-the-id\n", capture_output=True, text=True, env=env, timeout=120)
    assert cancelled.returncode == 1 and marker(installation_id)["exists"] is True

    done = subprocess.run([str(ROOT / "ced-reset"), installation_id],
                          input=f"{installation_id}\n", capture_output=True, text=True, env=env, timeout=120)
    assert done.returncode == 0, done.stdout + done.stderr
    assert "Verified:" in done.stdout and "scrapbook/" not in done.stdout and "postgresql://" not in done.stdout
    assert marker(installation_id)["exists"] is False
    assert marker(other_installation_id) == b_before

    again = subprocess.run([str(ROOT / "ced-reset"), installation_id],
                           input=f"{installation_id}\n", capture_output=True, text=True, env=env, timeout=120)
    assert again.returncode == 2 and "Nothing to reset" in again.stdout     # repeat: safe, nothing done


def test_ced_reset_has_no_reset_all(installation_id):
    for args in ([], ["--all"], ["*"], ["%"]):
        result = subprocess.run([str(ROOT / "ced-reset"), *args], input="\n", capture_output=True, text=True,
                                env={**os.environ, "CED_ENV_FILE": os.environ.get("CED_ENV_FILE", ".env")},
                                timeout=120)
        assert result.returncode != 0
