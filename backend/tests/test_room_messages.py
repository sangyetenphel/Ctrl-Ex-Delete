"""Ced's room message: the rules, the catalog, assignment and the API."""
import itertools
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from uuid import uuid4

import psycopg
from fastapi.testclient import TestClient

from app import room_messages
from app.config import settings
from app.main import app
from app.schemas import CheckIn
from scripts import seed_room_messages
from scripts.room_message_data import CATALOG, MESSAGES

client = TestClient(app)
DAY = "2026-10-20"


def headers(installation_id):
    return {"X-Installation-ID": installation_id}


def db():
    return psycopg.connect(settings.database_url)


def make(feeling="getting_through", urge=3, energy="medium", hardest=()):
    return CheckIn(id=1, installation_id=uuid4(), created_at=datetime.now(timezone.utc), local_date=DAY,
                   feeling=feeling, contact_urge=urge, energy_level=energy, hardest_areas=list(hardest))


# ── The rules ────────────────────────────────────────────────────

def test_strong_urge_starts_at_seven_like_the_recommendations():
    assert room_messages.STRONG_URGE == 7
    assert room_messages.pattern_for(make(urge=6)) == "general"
    assert room_messages.pattern_for(make(urge=7)) == "strong_urge"
    assert room_messages.pattern_for(make(urge=10)) == "strong_urge"


def test_a_strong_urge_wins_over_everything_else():
    # A lighter feeling and plenty of energy don't hide a strong pull.
    assert room_messages.pattern_for(make("hopeful", 9, "high")) == "strong_urge"
    assert room_messages.pattern_for(make("heavy", 7, "low", ["feeling_lonely"])) == "strong_urge"


def test_low_energy_comes_before_loneliness_and_feelings():
    assert room_messages.pattern_for(make("heavy", 3, "low")) == "heavy_low_energy"
    assert room_messages.pattern_for(make("missing_them", 6, "low", ["feeling_lonely"])) == "heavy_low_energy"
    assert room_messages.pattern_for(make("hopeful", 2, "low")) == "low_energy"
    assert room_messages.pattern_for(make("getting_through", 1, "low", ["feeling_lonely"])) == "low_energy"


def test_with_some_energy_loneliness_then_feeling_decide():
    assert room_messages.pattern_for(make("hopeful", 2, "high", ["feeling_lonely"])) == "lonely"
    assert room_messages.pattern_for(make("heavy", 2, "medium")) == "heavy_some_energy"
    assert room_messages.pattern_for(make("missing_them", 5, "high", ["wanting_answers"])) == "heavy_some_energy"
    assert room_messages.pattern_for(make("hopeful", 3, "medium")) == "lighter_with_energy"
    assert room_messages.pattern_for(make("getting_through", 3, "high")) == "general"


def test_every_possible_check_in_gets_a_pattern_with_messages():
    feelings = ["heavy", "getting_through", "missing_them", "hopeful"]
    hardest_options = [[], ["feeling_lonely"], ["wanting_answers", "resisting_contact"]]
    seen = set()
    for feeling, urge, energy, hardest in itertools.product(feelings, range(1, 11), ["low", "medium", "high"],
                                                            hardest_options):
        pattern = room_messages.pattern_for(make(feeling, urge, energy, hardest))
        assert pattern in room_messages.PRIORITY
        assert len(MESSAGES[pattern]) >= 3
        seen.add(pattern)
    assert seen == set(room_messages.PRIORITY)      # every rule is reachable


def test_choice_is_stable():
    candidates = [{"id": str(i)} for i in range(4)]
    assert room_messages.choose(candidates, "check-in:42") == room_messages.choose(candidates, "check-in:42")
    assert room_messages.choose([], "x") is None


# ── The catalog ──────────────────────────────────────────────────

def test_catalog_is_short_varied_and_gentle():
    assert set(MESSAGES) == set(room_messages.PRIORITY) | {room_messages.BEFORE_CHECK_IN}
    ids = [m[0] for m in CATALOG]
    assert len(ids) == len(set(ids)) and len({m[2] for m in CATALOG}) == len(CATALOG)
    for _, pattern, text in CATALOG:
        assert 3 <= len(MESSAGES[pattern]) <= 5
        assert len(text) <= 100, text                             # fits the room card
        assert len(re.findall(r"[.!?]", text)) <= 2, text         # one or two sentences
        assert not re.search(r"\b(must|should|healed|cured|faster|always|never|ex\b|him|her)\b", text, re.I), text


# ── Assignment and the API ───────────────────────────────────────

def check_in(installation_id, local_date=DAY, **answers):
    body = {"feeling": "hopeful", "contact_urge": 3, "energy_level": "medium", "hardest_areas": [],
            "local_date": local_date, **answers}
    return client.post("/check-ins", json=body, headers=headers(installation_id))


def status(installation_id, local_date=DAY):
    return client.get(f"/check-ins/today?local_date={local_date}", headers=headers(installation_id)).json()


def assigned_rows(installation_id):
    with db() as conn:
        return conn.execute(
            """SELECT count(*) FROM check_in_room_messages m JOIN check_ins c ON c.id = m.check_in_id
               WHERE c.installation_id = %s""", (installation_id,)).fetchone()[0]


def setup_module():
    with db() as conn:
        seed_room_messages.seed(conn)


def test_a_new_check_in_comes_back_with_its_message(installation_id):
    body = check_in(installation_id, feeling="hopeful", contact_urge=9, energy_level="high").json()
    message = body["room_message"]
    assert message["pattern"] == "strong_urge" and message["text"] in MESSAGES["strong_urge"]


def test_the_message_stays_the_same(installation_id):
    first = check_in(installation_id).json()["room_message"]
    again = check_in(installation_id, feeling="heavy", energy_level="low").json()   # a repeat: same day
    assert again["room_message"] == first
    for _ in range(3):                                            # refreshes, reopening the app
        today = status(installation_id)
        assert today["room_message"] == first and today["check_in"]["room_message"] == first
    assert assigned_rows(installation_id) == 1


def test_catalog_edits_dont_change_a_message_already_shown(installation_id):
    first = check_in(installation_id).json()["room_message"]
    with db() as conn:
        conn.execute("UPDATE room_messages SET text = 'Edited wording for later check-ins.' WHERE id = %s",
                     (first["id"],))
    try:
        assert status(installation_id)["room_message"]["text"] == first["text"]
    finally:
        with db() as conn:
            seed_room_messages.seed(conn)                          # restore the catalog


def test_an_older_check_in_gets_one_message_when_first_needed(installation_id):
    check_in(installation_id, feeling="heavy", energy_level="low")
    with db() as conn:                                            # as if made before migration 018
        conn.execute("""DELETE FROM check_in_room_messages WHERE check_in_id IN
                        (SELECT id FROM check_ins WHERE installation_id = %s)""", (installation_id,))
    assert assigned_rows(installation_id) == 0
    message = status(installation_id)["room_message"]
    assert message["pattern"] == "heavy_low_energy"
    assert status(installation_id)["room_message"] == message and assigned_rows(installation_id) == 1


def test_simultaneous_requests_assign_one_message(installation_id):
    check_in(installation_id)
    with db() as conn:
        conn.execute("""DELETE FROM check_in_room_messages WHERE check_in_id IN
                        (SELECT id FROM check_ins WHERE installation_id = %s)""", (installation_id,))

    def read(_):
        with TestClient(app) as own:
            return own.get(f"/check-ins/today?local_date={DAY}", headers=headers(installation_id)).json()["room_message"]

    with ThreadPoolExecutor(max_workers=8) as pool:
        messages = list(pool.map(read, range(8)))
    assert len({m["id"] for m in messages}) == 1 and assigned_rows(installation_id) == 1


def test_before_checking_in_and_on_the_next_day(installation_id):
    before = status(installation_id)
    assert before["check_in"] is None and before["room_message"]["pattern"] == "before_check_in"
    assert status(installation_id)["room_message"] == before["room_message"]      # same all day
    personal = check_in(installation_id, contact_urge=8).json()["room_message"]
    assert personal["pattern"] == "strong_urge"
    tomorrow = status(installation_id, "2026-10-21")
    assert tomorrow["check_in"] is None and tomorrow["room_message"]["pattern"] == "before_check_in"
    assert status(installation_id)["room_message"] == personal                    # yesterday's stays yesterday's


def test_each_installation_gets_its_own_message(installation_id, other_installation_id):
    check_in(installation_id, contact_urge=9)
    other = status(other_installation_id)
    assert other["check_in"] is None and other["room_message"]["pattern"] == "before_check_in"
