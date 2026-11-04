"""
The schema's own rules (db/migrations/001_schema.sql): what the database
refuses even when a write skips the API, and the fresh-start tooling.
"""
import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from scripts import migrate, verify_database
from tests.conftest import upload_test_photo

client = TestClient(app)
ALL_FIVE = ["without_overwhelm", "own_routines", "urge_manageable", "connected_to_self", "ready_not_pressured"]


def headers(installation_id):
    return {"X-Installation-ID": installation_id}


def check_in(installation_id, local_date="2026-10-14"):
    body = {"feeling": "hopeful", "contact_urge": 3, "energy_level": "medium",
            "hardest_areas": ["feeling_lonely"], "local_date": local_date}
    return client.post("/check-ins", json=body, headers=headers(installation_id))


@pytest.fixture
def uploaded(fake_s3):
    return fake_s3[0]


def in_progress_selection(installation_id) -> int:
    check_in(installation_id)
    card = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    return client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()["id"]


def test_reflection_notes_are_limited_to_1000_characters(installation_id, uploaded):
    selection = in_progress_selection(installation_id)
    photo = upload_test_photo(client, installation_id, uploaded)
    body = {"activity_selection_id": selection, "thought_about_ex": "a_little", "mood_change": "a_little_better",
            "photo_id": photo, "local_date": "2026-10-14"}
    assert client.post("/reflections", json={**body, "note": "x" * 1001}, headers=headers(installation_id)).status_code == 422
    assert client.post("/reflections", json={**body, "note": "x" * 1000}, headers=headers(installation_id)).status_code == 201
    # The database refuses a longer note too, whoever writes it.
    with psycopg.connect(settings.database_url) as conn:
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute("INSERT INTO reflections (installation_id, note, local_date) VALUES (%s, %s, '2026-10-14')",
                         (installation_id, "x" * 1001))


def test_hardest_areas_are_known_values_and_at_most_five(installation_id):
    assert check_in(installation_id).status_code == 201
    with psycopg.connect(settings.database_url) as conn:
        for areas in (["feeling_lonely"] * 6, ["made_up"]):
            with pytest.raises(psycopg.errors.CheckViolation):
                with conn.transaction():
                    conn.execute("""INSERT INTO check_ins (installation_id, feeling, contact_urge, energy_level,
                                                           hardest_areas, local_date)
                                    VALUES (%s, 'heavy', 5, 'low', %s, '2026-10-15')""", (installation_id, areas))


def test_last_seen_moves_on_at_most_once_a_day(installation_id):
    assert check_in(installation_id).status_code == 201

    def last_seen_after_a_write(set_to: str):
        with psycopg.connect(settings.database_url) as conn:
            conn.execute(f"UPDATE installations SET last_seen_at = {set_to} WHERE id = %s", (installation_id,))
        client.put("/bookmarks/1", headers=headers(installation_id))    # any write
        client.delete("/bookmarks/1", headers=headers(installation_id))
        with psycopg.connect(settings.database_url) as conn:
            return conn.execute("SELECT now() - last_seen_at < interval '1 minute' FROM installations WHERE id = %s",
                                (installation_id,)).fetchone()[0]

    assert last_seen_after_a_write("now() - interval '2 days'") is True     # a day or more: updated
    assert last_seen_after_a_write("now() - interval '2 hours'") is False   # same day: left alone


def test_moving_forward_returns_all_five_answers_without_storing_them(installation_id):
    saved = client.put("/moving-forward", json={"reflected_on": ALL_FIVE, "local_date": "2026-10-20"},
                       headers=headers(installation_id))
    assert saved.status_code == 201 and saved.json()["reflected_on"] == ALL_FIVE
    again = client.get("/moving-forward", headers=headers(installation_id)).json()["moving_forward"]
    assert again["reflected_on"] == ALL_FIVE and again["moved_forward_on"] == "2026-10-20"
    with psycopg.connect(settings.database_url) as conn:
        columns = {r[0] for r in conn.execute(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'moving_forward_check_ins'")}
    assert columns == {"installation_id", "moved_forward_on", "updated_at"}


def test_migrate_refuses_a_database_with_the_old_history():
    with psycopg.connect(settings.database_url) as conn:
        conn.execute("INSERT INTO schema_migrations (version) VALUES ('014_one_check_in_per_day.sql')")
    try:
        with pytest.raises(SystemExit) as refused:
            migrate.main()
        assert "old schema history" in str(refused.value)
    finally:
        with psycopg.connect(settings.database_url) as conn:
            conn.execute("DELETE FROM schema_migrations WHERE version = '014_one_check_in_per_day.sql'")


def test_the_database_matches_the_schema_and_the_catalogs():
    # Not --fresh: other tests' rows may be present.
    assert verify_database.verify(settings.database_url) is True
