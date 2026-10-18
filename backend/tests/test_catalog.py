"""
The 100-activity catalog (scripts/catalog_data.py, loaded by
scripts/seed_catalog.py) and how it behaves in the app. The database is
real (run `python -m scripts.migrate`, which also loads the catalog); S3 is
faked.
"""
import uuid

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from scripts import seed_catalog
from scripts.catalog_data import CATALOG, EYES_OPEN, RESEARCH_BASES, activities
from tests.conftest import upload_test_photo

client = TestClient(app)

LABELS = {
    "mindfulness_rest": "Mindfulness & Rest",
    "outdoor_movement": "Outdoor & Movement",
    "solo_exploration": "Solo Exploration",
    "social_connection": "Social Connection",
}
STATIONARY_OUTDOOR = {"notice_nature_outside", "green_courtyard", "watch_the_sky", "watch_wildlife"}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def db():
    return psycopg.connect(settings.database_url)


# ── The catalog data ─────────────────────────

def test_catalog_has_100_activities_25_per_category():
    rows = activities()
    assert len(rows) == 100
    assert {c: len(entries) for c, entries in CATALOG.items()} == {c: 25 for c in LABELS}
    assert len({r["slug"] for r in rows}) == 100
    assert len({r["title"] for r in rows}) == 100
    assert [r["sort_order"] for r in rows] == list(range(1, 101))


def test_every_activity_is_complete_and_valid():
    for r in activities():
        assert r["energy_level"] in ("low", "medium", "high"), r["slug"]
        assert r["duration_minutes"] > 0, r["slug"]
        assert r["research_codes"] and set(r["research_codes"]) <= set(RESEARCH_BASES), r["slug"]
        for field in ("title", "instructions", "why_it_fits", "evidence_note"):
            assert r[field].strip(), (r["slug"], field)
        assert "was not itself tested" in r["evidence_note"]


def test_research_bases_have_sources_and_scope():
    assert set(RESEARCH_BASES) == {"M", "B", "E", "N", "S", "K"}
    for code, base in RESEARCH_BASES.items():
        assert base["url"].startswith("https://"), code
        assert base["citation"] and base["approach"] and base["evidence_scope"], code


def test_wording_stays_modest():
    banned = ("will stop", "heal your", "heals your", "proves", "research shows", "your energy is",
              "nervous system")
    for r in activities():
        text = f"{r['instructions']} {r['why_it_fits']}".lower()
        assert not any(phrase in text for phrase in banned), r["slug"]


def test_inward_practices_offer_an_eyes_open_alternative():
    inward = {"guided_mindfulness_meditation", "notice_natural_breathing", "feel_feet_and_chair",
              "body_scan", "noticing_thoughts_practice"}
    for r in activities():
        if r["slug"] in inward:
            assert EYES_OPEN.strip() in r["instructions"], r["slug"]
        assert "hold your breath" not in r["instructions"].lower()


def test_movement_flag_separates_movement_from_being_outdoors():
    by_slug = {r["slug"]: r for r in activities()}
    assert not any(by_slug[s]["involves_movement"] for s in STATIONARY_OUTDOOR)
    assert by_slug["walk_around_block"]["involves_movement"]
    assert by_slug["dance_one_song"]["involves_movement"]
    # Every exercise-based activity counts as movement.
    for r in activities():
        if "E" in r["research_codes"]:
            assert r["involves_movement"], r["slug"]


# ── The database ─────────────────────────────

def test_database_has_the_catalog():
    with db() as conn:
        active = conn.execute(
            """SELECT slug, category, category_label, energy_level, duration_minutes, title,
                      involves_movement, evidence_note
               FROM activities WHERE is_active ORDER BY sort_order"""
        ).fetchall()
        per_category = dict(conn.execute(
            "SELECT category, count(*) FROM activities WHERE is_active GROUP BY 1").fetchall())
        links = conn.execute(
            """SELECT a.slug, array_agg(l.code ORDER BY l.code) FROM activities a
               JOIN activity_research_bases l ON l.activity_id = a.id
               WHERE a.is_active GROUP BY a.slug"""
        ).fetchall()
        bases = conn.execute("SELECT count(*) FROM research_bases").fetchone()[0]
    expected = activities()
    assert len(active) == 100
    assert per_category == {c: 25 for c in LABELS}
    for row, want in zip(active, expected):
        slug, category, label, energy, minutes, title, moves, note = row
        assert (slug, category, energy, minutes, title, moves, note) == (
            want["slug"], want["category"], want["energy_level"], want["duration_minutes"],
            want["title"], want["involves_movement"], want["evidence_note"])
        assert label == LABELS[category]
    assert dict(links) == {r["slug"]: sorted(r["research_codes"]) for r in expected}
    assert bases == 6


def test_seed_can_run_again_without_changes():
    with db() as conn:
        before = conn.execute(
            "SELECT count(*), count(*) FILTER (WHERE is_active), sum(id) FROM activities").fetchone()
        links_before = conn.execute("SELECT count(*) FROM activity_research_bases").fetchone()[0]
        counts = seed_catalog.seed(conn)
        after = conn.execute(
            "SELECT count(*), count(*) FILTER (WHERE is_active), sum(id) FROM activities").fetchone()
        links_after = conn.execute("SELECT count(*) FROM activity_research_bases").fetchone()[0]
        conn.rollback()
    assert counts == {"inserted": 0, "reused": 100, "removed": 0, "retired": 0, "total": 100, "active": 100}
    assert before == after and links_before == links_after


def test_database_holds_exactly_the_catalog():
    with db() as conn:
        rows = conn.execute("SELECT count(*), count(*) FILTER (WHERE is_active) FROM activities").fetchone()
        legacy = conn.execute(
            "SELECT count(*) FROM activities WHERE slug IN ('box_breathing', 'sit_in_sunlight', 'live_show')"
        ).fetchone()[0]
    assert rows == (100, 100)
    assert legacy == 0


def test_seed_never_deletes_user_history(installation_id, uploaded):
    # Two activities that left the catalog: one someone chose, one nobody used.
    with db() as conn:
        used, unused = [conn.execute(
            """INSERT INTO activities (slug, title, category, category_label, energy_level, duration_minutes,
                                       instructions, why_it_fits, sort_order)
               VALUES (%s, 'Leaving', 'mindfulness_rest', '', 'low', 5, 'x', 'y', 500) RETURNING id""",
            (slug,)).fetchone()[0] for slug in ("leaving_with_history", "leaving_unused")]
    try:
        client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
        photo_id = upload_test_photo(client, installation_id, uploaded)
        with db() as conn:
            check_in_id = conn.execute("SELECT id FROM check_ins WHERE installation_id = %s", (installation_id,)).fetchone()[0]
            rec = conn.execute("""INSERT INTO recommendations (installation_id, check_in_id, activity_id, position)
                                  VALUES (%s, %s, %s, 9) RETURNING id""", (installation_id, check_in_id, used)).fetchone()[0]
            sel = conn.execute("""INSERT INTO activity_selections (installation_id, recommendation_id, status, ended_at, completed_on)
                                  VALUES (%s, %s, 'completed', now(), '2026-10-17') RETURNING id""", (installation_id, rec)).fetchone()[0]
            conn.execute("""INSERT INTO reflections (installation_id, activity_selection_id, photo_id, note, thought_about_ex,
                                                     mood_change, local_date)
                            VALUES (%s, %s, %s, 'kept', 'a_little', 'worse', '2026-10-17')""", (installation_id, sel, photo_id))

        with db() as conn:
            counts = seed_catalog.seed(conn)
        assert (counts["removed"], counts["retired"]) == (1, 1)
        with db() as conn:
            assert conn.execute("SELECT is_active FROM activities WHERE id = %s", (used,)).fetchone() == (False,)
            assert conn.execute("SELECT count(*) FROM activities WHERE id = %s", (unused,)).fetchone()[0] == 0
            for table, where in (("recommendations", f"id = {rec}"), ("activity_selections", f"id = {sel}"),
                                 ("reflections", f"activity_selection_id = {sel}"), ("scrapbook_photos", f"id = {photo_id}")):
                assert conn.execute(f"SELECT count(*) FROM {table} WHERE {where}").fetchone()[0] == 1, table
        assert [m["note"] for m in client.get("/reflections", headers=headers(installation_id)).json()] == ["kept"]
    finally:
        with db() as conn:
            conn.execute("DELETE FROM installations WHERE id = %s", (installation_id,))
            conn.execute("DELETE FROM activities WHERE slug IN ('leaving_with_history', 'leaving_unused')")


def test_schema_constraints():
    with db() as conn:
        constraints = {r[0] for r in conn.execute(
            "SELECT conname FROM pg_constraint WHERE conrelid = 'activities'::regclass")}
        with pytest.raises(psycopg.errors.CheckViolation):
            with conn.transaction():
                conn.execute("UPDATE activities SET energy_level = 'extreme' WHERE slug = 'body_scan'")
        with pytest.raises(psycopg.errors.ForeignKeyViolation):
            with conn.transaction():
                conn.execute(
                    """INSERT INTO activity_research_bases (activity_id, code)
                       SELECT id, 'Z' FROM activities WHERE slug = 'body_scan'""")
        conn.rollback()
    assert {"activities_energy_level_check", "activities_category_label_fkey",
            "activities_category_check", "activities_slug_key"} <= constraints


# ── The app's flows ──────────────────────────

CHECK_IN = {"feeling": "heavy", "contact_urge": 3, "energy_level": "medium",
            "hardest_areas": ["wanting_answers"], "local_date": "2026-10-17"}


@pytest.fixture
def uploaded(fake_s3):
    return fake_s3[0]


def test_deleted_installation_recovers_on_its_next_check_in():
    # The app keeps its installation ID in the Keychain; if the database
    # forgot it (e.g. a dev reset), the next check-in registers it again.
    installation_id = str(uuid.uuid4())
    try:
        assert client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id)).status_code == 201
        with db() as conn:
            conn.execute("DELETE FROM installations WHERE id = %s", (installation_id,))

        # Reads work and show a fresh start, not an error.
        latest = client.get("/recommendations/latest", headers=headers(installation_id))
        assert latest.status_code == 200 and latest.json()["check_in_id"] is None
        for path in ("/reflections", "/bookmarks", "/activity-selections/current",
                     "/progress/summary", "/insights?period=week&today=2026-10-17"):
            assert client.get(path, headers=headers(installation_id)).status_code == 200, path

        again = client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
        assert again.status_code == 201
        assert len(client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]) == 3
    finally:
        with db() as conn:
            conn.execute("DELETE FROM installations WHERE id = %s", (installation_id,))


def test_retired_activity_in_progress_can_still_be_completed(installation_id, uploaded):
    assert client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id)).status_code == 201
    card = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()
    slug = card["activity"]["slug"]
    try:
        with db() as conn:
            conn.execute("UPDATE activities SET is_active = FALSE WHERE slug = %s", (slug,))

        # Still shown as the activity in progress, and it can be finished.
        current = client.get("/activity-selections/current", headers=headers(installation_id)).json()["selection"]
        assert current["activity"]["slug"] == slug
        saved = client.post("/reflections", headers=headers(installation_id), json={
            "activity_selection_id": selection["id"], "thought_about_ex": "a_little",
            "mood_change": "a_little_better", "note": "Still counts", "local_date": "2026-10-17",
            "photo_id": upload_test_photo(client, installation_id, uploaded),
        })
        assert saved.status_code == 201
        assert saved.json()["activity"]["slug"] == slug
        week = client.get("/insights?period=week&today=2026-10-17", headers=headers(installation_id)).json()
        assert week["completed"] == 1

        # But a retired activity isn't offered, started, recommended or saved again.
        other = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
        assert slug in {r["activity"]["slug"] for r in other}  # shown: it's the completed one
        with db() as conn:
            unchosen = conn.execute(
                """SELECT r.id, a.slug FROM recommendations r JOIN activities a ON a.id = r.activity_id
                   WHERE r.installation_id = %s AND r.id <> %s ORDER BY r.position LIMIT 1""",
                (installation_id, card["id"])).fetchone()
            conn.execute("UPDATE activities SET is_active = FALSE WHERE slug = %s", (unchosen[1],))
        try:
            shown = {r["activity"]["slug"] for r in client.get(
                "/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]}
            assert unchosen[1] not in shown
            blocked = client.post(f"/recommendations/{unchosen[0]}/selection", headers=headers(installation_id))
            assert blocked.status_code == 409 and "no longer offered" in blocked.json()["detail"]
        finally:
            with db() as conn:
                conn.execute("UPDATE activities SET is_active = TRUE WHERE slug = %s", (unchosen[1],))
        assert client.put(f"/bookmarks/{card['activity']['id']}", headers=headers(installation_id)).status_code == 404
        client.post("/check-ins", json={**CHECK_IN, "local_date": "2026-10-18"}, headers=headers(installation_id))
        fresh = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
        assert slug not in {r["activity"]["slug"] for r in fresh}
    finally:
        with db() as conn:
            conn.execute("UPDATE activities SET is_active = TRUE WHERE slug = %s", (slug,))
