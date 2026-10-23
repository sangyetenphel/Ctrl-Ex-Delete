"""The affirmation catalog: content rules, the seed, the endpoint and the bundled copy."""
import json
import re

import psycopg
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from scripts import export_affirmations, seed_affirmations
from scripts.affirmation_data import AFFIRMATIONS, SOURCES, THEME_SOURCES, THEMES

client = TestClient(app)


def db():
    return psycopg.connect(settings.database_url)


def test_thirty_affirmations_six_per_theme_unique_and_short():
    assert len(AFFIRMATIONS) == 30
    themes = [theme for _, theme, _, _ in AFFIRMATIONS]
    assert {code: themes.count(code) for code, _ in THEMES} == {code: 6 for code, _ in THEMES}
    ids = [a[0] for a in AFFIRMATIONS]
    texts = [a[2] for a in AFFIRMATIONS]
    assert len(set(ids)) == 30 and len(set(texts)) == 30
    for text in texts:
        assert len(text.split()) <= 10, text            # easy to say aloud
        assert text.endswith("."), text


def test_wording_avoids_pressure_promises_and_assumptions():
    banned = r"\b(always|never|must|should|healed|cured|over (him|her|them)|forgive|deadline|perfect|ex\b|by now)"
    for _, _, text, _ in AFFIRMATIONS:
        assert not re.search(banned, text, re.IGNORECASE), text


def test_every_theme_has_sources_and_every_link_is_real():
    for code, _ in THEMES:
        assert any(theme == code for theme, *_ in THEME_SOURCES), code
    for _, source, principle, rationale in THEME_SOURCES:
        assert source in SOURCES and principle and rationale
    for source in SOURCES.values():
        assert source["url"].startswith("https://doi.org/10.")
        assert source["finding"] and source["limitations"]


def test_seed_is_repeatable_and_never_deletes():
    with db() as conn:
        first = seed_affirmations.seed(conn)
    with db() as conn:
        again = seed_affirmations.seed(conn)
        assert (again["inserted"], again["retired"], again["active"]) == (0, 0, 30)
        assert conn.execute("SELECT count(*) FROM affirmations").fetchone()[0] >= 30
        assert conn.execute("SELECT count(*) FROM affirmation_theme_sources").fetchone()[0] == len(THEME_SOURCES)
    assert first["active"] == 30


def test_an_affirmation_that_left_the_catalog_is_retired_not_deleted():
    with db() as conn:
        conn.execute("""INSERT INTO affirmations (id, text, theme, sort_order)
                        VALUES ('test-old', 'An old sentence.', 'acceptance', 999)
                        ON CONFLICT (id) DO UPDATE SET is_active = TRUE""")
    try:
        with db() as conn:
            assert seed_affirmations.seed(conn)["retired"] == 1
            assert conn.execute("SELECT is_active FROM affirmations WHERE id = 'test-old'").fetchone() == (False,)
        ids = [a["id"] for a in client.get("/affirmations").json()["affirmations"]]
        assert "test-old" not in ids
    finally:
        with db() as conn:
            conn.execute("DELETE FROM affirmations WHERE id = 'test-old'")


def test_endpoint_returns_the_active_catalog_without_editorial_notes():
    with db() as conn:
        seed_affirmations.seed(conn)
    response = client.get("/affirmations")          # no installation id needed
    assert response.status_code == 200
    body = response.json()
    assert body["language"] == "en"
    assert [a["id"] for a in body["affirmations"]] == [a[0] for a in AFFIRMATIONS]
    assert set(body["affirmations"][0]) == {"id", "text", "theme", "theme_label"}
    assert client.get("/affirmations?language=fr").json()["affirmations"] == []


def test_bundled_app_copy_matches_the_catalog():
    bundled = json.loads(export_affirmations.BUNDLED.read_text(encoding="utf-8"))
    assert bundled == export_affirmations.catalog()
