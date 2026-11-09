# Running the Backend

The backend is a FastAPI server in the `backend/` folder. It stores data in our Neon PostgreSQL database. The full API contract is in [`docs/api.md`](../docs/api.md).

```
backend/
├── app/
│   ├── main.py                  # creates the FastAPI app and adds the routes
│   ├── config.py                # reads DATABASE_URL from backend/.env
│   ├── schemas.py               # request/response shapes (must match docs/api.md)
│   ├── storage.py               # the ONLY file that runs SQL
│   ├── recommendation_rules.py  # which activities to suggest after a check-in
│   ├── dependencies.py          # the X-Installation-ID header
│   └── routes/                  # health, check_ins, recommendations
├── db/migrations/               # 001_schema.sql builds a new database; legacy/ is the old history (reference)
├── scripts/
│   ├── migrate.py               # applies new migrations, then loads the catalog
│   ├── verify_database.py       # checks the schema and catalogs (read-only)
│   ├── catalog_data.py          # the 100-activity catalog and research sources
│   ├── seed_catalog.py          # loads the catalog (never deletes user history)
│   ├── reset_installation.py    # DEV ONLY: resets ONE installation (dry run by default)
│   ├── reset_dev_data.py        # DEV ONLY: deletes all user data and test uploads
│   └── reset_dev_db.py          # DEV ONLY: drops all CED tables
└── tests/test_api.py            # end-to-end tests (pytest)
```

## Requirements

- Python 3.11 or newer (check with `python3 --version`)
- The Neon connection string for our project (ask the team privately)
- Terminal commands below are for macOS

## First-time setup (only once)

From the repo root:

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
```

If your prompt starts with `(base)`, you have Anaconda active. Run `conda deactivate` **before** creating the venv.

### Settings files (secrets stay on this Mac)

Settings live in git-ignored files in `backend/` (`.gitignore` ignores every `.env*` except `.env.example`); every command picks one with `CED_ENV_FILE`:

| File | Use | How |
|---|---|---|
| `.env.production` | the production resources (Neon `production`/`neondb`, S3 `ced-photos-prod` with the IAM user `ced-production`, Groq, Gemini): the same values as the Render service | `CED_ENV_FILE=.env.production python -m scripts.…` (and `./ced-reset`). **Never** run `pytest` with it |
| `.env` (optional) | local development against a local PostgreSQL | `cp .env.example .env`, set a local `DATABASE_URL` (e.g. `postgresql://localhost/ced_dev`); used when `CED_ENV_FILE` isn't set |
| `.env.test` (optional) | the test suite's local database | see "Running the tests" |

Without a settings file a command stops with a `database_url … Field required` error: nothing ever falls back to production. For `.env.production`, copy the connection string from the Neon console (project `ctrl-ex-delete` ▸ branch `production` ▸ **Connect**; it ends with `?sslmode=require`) and the other values from wherever you keep them; Render's Environment tab holds the same ones.

- Never paste these values into Swift code, Slack, screenshots or commits.
- The iOS app never talks to Neon or S3 directly. Only this backend does.

### Create or update the database tables

```bash
python -m scripts.migrate
```

This applies any files in `db/migrations/` that haven't run yet and records them in a `schema_migrations` table, then loads the activity catalog (see below). It's safe to run again: it only applies new files, and the catalog load never duplicates anything or deletes user history (see below). Check what's applied with `python -m scripts.migrate --status` (changes nothing). `--no-seed` skips the catalog load.

### The activity catalog

The 100 activities (25 per category), their energy demand, duration, movement flag, wording and research sources live in `scripts/catalog_data.py`. Load or update them with:

```bash
python -m scripts.seed_catalog
```

It inserts or updates activities by `slug`. An activity that isn't in the file any more is deleted if nothing points at it; if someone was recommended, chose or saved it, it's **retired** instead (`is_active = false`: never recommended again, its history kept) and a warning is printed. On a database without old history (fresh, or after `reset_dev_data` below) the table holds exactly the catalog: 100 activities, all active. It runs automatically at the end of `python -m scripts.migrate`. To change the catalog, edit `catalog_data.py` and run it again. Research codes (M, B, E, N, S, K) link activities to broad research approaches in the `research_bases` table; they don't mean that specific activity was tested.

| Migration | What it does |
|---|---|
| `001_schema.sql` | The whole schema for a new, empty database: tables, keys, constraints and indexes (see `docs/DATABASE_DESIGN.md`). The catalogs come from the seed scripts that `migrate` runs afterwards |

The 19 earlier migrations are kept in `db/migrations/legacy/` for reference. They describe the original database, which `migrate` refuses to touch: it is kept only as a backup.

Check a database with `python -m scripts.verify_database` (add `--fresh` on a new one: user tables must be empty).

To change the schema later, **add a new numbered file** (e.g. `002_add_something.sql`). Don't edit a migration that has already been applied.

## Starting the server (every time)

```bash
cd backend
source venv/bin/activate
uvicorn app.main:app --reload
```

The server runs at `http://127.0.0.1:8000` until you press **Ctrl + C**. `--reload` restarts it when you save a file.

### Checking that it works

- `http://127.0.0.1:8000/health` should show `{"status":"ok"}`
- `http://127.0.0.1:8000/docs` lets you send test requests with **Try it out**. Endpoints that need an `X-Installation-ID` header need a UUID; run `uuidgen` in Terminal to get one.

### Running the tests

Against a **local** database only (some tests change shared catalogs or wipe user data). A throwaway PostgreSQL that needs no password, on its own port:

```bash
initdb -D /tmp/ced-pg -A trust -U ced_test
LC_ALL=en_US.UTF-8 pg_ctl -D /tmp/ced-pg -o "-p 55432 -c unix_socket_directories='' -c listen_addresses=localhost" -l /tmp/ced-pg.log start
createdb -h localhost -p 55432 -U ced_test ced_test
echo 'DATABASE_URL=postgresql://ced_test@localhost:55432/ced_test' > .env.test
CED_ENV_FILE=.env.test python -m scripts.migrate
CED_ENV_FILE=.env.test pytest -q
```

(`pg_ctl -D /tmp/ced-pg stop` afterwards.) The tests use the database named by `CED_ENV_FILE` (or `.env`). Each test makes its own random installation ID and deletes it (and all its rows) at the end, so other data isn't touched. The exception is `tests/test_reset_dev_data.py`, which wipes all user data, so it is skipped unless `DATABASE_URL` points at a local database (localhost or a Unix socket).

## Using it from the app

**By default every build (Debug and Release, Simulator and iPhone) uses the deployed backend on Render**, `https://ctrl-ex-delete-api.onrender.com` (`APIConfig.deployedBaseURL`; voice calls use `wss://` on the same host). Nothing needs setting up on a new Mac, and it works on any network, including cellular. Neon's `DATABASE_URL` and the API keys are only in Render's environment variables, never in the app. See [Deploying to Render](#deploying-to-render).

### Signing with your own Apple team (physical iPhone)

The team and bundle ID live in `CtrlExDelete/Config/Signing.xcconfig` (shared defaults, used by Debug and Release), not in `project.pbxproj`. To run on your own iPhone, put yours in your gitignored `CtrlExDelete/Config/DeveloperSettings.xcconfig` (copy the example file first), which wins over the defaults:
```
DEVELOPMENT_TEAM = YOURTEAMID
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.CtrlExDelete
```
Don't pick a team in Xcode's **Signing & Capabilities** tab: that writes it into `project.pbxproj` (a tracked file) and overrides these settings.

### Local development (optional, Debug only)

To make the app use the server on your Mac instead:

1. Once per Mac: copy `CtrlExDelete/Config/DeveloperSettings.example.xcconfig` to `CtrlExDelete/Config/DeveloperSettings.xcconfig` (gitignored, so every developer keeps their own) and uncomment
   ```
   CED_BACKEND = local
   ```
2. **Simulator:** start the server as above. The Simulator reaches it at `http://127.0.0.1:8000`.
3. **Physical iPhone (same Wi-Fi as your Mac):** `127.0.0.1` on a phone means the phone itself, so also set your Mac's local name (**System Settings ▸ General ▸ Sharing ▸ Local hostname**, or `scutil --get LocalHostName` plus `.local`):
   ```
   CED_DEV_SERVER_HOST[sdk=iphoneos*] = Your-Mac-Name.local
   ```
   and start the server with `uvicorn app.main:app --reload --host 0.0.0.0`. Tap **Allow** when iOS asks about devices on your local network.
4. Run from Xcode once after changing the file. The choice is built into the Debug app, so it also applies when the app is opened from the Home Screen. Comment `CED_BACKEND = local` out again (and run once) to go back to Render.

`CED_API_BASE_URL = <host>` in the same file points every Debug launch, Home Screen included, at another deployed backend (it wins over `CED_BACKEND`). A `-CEDAPIBaseURL http://…` launch argument still overrides everything, but only for runs started by Xcode (the shared scheme has it disabled).

A phone reaches a backend on your Mac only while the Mac is awake, the server is running with `--host 0.0.0.0`, and both are on the same network (some guest or campus Wi-Fi blocks devices from reaching each other). Debug builds include a narrow App Transport Security exception (`NSAllowsLocalNetworking`, in `CtrlExDelete/Config/Debug-Info.plist`) that allows plain `http` only to local-network addresses. Release builds don't have it.

## Deploying to Render

The backend runs as one **Render Free** web service, `ctrl-ex-delete-api`, described in `render.yaml` at the repository root (documentation only: the service isn't managed as a Blueprint). Production resources, all in Sangye's accounts:

| | |
|---|---|
| Render | `ctrl-ex-delete-api` (Free, Virginia), branch `main`, Auto-Deploy **off** (Manual Deploy only) |
| Database | Neon project `ctrl-ex-delete`, branch `production`, database `neondb` (PostgreSQL 18, AWS us-east-1) |
| Photos | AWS S3 bucket `ced-photos-prod` (private, us-east-1), IAM user `ced-production` (this bucket only) |
| Ced | Groq (text chat), Gemini Live (voice calls, relayed by the backend) |

Deploying never migrates, seeds or resets anything.

**Settings** (New ▸ Web Service, or New ▸ Blueprint with `render.yaml`):

| Setting | Value |
|---|---|
| Repository | `sangyetenphel/Ctrl-Ex-Delete` |
| Branch | `main` |
| Root Directory | `backend` |
| Runtime / Language | Python 3 |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `uvicorn app.main:app --host 0.0.0.0 --port $PORT --proxy-headers --forwarded-allow-ips "*"` |
| Health Check Path | `/health` |
| Instance Type | **Free** |

**Environment variables** (Environment tab; type the values there, never in a commit):

| Name | Required | What |
|---|---|---|
| `PYTHON_VERSION` | yes | `3.11` (the version the backend is tested with) |
| `DATABASE_URL` | yes | Neon connection string (with `sslmode=require`) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET` | for photos | without them, only the photo endpoints answer 503 |
| `GROQ_API_KEY` | for Ced chat | `GROQ_MODEL` optional (default `openai/gpt-oss-120b`) |
| `GEMINI_API_KEY` | for Ced calls | `GEMINI_VOICE` optional |
| `CED_VOICE_DIAGNOSTICS` | no | `true` turns on the temporary call diagnostics in the logs (off by default) |
| `CED_DAILY_MESSAGE_LIMIT`, `CED_VOICE_MAX_MINUTES`, `CED_VOICE_MAX_CONCURRENT`, `CED_VOICE_CALLS_PER_HOUR` | no | usage limits (defaults in `app/config.py`) |

**Service:** `https://ctrl-ex-delete-api.onrender.com` (Render service `ctrl-ex-delete-api`, Virginia region, Free).

**Checking it:** `https://ctrl-ex-delete-api.onrender.com/health` → `{"status":"ok"}` and `/health/db` → `{"status":"ok","database":"ok"}` (503 if Neon can't be reached).

**Free plan:** the service sleeps after about 15 minutes without requests; the next request wakes it, which can take a minute. The app waits for that on launch ("Waking up the server…") and wakes it when it comes back to the foreground. Auto-Deploy is off: after pushing, deploy with **Manual Deploy ▸ Deploy latest commit** (a rollback is **Rollback** on an earlier deploy).

**Public exposure:** every endpoint is open to anyone with the URL and a made-up installation ID (there are no accounts). The AI endpoints are limited per installation and for the whole server (chat: 8/min and 60/day per installation, 25/min server-wide; calls: one per installation, 3 at once, 30 started per hour, 15 minutes each), so the worst case is using up the free AI quotas, not someone's data.

## Resetting one installation (developer only, e.g. before a demo)

`scripts/reset_installation.py` resets **one** phone's data and nothing else: that installation's check-ins (and their room messages), recommendations, selections, bookmarks, memories, photo records and their S3 files, Moving Forward and Ced usage counts, and the installation row. Progress, the bookshelf and Insights are computed from these, so they reset too (the plant game and Ced conversations store nothing per user on the server). Catalogs and every other installation are never touched. There is deliberately no API endpoint for it.

It only runs against a local database (with no real S3 settings) or the production Neon `neondb` together with its bucket, recognised by SHA-256 fingerprints in the script; any other database, such as the original one, is refused before anything is read. A dry run is the default.

**One command** (from the repository root; it uses `backend/venv` and `backend/.env.production` by itself):

```bash
./ced-reset <installation-id>             # summary → paste the ID again → RESET PRODUCTION → reset → verified
./ced-reset <installation-id> --dry-run   # summary only
./ced-reset                               # asks you to paste the ID
```

It is a thin wrapper around the script below (same guards and confirmations). The same steps by hand, from `backend/` with the venv active: `SSL_CERT_FILE=$(python -m certifi) CED_ENV_FILE=.env.production python -m scripts.reset_installation <installation-id> [--execute --production]`. Without `CED_ENV_FILE` the script uses `.env` (a local database works the same way, without `--production`). The installation row is locked, its photo files are deleted from S3, then its rows are deleted in the same transaction and checked; if S3 fails nothing in the database changes, and if the database step fails it is rolled back. Either way it says what is left: run the same command again to finish. Output is counts only (no memory text, keys or links). Exit codes: 0 done or dry run, 1 cancelled, 2 not found, 3 not finished (retry), 4 refused.

**Finding the phone's installation ID:** run the Debug app from Xcode; its console logs `Installation ID: …` the first time the app contacts the server (Debug builds only; private in other logs). The ID may be upper-case; either case works.

**The phone afterwards: nothing to do.** It keeps its installation ID (Keychain) and, the next time it opens (Home Screen is fine), `GET /check-ins/today` reports that the installation's server record is gone or new (`installation` in docs/api.md). The app then forgets its on-phone copies of the old journey (`journey-cache.json`, `room-message.json`, the bookshelf's "books shown" counter) and shows a fresh day 1. It decides only from a successful response that has the field: a failed request, an empty journey or an older backend clears nothing. Photos, the scrapbook PDF, the affirmations cache and other settings are kept. This needs the backend and app from 2026-11-04 or later. A manual fallback remains for Debug builds: the Xcode launch argument `-CEDClearLocalJourneyCache YES` (once per value; untick after use). The Keychain ID survives deleting the app, so reinstalling does **not** give a new ID; to demo as a brand-new installation without resetting, use a different phone or simulator. Mac-side tests: `cd CtrlExDelete && ./DevTests/run.sh`.

## Clearing test data

To start the app fresh while keeping the catalog. **This deletes all user data** in the database from `.env`: installations, check-ins, recommendations, selections, bookmarks, memories, photo records and `ced_usage`. It also deletes the app's photo uploads in S3 (keys matching `scrapbook/<32 hex>.jpg` or `installations/<id>/<id>.jpg`, including orphans, and old versions if the AWS user may list them). Everything else in the bucket, the catalog, research sources, schema and migration history stay.

```bash
python -m scripts.reset_dev_data                  # asks you to type RESET DATA
python -m scripts.reset_dev_data --database-only  # if the AWS user can't delete objects
```

S3 files are deleted first and database rows last, only if every S3 deletion worked, so a failed run can be repeated. With `--database-only` the S3 files stay and are listed; a later full run removes them as orphans. Nothing else (server startup, `migrate`, `seed_catalog`) deletes user data. The app copes: its saved installation ID simply starts over with no history.

## Resetting the development database

Only if the tables are broken. **This deletes all CED data** in the database from `.env`:

```bash
python -m scripts.reset_dev_db   # asks you to type RESET
python -m scripts.migrate
```

It only drops this project's tables: `activity_research_bases`, `research_bases`, `activity_bookmarks`, `reflections`, `scrapbook_photos`, `activity_selections`, `recommendations`, `check_ins`, `activities`, `activity_categories`, `installations`, `schema_migrations`. Other tables (for example a teammate's `ced_usage`) are left alone. Apart from `reset_dev_data` and `reset_installation` above, it's the only command that deletes user data; `migrate` and `seed_catalog` never do.

## Troubleshooting

| Problem | Fix |
|---|---|
| `command not found: uvicorn` or `No module named fastapi` | The venv isn't active. Run `source venv/bin/activate` from `backend/`. |
| `No module named 'app'` | You're in the wrong folder. Run commands from inside `backend/`. |
| `database_url Field required` | `backend/.env` is missing or has no `DATABASE_URL` line. See "Add the database connection string". |
| API returns `503` "The database is unavailable" | The server can't reach Neon. Check your internet connection and the string in `.env`. |
| `Address already in use` | The server is already running in another Terminal tab. Stop that one with Ctrl + C. |
| `migrate` says the database has the old schema history | It's the original database (kept as a backup). Use a new, empty database instead. |
| `422` response | The request doesn't match `docs/api.md`. The `loc` field in the error shows which field is wrong. |
| App says "Couldn't reach the server" | The backend isn't running, or (on a phone) the base URL / `--host 0.0.0.0` step was missed. |
| New packages were added by a teammate | Pull, activate the venv, then run `pip install -r requirements-dev.txt` again. |


## Checking AWS S3

After adding `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` and `S3_BUCKET` to `.env`:

```
python -m scripts.check_s3
```

It uploads one test object under `scrapbook/_check-s3-…`, reads it back through a presigned URL, confirms an unsigned request is refused (the object is private), checks the bucket's public-access block, and deletes that one object. No secrets are printed.
