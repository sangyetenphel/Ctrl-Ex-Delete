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
├── db/migrations/               # numbered .sql files that build the database
├── scripts/
│   ├── migrate.py               # applies new migrations, then loads the catalog
│   ├── catalog_data.py          # the 100-activity catalog and research sources
│   ├── seed_catalog.py          # loads the catalog (never deletes user history)
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

### Add the database connection string

Secrets go in `backend/.env`, which is **never committed** (it's in `.gitignore`):

```bash
cp .env.example .env
open -e .env
```

Replace the example line with the real Neon connection string. In the Neon console: your project ▸ **Connect** ▸ copy the connection string (it starts with `postgresql://` and ends with `?sslmode=require`). Save the file.

- Never paste this string into Swift code, Slack, screenshots or commits.
- The iOS app never talks to Neon. Only this backend does.

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
| `001_baseline.sql` | `installations`, `check_ins`, `activities`, `activity_logs` (Alexa's original schema; skipped if the tables already exist) |
| `002_recommendations.sql` | Adds card fields to `activities`; creates `recommendations` and `activity_selections` |
| `003_seed_activities.sql` | Adds the three prototype activities to the catalog |
| `009_neutral_why_it_fits.sql` | Rewords one activity's "why it fits" text so it doesn't assume an answer |
| `010_single_reflection_note.sql` | One reflection text answer: moves `noticed` into `note`, drops `noticed` |
| `011_category_labels.sql` | `activity_categories` defines each category's display name; `category_label` is kept in step by the database |
| `012_activity_energy_and_research.sql` | Adds `energy_level`, `involves_movement`, `evidence_note`, and the `research_bases` / `activity_research_bases` tables. The catalog itself comes from `scripts/seed_catalog.py` |
| `013_remove_legacy_activities.sql` | Deletes the 21 earlier activities the new catalog replaced, or retires the ones that have user history (the other 28 earlier activities are part of the catalog) |
| `014_one_check_in_per_day.sql` | One check-in per installation per local day: a unique index on `(installation_id, local_date)`. Nothing is deleted: same-day duplicates from before keep their rows, and only the latest of them counts for the day (`counts_for_day`) |
| `015_moving_forward.sql` | `moving_forward_check_ins`: one moving-forward reflection per installation (ticked questions, optional note, the day it was chosen). Nothing else changes |
| `016_moving_forward_readiness_only.sql` | Drops the moving-forward `note` column: the check-in is now the five readiness questions only, and the API requires all five |
| `017_affirmations.sql` | The Grow with Kindness catalog: `affirmation_themes`, `affirmations` (stable id, text, theme, language, active, timestamps), `affirmation_sources`, `affirmation_theme_sources` (principle and rationale per source) and `affirmation_notes` (editorial, never shown). Filled by `scripts/seed_affirmations.py`, which `migrate` runs; it never deletes, only retires. After changing `scripts/affirmation_data.py`, also run `python -m scripts.export_affirmations` to update the app's bundled copy |

To change the database later, **add a new numbered file** (e.g. `004_add_something.sql`). Don't edit a migration that has already been applied.

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

```bash
pytest
```

The tests use the database in `.env`. Each test makes its own random installation ID and deletes it (and all its rows) at the end, so other data isn't touched. The exception is `tests/test_reset_dev_data.py`, which wipes all user data, so it is skipped unless `DATABASE_URL` points at a local database (localhost or a Unix socket).

## Using it from the app

### iOS Simulator

Start the server as above, then run the app from Xcode. Debug builds in the Simulator call `http://127.0.0.1:8000` (`CtrlExDelete/Config/Debug.xcconfig`). The Simulator shares your Mac's network, so nothing else is needed.

### Physical iPhone (same Wi-Fi as your Mac)

`127.0.0.1` on a phone means the phone itself, so:

1. Start the server so other devices can reach it:
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0
   ```
2. Find your Mac's local name: **System Settings ▸ General ▸ Sharing**, under "Local hostname" (e.g. `Your-Mac-Name.local`), or run `scutil --get LocalHostName` and add `.local`.
3. Once per Mac: copy `CtrlExDelete/Config/DeveloperSettings.example.xcconfig` to `CtrlExDelete/Config/DeveloperSettings.xcconfig` (gitignored, so every developer keeps their own) and set
   ```
   CED_DEV_SERVER_HOST[sdk=iphoneos*] = Your-Mac-Name.local
   ```
   The address is built into the Debug app, so it keeps working when the app is opened from the Home Screen or after a force-close, not only when Xcode starts it. (A `-CEDAPIBaseURL` launch argument only applies to runs started by Xcode; it still works for one-off tests.)
4. Run on the phone from Xcode once after changing it, and tap **Allow** when iOS asks about devices on your local network.

A phone reaches a backend on your Mac only while the Mac is awake, the server is running with `--host 0.0.0.0`, and both are on the same network (some guest or campus Wi-Fi blocks devices from reaching each other). If not, the app shows "We can't reach Ctrl+Ex+Delete right now" with Try again; nothing is reset.

Debug builds include a narrow App Transport Security exception (`NSAllowsLocalNetworking`, in `CtrlExDelete/Config/Debug-Info.plist`) that allows plain `http` only to local-network addresses. Release builds don't have it.

### Deployed backend (later)

When the API is hosted somewhere, it must use `https://`. Put its URL in `APIConfig.releaseBaseURL`. Neon's `DATABASE_URL` goes in the host's environment variables, never in the app.

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

It only drops this project's tables: `activity_research_bases`, `research_bases`, `activity_bookmarks`, `reflections`, `scrapbook_photos`, `activity_selections`, `recommendations`, `check_ins`, `activities`, `activity_categories`, `installations`, `schema_migrations`. Other tables (for example a teammate's `ced_usage`) are left alone. Apart from `reset_dev_data` above, it's the only command that deletes user data; `migrate` and `seed_catalog` never do.

## Troubleshooting

| Problem | Fix |
|---|---|
| `command not found: uvicorn` or `No module named fastapi` | The venv isn't active. Run `source venv/bin/activate` from `backend/`. |
| `No module named 'app'` | You're in the wrong folder. Run commands from inside `backend/`. |
| `database_url Field required` | `backend/.env` is missing or has no `DATABASE_URL` line. See "Add the database connection string". |
| API returns `503` "The database is unavailable" | The server can't reach Neon. Check your internet connection and the string in `.env`. |
| `Address already in use` | The server is already running in another Terminal tab. Stop that one with Ctrl + C. |
| Migration 003 fails on `SET NOT NULL` | The `activities` table has old rows without a `slug`. Delete them, or reset the dev database. |
| `422` response | The request doesn't match `docs/api.md`. The `loc` field in the error shows which field is wrong. |
| App says "Couldn't reach the server" | The backend isn't running, or (on a phone) the base URL / `--host 0.0.0.0` step was missed. |
| New packages were added by a teammate | Pull, activate the venv, then run `pip install -r requirements-dev.txt` again. |


## Checking AWS S3

After adding `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` and `S3_BUCKET` to `.env`:

```
python -m scripts.check_s3
```

It uploads one test object under `scrapbook/_check-s3-…`, reads it back through a presigned URL, confirms an unsigned request is refused (the object is private), checks the bucket's public-access block, and deletes that one object. No secrets are printed.
