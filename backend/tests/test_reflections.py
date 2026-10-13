"""
The activity-to-scrapbook journey: choose an activity ("I'll try this"),
keep it as the current choice, then save a reflection (optionally with a
photo), which completes it. S3 is faked; the database is real.
"""
import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

CHECK_IN = {
    "feeling": "getting_through",
    "contact_urge": 5,
    "energy_level": "medium",
    "hardest_areas": [],
    "local_date": "2026-10-04",
}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def check_in_and_list(installation_id: str) -> list[dict]:
    client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
    body = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    return body["recommendations"]


def select(installation_id: str, recommendation_id: int) -> dict:
    response = client.post(
        f"/recommendations/{recommendation_id}/selection", headers=headers(installation_id)
    )
    assert response.status_code in (200, 201)
    return response.json()


def current(installation_id: str) -> dict | None:
    response = client.get("/activity-selections/current", headers=headers(installation_id))
    assert response.status_code == 200
    return response.json()["selection"]


def reflect(installation_id: str, **fields) -> "httpx.Response":  # noqa: F821
    body = {"local_date": "2026-10-05", **fields}
    return client.post("/reflections", json=body, headers=headers(installation_id))


def upload_photo(installation_id: str, uploaded: dict) -> int:
    ticket = client.post("/scrapbook/photos", headers=headers(installation_id)).json()
    uploaded[ticket["upload_url"].removeprefix("https://s3.example/put/")] = 1000
    done = client.post(f"/scrapbook/photos/{ticket['id']}/complete", headers=headers(installation_id))
    assert done.status_code == 200
    return ticket["id"]


def test_nothing_selected_yet(installation_id):
    assert current(installation_id) is None


def test_selection_is_remembered_until_its_reflection_is_saved(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[1]["id"])

    # Selecting is not completing.
    remembered = current(installation_id)
    assert remembered["selection_id"] == selection["id"]
    assert remembered["recommendation_id"] == cards[1]["id"]
    assert remembered["activity"]["slug"] == cards[1]["activity"]["slug"]
    assert client.get("/reflections", headers=headers(installation_id)).json() == []
    assert client.get("/progress/summary", headers=headers(installation_id)).json()[
        "activities_completed"
    ] == 0

    saved = reflect(
        installation_id,
        activity_selection_id=selection["id"],
        note="I felt calmer outside",
        noticed="Birds",
        thought_about_ex="a_little",
        mood_change="a_little_better",
    )
    assert saved.status_code == 201
    memory = saved.json()
    assert memory["activity"]["slug"] == cards[1]["activity"]["slug"]
    assert memory["mood_change"] == "a_little_better"
    assert memory["thought_about_ex"] == "a_little"
    assert memory["image_url"] is None

    # Completed: no longer the current choice, and the card says so.
    assert current(installation_id) is None
    cards_after = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    assert cards_after["recommendations"][1]["completed_at"] is not None
    assert cards_after["recommendations"][0]["completed_at"] is None

    # Tapping "I'll try this" again on a completed card doesn't revive it.
    select(installation_id, cards[1]["id"])
    assert current(installation_id) is None


def test_saving_twice_returns_the_first_memory(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"])

    first = reflect(installation_id, activity_selection_id=selection["id"], note="first")
    again = reflect(installation_id, activity_selection_id=selection["id"], note="second")
    assert first.status_code == 201
    assert again.status_code == 200
    assert again.json()["id"] == first.json()["id"]
    assert again.json()["note"] == "first"
    assert len(client.get("/reflections", headers=headers(installation_id)).json()) == 1


def test_choosing_another_activity_keeps_earlier_memories(installation_id):
    cards = check_in_and_list(installation_id)
    first = select(installation_id, cards[0]["id"])
    reflect(installation_id, activity_selection_id=first["id"], note="sunlight")

    second = select(installation_id, cards[2]["id"])
    assert current(installation_id)["selection_id"] == second["id"]
    reflect(installation_id, activity_selection_id=second["id"], note="outing")

    memories = client.get("/reflections", headers=headers(installation_id)).json()
    assert [(m["note"], m["activity"]["slug"]) for m in memories] == [
        ("outing", cards[2]["activity"]["slug"]),
        ("sunlight", cards[0]["activity"]["slug"]),
    ]


def test_newer_choice_replaces_an_unfinished_one(installation_id):
    cards = check_in_and_list(installation_id)
    select(installation_id, cards[0]["id"])
    newer = select(installation_id, cards[1]["id"])
    assert current(installation_id)["selection_id"] == newer["id"]


def test_memory_without_an_activity(installation_id):
    saved = reflect(installation_id, note="Just a good day")
    assert saved.status_code == 201
    assert saved.json()["activity"] is None
    summary = client.get("/progress/summary", headers=headers(installation_id)).json()
    assert summary["memories"] == 1
    assert summary["activities_completed"] == 0


def test_reflection_with_photo(installation_id, fake_s3):
    uploaded, _ = fake_s3
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"])
    photo_id = upload_photo(installation_id, uploaded)

    saved = reflect(installation_id, activity_selection_id=selection["id"], photo_id=photo_id)
    assert saved.status_code == 201
    assert saved.json()["photo_id"] == photo_id
    assert saved.json()["image_url"].startswith("https://s3.example/get/scrapbook/")

    listed = client.get("/reflections", headers=headers(installation_id)).json()
    assert listed[0]["image_url"] == saved.json()["image_url"]

    # One photo, one memory.
    reused = reflect(installation_id, photo_id=photo_id)
    assert reused.status_code == 409


def test_photo_must_be_uploaded_and_owned(installation_id, fake_s3):
    reserved = client.post("/scrapbook/photos", headers=headers(installation_id)).json()
    assert reflect(installation_id, photo_id=reserved["id"]).status_code == 409

    stranger = str(uuid.uuid4())
    assert reflect(stranger, photo_id=reserved["id"]).status_code == 404


def test_cannot_reflect_on_another_installations_selection(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"])
    stranger = str(uuid.uuid4())
    assert reflect(stranger, activity_selection_id=selection["id"]).status_code == 404
    assert current(stranger) is None


def test_reflection_rejects_unknown_answers(installation_id):
    assert reflect(installation_id, mood_change="great").status_code == 422
    assert reflect(installation_id, thought_about_ex="sometimes").status_code == 422


def test_progress_summary(installation_id, fake_s3):
    uploaded, _ = fake_s3
    empty = client.get("/progress/summary", headers=headers(installation_id)).json()
    assert empty["journey_started_on"] is None
    assert all(m["reached_on"] is None for m in empty["milestones"])

    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"])
    reflect(
        installation_id,
        activity_selection_id=selection["id"],
        photo_id=upload_photo(installation_id, uploaded),
    )

    summary = client.get("/progress/summary", headers=headers(installation_id)).json()
    assert summary["journey_started_on"] == "2026-10-04"
    assert summary["check_ins"] == 1
    assert summary["activities_selected"] == 1
    assert summary["activities_completed"] == 1
    assert summary["memories"] == 1
    assert summary["photos"] == 1
    reached = {m["label"]: m["reached_on"] for m in summary["milestones"]}
    assert reached["Started the journey"] == "2026-10-04"
    assert reached["Completed a first activity"] == "2026-10-05"
    assert reached["Added a first photo memory"] == "2026-10-05"
    assert reached["5 activities milestone"] is None


def test_database_rejects_links_across_installations(installation_id):
    """The composite foreign keys from migration 005, checked without the API."""
    import psycopg
    import pytest

    from app.config import settings

    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"])
    other = str(uuid.uuid4())
    try:
        with psycopg.connect(settings.database_url) as conn:
            conn.execute("INSERT INTO installations (id) VALUES (%s)", (other,))
            conn.commit()
            # Another installation can't select this installation's card...
            with pytest.raises(psycopg.errors.ForeignKeyViolation):
                with conn.transaction():
                    conn.execute(
                        "INSERT INTO activity_selections (installation_id, recommendation_id) VALUES (%s, %s)",
                        (other, cards[1]["id"]),
                    )
            # ...or complete this installation's selection.
            with pytest.raises(psycopg.errors.ForeignKeyViolation):
                with conn.transaction():
                    conn.execute(
                        "INSERT INTO reflections (installation_id, activity_selection_id, local_date) VALUES (%s, %s, '2026-10-05')",
                        (other, selection["id"]),
                    )
    finally:
        with psycopg.connect(settings.database_url) as conn:
            conn.execute("DELETE FROM installations WHERE id = %s", (other,))
