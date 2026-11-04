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
    {"type": "state", "state": "listening" | "thinking" | "speaking" | "reconnecting"}
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
import time
from collections import deque
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from typing import Protocol
from uuid import UUID

from fastapi import WebSocket, WebSocketDisconnect

from app import storage
from app.ced import prompt, risk, safety
from app.config import settings

logger = logging.getLogger("ced")

# TEMPORARY diagnostics (settings.ced_voice_diagnostics): connection states,
# chunk counts and byte counts only. Never audio, transcripts or keys.
diag_log = logging.getLogger("ced.voice.diag")
if not diag_log.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(asctime)s [voice] %(message)s", "%H:%M:%S"))
    diag_log.addHandler(_handler)
    diag_log.setLevel(logging.INFO)
    diag_log.propagate = False


def diag(message: str, *args) -> None:
    if settings.ced_voice_diagnostics:
        diag_log.info(message, *args)

INPUT_MIME = "audio/pcm;rate=16000"


# ── The live model, behind a small interface (faked in tests) ──

class LiveSession(Protocol):
    async def send_audio(self, pcm: bytes) -> None: ...
    async def end_audio(self) -> None: ...
    async def greet(self, reconnected: bool = False) -> None: ...
    async def send_note(self, text: str) -> None: ...
    def events(self) -> AsyncIterator[tuple]: ...


# Events from events():
#   ("audio", bytes)          Ced's voice
#   ("user_text", str)        transcript of what the user said (safety checks only)
#   ("speech_start",)         Gemini heard the user start talking
#   ("speech_end",)           ...and stop (Gemini may or may not reply)
#   ("interrupted",)          the user talked over Ced
#   ("turn_complete",)        Ced finished a reply
#   ("resume_handle", str)    lets a dropped connection continue this conversation
#   ("go_away", str)          Gemini will close this connection soon


class GeminiSession:
    def __init__(self, session, types):
        self._s = session
        self._types = types

    async def send_audio(self, pcm: bytes) -> None:
        await self._s.send_realtime_input(audio=self._types.Blob(data=pcm, mime_type=INPUT_MIME))

    async def end_audio(self) -> None:
        await self._s.send_realtime_input(audio_stream_end=True)

    async def greet(self, reconnected: bool = False) -> None:
        text = ("(The line dropped for a moment and reconnected. In one short sentence, say you're back "
                "and ask them to repeat what they last said.)" if reconnected else "(The call just connected.)")
        await self._s.send_client_content(
            turns=self._types.Content(role="user", parts=[self._types.Part(text=text)]),
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
                _diag_message(message)
                activity = message.voice_activity
                if activity and activity.voice_activity_type:
                    kind = getattr(activity.voice_activity_type, "value", str(activity.voice_activity_type))
                    if kind.endswith("START"):
                        yield ("speech_start",)
                    elif kind.endswith("END"):
                        yield ("speech_end",)
                update = message.session_resumption_update
                if update and update.resumable and update.new_handle:
                    yield ("resume_handle", update.new_handle)
                if message.go_away:
                    yield ("go_away", str(message.go_away.time_left))
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


def live_config(resume_handle: str | None = None):
    """Everything Gemini Live is told when a call starts (inspectable in tests).
    With `resume_handle`, the new connection continues an earlier conversation."""
    from google.genai import types

    return types.LiveConnectConfig(
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
        # A Gemini connection lasts about 10 minutes and can drop; resumption
        # handles let a new connection pick up the same conversation.
        session_resumption=types.SessionResumptionConfig(handle=resume_handle),
    )


def _diag_message(message) -> None:
    """TEMPORARY: which kinds of message Gemini sends (never their content)."""
    if not settings.ced_voice_diagnostics:
        return
    if message.go_away:
        diag("gemini go_away: connection closes in %s", message.go_away.time_left)
    if message.session_resumption_update:
        update = message.session_resumption_update
        diag("gemini session resumption update: resumable %s, new handle %s",
             update.resumable, bool(update.new_handle))
    if message.usage_metadata:
        diag("gemini usage: total tokens %s", message.usage_metadata.total_token_count)
    content = message.server_content
    if content:
        flags = [name for name in ("generation_complete", "turn_complete", "interrupted", "waiting_for_input")
                 if getattr(content, name, None)]
        if flags or content.turn_complete_reason:
            diag("gemini %s%s", "+".join(flags) or "-",
                 f" (reason {content.turn_complete_reason})" if content.turn_complete_reason else "")
    if message.tool_call or message.voice_activity_detection_signal or message.voice_activity:
        diag("gemini other: tool %s, vad signal %s, voice activity %s", bool(message.tool_call),
             message.voice_activity_detection_signal, message.voice_activity)


@asynccontextmanager
async def gemini_connect(resume_handle: str | None = None) -> AsyncIterator[LiveSession]:
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=settings.gemini_api_key)
    config = live_config(resume_handle)
    diag("live config: model %s, voice %s, resuming %s", settings.gemini_live_model,
         config.speech_config.voice_config.prebuilt_voice_config.voice_name, bool(resume_handle))
    async with client.aio.live.connect(model=settings.gemini_live_model, config=config) as session:
        yield GeminiSession(session, types)


def is_configured() -> bool:
    return bool(settings.gemini_api_key)


# ── Who may call ──

class _Slots:
    """
    One call at a time per installation, and caps for the whole server: calls
    at once, and calls started per hour (so a script inventing installation
    IDs can't keep Gemini busy around the clock). In memory; a restart resets.
    """

    def __init__(self):
        self._active: set[UUID] = set()
        self._started: deque[float] = deque()

    def take(self, installation_id: UUID) -> str | None:
        if installation_id in self._active:
            return "You already have a call with Ced open."
        if len(self._active) >= settings.ced_voice_max_concurrent:
            return "Ced is on a lot of calls right now. Please try again in a few minutes."
        now = time.monotonic()
        while self._started and now - self._started[0] >= 3600:
            self._started.popleft()
        if len(self._started) >= settings.ced_voice_calls_per_hour:
            return "Ced is on a lot of calls right now. Please try again a little later."
        self._started.append(now)
        self._active.add(installation_id)
        return None

    def release(self, installation_id: UUID) -> None:
        self._active.discard(installation_id)

    def reset_for_tests(self) -> None:
        self._active.clear()
        self._started.clear()


slots = _Slots()


# ── The call ──

# Gemini doesn't answer everything it hears (an "um", a cough, a half
# sentence). Without a reply, "Ced is thinking..." would last forever, so the
# call goes back to listening after this long.
REPLY_TIMEOUT = 7.0
# Ced's voice stopped arriving mid-reply without a "turn complete".
SPEAKING_STALL_TIMEOUT = 10.0
# The transcript of what the user said arrives just after they stop talking.
TRANSCRIPT_GRACE = 1.5
# Reconnecting to Gemini within one call (expired or dropped connections).
MAX_RECONNECTS = 3


class GeminiDropped(Exception):
    """The Gemini connection ended without an error."""

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
        self.call_id = format(id(self) % 10_000, "04d")   # just to tell calls apart in logs
        self.audio_in = [0, 0]      # chunks, bytes from the app this turn
        self.audio_out = [0, 0]     # chunks, bytes to the app this turn
        self.audio_out_total = 0    # whole call: has Ced said anything yet?
        self.resume_handle: str | None = None
        self.state_since = asyncio.get_running_loop().time()
        self.last_audio_at = self.state_since
        self.uses_speech_events = False   # Gemini sends speech start/end

    async def send(self, **event) -> None:
        await self.ws.send_text(json.dumps(event))

    async def set_state(self, state: str) -> None:
        if state != self.state:
            diag("call %s: state %s -> %s (in %d chunks/%d B, out %d chunks/%d B)", self.call_id,
                 self.state, state, *self.audio_in, *self.audio_out)
            if state == "listening":
                self.audio_out = [0, 0]
            if state == "speaking":
                self.audio_in = [0, 0]
            self.state = state
            self.state_since = asyncio.get_running_loop().time()
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
        diag("call %s: safety level %s", self.call_id, level)
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
                    self.audio_in[0] += 1
                    self.audio_in[1] += len(message["bytes"])
                    if self.audio_in[0] == 1 or self.audio_in[0] % 100 == 0:
                        diag("call %s: mic audio from app: %d chunks / %d B this turn",
                             self.call_id, *self.audio_in)
                    await self.session.send_audio(message["bytes"])
            elif message.get("text") is not None:
                try:
                    command = json.loads(message["text"]).get("type")
                except (json.JSONDecodeError, AttributeError):
                    continue
                diag("call %s: app command %s", self.call_id, command)
                if command == "end":
                    return
                if command == "mute" and not self.muted:
                    self.muted = True
                    await self.session.end_audio()  # lets turn detection finish the turn
                elif command == "unmute":
                    self.muted = False

    async def _check_after_transcript(self) -> None:
        await asyncio.sleep(TRANSCRIPT_GRACE)
        if self.state != "speaking":  # if Ced is already replying, that path checked it
            await self.finish_user_turn()

    def _later(self, coroutine) -> None:
        task = asyncio.create_task(coroutine)
        self.checks.add(task)
        task.add_done_callback(self.checks.discard)

    async def watchdog(self) -> None:
        """Never stay stuck: Gemini went quiet while thinking or mid-reply."""
        loop = asyncio.get_running_loop()
        while True:
            await asyncio.sleep(0.5)
            now = loop.time()
            if self.state == "thinking" and now - self.state_since > REPLY_TIMEOUT:
                diag("call %s: no reply from gemini after %.0f s; back to listening", self.call_id, REPLY_TIMEOUT)
                await self.finish_user_turn()  # safety checks run even without a reply
                await self.set_state("listening")
            elif self.state == "speaking" and now - self.last_audio_at > SPEAKING_STALL_TIMEOUT:
                diag("call %s: ced's audio stalled for %.0f s; back to listening", self.call_id, SPEAKING_STALL_TIMEOUT)
                await self.finish_user_turn()
                await self.set_state("listening")

    async def from_model(self) -> None:
        async for event in self.session.events():
            kind = event[0]
            if kind == "user_text":
                diag("call %s: gemini heard speech (transcript chunk, %d chars)", self.call_id, len(event[1]))
                self.heard += event[1]
                # Older behaviour, only if Gemini doesn't send speech start/end.
                if not self.uses_speech_events and self.state == "listening":
                    await self.set_state("thinking")
            elif kind == "speech_start":
                self.uses_speech_events = True
                if self.state == "thinking":
                    await self.set_state("listening")  # they kept talking
            elif kind == "speech_end":
                self.uses_speech_events = True
                if self.state == "listening":
                    await self.set_state("thinking")
                self._later(self._check_after_transcript())
            elif kind == "resume_handle":
                self.resume_handle = event[1]
            elif kind == "go_away":
                diag("call %s: gemini will close this connection in %s; will resume", self.call_id, event[1])
            elif kind == "audio":
                if self.state != "speaking":
                    await self.finish_user_turn()
                    await self.set_state("speaking")
                self.audio_out[0] += 1
                self.audio_out[1] += len(event[1])
                self.audio_out_total += len(event[1])
                self.last_audio_at = asyncio.get_running_loop().time()
                if self.audio_out[0] == 1:
                    diag("call %s: first audio from gemini this turn (%d B)", self.call_id, len(event[1]))
                await self.ws.send_bytes(event[1])
            elif kind == "interrupted":
                diag("call %s: gemini says interrupted", self.call_id)
                await self.send(type="interrupted")
                await self.set_state("listening")
            elif kind == "turn_complete":
                diag("call %s: gemini turn complete (sent %d chunks / %d B of audio)", self.call_id, *self.audio_out)
                await self.finish_user_turn()
                await self.set_state("listening")
        raise GeminiDropped()


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

    diag("app connected")
    if not is_configured():
        diag("refused: no GEMINI_API_KEY")
        return await refuse("unavailable", "Calling Ced isn’t available right now.")
    problem = slots.take(installation_id)
    if problem:
        return await refuse("busy", problem)

    call: _Call | None = None
    try:
        # A database round trip: off the event loop, so other calls' audio never waits on it.
        if await asyncio.to_thread(storage.count_ced_message, installation_id) > settings.ced_daily_message_limit:
            return await refuse("limit", "You’ve reached today’s limit for talking with Ced. It resets tomorrow.")

        loop = asyncio.get_running_loop()
        call_started = loop.time()
        max_seconds = settings.ced_voice_max_minutes * 60
        reconnects = 0
        while True:
            # Continue the same conversation when Gemini dropped or expired the
            # last connection; otherwise start fresh with a greeting.
            handle = call.resume_handle if call else None
            started = loop.time()
            diag("connecting to %s (voice %s)%s", settings.gemini_live_model, settings.gemini_voice,
                 f", reconnect #{reconnects}" if reconnects else "")
            try:
                async with (connect(handle) if handle else connect()) as session:
                    if call is None:
                        call = _Call(ws, session, classify)
                        await call.send(type="ready", max_seconds=max_seconds)
                    else:
                        call.session = session
                    diag("call %s: gemini session ready in %.2f s%s", call.call_id, loop.time() - started,
                         " (resumed)" if handle else "")
                    if handle:
                        await call.set_state("listening")
                    else:
                        if call.state == "reconnecting":
                            await call.set_state("listening")
                        # "I'm back" only if the user already heard Ced on this call.
                        await session.greet(reconnected=call.audio_out_total > 0)

                    relays = [
                        asyncio.create_task(call.from_app()),
                        asyncio.create_task(call.from_model()),
                        asyncio.create_task(asyncio.sleep(max(0.0, max_seconds - (loop.time() - call_started)))),
                        asyncio.create_task(call.watchdog()),
                    ]
                    done, pending = await asyncio.wait(relays, return_when=asyncio.FIRST_COMPLETED)
                    for task in pending:
                        task.cancel()
                    diag("call %s: connection ended (%s)", call.call_id,
                         "app hung up" if relays[0] in done else "gemini closed" if relays[1] in done else "time limit")
                    if relays[2] in done:
                        await call.send(type="ended", reason="time_limit")
                    for task in done:
                        if task.exception() and not isinstance(task.exception(), WebSocketDisconnect):
                            raise task.exception()
                break
            except WebSocketDisconnect:
                raise
            except Exception as error:  # noqa: BLE001
                if reconnects >= MAX_RECONNECTS:
                    raise
                reconnects += 1
                if handle and call is not None:
                    # Resuming this handle failed (Gemini can refuse it after a
                    # crash on its side): next time start a fresh session.
                    call.resume_handle = None
                can_resume = call is not None and call.resume_handle is not None
                # Google's error text (never user content) helps tell quota, expiry and bugs apart.
                diag("gemini connection lost (%s %s: %s); %s", type(error).__name__, getattr(error, "code", ""),
                     str(getattr(error, "message", "") or error)[:160],
                     "resuming the conversation" if can_resume else "starting a fresh session")
                if call is not None:
                    with contextlib.suppress(Exception):
                        await call.set_state("reconnecting")
                await asyncio.sleep(min(2.0, 0.5 * reconnects))
                continue
    except WebSocketDisconnect:
        pass
    except Exception as error:  # noqa: BLE001
        # Only the error type is logged; never audio or transcripts.
        logger.warning("Voice call failed: %s", type(error).__name__)
        diag("call failed: %s", type(error).__name__)
        with contextlib.suppress(Exception):
            await ws.send_text(json.dumps({
                "type": "error", "code": "dropped",
                "message": "The call with Ced dropped. Tap \u201cCall again\u201d to reconnect.",
            }))
    finally:
        # Safety checks still running for this call (also after a failure).
        if call:
            for task in list(call.checks):
                task.cancel()
        slots.release(installation_id)
        with contextlib.suppress(Exception):
            await ws.close()
