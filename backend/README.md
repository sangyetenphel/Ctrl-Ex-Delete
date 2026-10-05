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
│   ├── migrate.py               # applies new migrations
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

This applies any files in `db/migrations/` that haven't run yet and records them in a `schema_migrations` table. It's safe to run again: it only applies new files. Check what's applied with `python -m scripts.migrate --status`.

| Migration | What it does |
|---|---|
| `001_baseline.sql` | `installations`, `check_ins`, `activities`, `activity_logs` (Alexa's original schema; skipped if the tables already exist) |
| `002_recommendations.sql` | Adds card fields to `activities`; creates `recommendations` and `activity_selections` |
| `003_seed_activities.sql` | Adds the three prototype activities to the catalog |

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

The tests use the database in `.env`. Each test makes its own random installation ID and deletes it (and all its rows) at the end, so other data isn't touched.

## Using it from the app

### iOS Simulator

Start the server as above, then run the app from Xcode. Debug builds call `http://127.0.0.1:8000` (set in `CtrlExDelete/CtrlExDelete/Networking/APIConfig.swift`). The Simulator shares your Mac's network, so nothing else is needed.

### Physical iPhone (same Wi-Fi as your Mac)

`127.0.0.1` on a phone means the phone itself, so:

1. Start the server so other devices can reach it:
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0
   ```
2. Find your Mac's local name: **System Settings ▸ General ▸ Sharing**, under "Local hostname" (e.g. `Your-Mac-Name.local`).
3. In Xcode: **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸ Arguments Passed On Launch**, add:
   ```
   -CEDAPIBaseURL http://Your-Mac-Name.local:8000
   ```
4. Run on the phone and tap **Allow** when iOS asks about devices on your local network.

Debug builds include a narrow App Transport Security exception (`NSAllowsLocalNetworking`, in `CtrlExDelete/Config/Debug-Info.plist`) that allows plain `http` only to local-network addresses. Release builds don't have it.

### Deployed backend (later)

When the API is hosted somewhere, it must use `https://`. Put its URL in `APIConfig.releaseBaseURL`. Neon's `DATABASE_URL` goes in the host's environment variables, never in the app.

## Resetting the development database

Only if the tables are broken or you want to start clean. **This deletes all CED data** in the database from `.env`:

```bash
python -m scripts.reset_dev_db   # asks you to type RESET
python -m scripts.migrate
```

It only drops this project's tables: `activity_selections`, `recommendations`, `activity_logs`, `check_ins`, `activities`, `installations`, `schema_migrations`.

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
