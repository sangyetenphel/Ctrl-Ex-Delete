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
    {"type": "safety", "support": "crisis" | "danger", "risk": "...", "hotline": "dv"}
                                                      support panel ("hotline" only when the
                                                      domestic violence hotline belongs on it);
                                                      sent again, at most once per turn, when
                                                      something new comes up
    {"type": "ended", "reason": "time_limit"}
    {"type": "error", "code": "unavailable" | "busy" | "limit" | "dropped", "message": "..."}

Safety does not rest on the voice model alone. What the user says (Gemini's
transcript of it) is checked with the same rules as text chat (safety.assess)
as soon as they stop talking, read with Ced's last question so a short answer
("not really") counts, and again by an independent classifier (risk.py) once
the turn is over. Clear warning signs and some unclear ones put resources on
the call screen; every finding gives the voice model a note, early enough to
shape the reply to that turn when the transcript arrives in time. Emotional
pain, venting, ordinary injuries and being stalked never bring up 911 by
themselves. A fresh connection after a drop is told what was noted earlier.

Privacy: audio and transcripts (the user's and Ced's) pass through memory
only; nothing is stored or logged. The classifier gets one turn, plus Ced's
last question when there was one. A call counts as one message toward the
daily Ced limit.
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
#   ("ced_text", str)         transcript of what Ced said (safety checks only)
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
        text = prompt.VOICE_RECONNECTED if reconnected else prompt.VOICE_GREETING
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
                if content.output_transcription and content.output_transcription.text:
                    yield ("ced_text", content.output_transcription.text)
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
        # Transcripts of what the user says and what Ced says, for the
        # backend's safety checks only (memory only; never stored or logged):
        # Ced's last question lets a short answer ("not really") be read
        # correctly, and its replies are screened like text chat's.
        input_audio_transcription=types.AudioTranscriptionConfig(),
        output_audio_transcription=types.AudioTranscriptionConfig(),
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


# Notes that also put the National Domestic Violence Hotline on the call
# screen's support panel (as in text chat, where it's added under the reply).
DV_HOTLINE_NOTES = {"in_danger", "abuse_concern", "possible_danger", "past_danger"}
# On a call the hotline is on the screen, not under a reply.
_VOICE_DV_LINE = ("The National Domestic Violence Hotline's call and text buttons are on their screen; "
                  "you can mention it by name, but don't read out any numbers.")

# What a fresh connection is told about this call's safety notes, so Ced
# doesn't greet someone in crisis as if nothing had happened.
_EARLIER_IN_CALL = {
    "self_harm": "they talked about hurting themselves or not wanting to live",
    "unsafe_answer": "they said they might not be safe right now",
    "possible_self_harm": "they said something that might mean thoughts of ending their life",
    "unclear_distress": "they sounded worn out and overwhelmed",
    "unclear_injury": "they mentioned hurting themselves (maybe an accident)",
    "past_self_harm": "they mentioned past self-harm",
    "denied_self_harm": "they mentioned self-harm but said it isn't what they're feeling",
    "someone_else_at_risk": "someone else may be threatening to hurt themselves",
    "in_danger": "they may be in danger from someone",
    "abuse_concern": "they described being stalked, tracked, controlled or threatened",
    "possible_danger": "they may not feel safe with someone",
    "past_danger": "they described being hurt or threatened in the past",
    "violence": "they talked about hurting someone",
    "possible_violence": "they used violent words about someone, maybe venting",
    "harm_to_others": "they described watching, tracking or getting back at someone",
}


def _voice_note(key: str) -> str:
    """A text-chat safety note, worded for a call (no JSON, no bubbles, no text under a reply)."""
    note = re.sub(r'\s*Set "risk" to "[a-z_]+"\.', "", prompt.SAFETY_NOTES[key])
    note = note.replace(prompt.DV_HOTLINE_ADDED, _VOICE_DV_LINE)
    return prompt.VOICE_SAFETY_PREFIX + note.replace("Reply in 2–3 short, warm bubbles", "Reply briefly and warmly")


def _reconnect_note(noted: set[str]) -> str:
    earlier = "; ".join(_EARLIER_IN_CALL[k] for k in sorted(noted) if k in _EARLIER_IN_CALL)
    return (prompt.VOICE_SAFETY_PREFIX + "The call reconnected on a new line, so you don't hear what came before. "
            f"Earlier in this call, {earlier}. Keep that in mind and check in gently; the support options "
            "are still on their screen. Don't repeat this note back to them.")


_EARLIER_CONCERN = {
    "self_harm": "Earlier in this call the concern was about thoughts of self-harm, not danger from another person.",
    "in_danger": "Earlier in this call the concern was about danger from another person.",
}


def _classifier_input(question: str | None, answer: str, concern: str | None = None) -> str:
    """What the independent classifier reads: the turn, Ced's question when
    there was one, and (as a fixed phrase, never earlier words) what an
    earlier safety concern was about."""
    if not question:
        return answer
    lines = [_EARLIER_CONCERN[concern]] if concern in _EARLIER_CONCERN else []
    lines.append(f'Ced (the companion) just asked: "{question.strip()}"\nThe person answered: "{answer}"')
    return "\n".join(lines)


class _Call:
    def __init__(self, ws: WebSocket, session: LiveSession, classify: Callable[[str], str | None]):
        self.ws = ws
        self.session = session
        self.classify = classify
        self.state = "listening"
        self.muted = False
        self.heard = ""                 # what the user said this turn (transcript, memory only)
        self.ced_said = ""              # what Ced said this turn (transcript, memory only)
        self.last_ced_question: str | None = None   # Ced's last question, to read a short answer
        self.turn = 0                   # user turns so far
        self.panel: safety.Support | None = None    # most urgent resources shown so far
        self.dv_hotline = False         # the panel includes the domestic violence hotline
        self.shown: set[tuple] = set()  # (turn, support, hotline) already sent: once per turn
        self.concern: str | None = None   # what this call's safety concern is about: self_harm or in_danger
        self.concern_turn: int | None = None   # the turn it was first raised
        self.turn_findings: dict[int, set[str]] = {}   # notes the patterns found, per turn
        self.noted: set[str] = set()    # safety notes already given to this call's model
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
    #
    # The same rules as text chat (safety.assess): clear warning signs and
    # some unclear ones put resources on the screen; every finding gives the
    # model a note. Emotional pain, venting, ordinary injuries and being
    # stalked never bring up 911 by themselves. Notes go to the model as soon
    # as the user's words are known (at the end of their speech), so they can
    # shape Ced's reply to that same turn whenever the transcript is ready in time.

    async def _show(self, support: safety.Support | None, risk_level: str, hotline: bool, turn: int) -> None:
        """Puts (or re-shows, once per turn) the support panel on the call screen."""
        if support is None:
            return
        self.panel = safety.more_urgent(self.panel, support)
        self.dv_hotline = self.dv_hotline or hotline
        if (turn, self.panel, self.dv_hotline) in self.shown:
            return
        self.shown.add((turn, self.panel, self.dv_hotline))
        event = {"type": "safety", "support": self.panel, "risk": risk_level}
        if self.dv_hotline:
            event["hotline"] = "dv"
        await self.send(**event)
        diag("call %s: support panel %s%s", self.call_id, self.panel, " + dv hotline" if self.dv_hotline else "")

    async def _note(self, key: str) -> None:
        if key in self.noted or key not in prompt.SAFETY_NOTES:
            return
        self.noted.add(key)
        with contextlib.suppress(Exception):  # the on-screen resources don't depend on this
            await self.session.send_note(_voice_note(key))

    def _set_concern(self, concern: str, turn: int) -> None:
        if self.concern != concern:
            self.concern, self.concern_turn = concern, turn

    def _earlier_concern(self, turn: int) -> str | None:
        """The concern raised before this turn (not by this turn's own words)."""
        return self.concern if self.concern_turn is not None and self.concern_turn < turn else None

    async def _apply(self, signal: safety.Signal, turn: int) -> None:
        self.turn_findings.setdefault(turn, set()).add(signal.note if not signal.certain else f"certain:{signal.note}")
        if signal.risk in safety.SUPPORT_FOR_RISK:
            self._set_concern("in_danger" if signal.risk in ("in_danger", "violence") else "self_harm", turn)
        hotline = signal.note in DV_HOTLINE_NOTES
        # Abuse disclosures without guaranteed resources still get the
        # gentler panel, because on a call the hotline can't be put in a reply.
        support = signal.guaranteed_support or ("crisis" if hotline else None)
        await self._show(support, signal.risk, hotline, turn)
        await self._note(signal.note)

    async def _check_words(self, text: str, turn: int, question: str | None) -> None:
        """The patterns (instant), read with Ced's last question (for a short answer)."""
        for signal in safety.assess(text, question).signals:
            if signal.note == "unsafe_answer" and self._earlier_concern(turn) == "in_danger":
                signal = safety.Signal("in_danger", True, "unsafe_answer")
            await self._apply(signal, turn)

    async def _escalate(self, level: str | None, turn: int) -> None:
        """The independent classifier's rating (it may raise, never lower)."""
        if not level or level not in safety.SUPPORT_FOR_RISK and level not in prompt.SAFETY_NOTES:
            return
        diag("call %s: classifier rated %s", self.call_id, level)
        if level in safety.SUPPORT_FOR_RISK and self.concern is None:
            self._set_concern("in_danger" if level in ("in_danger", "violence") else "self_harm", turn)
        support = safety.SUPPORT_FOR_RISK.get(level)
        if level == "in_danger" and self._not_imminent(turn):
            # The patterns read this turn as stalking or past abuse with no
            # immediate threat (live run: the classifier still said in_danger
            # for "I've been stalked by my ex for months"). Keep the gentler
            # panel with the hotline; 911 stays on it as "in immediate danger".
            support = "crisis"
        await self._show(support, level, level == "in_danger", turn)
        await self._note(level)

    def _not_imminent(self, turn: int) -> bool:
        found = self.turn_findings.get(turn, set())
        return bool(found & {"abuse_concern", "past_danger"}) and "certain:in_danger" not in found

    async def _classify_in_background(self, text: str, turn: int) -> None:
        level = await asyncio.to_thread(self.classify, text)
        await self._escalate(level, turn)

    async def check_heard_so_far(self) -> None:
        """At the end of the user's speech (and for transcript that arrives
        after it): check what's known now, before Ced answers if possible."""
        if self.heard.strip():
            await self._check_words(self.heard.strip(), self.turn, self.last_ced_question)

    async def finish_user_turn(self) -> None:
        text, self.heard = self.heard.strip(), ""
        if not text:
            return   # nothing heard: Ced's question still waits for an answer
        turn, self.turn = self.turn, self.turn + 1
        question, self.last_ced_question = self.last_ced_question, None
        await self._check_words(text, turn, question)
        task = asyncio.create_task(self._classify_in_background(_classifier_input(question, text, self._earlier_concern(turn)), turn))
        self.checks.add(task)
        task.add_done_callback(self.checks.discard)

    async def finish_ced_turn(self) -> None:
        """Ced finished (or was interrupted): keep its last question for the
        user's answer, and screen what it said (memory only, never logged)."""
        said, self.ced_said = self.ced_said.strip(), ""
        if not said:
            return
        questions = re.findall(r"[^.!?]*\?", said)
        self.last_ced_question = questions[-1].strip() if questions else None
        if safety.check_reply(said) != said and "reply_correction" not in self.noted:
            self.noted.add("reply_correction")
            diag("call %s: ced's reply crossed a boundary; correction note sent", self.call_id)
            with contextlib.suppress(Exception):
                await self.session.send_note(prompt.VOICE_SAFETY_PREFIX + VOICE_REPLY_CORRECTION)

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
                await self.finish_ced_turn()
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
                elif self.state == "thinking":
                    # Transcript that arrives after they stopped talking:
                    # check it now, before Ced's reply if possible.
                    await self.check_heard_so_far()
            elif kind == "ced_text":
                self.ced_said += event[1]
            elif kind == "speech_start":
                self.uses_speech_events = True
                if self.state == "thinking":
                    await self.set_state("listening")  # they kept talking
            elif kind == "speech_end":
                self.uses_speech_events = True
                if self.state == "listening":
                    await self.set_state("thinking")
                await self.check_heard_so_far()       # what's known already, right away
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
                await self.finish_ced_turn()
                await self.set_state("listening")
            elif kind == "turn_complete":
                diag("call %s: gemini turn complete (sent %d chunks / %d B of audio)", self.call_id, *self.audio_out)
                await self.finish_ced_turn()
                await self.finish_user_turn()
                await self.set_state("listening")
        raise GeminiDropped()


# Sent when what Ced said on a call crossed a boundary (claimed to be a
# therapist, diagnosed, gave medication advice or promised an outcome). Audio
# can't be taken back, so the model is asked to correct it next.
VOICE_REPLY_CORRECTION = (
    "Your last reply may have sounded like a diagnosis, medical advice, a promise, or a "
    "professional's opinion. In your next turn, gently correct that in one short sentence: "
    "you're an AI companion, not a therapist or doctor. Then carry on listening."
)


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
                        if call.noted:
                            # A fresh line knows nothing of this call: tell it
                            # what the safety checks noted before it greets.
                            call.last_ced_question = None
                            with contextlib.suppress(Exception):
                                await session.send_note(_reconnect_note(call.noted))
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
