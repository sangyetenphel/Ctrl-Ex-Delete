"""
One check-in per local calendar day (a unique constraint since the baseline schema).

"Today" is the local_date the app sends: the user's own calendar day in the
phone's time zone. The server never uses its clock or a rolling 24 hours.
"""
from concurrent.futures import ThreadPoolExecutor

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)

DAY = "2026-10-17"
ANSWERS = {"feeling": "hopeful", "contact_urge": 3, "energy_level": "medium", "hardest_areas": []}


def headers(installation_id):
    return {"X-Installation-ID": installation_id}


def check_in(installation_id, local_date=DAY, **answers):
    return client.post("/check-ins", json={**ANSWERS, **answers, "local_date": local_date},
                       headers=headers(installation_id))


def status(installation_id, local_date=DAY):
    response = client.get(f"/check-ins/today?local_date={local_date}", headers=headers(installation_id))
    assert response.status_code == 200
    return response.json()


def rows(installation_id):
    with psycopg.connect(settings.database_url) as conn:
        return conn.execute(
            """SELECT (SELECT count(*) FROM check_ins WHERE installation_id = %(i)s),
                      (SELECT count(*) FROM recommendations WHERE installation_id = %(i)s)""",
            {"i": installation_id}).fetchone()


def test_status_before_and_after_the_days_check_in(installation_id):
    before = status(installation_id)
    assert (before["local_date"], before["check_in"], before["has_any_check_in"]) == (DAY, None, False)
    saved = check_in(installation_id).json()
    today = status(installation_id)
    assert today["check_in"]["id"] == saved["id"] and today["has_any_check_in"] is True
    tomorrow = status(installation_id, "2026-10-18")
    assert tomorrow["check_in"] is None and tomorrow["has_any_check_in"] is True


def test_status_reads_nothing_into_the_database(installation_id):
    status(installation_id)
    with psycopg.connect(settings.database_url) as conn:
        assert conn.execute("SELECT count(*) FROM installations WHERE id = %s", (installation_id,)).fetchone()[0] == 0


def test_second_check_in_the_same_day_returns_the_first(installation_id):
    first = check_in(installation_id)
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    # A repeated tap, or a retry after the first response was lost, even with other answers.
    again = check_in(installation_id, feeling="heavy", energy_level="low")

    assert (first.status_code, again.status_code) == (201, 200)
    assert again.json() == first.json()                       # the original answers are kept
    assert rows(installation_id) == (1, 3)                     # no second check-in, no extra cards
    assert client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"] == cards


def test_simultaneous_check_ins_make_one(installation_id):
    def send(_):
        with TestClient(app) as own_client:
            return own_client.post("/check-ins", json={**ANSWERS, "local_date": DAY}, headers=headers(installation_id))

    with ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(pool.map(send, range(8)))

    assert sorted(r.status_code for r in responses) == [200] * 7 + [201]
    assert len({r.json()["id"] for r in responses}) == 1
    assert rows(installation_id) == (1, 3)


def test_the_next_local_day_is_a_new_check_in_however_close_in_time(installation_id):
    # 23:59 and 00:01 on the phone: minutes apart, but different calendar days.
    late = check_in(installation_id, "2026-10-17")
    early = check_in(installation_id, "2026-10-18")
    assert (late.status_code, early.status_code) == (201, 201)
    assert rows(installation_id) == (2, 6)


def test_the_day_is_the_phones_not_the_servers(installation_id):
    # 18:00 on Oct 17 in California is already Oct 18 in UTC. The app sends
    # Oct 17, and that's the day the check-in belongs to.
    check_in(installation_id, "2026-10-17")
    assert status(installation_id, "2026-10-17")["check_in"] is not None
    assert status(installation_id, "2026-10-18")["check_in"] is None


def test_unfinished_activity_carries_over_to_the_next_day(installation_id):
    check_in(installation_id, "2026-10-17")
    card = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()

    assert check_in(installation_id, "2026-10-18").status_code == 201
    current = client.get("/activity-selections/current", headers=headers(installation_id)).json()["selection"]
    assert current["selection_id"] == selection["id"]       # still in progress
    new_card = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    blocked = client.post(f"/recommendations/{new_card['id']}/selection", headers=headers(installation_id))
    assert blocked.status_code == 409                       # still one activity at a time


def test_the_database_itself_allows_one_check_in_per_day(installation_id):
    # Even a write that skips the API can't add a second check-in for the same day.
    counted = check_in(installation_id).json()
    with psycopg.connect(settings.database_url) as conn:
        with pytest.raises(psycopg.errors.UniqueViolation):
            conn.execute("""INSERT INTO check_ins (installation_id, feeling, contact_urge, energy_level, local_date)
                            VALUES (%s, 'heavy', 5, 'low', %s)""", (installation_id, DAY))
    assert status(installation_id)["check_in"]["id"] == counted["id"]
    assert rows(installation_id)[0] == 1


def test_the_urge_is_saved_exactly_as_sent(installation_id, other_installation_id):
    # The app's slider starts at 1: an untouched slider sends 1, and 1 is saved.
    assert check_in(installation_id, contact_urge=1).json()["contact_urge"] == 1
    assert check_in(other_installation_id, contact_urge=7).json()["contact_urge"] == 7
    with psycopg.connect(settings.database_url) as conn:
        saved = dict(conn.execute("SELECT installation_id::text, contact_urge FROM check_ins WHERE installation_id IN (%s, %s)",
                                  (installation_id, other_installation_id)).fetchall())
    assert saved == {installation_id: 1, other_installation_id: 7}
    # Nothing fills in a missing urge: the app must always send it.
    body = {k: v for k, v in ANSWERS.items() if k != "contact_urge"}
    response = client.post("/check-ins", json={**body, "local_date": "2026-10-18"}, headers=headers(installation_id))
    assert response.status_code == 422
