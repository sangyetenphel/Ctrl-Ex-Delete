# Ctrl + Ex + Delete — AI Integration Handoff

_Written 2026-10-23 for a fresh Claude Code session. Covers the work on branches
`integration/full-app` and `feature/ced-ai-integration`._

Legend used throughout:
- **✅ Verified** — run and observed (tests, real API calls, simulator, Neon queries).
- **⚠️ Not verified** — implemented but not yet observed working in that environment.
- **💡 Proposed** — an idea or recommendation, not implemented.

No secret values appear in this document. `backend/.env` is git-ignored and must never be printed, committed or pasted.

---

## 0. Resume checklist (read first)

1. Branch: `feature/ced-ai-integration` (local only, **not pushed**). Latest commit `2d3085f`.
2. Uncommitted changes in the working tree belong to the user (physical-iPhone setup, §2). **Do not revert or commit them without asking.**
3. The "Thinking…" freeze fixes are **committed** (`2d3085f`) and verified against the real Gemini API from scripts and the simulator. **Not yet verified on a physical iPhone** — that is the next step (§8, P1).
4. The user's own backend runs as `uvicorn app.main:app --reload` (port 8000). `--reload` does **not** re-read `.env`; restart it after `.env` changes.
5. Rules the user set: never push / merge / touch `main` without permission; preserve Ayusha's SwiftUI design; no secrets in output; explain destructive DB operations and confirm the target before running them.

---

## 1. Project overview

**Ctrl + Ex + Delete (CED)** — a UNCG Fall 2026 senior capstone iOS app for breakup recovery. Anonymous (no accounts): each install has a random UUID **installation ID** stored in the Keychain (`InstallationID.swift`) and sent as `X-Installation-ID` on every request (and on the voice WebSocket).

Team (from README): Ayusha Thapa (SwiftUI frontend), Sangye Tengkhar (AI integration & safety — the user driving these sessions), Alexa Chegue-Santos (backend logic/recommendations), Leonard "Leo" Parra (database & S3).

### Architecture
```
SwiftUI app (iOS 26, Xcode 26, Swift 5 mode, default actor isolation = MainActor)
   │  HTTPS/HTTP JSON  +  WebSocket (/ced/voice)
FastAPI backend (Python 3.11 venv in backend/venv)
   ├─ Neon PostgreSQL (psycopg 3)            — all app data
   ├─ AWS S3 (boto3, presigned URLs)          — scrapbook photos, private bucket
   ├─ Groq (groq SDK, openai/gpt-oss-120b)    — Ced text chat + transcript risk classifier
   └─ Gemini Live (google-genai, gemini-3.8-live) — Ced voice calls (relayed by backend)
```

### Features and status
| Feature | Status |
|---|---|
| Daily Check-In | ✅ working, persisted |
| Activity recommendations (3 cards; saved/bookmarked first) | ✅ |
| "I'll try this" → one activity **in progress** at a time (DB-enforced) | ✅ |
| Save for later (bookmarks) | ✅ |
| Reflection → completes activity, optional photo (PhotosPicker → S3) | ✅ (real S3 configured by user; see §8 for what was verified) |
| Scrapbook (memories, photos, delete via long-press) | ✅ |
| Progress & Insights (week/month, urges, mood answers, categories, observations) | ✅ real data |
| Healing Room (Day N, navigation) | ✅ |
| Ced text chat (Groq) — bubbles, safety, crisis card | ✅ |
| "Say it here first" (no-contact companion) → chat | ✅ |
| **Call Ced** voice (Gemini Live) | ✅ simulator/API; ⚠️ physical iPhone |
| Moving Forward / Final Gift persistence | ❌ not built |
| Device credential (anonymous auth) | 💡 proposed only (§10) |

---

## 2. Current Git state (at time of writing)

- **Branch:** `feature/ced-ai-integration`, created from `integration/full-app` @ `d66307e`.
- `origin/integration/full-app` = `d66307e` (the user pushed it). `feature/ced-ai-integration` has **no upstream** and is **6 commits ahead** of it.
- **Commits on this branch (newest first):**
  - `2d3085f` Voice calls: never stuck on "Thinking", resume dropped connections
  - `c2abe48` Fix silent Ced and stuck "Listening" on voice calls
  - `9409422` Call Ced: voice calls with Gemini Live, relayed by the backend
  - `eaa89ca` Ced: warmer replies in short bubbles, in-chat crisis resources
  - `1e7e3ee` Accept GROQ_MODEL in .env and ignore unrelated .env lines
  - `d8e0984` Ced AI chat through Groq, with backend safety checks and limits
- **Earlier (on `integration/full-app`):** `d66307e`, `26898be` (Insights, S3 lifecycle), `eedfa0b` (activity status/bookmarks), `9653ae1` (schema 005), `44905c3` (journey), `dd4dc38` (S3 optional), plus the two merges `6b74e4f` / `1c0de9b`.
- **Uncommitted changes (made by the user, not by Claude — preserve them):**
  - `M CtrlExDelete/CtrlExDelete.xcodeproj/project.pbxproj` — `DEVELOPMENT_TEAM` set; `PRODUCT_BUNDLE_IDENTIFIER = com.sangye.CtrlExDelete` (was `devplaceholder…`); `INFOPLIST_KEY_NSLocalNetworkUsageDescription` added to both configs.
  - `M CtrlExDelete/Config/Debug-Info.plist` — header comment and `NSLocalNetworkUsageDescription` removed (moved to build settings above; `NSAllowsLocalNetworking` kept).
  - `?? CtrlExDelete/CtrlExDelete.xcodeproj/xcshareddata/xcschemes/CtrlExDelete.xcscheme` — shared scheme with launch argument `-CEDAPIBaseURL http://<LAN IP>:8000` (physical-iPhone testing).
  - These look intentional (device testing). Ask the user before committing; a hard-coded LAN IP in a shared scheme is probably not something to push.
- **Teammate branches on GitHub not yet integrated** (seen via `git ls-remote`, not inspected): `backend/personal-insights`, `backend/smarter-recommendations`, `feature/moving-forward-scrapbook`, `front-end/updated-activity-recommendations` (plus older `Leo_branch`, `backend/recommendations`, `front-end/completed-screens`, `front-end/setup`).

---

## 3. Completed work (all sessions so far)

### Integration (Phase 2) — ✅
- `integration/full-app` = `integration/checkin-activities` + merge `frontend/completed-screens` (Ayusha) + merge `feature/scrapbook-integration` (Leo). 3 conflicts resolved (kept Ayusha's `ContentView`/`ScrapbookView`; deleted `PlaceholderScreens.swift`).
- Leo's S3 code: AWS settings made optional (API runs without them; photo routes 503), boto3 client lazy, **random S3 keys** `scrapbook/<uuid>.jpg` (old keys contained the installation ID), reset-script typo fixed.

### Database (Neon) — ✅ migrations 001–008 applied (each after a backup + rehearsal on a local copy)
| Migration | Purpose |
|---|---|
| 001–003 | baseline, recommendations, seed activities (pre-existing) |
| 004 | `scrapbook_photos` (Leo; left byte-for-byte unchanged) |
| 005 | `reflections` replaces unused `activity_logs`; dropped unused photo columns; composite `(id, installation_id)` FKs so rows can't link across installations |
| 006 | `activity_selections.status` (`in_progress`/`completed`/`abandoned`) + `ended_at`; partial unique index = one in-progress per installation; `activity_bookmarks` |
| 007 | `activity_selections.completed_on` (deleting a memory never undoes a completion) |
| 008 | `ced_usage` (per-installation daily message **count only**, no text) |

### Product features — ✅
Journey (check-in → recommendations → select → reflection w/ photo → scrapbook → insights), bookmarks, one-in-progress lock with "Change activity" confirmation, memory deletion, real Progress/Insights (`app/insights.py`, pure functions), "Day N".

### Ced text chat (Groq) — ✅ (see §4b)
### Ced voice calls (Gemini Live) — ✅ simulator/API, ⚠️ device (see §4)

---

## 4. Gemini Live voice calls ("Call Ced")

### 4a. How it works
```
iPhone mic ─16 kHz PCM16─▶ WS /ced/voice (FastAPI) ─▶ Gemini Live (gemini-3.8-live)
iPhone spk ◀─24 kHz PCM16── WS /ced/voice ◀──────────── Gemini audio
            ◀─ JSON events (ready/state/interrupted/safety/ended/error)
```
- **Why a backend relay** (decided with the user): the Gemini key never leaves the server; the backend sees transcripts for independent safety checks; per-installation limits. (Ephemeral client tokens were considered and rejected.)
- **Wire protocol** (authoritative docstring at top of `backend/app/ced/voice.py`; also `docs/api.md`):
  - App → server: binary PCM16 LE **16 kHz mono** (~100 ms chunks); JSON `{"type":"mute"|"unmute"|"end"}`.
  - Server → app: binary PCM16 LE **24 kHz mono**; JSON `ready{max_seconds}`, `state{listening|thinking|speaking|reconnecting}`, `interrupted`, `safety{support: crisis|danger, risk}`, `ended{reason: time_limit}`, `error{code: unavailable|busy|limit|dropped, message}`.
- **Gemini config** (`voice.live_config(resume_handle=None)`): `response_modalities=["AUDIO"]`, `system_instruction=prompt.VOICE_PROMPT`, voice `settings.gemini_voice`, `input_audio_transcription` (for safety only; output transcription off), automatic activity detection (`END_SENSITIVITY_LOW`, `silence_duration_ms=700`), context-window compression (sliding window), `session_resumption=SessionResumptionConfig(handle=…)`.
- **Greeting:** on a fresh session the backend sends client content "(The call just connected.)" so Ced greets first; after a mid-call fresh restart it asks Ced to say it's back.
- **States** (backend is authoritative, app just displays): `speech_end` (Gemini voice-activity END) → `thinking`; first reply audio → `speaking`; `turn_complete`/`interrupted` → `listening`; `speech_start` while thinking → `listening`. Transcript-driven `thinking` is only a fallback if Gemini sends no voice-activity events.
- **Timeouts (backend, `voice.py`):** `REPLY_TIMEOUT=7.0` s (thinking → listening if Gemini never replies), `SPEAKING_STALL_TIMEOUT=10.0` s, `TRANSCRIPT_GRACE=1.5` s (safety check after speech end), `MAX_RECONNECTS=3`.
- **Reconnection (backend):** stores `session_resumption_update.new_handle`. On any Gemini connection error (incl. ~10-min lifetime / `go_away`): send `state: reconnecting`, back off 0.5–2 s, reconnect **with handle** (conversation continues, no greeting). If a resume attempt fails, the handle is dropped and the next attempt is a **fresh** session with the "I'm back" greeting. After 3 reconnects → `error/dropped` ("The call with Ced dropped. Tap “Call again” to reconnect.").
- **App side:**
  - `CallAudio` (AVAudioEngine): `.playAndRecord` / `.voiceChat`, voice processing (AEC) on input, tap → `AVAudioConverter` → 16 kHz Int16; playback node at 24 kHz Float32; **restarts the engine on `AVAudioEngineConfigurationChange`**; holds Ced's audio while (re)starting; `stopPlayback()` on `interrupted`; speaker toggle via `overrideOutputAudioPort`.
  - **Simulator-only echo guard**: while Ced's audio is actually playing (+0.45 s), mic sends zeros (simulator has no usable AEC — Mac speakers → Mac mic). Consequence: **no barge-in in the simulator**; real iPhone keeps full barge-in.
  - `LiveVoiceTransport`: `URLSessionWebSocketTask`, ignores events from replaced transports, keep-alive ping every 10 s (failure → dropped).
  - `CallSession`: phases connecting/active/ended; 25 s watchdog ends a call that hears nothing from the server while not listening; interruption notifications end the call; Debug-only mock fallback when server says `unavailable`.
  - `CallCedView`: FaceTime-inspired, pixel Ced from `RoomArtwork.PixelCedArt`; mute/speaker/end; Support button + automatic crisis panel (Call 988 / Text 988 / Call 911 for danger) that **ends the call before** opening `tel:`/`sms:` — only on tap; ended screen has **Close** + **Call again**.
- **Voice safety** (not reliant on the live model): each finished user turn's transcript → `safety.check_message` (patterns) + `risk.classify` (independent Groq JSON classifier, background). Self-harm/danger → `safety` event (panel) + a note to Gemini via `send_client_content(turn_complete=False)` prefixed `VOICE_SAFETY_PREFIX`. Stalking → note only. Runs even when Gemini doesn't reply (since `2d3085f`).
- **Limits:** one call per installation, `CED_VOICE_MAX_CONCURRENT=3` server-wide, `CED_VOICE_MAX_MINUTES=15` per call; each call counts as 1 toward the daily Ced limit.
- **Privacy:** audio and transcripts in memory only; nothing stored; diagnostics log counts/types/sizes only.

### 4b. Ced text chat (Groq) — for context
- `POST /ced/messages`; app sends recent turns (≤40, server uses last 12 / ~6,000 chars); server stores **no text** (only `ced_usage` counts).
- Model replies in JSON `{"risk", "messages": [1–3 bubbles]}`; `bubbles.split` enforces 1–3 bubbles of 1–3 sentences.
- Risk = more serious of patterns (`safety.check_message`) and model's own rating. Self-harm/in-danger replies always contain a direct "are you safe right now?" (appended if missing). `support: crisis|danger` → in-chat `CrisisSupportCard` (Call/Text 988, 911); nothing opens automatically.
- Fallbacks: crisis messages are always answered (human-written bubbles) even with no key / limits / provider errors. Unsafe replies (therapist claims, diagnoses, medication, promises) are replaced.
- Limits: 8/min & 60/day per installation, 25/min server-wide; Groq 429 → friendly 429 with Retry-After.

---

## 5. Debugging findings (chronological, significant only)

| # | Symptom | Root cause (confirmed?) | Fix / outcome |
|---|---|---|---|
| 1 | `GET /recommendations/latest` 500, `column l.activity_selection_id does not exist` | ✅ migration 005 not yet applied to Neon | Rewrote 005 as a cleanup (reflections table), applied after backup |
| 2 | App crash at launch (`swift_task_dealloc`) | ✅ `async let` in `JourneyStore.refresh` with MainActor default isolation | Sequential awaits |
| 3 | Second simulator call "dropped" immediately | ✅ late close event from the replaced (unavailable→mock) transport | Ignore events from non-current transport; mark closed after server error |
| 4 | Backend wouldn't start | ✅ `.env` had `GROQ_MODEL`; settings forbade unknown keys | `GROQ_MODEL` alias for `AI_MODEL`; `extra="ignore"` |
| 5 | Voice: "Ced is speaking" but silent; stuck "Listening" | ✅ enabling voice processing + speaker route triggers `AVAudioEngineConfigurationChange`, which **stopped the engine** (no playback, no mic → backend got 0 mic chunks) | Restart engine on config change; hold audio meanwhile (`c2abe48`) |
| 6 | Simulator: Ced constantly "interrupted" | ✅ simulator echo (Mac speakers → Mac mic; AEC ineffective) | Simulator-only echo guard (no barge-in in simulator) |
| 7 | Gemini session closed right after setup (`1011 Internal error`) | ✅ transient Google-side error (retries all succeeded) | Reconnect logic |
| 8 | **Stuck on "Thinking…"** | ✅ see §6 | `2d3085f` |
| 9 | One real mid-call drop `1006`, then resume refused `1008` ×3 | ⚠️ cause not confirmed (Google-side; direct resume tests after abrupt client abort all succeeded at 0/2/5 s) | On resume failure fall back to a fresh session |
| 10 | Unknown `GEMINI_VOICE` silently accepted by Gemini | ✅ ("NotARealVoice" accepted, sounded like default) | Validate against 30 documented voices; warn + default |

Approaches that **did not work / were wrong** (don't repeat):
- Treating `TestClient` WebSocket close as an exception — Starlette's test client *returns* a `websocket.close` message; loop until it.
- `xcrun simctl` taps: the first tap after launch/transition is often dropped; screenshots can lag one frame — re-capture before concluding.
- Python loop variable named `path` in zsh shell snippets breaks `PATH`.
- Assuming a closed Gemini connection hangs `receive()` — it doesn't; the SDK raises `APIError` (checked in `google/genai/live.py`).

---

## 6. The "Thinking…" freeze (current issue)

**Status:** root cause ✅ confirmed with the real API; fix ✅ committed in `2d3085f` and ✅ verified with real Gemini (scripted probes + simulator). ⚠️ **Not yet verified on a physical iPhone**, and the user's port-8000 server must be **restarted** to load it.

### Reproduction (real API, before the fix)
- 12-minute scripted conversation (47 synthetic `say` turns, open mic with silence between): **0 freezes**, no `go_away`, ~18k tokens context at end. So long calls/quota were *not* the cause.
- Edge sounds: `"Um."`, `"Hmm."`, `"So I was thinking that maybe"`, a 0.4 s noise burst, quiet fast speech. After `"Um."` the call stayed in **thinking for >80 s** until the quiet speech triggered a reply.
- Backend log showed Gemini sent `voice_activity ACTIVITY_START/END` and an input transcription (1 char) but **no generation, no turn_complete** — Gemini 3.8 Live chooses not to answer fillers/half sentences/noise.
- Old relay set `thinking` on any transcript and only left it on reply audio/turn_complete → stuck. Also the user-turn safety check only ran when Ced replied (safety gap).

### Fixes in `2d3085f`
- States from Gemini's voice-activity events; `REPLY_TIMEOUT` 7 s → listening (+ safety check runs); `SPEAKING_STALL_TIMEOUT` 10 s; reconnect/resume (§4a); `reconnecting` state; app keep-alive ping, 25 s watchdog, **Call again** button; voice-name validation; more diagnostics.

### Verification after the fix (✅ real API)
- Same edge sounds: none stuck (`"Um."` either got a short reply or the stall timeout returned to listening).
- Simulator real call: greeting + `"Um."` + question → normal states.
- Killing the server mid-call → app showed "The call with Ced dropped… Call again" within ~3 s; **Call again** connected (session ready 0.58 s).
- Direct resumption: handle accepted immediately and after 0/2/5 s following an abrupt client abort.
- 3 concurrent sessions (+1 simulator call) — no quota error.
- `pytest`: 133 passed, 2 skipped (skips = "no key configured" checks, because keys exist).

---

## 7. Important files

**Backend (`backend/`)**
- `app/main.py` — routers; `app/config.py` — `Settings` (pydantic-settings, `.env`, `extra="ignore"`, `GEMINI_VOICES`, voice validator, `GROQ_MODEL`/`AI_MODEL` alias).
- `app/storage.py` — the only DB module (journey, bookmarks, reflections, progress, insight records, `count_ced_message`).
- `app/media.py` — S3 (presigned PUT 5 min / GET 1 h, `new_key()`); `app/insights.py` — Insights calculations.
- `app/ced/prompt.py` — `CHARACTER`, `TEXT_OUTPUT`, `SYSTEM_PROMPT`, `VOICE_STYLE`, `VOICE_PROMPT`, `SAFETY_NOTES`, `VOICE_SAFETY_PREFIX`, `UNSENT_MESSAGE_CONTEXT`.
- `app/ced/safety.py` — `check_message`, `RISK_ORDER`, `SUPPORT_FOR_RISK`, `FALLBACK_REPLIES`, `check_reply`, `FALLBACK_REPLY`.
- `app/ced/chat.py` (text turn), `bubbles.py`, `providers.py` (Groq; `complete(messages, json_reply)`), `limits.py`, `risk.py` (`classify` for transcripts).
- `app/ced/voice.py` — `GeminiSession` (`send_audio`, `end_audio`, `greet(reconnected)`, `send_note`, `events()`), `live_config`, `gemini_connect(resume_handle)`, `_Slots`, `_Call` (`from_app`, `from_model`, `watchdog`, `finish_user_turn`, `_escalate`), `run_call`, `diag`/`_diag_message` (temporary diagnostics).
- `app/routes/*.py` — incl. `ced.py` (`POST /ced/messages`, `WS /ced/voice`).
- `db/migrations/001–008`, `scripts/migrate.py` (`--status`), `scripts/reset_dev_db.py` (destructive, asks to type RESET), `scripts/check_s3.py`.
- Tests: `tests/conftest.py` (`installation_id`, `fake_s3`), `test_api`, `test_bookmarks`, `test_reflections`, `test_scrapbook`, `test_insights`, `test_ced` (Groq faked), `test_ced_voice` (Gemini faked via `FakeLive`; b"SAY:…" / b"SAY:silent:…").

**App (`CtrlExDelete/CtrlExDelete/`)**
- `Networking/APIClient.swift`, `APIModels.swift`, `APIConfig.swift` (Debug base URL `127.0.0.1:8000`, override `-CEDAPIBaseURL`), `InstallationID.swift`.
- `Models/JourneyStore.swift`, `SampleData.swift` (Activity, ActivityDeck, enums), `Insights.swift`, `CedChat.swift`.
- `Screens/ActivitiesView.swift`, `ReflectionView.swift`, `ScrapbookView.swift`, `ProgressInsightsView.swift`, `Room/HealingRoomView.swift`, `Room/RoomArtwork.swift` (`PixelCedArt`).
- `Screens/Talk/TalkView.swift`, `CedChatView.swift`, `CrisisSupportCard.swift`, `SupportSheet.swift`, `CallCedView.swift` (incl. `CallCedButton`).
- `Voice/CallAudio.swift`, `CallSession.swift`, `VoiceTransport.swift` (`LiveVoiceTransport`, Debug `MockVoiceTransport`), `CallDiagnostics.swift`.
- Docs: `docs/api.md` (API contract — keep in sync), `backend/README.md`, root `README.md`.

**Config (names only)** — `backend/.env`: `DATABASE_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET`, `GROQ_API_KEY`, `GROQ_MODEL`, `GEMINI_API_KEY`, `GEMINI_VOICE` (=Zephyr). Optional: `GEMINI_LIVE_MODEL`, `CED_VOICE_MAX_MINUTES`, `CED_VOICE_MAX_CONCURRENT`, `CED_VOICE_DIAGNOSTICS`, `CED_DAILY_MESSAGE_LIMIT`, `S3_ENDPOINT_URL`, `AI_PROVIDER`.

---

## 8. Pending tasks (prioritised)

**P1 — demo readiness (voice)**
1. Restart the user's backend (`.env`/code reload) and rebuild the app.
2. ⚠️ Test Call Ced on a **physical iPhone** (user has set signing + LAN scheme): greeting audible, turn-taking, **barge-in**, earpiece/speaker toggle, crisis panel, "Reconnecting…", Call again. Read app logs in Console.app (subsystem `com.ctrlexdelete`, category `call`).
3. ⚠️ Confirm on device that echo cancellation prevents self-interruption (the simulator echo guard is compiled out on device).
4. ⚠️ Not verified: whether `gemini-3.8-live` honours mid-session `send_client_content(turn_complete=False)` safety notes (errors are suppressed; the on-screen panel doesn't depend on it).
5. Turn off temporary diagnostics before the demo: `CED_VOICE_DIAGNOSTICS=false` (backend), `CallDiagnostics.enabled = false` (app) — or remove them.
6. User to check free-tier limits at aistudio.google.com/rate-limit (Google doesn't publish Live free-tier numbers; observed: 4 concurrent sessions OK, no quota errors).

**P2 — product**
7. Moving Forward / Final Gift persistence (+ "Moving forward check-in" milestone; Final Gift buttons "Keep the app"/"Archive room" have no action).
8. Integrate teammate branches on GitHub (`backend/personal-insights`, `backend/smarter-recommendations`, `feature/moving-forward-scrapbook`, `front-end/updated-activity-recommendations`) — inspect for overlap with work here first.
9. Device-credential decision (💡 proposal in §10).

**P3 — housekeeping**
10. Decide what to do with the user's uncommitted Xcode changes (§2).
11. Leo's 7 legacy `scrapbook_photos` rows use old keys containing installation IDs (left untouched by request scope).
12. Push `feature/ced-ai-integration` / open PR — **only with the user's permission**.
13. Groq Zero Data Retention: recommended to the user (console → Settings → Data Controls); not confirmed whether enabled.

---

## 9. Testing

```bash
cd backend && source venv/bin/activate
pytest -q                                   # uses DATABASE_URL (Neon); each test uses + deletes a random installation
DATABASE_URL=postgresql://<local> pytest -q # optional throwaway local Postgres (migrate it first)
python -m scripts.migrate --status          # read-only status (creates schema_migrations if missing)
python -m scripts.check_s3                  # one throwaway object under scrapbook/_check-s3-…; no secrets printed
uvicorn app.main:app --reload               # local dev (simulator uses 127.0.0.1:8000)
uvicorn app.main:app --host 0.0.0.0 --port 8000   # physical iPhone on same Wi-Fi
```
App build (simulator):
```bash
cd CtrlExDelete && xcodebuild -scheme CtrlExDelete -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
App call diagnostics (simulator):
```bash
xcrun simctl spawn booted log stream --level info --predicate 'subsystem == "com.ctrlexdelete" AND category == "call"'
```
Debug launch arguments: `-CEDStartScreen <screen>`, `-CEDAPIBaseURL <url>`, `-CEDMockVoice YES`, `-CEDMockVoiceCrisis YES`.

**Last results:** ✅ 133 passed, 2 skipped (backend); ✅ iOS build clean (no warnings) at `2d3085f`.

**Real-API probes used in this session** (scripts lived in a temporary scratchpad and are gone; recreate if needed): stream macOS `say` audio (converted with `afconvert -f WAVE -d LEI16@16000 -c 1`) over the WebSocket in 100 ms chunks followed by zero-filled "open mic" chunks; log only event types, timings and byte counts.

**Still to run:** physical-iPhone checklist (§8 P1), a full Groq/Gemini regression after any prompt change, Moving Forward once built.

**Simulator limitations:** no real echo cancellation (Mac speaker → Mac mic; barge-in disabled there); `tel:`/`sms:` don't open (no Phone/Messages); first taps after transitions are often dropped.

---

## 10. Important decisions & user requirements (preserve)

- **Never** push, merge, or modify `main` / team branches without explicit permission. Commit locally when finishing a unit of work (the user has accepted local commits).
- **Preserve Ayusha's Figma/SwiftUI visual design** (colors, Lora/Nunito typography, pixel art, navigation). Functional UI additions are OK when needed; avoid redesigns.
- **Secrets:** never print/commit `.env` values or keys; verify presence by name/length only.
- **Database:** additive, re-runnable migrations; never edit applied migrations; back up + rehearse on a copy, confirm the target, and explain impact before applying to Neon. The user permitted resetting **development** data but wants destructive steps explained first.
- **Activity categories stay** `outdoor_movement`, `mindfulness_rest`, `solo_exploration`, `social_connection` (no remap).
- **Mood after activities** stored and shown as the original answers (worse / about the same / a little better / much better) — never numeric scores.
- **Selection ≠ completion.** Only a saved reflection completes an activity; one in-progress activity per installation (DB-enforced); "Change activity" abandons without completing.
- **Insights** must be backed by real records; describe, never imply causation; empty states for new users.
- **Chat privacy:** no permanent chat history; no message text in Neon or logs; only usage counts. No inferred triggers stored without consent.
- **Ced persona:** warm, concise, non-clinical; not a therapist; no diagnoses/medication/promises; no help with stalking/revenge/tracking; encourage real-world support and independence; doesn't over-suggest therapy.
- **Crisis UX:** resources (Call/Text 988; Call 911 for danger) appear **in context, only open on tap**; safety never relies solely on the model (patterns + independent classifier + guaranteed safety question / panel).
- **AI providers:** Groq `openai/gpt-oss-120b` for text (free tier); Gemini Live `gemini-3.8-live` for voice, voice **Zephyr** (user's choice); providers configurable via `.env`.
- **Voice architecture:** backend relay (key stays server-side); temporary context only; diagnostics are temporary and privacy-safe.
- 💡 **Device credential proposal (pending user decision):** app-generated 256-bit secret in Keychain sent as `Authorization: Bearer`, server stores only a hash (nullable `installations.secret_hash`), trust-on-first-use for existing installs, required first on new private endpoints and later on check-ins/recommendations.
