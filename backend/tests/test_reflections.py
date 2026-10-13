"""
The activity journey: "I'll try this" starts ONE activity (in_progress), the
reflection completes it, "Change activity" abandons it. S3 is faked; the
database is real.
"""
import uuid

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)

CHECK_IN = {
    "feeling": "getting_through",
    "contact_urge": 5,
    "energy_level": "medium",
    "hardest_areas": [],
    "local_date": "2026-10-04",
}
ANSWERS = {"thought_about_ex": "a_little", "mood_change": "a_little_better"}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def check_in_and_list(installation_id: str) -> list[dict]:
    client.post("/check-ins", json=CHECK_IN, headers=headers(installation_id))
    return latest(installation_id)


def latest(installation_id: str) -> list[dict]:
    body = client.get("/recommendations/latest", headers=headers(installation_id)).json()
    return body["recommendations"]


def select(installation_id: str, recommendation_id: int):
    return client.post(
        f"/recommendations/{recommendation_id}/selection", headers=headers(installation_id)
    )


def current(installation_id: str) -> dict | None:
    response = client.get("/activity-selections/current", headers=headers(installation_id))
    assert response.status_code == 200
    return response.json()["selection"]


def abandon(installation_id: str, selection_id: int):
    return client.post(
        f"/activity-selections/{selection_id}/abandon", headers=headers(installation_id)
    )


def reflect(installation_id: str, selection_id: int, **fields):
    body = {"activity_selection_id": selection_id, "local_date": "2026-10-05", **ANSWERS, **fields}
    return client.post("/reflections", json=body, headers=headers(installation_id))


def summary(installation_id: str) -> dict:
    return client.get("/progress/summary", headers=headers(installation_id)).json()


def upload_photo(installation_id: str, uploaded: dict) -> int:
    ticket = client.post("/scrapbook/photos", headers=headers(installation_id)).json()
    uploaded[ticket["upload_url"].removeprefix("https://s3.example/put/")] = 1000
    done = client.post(f"/scrapbook/photos/{ticket['id']}/complete", headers=headers(installation_id))
    assert done.status_code == 200
    return ticket["id"]


# ── Selecting ────────────────────────────────

def test_nothing_in_progress_yet(installation_id):
    assert current(installation_id) is None


def test_selecting_starts_one_activity_without_completing_it(installation_id):
    cards = check_in_and_list(installation_id)
    response = select(installation_id, cards[1]["id"])
    assert response.status_code == 201
    selection = response.json()
    assert selection["status"] == "in_progress" and selection["ended_at"] is None

    in_progress = current(installation_id)
    assert in_progress["selection_id"] == selection["id"]
    assert in_progress["activity"]["slug"] == cards[1]["activity"]["slug"]
    assert latest(installation_id)[1]["status"] == "in_progress"

    # Selecting is not completing.
    assert client.get("/reflections", headers=headers(installation_id)).json() == []
    assert summary(installation_id)["activities_completed"] == 0


def test_repeated_tap_returns_the_same_selection(installation_id):
    cards = check_in_and_list(installation_id)
    first = select(installation_id, cards[0]["id"])
    again = select(installation_id, cards[0]["id"])
    assert (first.status_code, again.status_code) == (201, 200)
    assert again.json()["id"] == first.json()["id"]


def test_only_one_activity_in_progress(installation_id):
    cards = check_in_and_list(installation_id)
    first = select(installation_id, cards[0]["id"]).json()

    blocked = select(installation_id, cards[1]["id"])
    assert blocked.status_code == 409
    assert "in progress" in blocked.json()["detail"]
    assert current(installation_id)["selection_id"] == first["id"]


def test_database_allows_one_in_progress_activity(installation_id):
    """The partial unique index from migration 006, checked without the API."""
    cards = check_in_and_list(installation_id)
    select(installation_id, cards[0]["id"])
    with psycopg.connect(settings.database_url) as conn:
        with pytest.raises(psycopg.errors.UniqueViolation):
            conn.execute(
                "INSERT INTO activity_selections (installation_id, recommendation_id) VALUES (%s, %s)",
                (installation_id, cards[1]["id"]),
            )


# ── Changing activity ────────────────────────

def test_change_activity_abandons_without_completing(installation_id):
    cards = check_in_and_list(installation_id)
    first = select(installation_id, cards[0]["id"]).json()

    response = abandon(installation_id, first["id"])
    assert response.status_code == 200
    assert response.json()["status"] == "abandoned"
    assert response.json()["ended_at"] is not None
    assert abandon(installation_id, first["id"]).status_code == 200  # safe to repeat

    assert current(installation_id) is None
    assert summary(installation_id)["activities_completed"] == 0
    assert latest(installation_id)[0]["status"] is None  # the card can be chosen again

    # A different activity can start now, and the abandoned one can't be completed.
    second = select(installation_id, cards[1]["id"])
    assert second.status_code == 201
    assert reflect(installation_id, first["id"]).status_code == 409

    # The abandoned card can also be tried again later, as a new attempt.
    abandon(installation_id, second.json()["id"])
    retry = select(installation_id, cards[0]["id"])
    assert retry.status_code == 201 and retry.json()["id"] != first["id"]


def test_cannot_abandon_a_completed_activity(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()
    reflect(installation_id, selection["id"])
    assert abandon(installation_id, selection["id"]).status_code == 409


# ── Completing through the reflection ────────

def test_reflection_completes_the_activity(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[1]["id"]).json()

    saved = reflect(installation_id, selection["id"], note="I felt calmer outside", noticed="Birds")
    assert saved.status_code == 201
    memory = saved.json()
    assert memory["activity"]["slug"] == cards[1]["activity"]["slug"]
    assert memory["mood_change"] == "a_little_better"
    assert memory["thought_about_ex"] == "a_little"
    assert memory["image_url"] is None

    assert current(installation_id) is None
    cards_after = latest(installation_id)
    assert cards_after[1]["status"] == "completed"
    assert cards_after[1]["completed_at"] is not None
    assert summary(installation_id)["activities_completed"] == 1

    # A completed card can't be started again.
    assert select(installation_id, cards[1]["id"]).status_code == 409


def test_submitting_twice_returns_the_first_memory(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()

    first = reflect(installation_id, selection["id"], note="first")
    again = reflect(installation_id, selection["id"], note="second")
    assert (first.status_code, again.status_code) == (201, 200)
    assert again.json()["id"] == first.json()["id"]
    assert again.json()["note"] == "first"
    assert len(client.get("/reflections", headers=headers(installation_id)).json()) == 1


def test_reflection_requires_the_questions(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()
    body = {"activity_selection_id": selection["id"], "local_date": "2026-10-05"}

    assert client.post("/reflections", json=body, headers=headers(installation_id)).status_code == 422
    assert reflect(installation_id, selection["id"], mood_change="great").status_code == 422
    assert reflect(installation_id, selection["id"], thought_about_ex="sometimes").status_code == 422
    no_activity = {"local_date": "2026-10-05", **ANSWERS}
    assert client.post("/reflections", json=no_activity, headers=headers(installation_id)).status_code == 422
    assert current(installation_id) is not None  # still in progress


def test_earlier_memories_keep_their_activities(installation_id):
    cards = check_in_and_list(installation_id)
    first = select(installation_id, cards[0]["id"]).json()
    reflect(installation_id, first["id"], note="sunlight")
    second = select(installation_id, cards[2]["id"]).json()
    reflect(installation_id, second["id"], note="outing")

    memories = client.get("/reflections", headers=headers(installation_id)).json()
    assert [(m["note"], m["activity"]["slug"]) for m in memories] == [
        ("outing", cards[2]["activity"]["slug"]),
        ("sunlight", cards[0]["activity"]["slug"]),
    ]


def test_reflection_with_photo(installation_id, fake_s3):
    uploaded, _ = fake_s3
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()
    photo_id = upload_photo(installation_id, uploaded)

    saved = reflect(installation_id, selection["id"], photo_id=photo_id)
    assert saved.status_code == 201
    assert saved.json()["photo_id"] == photo_id
    assert saved.json()["image_url"].startswith("https://s3.example/get/scrapbook/")
    listed = client.get("/reflections", headers=headers(installation_id)).json()
    assert listed[0]["image_url"] == saved.json()["image_url"]

    # One photo, one memory.
    other = select(installation_id, cards[1]["id"]).json()
    assert reflect(installation_id, other["id"], photo_id=photo_id).status_code == 409


def test_photo_must_be_uploaded_and_owned(installation_id, fake_s3):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()
    reserved = client.post("/scrapbook/photos", headers=headers(installation_id)).json()
    assert reflect(installation_id, selection["id"], photo_id=reserved["id"]).status_code == 409

    stranger = str(uuid.uuid4())
    assert reflect(stranger, selection["id"], photo_id=reserved["id"]).status_code == 404


def test_other_installations_cannot_touch_my_activity(installation_id):
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()
    stranger = str(uuid.uuid4())
    assert reflect(stranger, selection["id"]).status_code == 404
    assert abandon(stranger, selection["id"]).status_code == 404
    assert current(stranger) is None


def test_database_rejects_links_across_installations(installation_id):
    """The composite foreign keys from migration 005, checked without the API."""
    cards = check_in_and_list(installation_id)
    selection = select(installation_id, cards[0]["id"]).json()
    other = str(uuid.uuid4())
    try:
        with psycopg.connect(settings.database_url) as conn:
            conn.execute("INSERT INTO installations (id) VALUES (%s)", (other,))
            conn.commit()
            with pytest.raises(psycopg.errors.ForeignKeyViolation):
                with conn.transaction():
                    conn.execute(
                        "INSERT INTO activity_selections (installation_id, recommendation_id) VALUES (%s, %s)",
                        (other, cards[1]["id"]),
                    )
            with pytest.raises(psycopg.errors.ForeignKeyViolation):
                with conn.transaction():
                    conn.execute(
                        "INSERT INTO reflections (installation_id, activity_selection_id, local_date) VALUES (%s, %s, '2026-10-05')",
                        (other, selection["id"]),
                    )
    finally:
        with psycopg.connect(settings.database_url) as conn:
            conn.execute("DELETE FROM installations WHERE id = %s", (other,))


# ── Progress ─────────────────────────────────

def test_progress_summary(installation_id, fake_s3):
    uploaded, _ = fake_s3
    empty = summary(installation_id)
    assert empty["journey_started_on"] is None
    assert all(m["reached_on"] is None for m in empty["milestones"])

    cards = check_in_and_list(installation_id)
    abandoned = select(installation_id, cards[1]["id"]).json()
    abandon(installation_id, abandoned["id"])
    selection = select(installation_id, cards[0]["id"]).json()
    reflect(installation_id, selection["id"], photo_id=upload_photo(installation_id, uploaded))

    result = summary(installation_id)
    assert result["journey_started_on"] == "2026-10-04"
    assert result["check_ins"] == 1
    assert result["activities_selected"] == 2
    assert result["activities_completed"] == 1
    assert result["memories"] == 1
    assert result["photos"] == 1
    reached = {m["label"]: m["reached_on"] for m in result["milestones"]}
    assert reached["Started the journey"] == "2026-10-04"
    assert reached["Completed a first activity"] == "2026-10-05"
    assert reached["Added a first photo memory"] == "2026-10-05"
    assert reached["5 activities milestone"] is None
