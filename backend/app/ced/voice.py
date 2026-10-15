"""
Voice calls with Ced: the app streams microphone audio to the backend over a
WebSocket (/ced/voice) and the backend relays it to Gemini Live, which
answers with speech. The Gemini key never leaves the server.

Wire protocol with the app
- App -> server, binary: raw PCM, 16-bit little-endian, 16 kHz, mono.
- App -> server, text JSON: {"type": "mute"} | {"type": "unmute"} | {"type": "end"}
- Server -> app, binary: Ced's voice, PCM 16-bit little-endian, 24 kHz, mono.
- Server -> app, text JSON:
    {"type": "ready", "max_seconds": 900}             call connected
    {"type": "state", "state": "listening" | "thinking" | "speaking"}
    {"type": "interrupted"}                           user talked over Ced: stop playback
    {"type": "safety", "support": "crisis" | "danger", "risk": "..."}
    {"type": "ended", "reason": "time_limit"}
    {"type": "error", "code": "unavailable" | "busy" | "limit" | "dropped", "message": "..."}

Safety does not rest on the voice model alone. Every finished turn of what
the user said (Gemini's transcript of it) is checked by the backend patterns
(safety.py) and by an independent classifier (risk.py). If either finds
self-harm or danger, the app is told to show crisis resources on the call
screen, and the voice model gets a note so its next words address safety.

Privacy: audio and transcripts pass through memory only; nothing is stored
or logged. A call counts as one message toward the daily Ced limit.
"""
import asyncio
import contextlib
import json
import logging
import re
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from typing import Protocol
from uuid import UUID

from fastapi import WebSocket, WebSocketDisconnect

from app import storage
from app.ced import prompt, risk, safety
from app.config import settings

logger = logging.getLogger("ced")

INPUT_MIME = "audio/pcm;rate=16000"


# ── The live model, behind a small interface (faked in tests) ──

class LiveSession(Protocol):
    async def send_audio(self, pcm: bytes) -> None: ...
    async def end_audio(self) -> None: ...
    async def greet(self) -> None: ...
    async def send_note(self, text: str) -> None: ...
    def events(self) -> AsyncIterator[tuple]: ...


# Events from events(): ("audio", bytes), ("user_text", str), ("interrupted",), ("turn_complete",)


class GeminiSession:
    def __init__(self, session, types):
        self._s = session
        self._types = types

    async def send_audio(self, pcm: bytes) -> None:
        await self._s.send_realtime_input(audio=self._types.Blob(data=pcm, mime_type=INPUT_MIME))

    async def end_audio(self) -> None:
        await self._s.send_realtime_input(audio_stream_end=True)

    async def greet(self) -> None:
        await self._s.send_client_content(
            turns=self._types.Content(role="user", parts=[self._types.Part(text="(The call just connected.)")]),
            turn_complete=True,
        )

    async def send_note(self, text: str) -> None:
        # Added to the conversation without asking for a reply.
        await self._s.send_client_content(
            turns=self._types.Content(role="user", parts=[self._types.Part(text=text)]),
            turn_complete=False,
        )

    async def events(self) -> AsyncIterator[tuple]:
        while True:
            received = False
            # receive() ends after each completed turn; loop for the next one.
            async for message in self._s.receive():
                received = True
                content = message.server_content
                if not content:
                    continue
                if content.input_transcription and content.input_transcription.text:
                    yield ("user_text", content.input_transcription.text)
                if content.model_turn:
                    for part in content.model_turn.parts or []:
                        if part.inline_data and part.inline_data.data:
                            yield ("audio", part.inline_data.data)
                if content.interrupted:
                    yield ("interrupted",)
                if content.turn_complete:
                    yield ("turn_complete",)
            if not received:
                return  # the connection closed


@asynccontextmanager
async def gemini_connect() -> AsyncIterator[LiveSession]:
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=settings.gemini_api_key)
    config = types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=prompt.VOICE_PROMPT,
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=settings.gemini_voice)
            )
        ),
        # Transcripts of what the user says, for the backend's safety checks only.
        input_audio_transcription=types.AudioTranscriptionConfig(),
        realtime_input_config=types.RealtimeInputConfig(
            automatic_activity_detection=types.AutomaticActivityDetection(
                disabled=False,
                end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_LOW,
                silence_duration_ms=700,  # room for natural pauses before Ced answers
            )
        ),
        # Long calls keep going by forgetting the oldest audio.
        context_window_compression=types.ContextWindowCompressionConfig(sliding_window=types.SlidingWindow()),
    )
    async with client.aio.live.connect(model=settings.gemini_live_model, config=config) as session:
        yield GeminiSession(session, types)


def is_configured() -> bool:
    return bool(settings.gemini_api_key)


# ── Who may call ──

class _Slots:
    """One call at a time per installation, and a cap for the whole server."""

    def __init__(self):
        self._active: set[UUID] = set()

    def take(self, installation_id: UUID) -> str | None:
        if installation_id in self._active:
            return "You already have a call with Ced open."
        if len(self._active) >= settings.ced_voice_max_concurrent:
            return "Ced is on a lot of calls right now. Please try again in a few minutes."
        self._active.add(installation_id)
        return None

    def release(self, installation_id: UUID) -> None:
        self._active.discard(installation_id)


slots = _Slots()


# ── The call ──

def _voice_note(level: str) -> str:
    """The text-chat safety note, minus its instruction about the JSON reply."""
    note = re.sub(r'\s*Set "risk" to "[a-z_]+"\.', "", prompt.SAFETY_NOTES[level])
    return prompt.VOICE_SAFETY_PREFIX + note.replace("Reply in 2–3 short, warm bubbles", "Reply briefly and warmly")


class _Call:
    def __init__(self, ws: WebSocket, session: LiveSession, classify: Callable[[str], str | None]):
        self.ws = ws
        self.session = session
        self.classify = classify
        self.state = "listening"
        self.muted = False
        self.heard = ""                 # what the user said this turn (transcript)
        self.flagged = "none"           # most serious risk seen so far in this call
        self.noted: set[str] = set()    # safety notes already given to the model
        self.checks: set[asyncio.Task] = set()

    async def send(self, **event) -> None:
        await self.ws.send_text(json.dumps(event))

    async def set_state(self, state: str) -> None:
        if state != self.state:
            self.state = state
            await self.send(type="state", state=state)

    # Safety ──────────────────────────────────

    async def _escalate(self, level: str | None) -> None:
        if not level or level == "none":
            return
        if safety.RISK_ORDER.get(level, 0) > safety.RISK_ORDER.get(self.flagged, 0) or (
            level in safety.SUPPORT_FOR_RISK and self.flagged not in safety.SUPPORT_FOR_RISK
        ):
            self.flagged = level
            support = safety.SUPPORT_FOR_RISK.get(level)
            if support:
                await self.send(type="safety", support=support, risk=level)
        if level in prompt.SAFETY_NOTES and level not in self.noted:
            self.noted.add(level)
            with contextlib.suppress(Exception):  # the on-screen resources don't depend on this
                await self.session.send_note(_voice_note(level))

    async def _classify_in_background(self, text: str) -> None:
        level = await asyncio.to_thread(self.classify, text)
        await self._escalate(level)

    async def finish_user_turn(self) -> None:
        text, self.heard = self.heard.strip(), ""
        if not text:
            return
        await self._escalate(safety.check_message(text))     # instant
        task = asyncio.create_task(self._classify_in_background(text))  # a second opinion
        self.checks.add(task)
        task.add_done_callback(self.checks.discard)

    # Relays ──────────────────────────────────

    async def from_app(self) -> None:
        while True:
            message = await self.ws.receive()
            if message["type"] == "websocket.disconnect":
                return
            if message.get("bytes") is not None:
                if not self.muted:
                    await self.session.send_audio(message["bytes"])
            elif message.get("text") is not None:
                try:
                    command = json.loads(message["text"]).get("type")
                except (json.JSONDecodeError, AttributeError):
                    continue
                if command == "end":
                    return
                if command == "mute" and not self.muted:
                    self.muted = True
                    await self.session.end_audio()  # lets turn detection finish the turn
                elif command == "unmute":
                    self.muted = False

    async def from_model(self) -> None:
        async for event in self.session.events():
            kind = event[0]
            if kind == "user_text":
                self.heard += event[1]
                if self.state == "listening":
                    await self.set_state("thinking")
            elif kind == "audio":
                if self.state != "speaking":
                    await self.finish_user_turn()
                    await self.set_state("speaking")
                await self.ws.send_bytes(event[1])
            elif kind == "interrupted":
                await self.send(type="interrupted")
                await self.set_state("listening")
            elif kind == "turn_complete":
                await self.finish_user_turn()
                await self.set_state("listening")
        await self.send(type="error", code="dropped", message="The call dropped. Please try calling again.")


async def run_call(
    ws: WebSocket,
    installation_id: UUID,
    connect: Callable | None = None,
    classify: Callable[[str], str | None] | None = None,
) -> None:
    connect = connect or gemini_connect
    classify = classify or risk.classify
    await ws.accept()

    async def refuse(code: str, message: str) -> None:
        await ws.send_text(json.dumps({"type": "error", "code": code, "message": message}))
        await ws.close()

    if not is_configured():
        return await refuse("unavailable", "Calling Ced isn’t available right now.")
    problem = slots.take(installation_id)
    if problem:
        return await refuse("busy", problem)

    try:
        if storage.count_ced_message(installation_id) > settings.ced_daily_message_limit:
            return await refuse("limit", "You’ve reached today’s limit for talking with Ced. It resets tomorrow.")

        async with connect() as session:
            call = _Call(ws, session, classify)
            await call.send(type="ready", max_seconds=settings.ced_voice_max_minutes * 60)
            await session.greet()

            relays = [
                asyncio.create_task(call.from_app()),
                asyncio.create_task(call.from_model()),
                asyncio.create_task(asyncio.sleep(settings.ced_voice_max_minutes * 60)),
            ]
            done, pending = await asyncio.wait(relays, return_when=asyncio.FIRST_COMPLETED)
            for task in [*pending, *call.checks]:
                task.cancel()
            if relays[2] in done:
                await call.send(type="ended", reason="time_limit")
            for task in done:
                if task.exception() and not isinstance(task.exception(), WebSocketDisconnect):
                    raise task.exception()
    except WebSocketDisconnect:
        pass
    except Exception as error:  # noqa: BLE001
        # Only the error type is logged; never audio or transcripts.
        logger.warning("Voice call failed: %s", type(error).__name__)
        with contextlib.suppress(Exception):
            await ws.send_text(json.dumps({
                "type": "error", "code": "dropped",
                "message": "Ced couldn’t stay on the call. Please try again.",
            }))
    finally:
        slots.release(installation_id)
        with contextlib.suppress(Exception):
            await ws.close()
