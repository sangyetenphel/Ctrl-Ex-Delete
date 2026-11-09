"""
Context-aware Ced: a short summary of THIS installation's journey in the
instructions for text chat and voice calls. Fictional data in the local test
database; AI providers faked; S3 faked.
"""
import json
import logging
import time
from contextlib import asynccontextmanager

import pytest
from fastapi.testclient import TestClient

from app import storage
from app.ced import context, limits, prompt, providers, risk, voice
from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)
DAY_1, DAY_2 = "2026-10-04", "2026-10-05"


def h(installation_id: str) -> dict:
    return {"X-Installation-ID": installation_id}


def check_in(installation_id: str, day: str = DAY_2, **answers):
    body = {"feeling": "getting_through", "contact_urge": 3, "energy_level": "medium",
            "hardest_areas": [], "local_date": day, **answers}
    assert client.post("/check-ins", json=body, headers=h(installation_id)).status_code in (200, 201)


def complete(installation_id: str, uploaded: dict, day: str, mood: str = "a_little_better",
             note: str = "A quiet walk") -> str:
    """Completes today's first suggested activity; returns its title."""
    rec = client.get("/recommendations/latest", headers=h(installation_id)).json()["recommendations"][0]
    client.post(f"/recommendations/{rec['id']}/selection", headers=h(installation_id))
    selection = client.get("/activity-selections/current", headers=h(installation_id)).json()["selection"]
    assert client.post("/reflections", headers=h(installation_id), json={
        "activity_selection_id": selection["selection_id"], "local_date": day, "note": note,
        "thought_about_ex": "a_lot", "mood_change": mood,
        "photo_id": upload_test_photo(client, installation_id, uploaded)}).status_code in (200, 201)
    return rec["activity"]["title"]


def summary(installation_id: str, day: str | None = DAY_2) -> str | None:
    import uuid
    from datetime import date
    return context.load(uuid.UUID(installation_id), date.fromisoformat(day) if day else None)


@pytest.fixture
def uploaded(fake_s3):
    return fake_s3[0]


@pytest.fixture
def fake_ai(monkeypatch):
    calls: list = []
    state = {"reply": json.dumps({"risk": "none", "messages": ["I'm here."]})}

    def complete_(messages, json_reply=False):
        calls.append(messages)
        return state["reply"]

    limits.reset_for_tests()
    monkeypatch.setattr(providers, "is_configured", lambda: True)
    monkeypatch.setattr(providers, "complete", complete_)
    return calls, state


def chat(installation_id: str, text: str, day: str | None = DAY_2):
    body = {"messages": [{"role": "user", "content": text}]}
    if day:
        body["local_date"] = day
    return client.post("/ced/messages", json=body, headers=h(installation_id))


# ── What the summary says ─────────────────────

def test_a_new_installation_has_no_context(installation_id, fake_ai):
    assert summary(installation_id) is None
    calls, _ = fake_ai
    chat(installation_id, "hi")
    assert "THEIR JOURNEY IN THE APP" not in calls[0][0].content


def test_low_energy_and_a_strong_urge_are_described_in_words_not_numbers(installation_id):
    check_in(installation_id, feeling="missing_them", contact_urge=8, energy_level="low",
             hardest_areas=["resisting_contact", "feeling_lonely"])
    text = summary(installation_id)
    assert text.startswith("- Today they checked in:")
    assert "low energy" in text and "strong urge to contact their ex" in text
    assert "resisting the urge to make contact" in text and "feeling lonely" in text
    assert "8" not in text.split("Progress")[0]   # no ratings to quote back
    assert "Today's suggested activities in the app:" in text


def test_completed_activities_and_how_they_felt_afterwards(installation_id, uploaded):
    check_in(installation_id)
    title = complete(installation_id, uploaded, DAY_2, mood="worse")
    text = summary(installation_id)
    assert f'"{title}" today (felt worse afterwards, thought about their ex a lot)' in text
    assert "1 activities completed in all" in text
    assert "never claim it helped" in prompt.JOURNEY_RULES


def test_a_previous_days_check_in_is_not_presented_as_today(installation_id, uploaded):
    # Live Groq run: with yesterday's answers in the summary, Ced said "the urge
    # to reach out to your ex is still strong". Older answers are now left out.
    check_in(installation_id, DAY_1, feeling="heavy", energy_level="low", contact_urge=9,
             hardest_areas=["feeling_lonely"])
    text = summary(installation_id, DAY_2)
    assert "They haven't checked in today; their last check-in was yesterday." in text
    assert "ask" in text
    for answer in ("overwhelming", "low energy", "urge", "lonely"):
        assert answer not in text
    assert "Today's suggested activities" not in text   # those were for yesterday


def test_without_the_users_date_nothing_counts_as_today(installation_id):
    check_in(installation_id, DAY_2, energy_level="low")
    text = summary(installation_id, None)
    assert "Today they checked in" not in text and "low energy" not in text
    assert "You don't know if they've checked in today" in text


def test_free_text_photos_and_identifiers_are_never_included(installation_id, uploaded):
    check_in(installation_id)
    complete(installation_id, uploaded, DAY_2, note="fictional-private-note-5150")
    text = summary(installation_id)
    assert "fictional-private-note-5150" not in text
    assert installation_id not in text
    assert "http" not in text and "s3.example" not in text and "scrapbook/" not in text   # no photo links or keys


def test_the_summary_is_small_and_bounded():
    data = {"check_in": {"local_date": DAY_2, "feeling": "heavy", "contact_urge": 9, "energy_level": "low",
                         "hardest_areas": list(context._HARDEST)},
            "suggested": [{"title": "T" * 120, "category": "mindfulness_rest", "duration_minutes": 10,
                           "why_it_fits": "W" * 400}] * 3,
            "completed": [{"title": "C" * 120, "category": "outdoor_movement", "completed_on": DAY_2,
                           "mood_change": "worse", "thought_about_ex": "a_lot"}] * 3,
            "journey_started_on": DAY_1, "check_ins": 40, "activities_completed": 99, "moved_forward_on": DAY_2}
    from datetime import date
    text = context.render(data, date.fromisoformat(DAY_2))
    assert len(text) <= context.MAX_CHARS


# ── Isolation and failures ────────────────────

def test_each_installation_only_gets_its_own_journey(installation_id, other_installation_id):
    check_in(installation_id, feeling="heavy")
    check_in(other_installation_id, feeling="hopeful")
    mine, theirs = summary(installation_id), summary(other_installation_id)
    assert "overwhelming" in mine and "hopeful" not in mine
    assert "hopeful" in theirs and "overwhelming" not in theirs


def test_the_body_cannot_ask_for_another_installations_context(installation_id, other_installation_id, fake_ai):
    check_in(other_installation_id, feeling="hopeful")
    calls, _ = fake_ai
    response = client.post("/ced/messages", headers=h(installation_id), json={
        "messages": [{"role": "user", "content": "hi"}], "local_date": DAY_2,
        "installation_id": other_installation_id})
    assert response.status_code == 200
    assert "hopeful" not in calls[0][0].content   # only the header's installation is ever read


def test_a_database_failure_leaves_ced_working_without_context(installation_id, fake_ai, monkeypatch, caplog):
    check_in(installation_id, feeling="heavy")

    def broken(*args, **kwargs):
        raise RuntimeError("database unavailable")

    monkeypatch.setattr(storage, "get_ced_context", broken)
    calls, _ = fake_ai
    with caplog.at_level(logging.WARNING):
        response = chat(installation_id, "hi")
    assert response.status_code == 200 and "THEIR JOURNEY IN THE APP" not in calls[0][0].content
    assert "Ced context unavailable: RuntimeError" in caplog.text


# ── Text chat ─────────────────────────────────

def test_text_chat_gets_a_fresh_summary_on_every_message(installation_id, fake_ai, uploaded):
    calls, _ = fake_ai
    check_in(installation_id, energy_level="low")
    chat(installation_id, "hi")
    assert "low energy" in calls[0][0].content and "Recently completed" not in calls[0][0].content
    complete(installation_id, uploaded, DAY_2)
    chat(installation_id, "I did it")
    assert "Recently completed activities" in calls[1][0].content


def test_safety_notes_come_after_the_journey_and_crisis_still_wins(installation_id, fake_ai):
    calls, state = fake_ai
    check_in(installation_id, feeling="hopeful", energy_level="high")
    state["reply"] = json.dumps({"risk": "distress", "messages": ["I'm here with you."]})
    body = chat(installation_id, "I want to end my life").json()
    system = calls[0][0].content
    assert system.index("THEIR JOURNEY IN THE APP") < system.index("SAFETY NOTE")
    assert body["support"] == "crisis" and body["risk"] == "self_harm"
    assert any("safe" in m.lower() and "?" in m for m in body["messages"])


def test_the_context_never_reaches_the_logs(installation_id, fake_ai, caplog):
    check_in(installation_id, feeling="missing_them", hardest_areas=["wanting_answers"])
    with caplog.at_level(logging.DEBUG):
        chat(installation_id, "hi")
    assert "wanting answers" not in caplog.text and "thoughts that keep returning" not in caplog.text


def test_loading_the_context_is_quick(installation_id, uploaded):
    check_in(installation_id)
    complete(installation_id, uploaded, DAY_2)
    summary(installation_id)            # warm the connection pool, as a running server would
    start = time.perf_counter()
    for _ in range(10):
        summary(installation_id)
    assert (time.perf_counter() - start) / 10 < 0.1   # one query; well under 100 ms locally


# ── Voice calls ───────────────────────────────

class _Live:
    def __init__(self):
        import asyncio
        self.queue = asyncio.Queue()

    async def send_audio(self, pcm):
        if pcm.startswith(b"SAY:"):
            await self.queue.put(("user_text", pcm[4:].decode()))
            await self.queue.put(("speech_end",))
            await self.queue.put(("audio", b"reply"))
            await self.queue.put(("turn_complete",))
        if pcm == b"DROP":
            await self.queue.put(None)

    async def end_audio(self):
        pass

    async def greet(self, reconnected=False):
        await self.queue.put(("audio", b"hello"))
        await self.queue.put(("turn_complete",))

    async def send_note(self, text):
        pass

    async def events(self):
        while (event := await self.queue.get()) is not None:
            yield event


@pytest.fixture
def voice_calls(monkeypatch):
    state = {"journeys": [], "loads": 0}
    real_load = context.load

    @asynccontextmanager
    async def connect(resume_handle=None, journey=None):
        state["journeys"].append(journey)
        yield _Live()

    def counting_load(*args):
        state["loads"] += 1
        return real_load(*args)

    voice.slots.reset_for_tests()
    monkeypatch.setattr(voice, "is_configured", lambda: True)
    monkeypatch.setattr(voice, "gemini_connect", connect)
    monkeypatch.setattr(risk, "classify", lambda text: None)
    monkeypatch.setattr(context, "load", counting_load)
    return state


def _wait_listening(ws, turns=1):
    seen = 0
    while seen < turns:
        message = ws.receive()
        if message.get("text") and json.loads(message["text"]) == {"type": "state", "state": "listening"}:
            seen += 1


def test_a_call_loads_the_journey_once_and_every_connection_gets_it(installation_id, voice_calls):
    check_in(installation_id, energy_level="low", contact_urge=9)
    with client.websocket_connect(f"/ced/voice?local_date={DAY_2}", headers=h(installation_id)) as ws:
        assert json.loads(ws.receive()["text"])["type"] == "ready"
        _wait_listening(ws)
        for words in (b"SAY:hi", b"SAY:still here", b"SAY:okay"):
            ws.send_bytes(words)
            _wait_listening(ws)
        ws.send_bytes(b"DROP")   # a fresh connection
        for _ in range(12):
            if len(voice_calls["journeys"]) == 2:
                break
            ws.receive()
    assert voice_calls["loads"] == 1   # no database query during turns or the reconnect
    assert len(voice_calls["journeys"]) == 2
    assert voice_calls["journeys"][0] == voice_calls["journeys"][1]
    assert "low energy" in voice_calls["journeys"][0] and "strong urge" in voice_calls["journeys"][0]


def test_the_journey_is_in_geminis_session_instructions_with_the_voice_rules():
    instruction = voice.live_config(journey="- Today they checked in: feeling heavy.").system_instruction
    assert instruction.startswith(prompt.VOICE_PROMPT)
    assert "HOW TO SAY YOUR NAME" in instruction and "THEIR JOURNEY IN THE APP" in instruction
    assert instruction.endswith("- Today they checked in: feeling heavy.")
    assert voice.live_config().system_instruction == prompt.VOICE_PROMPT   # no summary, nothing added


def test_text_and_voice_get_the_same_rules_and_summary(installation_id, fake_ai, voice_calls):
    check_in(installation_id, feeling="heavy", energy_level="low")
    calls, _ = fake_ai
    chat(installation_id, "hi")
    with client.websocket_connect(f"/ced/voice?local_date={DAY_2}", headers=h(installation_id)) as ws:
        assert json.loads(ws.receive()["text"])["type"] == "ready"
        _wait_listening(ws)
    text_block = calls[0][0].content.split("THEIR JOURNEY IN THE APP", 1)[1]
    assert (prompt.JOURNEY_RULES + voice_calls["journeys"][0]).endswith(text_block.split("\n", 1)[1])


def test_a_call_from_an_older_app_without_a_date_still_works(installation_id, voice_calls):
    check_in(installation_id, DAY_2)
    with client.websocket_connect("/ced/voice", headers=h(installation_id)) as ws:
        assert json.loads(ws.receive()["text"])["type"] == "ready"
    assert "Today they checked in" not in voice_calls["journeys"][0]
