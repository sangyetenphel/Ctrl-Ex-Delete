"""
`activities_completed_today` on the day's check-in: the room invites the user
to try an activity ("Let's try something small together.") while it's 0.
Counted per LOCAL calendar day from completed activities, so it survives
deleting the memory and starts again at 0 on a new day. S3 is faked; the
database is the local test one.
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)

DAY_1, DAY_2 = "2026-10-04", "2026-10-05"


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def check_in(installation_id: str, local_date: str):
    return client.post("/check-ins", headers=headers(installation_id), json={
        "feeling": "getting_through", "contact_urge": 5, "energy_level": "medium",
        "hardest_areas": [], "local_date": local_date})


def status(installation_id: str, local_date: str) -> dict:
    response = client.get("/check-ins/today", params={"local_date": local_date}, headers=headers(installation_id))
    assert response.status_code == 200
    return response.json()


def complete_an_activity(installation_id: str, uploaded: dict, local_date: str) -> int:
    recommendation = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    selection = client.post(f"/recommendations/{recommendation['id']}/selection", headers=headers(installation_id))
    assert selection.status_code in (200, 201)
    selection_id = client.get("/activity-selections/current", headers=headers(installation_id)).json()["selection"]["selection_id"]
    reflection = client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection_id, "local_date": local_date, "note": "A quiet walk",
        "thought_about_ex": "a_little", "mood_change": "a_little_better",
        "photo_id": upload_test_photo(client, installation_id, uploaded)})
    assert reflection.status_code in (200, 201)
    return reflection.json()["id"]


@pytest.fixture
def uploaded(fake_s3):
    return fake_s3[0]


def test_a_fresh_check_in_reports_no_activity_yet(installation_id):
    body = check_in(installation_id, DAY_1).json()
    assert body["activities_completed_today"] == 0
    assert status(installation_id, DAY_1)["check_in"]["activities_completed_today"] == 0


def test_completing_an_activity_counts_for_that_local_day(installation_id, uploaded):
    check_in(installation_id, DAY_1)
    complete_an_activity(installation_id, uploaded, DAY_1)
    assert status(installation_id, DAY_1)["check_in"]["activities_completed_today"] == 1
    # The same check-in sent again (a retry) reports it too.
    assert check_in(installation_id, DAY_1).json()["activities_completed_today"] == 1


def test_a_new_local_day_starts_again_at_zero(installation_id, uploaded):
    check_in(installation_id, DAY_1)
    complete_an_activity(installation_id, uploaded, DAY_1)
    assert check_in(installation_id, DAY_2).json()["activities_completed_today"] == 0
    assert status(installation_id, DAY_2)["check_in"]["activities_completed_today"] == 0


def test_the_local_date_decides_not_the_server_clock(installation_id, uploaded):
    # Completed late at night on the user's DAY_1 (whatever UTC says): it
    # belongs to DAY_1, not to the next day.
    check_in(installation_id, DAY_1)
    complete_an_activity(installation_id, uploaded, DAY_1)
    check_in(installation_id, DAY_2)
    assert status(installation_id, DAY_2)["check_in"]["activities_completed_today"] == 0
    assert status(installation_id, DAY_1)["check_in"]["activities_completed_today"] == 1


def test_an_activity_finished_today_before_checking_in_counts(installation_id, uploaded):
    check_in(installation_id, DAY_1)
    recommendation = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"][0]
    client.post(f"/recommendations/{recommendation['id']}/selection", headers=headers(installation_id))
    selection_id = client.get("/activity-selections/current", headers=headers(installation_id)).json()["selection"]["selection_id"]
    client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection_id, "local_date": DAY_2, "note": "Finished it this morning",
        "thought_about_ex": "not_really", "mood_change": "about_the_same",
        "photo_id": upload_test_photo(client, installation_id, uploaded)})
    assert check_in(installation_id, DAY_2).json()["activities_completed_today"] == 1


def test_deleting_the_memory_keeps_the_activity_completed(installation_id, uploaded):
    check_in(installation_id, DAY_1)
    reflection_id = complete_an_activity(installation_id, uploaded, DAY_1)
    assert client.delete(f"/reflections/{reflection_id}", headers=headers(installation_id)).status_code in (200, 204)
    assert status(installation_id, DAY_1)["check_in"]["activities_completed_today"] == 1


def test_before_checking_in_there_is_no_count(installation_id):
    assert status(installation_id, DAY_1)["check_in"] is None


def test_other_installations_are_not_counted(installation_id, other_installation_id, uploaded):
    check_in(installation_id, DAY_1)
    complete_an_activity(installation_id, uploaded, DAY_1)
    assert check_in(other_installation_id, DAY_1).json()["activities_completed_today"] == 0
