# CED backend

The FastAPI service behind Ctrl + Ex + Delete: check-ins, activity recommendations, memories and photos, Insights, and Ced (text chat and voice, relayed to Groq and Gemini Live). Data lives in PostgreSQL and photos in a private S3 bucket.

- How the pieces fit together: [`docs/architecture.md`](../docs/architecture.md)
- The API contract: [`docs/api.md`](../docs/api.md)
- The schema and photo storage: [`docs/DATABASE_DESIGN.md`](../docs/DATABASE_DESIGN.md)

```
backend/
├── app/         FastAPI app: routes/, storage.py (all SQL), media.py (all S3), the rule modules, ced/
├── db/          migrations/001_schema.sql, plus legacy/ (the earlier history, reference only)
├── scripts/     migrate, catalog seeds and data, verify_database, check_s3, developer tools
├── tests/       pytest suite
└── .env.example every setting, with placeholders
```

## Requirements

- Python 3.11 or later
- PostgreSQL running locally (for development and tests)
- Optional: an S3 bucket for photos, and Groq and Gemini API keys for Ced

## Local setup

```bash
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements-dev.txt
createdb ced_dev
cp .env.example .env              # set DATABASE_URL=postgresql://localhost/ced_dev
python -m scripts.migrate         # schema and catalogs (see Database)
uvicorn app.main:app --reload
```

The server runs at `http://127.0.0.1:8000`: `/health` answers `{"status":"ok"}` and `/docs` lets you try the endpoints (most need an `X-Installation-ID` header; `uuidgen` makes one). Restart the server after changing settings, because `--reload` does not re-read them.

## Settings

Settings come from `backend/.env`, or from the file named by `CED_ENV_FILE` (for example `CED_ENV_FILE=.env.test`), and the server and every script read them the same way. Without a settings file a command stops with `database_url Field required`; nothing falls back to another environment. Every `.env*` file except `.env.example` is git-ignored: keep one file per environment and never commit or paste values.

| Variable | Needed for | Placeholder |
|---|---|---|
| `DATABASE_URL` | everything | `postgresql://localhost/ced_dev` |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET` | photos (without them only the photo endpoints answer 503) | `<key-id>`, `<secret>`, `us-east-1`, `<bucket>` |
| `S3_ENDPOINT_URL` | a local S3-compatible server such as MinIO | `http://127.0.0.1:9000` |
| `GROQ_API_KEY` | Ced text chat (without it the chat answers 503) | `<key>` |
| `GEMINI_API_KEY` | Ced voice calls (without it calls are unavailable) | `<key>` |
| `AI_MODEL`, `GEMINI_LIVE_MODEL`, `GEMINI_VOICE`, `CED_*` limits and diagnostics | optional tuning | defaults in `app/config.py` |

The iOS app never holds a database, storage or AI key; only the backend does.

## Database

```bash
python -m scripts.migrate              # apply new migrations, then load the catalogs
python -m scripts.migrate --status     # list applied migrations (changes nothing)
python -m scripts.verify_database      # check the schema and catalogs; add --fresh on a new database
```

- `migrate` runs each unapplied file in `db/migrations/` once, in order, and records it in `schema_migrations`. It is safe to run again. `--no-seed` skips the catalogs.
- The catalogs (100 activities, the affirmations, Ced's room messages) come from `scripts/catalog_data.py`, `affirmation_data.py` and `room_message_data.py`. Edit one and run `python -m scripts.seed_catalog` (or `seed_affirmations`, `seed_room_messages`); a load updates rows by stable id and retires, never deletes, an activity that users have history with.
- To change the schema, add a new numbered file (`002_*.sql`). Never edit a migration that has already been applied.
- `db/migrations/legacy/` holds the earlier history for reference. `migrate` refuses a database that has it.

## Running the tests

Some tests change shared catalogs or delete rows, so run them only against an isolated local database, never one that holds real data. A throwaway PostgreSQL on its own port needs no password:

```bash
initdb -D /tmp/ced-pg -A trust -U ced_test
LC_ALL=en_US.UTF-8 pg_ctl -D /tmp/ced-pg -o "-p 55432 -c unix_socket_directories='' -c listen_addresses=localhost" -l /tmp/ced-pg.log start
createdb -h localhost -p 55432 -U ced_test ced_test
echo 'DATABASE_URL=postgresql://ced_test@localhost:55432/ced_test' > .env.test
CED_ENV_FILE=.env.test python -m scripts.migrate
CED_ENV_FILE=.env.test pytest -q
pg_ctl -D /tmp/ced-pg stop            # when you are done
```

The tests use the database named by `CED_ENV_FILE`. Each test creates a random installation and removes its rows afterwards; the AI providers and S3 are faked, so no network or keys are needed. Tests that reset data skip themselves unless the database is local. Never point `CED_ENV_FILE` at a deployed environment.

## Using the local backend from the app

By default the app uses the deployed backend (`APIConfig.deployedBaseURL`). To use yours, copy `CtrlExDelete/Config/DeveloperSettings.example.xcconfig` to `DeveloperSettings.xcconfig` (git-ignored), add `CED_BACKEND = local`, and run the app once from Xcode. The Simulator reaches `http://127.0.0.1:8000`. A physical iPhone on the same Wi-Fi also needs `CED_DEV_SERVER_HOST[sdk=iphoneos*] = <your-mac>.local` in that file and the server started with `--host 0.0.0.0`; Debug builds allow plain `http` to local-network addresses only.

## Photos and deployment

- `python -m scripts.check_s3` checks the bucket named by your settings: it uploads one small test object, reads it back through a signed link, confirms an unsigned request is refused, then deletes that object. Bucket setup is in [`docs/DATABASE_DESIGN.md`](../docs/DATABASE_DESIGN.md).
- The hosted service is one Render web service built from `backend/`. `render.yaml` records its settings and the environment variable names; [`docs/architecture.md`](../docs/architecture.md) describes the deployment. Deploying never migrates or seeds a database.

## Developer scripts

`seed_*`, `export_affirmations` (rewrites the app's bundled affirmation file) and `verify_database` are safe to rerun. The `reset_*` scripts delete data and are for local development databases; each states its confirmation steps in its module docstring.
