"""
Voice calls (/ced/voice). Gemini Live is replaced by a fake that "hears"
binary frames of the form b"SAY:<words>" and answers with fake audio, so the
whole relay (states, interruptions, muting, safety, limits) is tested
without any real audio or API calls.
"""
import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.ced import prompt, risk, voice
from app.config import settings
from app.main import app

client = TestClient(app)


class FakeLive:
    def __init__(self):
        self.queue: asyncio.Queue = asyncio.Queue()
        self.audio_in: list[bytes] = []
        self.notes: list[str] = []
        self.audio_ended = 0

    async def send_audio(self, pcm: bytes) -> None:
        self.audio_in.append(pcm)
        if pcm.startswith(b"SAY:"):
            words = pcm[4:].decode()
            await self.queue.put(("user_text", words))
            if words == "interrupt me":
                await self.queue.put(("audio", b"ced-starts"))
                await self.queue.put(("interrupted",))
            else:
                await self.queue.put(("audio", b"ced-reply-1"))
                await self.queue.put(("audio", b"ced-reply-2"))
                await self.queue.put(("turn_complete",))

    async def end_audio(self) -> None:
        self.audio_ended += 1

    async def greet(self) -> None:
        await self.queue.put(("audio", b"ced-hello"))
        await self.queue.put(("turn_complete",))

    async def send_note(self, text: str) -> None:
        self.notes.append(text)

    async def events(self):
        while (event := await self.queue.get()) is not None:
            yield event


@pytest.fixture
def live(monkeypatch):
    """A fake Gemini session; also returns what the classifier was asked."""
    state = {"session": None, "classified": [], "classifier_says": None}

    @asynccontextmanager
    async def connect():
        state["session"] = FakeLive()
        yield state["session"]

    def classify(text):
        state["classified"].append(text)
        return state["classifier_says"]

    monkeypatch.setattr(voice, "is_configured", lambda: True)
    monkeypatch.setattr(voice, "gemini_connect", connect)
    monkeypatch.setattr(risk, "classify", classify)
    return state


def call(installation_id):
    return client.websocket_connect("/ced/voice", headers={"X-Installation-ID": installation_id})


def read_until(ws, predicate, limit=20):
    """Reads messages (JSON events as dicts, audio as bytes) until predicate matches."""
    seen = []
    for _ in range(limit):
        message = ws.receive()
        item = message.get("bytes") if message.get("bytes") is not None else json.loads(message["text"])
        seen.append(item)
        if predicate(item):
            return seen
    raise AssertionError(f"not found in {seen}")


def event(kind, **fields):
    return lambda item: isinstance(item, dict) and item.get("type") == kind and all(
        item.get(k) == v for k, v in fields.items())


def connected(ws):
    """Waits for the call to connect and Ced's greeting to finish."""
    seen = read_until(ws, event("ready"))
    seen += read_until(ws, event("state", state="listening"))
    return seen


# ── Connecting ───────────────────────────────

def test_without_a_key_the_app_is_told_voice_is_unavailable(installation_id, monkeypatch):
    monkeypatch.setattr(voice, "is_configured", lambda: False)
    with call(installation_id) as ws:
        assert ws.receive_json() == {
            "type": "error", "code": "unavailable", "message": "Calling Ced isn’t available right now."}


def test_call_connects_and_ced_greets(installation_id, live):
    with call(installation_id) as ws:
        seen = connected(ws)
    assert seen[0] == {"type": "ready", "max_seconds": settings.ced_voice_max_minutes * 60}
    assert {"type": "state", "state": "speaking"} in seen
    assert b"ced-hello" in seen


def test_the_voice_prompt_is_ced_without_the_json_format():
    assert "You are Ced" in prompt.VOICE_PROMPT and "THIS IS A VOICE CALL" in prompt.VOICE_PROMPT
    assert "JSON" not in prompt.VOICE_PROMPT


# ── Talking ──────────────────────────────────

def test_user_speaks_ced_thinks_then_speaks(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:I really miss them")
        seen = read_until(ws, event("state", state="listening"))
    states = [item["state"] for item in seen if isinstance(item, dict) and item["type"] == "state"]
    assert states == ["thinking", "speaking", "listening"]
    assert [item for item in seen if isinstance(item, bytes)] == [b"ced-reply-1", b"ced-reply-2"]
    assert live["session"].audio_in == [b"SAY:I really miss them"]
    assert live["classified"] == ["I really miss them"]  # every turn gets a second opinion


def test_interrupting_ced(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:interrupt me")
        seen = read_until(ws, event("interrupted"))
        seen += read_until(ws, event("state", state="listening"))
    assert b"ced-starts" in seen


def test_muting_stops_the_microphone_audio(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_text(json.dumps({"type": "mute"}))
        ws.send_bytes(b"while muted")
        ws.send_text(json.dumps({"type": "unmute"}))
        ws.send_bytes(b"SAY:back again")
        read_until(ws, event("state", state="listening"))
    session = live["session"]
    assert b"while muted" not in session.audio_in and b"SAY:back again" in session.audio_in
    assert session.audio_ended == 1


def test_ending_the_call_frees_the_line(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_text(json.dumps({"type": "end"}))
        for _ in range(10):  # the server hangs up
            if ws.receive()["type"] == "websocket.close":
                break
        else:
            raise AssertionError("the call didn't end")
    with call(installation_id) as ws:  # can call again
        assert ws.receive_json()["type"] == "ready"


# ── Limits ───────────────────────────────────

def test_one_call_at_a_time(installation_id, live):
    with call(installation_id) as first:
        connected(first)
        with call(installation_id) as second:
            assert second.receive_json()["code"] == "busy"


def test_server_wide_call_cap(installation_id, live, monkeypatch):
    monkeypatch.setattr(settings, "ced_voice_max_concurrent", 0)
    with call(installation_id) as ws:
        assert ws.receive_json()["code"] == "busy"


def test_daily_limit(installation_id, live, monkeypatch):
    monkeypatch.setattr(settings, "ced_daily_message_limit", 0)
    with call(installation_id) as ws:
        assert ws.receive_json()["code"] == "limit"


def test_time_limit_ends_the_call(installation_id, live, monkeypatch):
    monkeypatch.setattr(settings, "ced_voice_max_minutes", 0)
    with call(installation_id) as ws:
        read_until(ws, event("ended", reason="time_limit"))


# ── Safety ───────────────────────────────────

def test_crisis_words_show_resources_and_tell_the_model(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:I want to end my life")
        seen = read_until(ws, event("safety"))
    assert {"type": "safety", "support": "crisis", "risk": "self_harm"} in seen
    [note] = live["session"].notes
    assert note.startswith(prompt.VOICE_SAFETY_PREFIX) and "safe right now" in note
    assert "JSON" not in note and '"risk"' not in note


def test_danger_shows_911_resources(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:my ex threatened me and I'm not safe")
        seen = read_until(ws, event("safety"))
    assert seen[-1]["support"] == "danger"


def test_the_second_opinion_catches_what_patterns_miss(installation_id, live):
    live["classifier_says"] = "self_harm"
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:I don't see the point of anything anymore")
        seen = read_until(ws, event("safety"))
    assert seen[-1] == {"type": "safety", "support": "crisis", "risk": "self_harm"}


def test_stalking_gets_a_note_but_no_crisis_resources(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:I stalked my ex all day, I need to know where they are")
        seen = read_until(ws, event("state", state="listening"))
    assert not any(isinstance(i, dict) and i["type"] == "safety" for i in seen)
    assert any("watching, tracking" in n for n in live["session"].notes)


def test_resources_are_sent_once_per_level(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:I want to end my life")
        read_until(ws, event("safety"))
        ws.send_bytes(b"SAY:I want to end my life")
        seen = read_until(ws, event("state", state="listening"))
    assert not any(isinstance(i, dict) and i["type"] == "safety" for i in seen)
    assert len(live["session"].notes) == 1


def test_everyday_words_are_not_flagged(installation_id, live):
    with call(installation_id) as ws:
        connected(ws)
        for words in [b"SAY:I can't sleep", b"SAY:I'm feeling a little better today"]:
            ws.send_bytes(words)
            seen = read_until(ws, event("state", state="listening"))
            assert not any(isinstance(i, dict) and i["type"] == "safety" for i in seen)
    assert live["session"].notes == []


def test_nothing_said_appears_in_logs(installation_id, live, caplog):
    secret = "my-private-spoken-words-5678"
    with caplog.at_level(logging.DEBUG):
        with call(installation_id) as ws:
            connected(ws)
            ws.send_bytes(f"SAY:I want to end my life {secret}".encode())
            read_until(ws, event("safety"))
    assert secret not in caplog.text


def test_a_failed_note_never_hides_the_resources(installation_id, live):
    async def broken_note(text):
        raise RuntimeError("model rejected the note")

    with call(installation_id) as ws:
        connected(ws)
        live["session"].send_note = broken_note
        ws.send_bytes(b"SAY:I want to end my life")
        seen = read_until(ws, event("safety"))
    assert seen[-1]["support"] == "crisis"


def test_invalid_installation_id_is_refused():
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ced/voice", headers={"X-Installation-ID": "nope"}) as ws:
            ws.receive()
