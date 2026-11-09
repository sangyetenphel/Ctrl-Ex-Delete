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
    """Behaves like Gemini Live: speech start/end, transcript, reply audio.
    b"SAY:silent:<words>" is heard but gets no reply (like an "um")."""

    def __init__(self):
        self.queue: asyncio.Queue = asyncio.Queue()
        self.audio_in: list[bytes] = []
        self.notes: list[str] = []
        self.audio_ended = 0

    async def send_audio(self, pcm: bytes) -> None:
        self.audio_in.append(pcm)
        if pcm.startswith(b"SAY:"):
            words = pcm[4:].decode()
            await self.queue.put(("speech_start",))
            await self.queue.put(("user_text", words.removeprefix("silent:")))
            await self.queue.put(("speech_end",))
            if words.startswith("silent:"):
                return  # Gemini heard it but doesn't answer
            if words == "interrupt me":
                await self.queue.put(("audio", b"ced-starts"))
                await self.queue.put(("interrupted",))
            else:
                await self.queue.put(("audio", b"ced-reply-1"))
                await self.queue.put(("audio", b"ced-reply-2"))
                await self.queue.put(("turn_complete",))

    async def end_audio(self) -> None:
        self.audio_ended += 1

    async def greet(self, reconnected: bool = False) -> None:
        self.greeted_after_reconnect = reconnected
        await self.queue.put(("audio", b"ced-back" if reconnected else b"ced-hello"))
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
    async def connect(resume_handle=None, journey=None):
        state["session"] = FakeLive()
        state.setdefault("handles", []).append(resume_handle)
        yield state["session"]

    def classify(text):
        state["classified"].append(text)
        return state["classifier_says"]

    voice.slots.reset_for_tests()
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


def test_voice_and_resumption_are_in_the_live_config(monkeypatch):
    monkeypatch.setattr(settings, "gemini_voice", "Zephyr")
    config = voice.live_config()
    assert config.speech_config.voice_config.prebuilt_voice_config.voice_name == "Zephyr"
    assert config.session_resumption is not None and config.session_resumption.handle is None
    assert voice.live_config("handle-1").session_resumption.handle == "handle-1"


@pytest.mark.parametrize("raw, used", [("Zephyr", "Zephyr"), ("zephyr", "Zephyr"), (" Charon ", "Charon"),
                                       ("Zepher", "Vindemiatrix")])
def test_voice_setting_is_checked(raw, used):
    from app.config import Settings

    assert Settings(gemini_voice=raw).gemini_voice == used


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


def test_server_wide_hourly_call_cap(installation_id, other_installation_id, live, monkeypatch):
    monkeypatch.setattr(settings, "ced_voice_calls_per_hour", 1)
    with call(installation_id) as ws:
        connected(ws)
    with call(other_installation_id) as ws:  # a different installation is refused too
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


def test_the_note_is_given_once_per_call(installation_id, live):
    # Resources may be re-shown once per turn (tests/test_ced_voice_safety.py).
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:I want to end my life")
        read_until(ws, event("safety"))
        ws.send_bytes(b"SAY:I want to end my life")
        read_until(ws, event("safety"))
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


# ── Reliability ──────────────────────────────

class FailingLive(FakeLive):
    """Fails like Gemini's temporary '1011 internal error'."""

    def __init__(self, after_greeting: bool):
        super().__init__()
        self.after_greeting = after_greeting

    async def events(self):
        if self.after_greeting:
            yield await self.queue.get()  # the greeting it was asked for
        raise RuntimeError("1011 internal error")


def test_reconnects_once_if_gemini_fails_before_ced_speaks(installation_id, live, monkeypatch):
    attempts = []

    @asynccontextmanager
    async def connect(journey=None):
        attempts.append(1)
        live["session"] = FailingLive(after_greeting=False) if len(attempts) == 1 else FakeLive()
        yield live["session"]

    monkeypatch.setattr(voice, "gemini_connect", connect)
    with call(installation_id) as ws:
        seen = read_until(ws, lambda item: item == b"ced-hello")
    assert len(attempts) == 2
    assert [i for i in seen if isinstance(i, dict) and i["type"] == "ready"] == [
        {"type": "ready", "max_seconds": settings.ced_voice_max_minutes * 60}]  # the app saw one call
    assert b"ced-hello" in seen


def test_repeated_failures_after_ced_spoke_end_with_a_clear_error(installation_id, live, monkeypatch):
    attempts = []

    @asynccontextmanager
    async def connect(resume_handle=None, journey=None):
        attempts.append(1)
        live["session"] = FailingLive(after_greeting=True)
        yield live["session"]

    monkeypatch.setattr(voice, "gemini_connect", connect)
    with call(installation_id) as ws:
        seen = read_until(ws, event("error", code="dropped"), limit=60)
    assert len(attempts) == 1 + voice.MAX_RECONNECTS
    assert {"type": "state", "state": "reconnecting"} in seen
    assert b"ced-back" in seen  # each fresh session said it was back



# ── Never stuck ──────────────────────────────

def states_in(seen):
    return [i["state"] for i in seen if isinstance(i, dict) and i.get("type") == "state"]


def test_no_reply_from_gemini_returns_to_listening(installation_id, live, monkeypatch):
    monkeypatch.setattr(voice, "REPLY_TIMEOUT", 0.6)
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:silent:um")
        seen = read_until(ws, event("state", state="listening"))
    assert states_in(seen) == ["thinking", "listening"]
    assert live["classified"] == ["um"]  # safety checks still ran


def test_crisis_words_without_a_reply_still_show_resources(installation_id, live, monkeypatch):
    monkeypatch.setattr(voice, "REPLY_TIMEOUT", 0.6)
    monkeypatch.setattr(voice, "TRANSCRIPT_GRACE", 0.1)
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:silent:I want to end my life")
        seen = read_until(ws, event("safety"))
    assert seen[-1] == {"type": "safety", "support": "crisis", "risk": "self_harm"}


def test_still_talking_goes_back_to_listening(installation_id, live, monkeypatch):
    monkeypatch.setattr(voice, "REPLY_TIMEOUT", 30)
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:silent:so I was thinking")
        read_until(ws, event("state", state="thinking"))
        ws.send_bytes(b"SAY:that maybe I should call her")  # speech_start -> listening, then a reply
        seen = read_until(ws, event("state", state="speaking"))
    assert states_in(seen)[:2] == ["listening", "thinking"]


def test_stalled_reply_returns_to_listening(installation_id, live, monkeypatch):
    monkeypatch.setattr(voice, "SPEAKING_STALL_TIMEOUT", 0.6)
    with call(installation_id) as ws:
        connected(ws)
        session = live["session"]
        session.queue.put_nowait(("audio", b"half a reply"))  # ...and then nothing
        seen = read_until(ws, event("state", state="listening"))
    assert "speaking" in states_in(seen)


# ── Dropped Gemini connections ───────────────

class DroppingLive(FakeLive):
    """Greets, hands out a resumption handle, then the connection drops."""

    async def events(self):
        yield ("resume_handle", "handle-123")
        yield ("audio", b"ced-hello")
        yield ("turn_complete",)
        raise RuntimeError("1011 connection closed")


def test_a_dropped_connection_resumes_the_conversation(installation_id, live, monkeypatch):
    connections = []

    @asynccontextmanager
    async def connect(resume_handle=None, journey=None):
        connections.append(resume_handle)
        live["session"] = DroppingLive() if len(connections) == 1 else FakeLive()
        yield live["session"]

    monkeypatch.setattr(voice, "gemini_connect", connect)
    with call(installation_id) as ws:
        connected(ws)
        ws.send_bytes(b"SAY:are you still there")
        seen = read_until(ws, event("state", state="speaking"))
    assert connections == [None, "handle-123"]  # second connection resumed, no new greeting
    assert not any(isinstance(i, dict) and i.get("type") == "error" for i in seen)


def test_gives_up_after_repeated_drops(installation_id, live, monkeypatch):
    @asynccontextmanager
    async def connect(resume_handle=None, journey=None):
        live["session"] = DroppingLive()
        yield live["session"]

    monkeypatch.setattr(voice, "gemini_connect", connect)
    with call(installation_id) as ws:
        seen = read_until(ws, event("error", code="dropped"), limit=60)
    assert "Call again" in seen[-1]["message"]



def test_refused_resume_falls_back_to_a_fresh_session(installation_id, live, monkeypatch):
    connections = []

    class RefusedResume(FakeLive):
        async def events(self):
            raise RuntimeError("1008 policy violation")
            yield  # pragma: no cover

    @asynccontextmanager
    async def connect(resume_handle=None, journey=None):
        connections.append(resume_handle)
        if len(connections) == 1:
            live["session"] = DroppingLive()       # hands out a handle, then drops
        elif resume_handle:
            live["session"] = RefusedResume()      # Gemini refuses the handle
        else:
            live["session"] = FakeLive()           # fresh session works
        yield live["session"]

    monkeypatch.setattr(voice, "gemini_connect", connect)
    with call(installation_id) as ws:
        seen = read_until(ws, lambda item: item == b"ced-back", limit=40)
    assert connections == [None, "handle-123", None]
    assert {"type": "state", "state": "reconnecting"} in seen
    assert not any(isinstance(i, dict) and i.get("type") == "error" for i in seen)
