# Handoff: deploying the optimized CED backend (2026-11-04)

For a fresh Claude Code session. Read `CLAUDE.md` first, then this file.
No credentials or user data appear here; settings are named, never shown.

## 1. Where things stand

| | State |
|---|---|
| Working branch | `refactor/final-optimization` at `3f9f235`, pushed, 15 commits ahead of `integration/ai-room-progress` |
| Known-good backup branch | `integration/ai-room-progress` at `3066b70` (what the live service deploys) |
| `main` | `f180e3b`, untouched |
| Uncommitted, local only | `CtrlExDelete.xcodeproj/project.pbxproj` (Sangye's signing team and bundle ID `com.sangye.CtrlExDelete`; the committed values are Ayusha's) and `xcshareddata/xcschemes/CtrlExDelete.xcscheme` (3 `BlueprintName` lines Xcode adds). **Never commit them.** |
| Git-ignored settings files (`backend/`) | `.env` (Leo's original infrastructure: the live service's values), `.env.production` (the new Neon `neondb`, the new bucket, the `ced-production` IAM key), `.env.migration` (earlier plan, now unused), `.local-backup/2026-11-04/` (old database dump and photo copies: user data) |
| Live Render service | `ctrl-ex-delete-api`, `https://ctrl-ex-delete-api.onrender.com`, Free, Virginia, auto-deploys `integration/ai-room-progress`, still serving the **old** code (`de1df9a`) against Leo's Neon and S3. Pushes since then carried `[skip render]` |
| Planned test service | `ced-backend-test`: approved by Sangye, **not created yet** (section 5) |
| Render plugin | Render's official Claude Code plugin was offered and approved as the route; installation and its OAuth sign-in were **not yet confirmed** when this was written. Check with ListPlugins |

## 2. What was done on `refactor/final-optimization`

All tested; `pytest` (against a local database) passes 297.

**Ced chat (root cause found).** Ced's earlier turns went back to Groq as plain
text while JSON was required, so gpt-oss often answered in plain text and
Groq rejected it (`json_validate_failed`), shown as "Ced couldn't answer just
now". Earlier turns are now sent in the JSON shape (one item per bubble):
24/24 fast real-Groq conversations succeeded, crisis detection unchanged. The
Groq SDK no longer silently waits up to 60 s on a 429; one immediate retry for
dropped connections, 5xx and JSON rejections. A crisis message still gets the
human-written reply when the database is down. The voice risk check uses a
300-token budget at temperature 0.

**Backend.** psycopg connection pool (one-query endpoints ~425 → ~160 ms,
month Insights 1.5 → 0.8 s, measured against Neon); S3 timeouts and bounded
retries; one photo-link helper; input checks; voice daily-limit call off the
event loop; temporary voice diagnostics off by default; photo rows deleted
before their S3 files.

**iOS** (built for Simulator, iPhone and Release; not installed on a phone
since): cancelled requests no longer show "couldn't reach the server"; chat
turns capped at 2,000 characters (long unsent letters broke the chat with
422); Mute stops sending audio; call diagnostics Debug-only, no crisis label
logged; 3 unused fonts, 3 icons and strict unused response fields removed
(bundle 12.5 → 11.9 MB). Earlier UI work (portrait only, Story dots, Support
buttons, Files export) is on both branches.

**Database (fresh start, approved changes A–H).** `backend/db/migrations/001_schema.sql`
is the whole schema for a new database; the 19 old migrations are in
`db/migrations/legacy/` and `scripts.migrate` refuses a database that ran them.
One check-in per day as a real constraint; category names only in
`activity_categories` (copied column and trigger removed); six unused columns
dropped; note ≤ 1,000 characters and ≤ 5 hardest areas enforced; two indexes
added, five unused ones dropped (no query got slower); `last_seen_at` at most
daily. API responses are identical (40-call comparison), so the app needs no
change. `scripts.verify_database [--fresh]` checks schema and catalogs.
`CED_ENV_FILE=.env.production` makes the server and every script use that
file. Details: `docs/DATABASE_DESIGN.md`, setup: `docs/MIGRATION.md`.

**Decided, not built:** Gemini for text chat (Groq kept: no training on data,
higher free limits, cause was our bug); Ced personalization from app data
(deferred by Sangye; the opt-in design is in the session's privacy audit).

## 3. The new infrastructure (Sangye's accounts)

**Neon:** project `ctrl-ex-delete`, branch `production`, PostgreSQL 18.6,
AWS us-east-1. Database `neondb`: schema and catalogs initialized,
`verify_database --fresh` passed (21 tables, 23 foreign keys, 100 activities,
109 research links, 30 affirmations, 32 room messages, 4 categories, empty
user tables). Database `rehearsal` on the same branch holds a copy of old user
data from an earlier migration rehearsal: **to be deleted only when Sangye
says so.**

**AWS S3:** a private bucket in us-east-1 (name in `.env.production`), Block
Public Access on (all four), ACLs disabled, SSE-S3, versioning off; IAM user
`ced-production` with an inline policy for that bucket only
(`ListBucket`, `GetBucketPublicAccessBlock`, `Get/Put/DeleteObject`); root MFA
on. Verified: `check_s3` passed (private upload, presigned download,
anonymous request refused, test object deleted); the phone's presigned PUT
works and a wrong content type is refused; objects are encrypted (AES256);
the key is refused for other buckets, account listing and IAM. Bucket empty.

Commands against it (from `backend/`, venv active; on this Mac add
`SSL_CERT_FILE=$(python -m certifi)` for `check_s3`):

```bash
CED_ENV_FILE=.env.production python -m scripts.verify_database --fresh
CED_ENV_FILE=.env.production python -m scripts.check_s3
```

## 4. Rules for whoever continues

Without Sangye's explicit approval, never: merge any branch, change the live
service (`ctrl-ex-delete-api`: settings, branch, environment, deploys), create
anything billable, write to Leo's Neon database or bucket, delete `rehearsal`
or anything in AWS, commit the Xcode signing or scheme files, or print,
paste or commit any secret. Claude must not type passwords or API keys into
Render (dashboard or API): Sangye enters secret values; Claude may check
variable **names** only. Push to `integration/ai-room-progress` deploys
production (autoDeploy), so don't push there.

## 5. Next steps

**A. Create `ced-backend-test`** (approved: Free, $0).
1. Confirm the Render plugin is installed and signed in (ListPlugins, then
   its tools). If not, use the dashboard walkthrough in `docs/MIGRATION.md`
   section 4 with the values below.
2. Create a **Web Service** (not a Blueprint): repo
   `sangyetenphel/Ctrl-Ex-Delete`, branch `refactor/final-optimization`, root
   `backend`, Python 3, build `pip install -r requirements.txt`, start
   `uvicorn app.main:app --host 0.0.0.0 --port $PORT --proxy-headers --forwarded-allow-ips "*"`,
   region Virginia, Free, health check `/health`, auto-deploy **off**.
   Stop if Render asks for a payment method or a paid plan.
3. Non-secret variables Claude may set: `PYTHON_VERSION=3.11`,
   `AWS_REGION=us-east-1`, `GROQ_MODEL=openai/gpt-oss-120b`, `GEMINI_VOICE`
   (same as live), `S3_BUCKET` (from `.env.production`).
4. Secret variables Sangye pastes in the service's Environment tab:
   `DATABASE_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from
   `.env.production`), `GROQ_API_KEY`, `GEMINI_API_KEY` (same as live). Leave
   `CED_ENV_FILE` and `CED_VOICE_DIAGNOSTICS` unset.
5. Deploy; check names-only that all variables exist.

**B. Verify it.** Startup logs without errors; `/health` and `/health/db`;
`/openapi.json` shows the new code (UrgePoint's description mentions "a
seven-day week of the user's journey"; the old one says "a week of the
month"); `/affirmations` returns 30. To prove it uses the new resources
without exposing anything: one `POST /check-ins` with a throwaway UUID, find
it in `neondb` (via `.env.production`), and one `POST /scrapbook/photos`
whose upload link's host names the new bucket (compare, don't print); then
delete that installation in `neondb` (cascades), and the object if any.

**C. iPhone test** (Debug build only; the production URL in `APIConfig.swift`
stays unchanged). In the git-ignored `CtrlExDelete/Config/DeveloperSettings.xcconfig`
add `CED_API_BASE_URL = <test-service>.onrender.com` (host only: `//` starts
an xcconfig comment), then Run once from Xcode. It's built into the Debug app,
so Home Screen launches use it too. (The `-CEDAPIBaseURL` launch argument is
not enough: it only applies to runs started by Xcode, and a Home Screen
launch silently went to production on 2026-11-04.) The Debug app logs
`Backend: <host> (<source>)` at launch (Xcode console, or Console.app with
the phone selected, subsystem `CtrlExDelete`). On-phone copies of progress
and Ced's room message are matched by backend, so production data never
shows against the test database. Remove the line and Run again to go back to
production. The test service has its own fresh database, so the phone starts
as a new user there; production data returns when the line is removed. Checklist: wake-up on first launch (~1 min on Free), check-in, room
message, recommendations, choose/abandon/complete an activity, reflection
with camera and library photo, Story timeline and photos, Insights week and
month (switch quickly: no error card), bookshelf, bookmarks, plant game
(microphone), Ced text chat (several fast messages; a 2,000+ character unsent
message), Ced voice call (Mute: no audio sent), crisis wording shows 988/911
buttons, Moving Forward, scrapbook PDF saved to Files, portrait lock,
relaunch keeps progress. Afterwards, clear test data in `neondb` only with
Sangye's approval (`scripts.reset_dev_data` is local-only by design; a
targeted delete by installation is safer).

**D. Production switch-over** (only with approval):
1. Live service: Auto-Deploy **off**.
2. Merge `refactor/final-optimization` into `integration/ai-room-progress`.
3. Live service Environment: replace `DATABASE_URL`, `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET` with the new values
   (Sangye enters them), then **Save, rebuild, and deploy**: code and settings
   must change in one deploy (the new code needs the new schema).
4. Check `/health/db` and the app; Auto-Deploy back on; suspend or delete
   `ced-backend-test`. Users start fresh (decided).

**Rollback:** restore the old variable values in the live service and roll
back to the previous deploy (`3066b70`/`de1df9a` code); Leo's database and
bucket are untouched.

## 6. Privacy and security, open items

- Gemini: if the key is on the free tier, Google may use call audio and
  transcripts to improve its products (human review). Move the Gemini project
  to paid with logging off before real use; its terms also require users 18+.
- Live backend still logs voice diagnostics, including a crisis rating per
  call, and Render's access logs hold client IPs (fixed on this branch:
  diagnostics off by default; the rating line remains when turned on).
- Groq may keep requests up to 30 days for abuse checks: consider Zero Data
  Retention in the Groq console.
- The app doesn't tell users that messages go to Groq and Google.
- Keys pasted into chat earlier in development should be rotated (Groq,
  Gemini, Leo's AWS and Neon).
- `Config/Debug-Info.plist` still has an ATS exception for an old campus IP.
- After go-live: delete `rehearsal`, `backend/.env.migration` and
  `.local-backup/`; Leo deletes the original database and bucket after grading.
