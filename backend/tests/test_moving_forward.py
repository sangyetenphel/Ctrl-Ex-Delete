"""
The moving-forward check-in (PUT/GET /moving-forward), the farewell
scrapbook export (GET /farewell-scrapbook) and fresh photo links
(GET /scrapbook/photos/{id}).
"""
from concurrent.futures import ThreadPoolExecutor

import psycopg
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)

ALL_FIVE = ["without_overwhelm", "own_routines", "urge_manageable", "connected_to_self", "ready_not_pressured"]

# Reflections allow 1000 characters.
LONG_NOTE = ("I walked the long way home today.\n\nIt rained, and for once I didn't check my phone. "
             "Line two with an emoji \U0001F33F and “curly quotes”. ") * 12
LONG_MEMORY = LONG_NOTE[:1000].rstrip()


def headers(installation_id):
    return {"X-Installation-ID": installation_id}


def save(installation_id, **body):
    return client.put("/moving-forward", headers=headers(installation_id),
                      json={"reflected_on": ALL_FIVE, "local_date": "2026-10-20", **body})


def db():
    return psycopg.connect(settings.database_url)


# ── Moving forward ───────────────────────────────────────────────

def test_nothing_saved_until_the_user_chooses_it(installation_id):
    assert client.get("/moving-forward", headers=headers(installation_id)).json() == {"moving_forward": None}


def test_ready_needs_all_five_questions(installation_id):
    for ticked in ([], ALL_FIVE[:4], ALL_FIVE[1:], ["urge_manageable"] * 5):
        assert save(installation_id, reflected_on=ticked).status_code == 422
    assert save(installation_id, reflected_on=["made_up", *ALL_FIVE]).status_code == 422
    assert client.get("/moving-forward", headers=headers(installation_id)).json() == {"moving_forward": None}
    # Any order is fine; it's stored in the app's order.
    saved = save(installation_id, reflected_on=list(reversed(ALL_FIVE)))
    assert saved.status_code == 201 and saved.json()["reflected_on"] == ALL_FIVE


def test_the_note_is_gone(installation_id):
    body = save(installation_id, note="ignored").json()
    assert "note" not in body
    with db() as conn:
        columns = [r[0] for r in conn.execute(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'moving_forward_check_ins'")]
    assert "note" not in columns


def test_confirming_again_keeps_one_row_and_the_first_day(installation_id):
    first = save(installation_id)
    again = save(installation_id, local_date="2026-10-25")    # a later attempt
    assert (first.status_code, again.status_code) == (201, 200)
    assert again.json()["moved_forward_on"] == "2026-10-20"
    with db() as conn:
        assert conn.execute("SELECT count(*) FROM moving_forward_check_ins WHERE installation_id = %s",
                            (installation_id,)).fetchone()[0] == 1
    assert client.get("/moving-forward", headers=headers(installation_id)).json()["moving_forward"] == again.json()


def test_simultaneous_saves_make_one(installation_id):
    def send(_):
        with TestClient(app) as own:
            return own.put("/moving-forward", headers=headers(installation_id),
                           json={"reflected_on": ALL_FIVE, "local_date": "2026-10-20"})
    with ThreadPoolExecutor(max_workers=6) as pool:
        codes = sorted(r.status_code for r in pool.map(send, range(6)))
    assert codes == [200] * 5 + [201]
    with db() as conn:
        assert conn.execute("SELECT count(*) FROM moving_forward_check_ins WHERE installation_id = %s",
                            (installation_id,)).fetchone()[0] == 1


def test_each_installation_only_sees_its_own(installation_id, other_installation_id):
    save(installation_id)
    assert client.get("/moving-forward", headers=headers(other_installation_id)).json() == {"moving_forward": None}


def test_moving_forward_deletes_and_locks_nothing(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    journey = make_journey(installation_id, uploaded)
    with db() as conn:
        before = counts(conn, installation_id)
    deleted_before = list(deleted)          # make_journey deletes one memory on purpose
    save(installation_id)
    with db() as conn:
        assert counts(conn, installation_id) == before
    assert deleted == deleted_before
    summary = client.get("/progress/summary", headers=headers(installation_id)).json()
    reached = {m["label"]: m["reached_on"] for m in summary["milestones"]}
    assert reached["Moving forward check-in"] == "2026-10-20"
    # The app keeps working: the next day's check-in still goes through.
    assert check_in(installation_id, "2026-10-21").status_code == 201
    assert journey  # (made above)


# ── Farewell scrapbook export ────────────────────────────────────

def check_in(installation_id, local_date, feeling="heavy", urge=6):
    return client.post("/check-ins", headers=headers(installation_id), json={
        "feeling": feeling, "contact_urge": urge, "energy_level": "low",
        "hardest_areas": ["feeling_lonely"], "local_date": local_date})


def complete(installation_id, uploaded, local_date, note, mood="a_little_better"):
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    card = next(c for c in cards if c["status"] is None)
    response = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id))
    assert response.status_code == 201, response.text
    selection = response.json()
    photo_id = upload_test_photo(client, installation_id, uploaded)
    memory = client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection["id"], "thought_about_ex": "a_little", "mood_change": mood,
        "note": note, "local_date": local_date, "photo_id": photo_id}).json()
    return card["activity"], memory


def make_journey(installation_id, uploaded):
    """Three days: two completed activities with photo memories (one long), one memory later deleted."""
    check_in(installation_id, "2026-10-14", "heavy", 8)
    first = complete(installation_id, uploaded, "2026-10-14", LONG_MEMORY)
    check_in(installation_id, "2026-10-15", "getting_through", 6)
    second = complete(installation_id, uploaded, "2026-10-15", "Short one")
    check_in(installation_id, "2026-10-16", "hopeful", 3)
    third = complete(installation_id, uploaded, "2026-10-16", "This one I deleted")
    client.delete(f"/reflections/{third[1]['id']}", headers=headers(installation_id))
    return first, second, third


def counts(conn, installation_id):
    return conn.execute(
        """SELECT (SELECT count(*) FROM check_ins WHERE installation_id = %(i)s),
                  (SELECT count(*) FROM activity_selections WHERE installation_id = %(i)s),
                  (SELECT count(*) FROM reflections WHERE installation_id = %(i)s),
                  (SELECT count(*) FROM scrapbook_photos WHERE installation_id = %(i)s),
                  (SELECT count(*) FROM activity_bookmarks WHERE installation_id = %(i)s)""",
        {"i": installation_id}).fetchone()


def test_export_holds_the_whole_journey_in_order(installation_id, other_installation_id, fake_s3):
    uploaded, _ = fake_s3
    (first_activity, first_memory), (second_activity, second_memory), (third_activity, _) = make_journey(
        installation_id, uploaded)
    check_in(other_installation_id, "2026-10-15", "missing_them", 9)       # someone else's
    save(installation_id)

    body = client.get("/farewell-scrapbook", headers=headers(installation_id)).json()

    assert body["journey_started_on"] == "2026-10-14"
    assert body["journey_last_on"] == "2026-10-20"                          # the moving-forward day
    assert [(c["local_date"], c["feeling"], c["contact_urge"]) for c in body["check_ins"]] == [
        ("2026-10-14", "heavy", 8), ("2026-10-15", "getting_through", 6), ("2026-10-16", "hopeful", 3)]
    done = body["completed_activities"]
    assert [a["activity"]["id"] for a in done] == [first_activity["id"], second_activity["id"], third_activity["id"]]
    assert [a["completed_on"] for a in done] == ["2026-10-14", "2026-10-15", "2026-10-16"]
    assert done[0]["memory"]["note"] == LONG_MEMORY                          # their words, untouched
    assert done[0]["memory"]["id"] == first_memory["id"] and done[1]["memory"]["id"] == second_memory["id"]
    assert all(a["memory"]["image_url"].startswith("https://s3.example/get/scrapbook/") for a in done[:2])
    assert done[2]["memory"] is None                     # still completed; its memory was deleted
    assert body["other_memories"] == []
    assert body["moving_forward"]["reflected_on"] == ALL_FIVE


def test_export_for_someone_with_no_history(installation_id):
    assert client.get("/farewell-scrapbook", headers=headers(installation_id)).json() == {
        "journey_started_on": None, "journey_last_on": None, "check_ins": [],
        "completed_activities": [], "other_memories": [], "moving_forward": None}


def test_export_changes_nothing(installation_id, fake_s3):
    uploaded, deleted = fake_s3
    make_journey(installation_id, uploaded)
    with db() as conn:
        before = counts(conn, installation_id)
    client.get("/farewell-scrapbook", headers=headers(installation_id))
    with db() as conn:
        assert counts(conn, installation_id) == before


def test_fresh_photo_link_only_for_the_owner(installation_id, other_installation_id, fake_s3):
    uploaded, _ = fake_s3
    photo_id = upload_test_photo(client, installation_id, uploaded)
    mine = client.get(f"/scrapbook/photos/{photo_id}", headers=headers(installation_id))
    assert mine.status_code == 200 and mine.json()["image_url"].startswith("https://s3.example/get/")
    assert client.get(f"/scrapbook/photos/{photo_id}", headers=headers(other_installation_id)).status_code == 404


def test_a_later_attempt_sees_new_journey_content(installation_id, fake_s3):
    uploaded, _ = fake_s3
    make_journey(installation_id, uploaded)
    save(installation_id)
    first = client.get("/farewell-scrapbook", headers=headers(installation_id)).json()
    # The journey goes on after the first scrapbook...
    check_in(installation_id, "2026-10-22", "hopeful", 2)
    complete(installation_id, uploaded, "2026-10-22", "A new memory after the first scrapbook")
    save(installation_id, local_date="2026-10-22")             # ready again
    later = client.get("/farewell-scrapbook", headers=headers(installation_id)).json()
    assert len(later["check_ins"]) == len(first["check_ins"]) + 1
    assert later["completed_activities"][-1]["memory"]["note"] == "A new memory after the first scrapbook"
    assert later["journey_last_on"] == "2026-10-22"
