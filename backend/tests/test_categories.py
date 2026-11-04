"""
Category names: one descriptive name per category, stored once in the
database (activity_categories) and read from there for every activity as
category_label. The key (`category`) never changes. S3 is faked; the database
is real.
"""
from typing import get_args

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.schemas import ActivityCategory
from tests.conftest import upload_test_photo

client = TestClient(app)

EXPECTED = {
    "mindfulness_rest": "Mindfulness & Rest",
    "outdoor_movement": "Outdoor & Movement",
    "solo_exploration": "Solo Exploration",
    "social_connection": "Social Connection",
}
OLD_NAMES = {"Gentle Reset", "Fresh Air", "Solo Adventure", "Reconnect"}


def headers(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def db():
    return psycopg.connect(settings.database_url)


def test_one_definition_with_the_descriptive_names():
    with db() as conn:
        rows = conn.execute("SELECT category, label FROM activity_categories ORDER BY sort_order").fetchall()
    assert dict(rows) == EXPECTED
    assert set(EXPECTED) == set(get_args(ActivityCategory))  # same keys as the API accepts


def test_the_name_is_stored_once_in_activity_categories():
    with db() as conn:
        columns = {r[0] for r in conn.execute(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'activities'")}
        categories = {r[0] for r in conn.execute("SELECT DISTINCT category FROM activities")}
    assert "category_label" not in columns                  # no copy to keep in step
    assert {"slug", "is_active", "sort_order"} <= columns
    assert categories == set(EXPECTED)                       # every activity is in one of the four


def test_renaming_a_category_reaches_every_activity_and_unknown_ones_are_refused(installation_id):
    with db() as conn:
        conn.execute("UPDATE activity_categories SET label = 'Outdoors' WHERE category = 'outdoor_movement'")
        names = {r[0] for r in conn.execute(
            """SELECT ac.label FROM activities a JOIN activity_categories ac ON ac.category = a.category
               WHERE a.category = 'outdoor_movement'""")}
        assert names == {"Outdoors"}
        # An unknown category can't be stored: activities.category references activity_categories.
        with pytest.raises(psycopg.errors.ForeignKeyViolation):
            with conn.transaction():
                conn.execute("UPDATE activities SET category = 'mystery' WHERE slug = (SELECT min(slug) FROM activities)")
        # ...and the category table only knows the four keys.
        with pytest.raises(psycopg.errors.CheckViolation):
            with conn.transaction():
                conn.execute("INSERT INTO activity_categories VALUES ('mystery', 'Mystery', 9)")
        conn.rollback()  # leave the names as they were


@pytest.fixture
def uploaded(fake_s3):
    return fake_s3[0]


def test_cards_reflections_story_bookmarks_and_insights_match(installation_id, uploaded):
    body = {"feeling": "hopeful", "contact_urge": 2, "energy_level": "high",
            "hardest_areas": ["feeling_lonely"], "local_date": "2026-10-14"}
    assert client.post("/check-ins", json=body, headers=headers(installation_id)).status_code == 201
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    for card in cards:
        assert card["activity"]["category_label"] == EXPECTED[card["activity"]["category"]]

    client.put(f"/bookmarks/{cards[0]['activity']['id']}", headers=headers(installation_id))
    [bookmark] = client.get("/bookmarks", headers=headers(installation_id)).json()
    assert bookmark["activity"]["category_label"] == cards[0]["activity"]["category_label"]

    for card in cards:
        selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()
        saved = client.post("/reflections", headers=headers(installation_id), json={
            "activity_selection_id": selection["id"], "thought_about_ex": "not_really",
            "mood_change": "much_better", "note": "A quiet moment", "local_date": "2026-10-14",
            "photo_id": upload_test_photo(client, installation_id, uploaded),
        })
        assert saved.status_code == 201
        assert saved.json()["activity"]["category_label"] == card["activity"]["category_label"]

    week = client.get("/insights?period=week&today=2026-10-14", headers=headers(installation_id)).json()
    assert [c["label"] for c in week["categories"]] == [
        "Outdoor & Movement", "Mindfulness & Rest", "Solo Exploration", "Social Connection"]
    for share in week["categories"]:
        assert share["label"] == EXPECTED[share["category"]]
        assert share["count"] == sum(1 for c in cards if c["activity"]["category"] == share["category"])
    assert sum(c["count"] for c in week["categories"]) == len(cards) == week["completed"]

    memories = client.get("/reflections", headers=headers(installation_id)).json()
    shown = {m["activity"]["category_label"] for m in memories} | {c["label"] for c in week["categories"]}
    assert not shown & OLD_NAMES
    assert not any(old in text for old in OLD_NAMES for text in week["observations"] + [week["takeaway"]["headline"]])
