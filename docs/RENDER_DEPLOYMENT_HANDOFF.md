# Handoff: CED production setup (final, 2026-11-08)

For a fresh Claude Code session. Read `CLAUDE.md` first, then this file.
No credentials or user data appear here; settings are named, never shown.
The full record of how we got here: `docs/INFRASTRUCTURE_CONSOLIDATION_PLAN.md`.

## 1. Production (all in Sangye's accounts)

| | |
|---|---|
| Backend | Render web service **`ctrl-ex-delete-api`**, `https://ctrl-ex-delete-api.onrender.com` (Free, Virginia). Built into the app (`APIConfig.deployedBaseURL`) |
| Code | branch **`main`** (production since 2026-11-09; release tag `ced-demo-v1`), root `backend/`. Auto-Deploy **off**: deploy with Manual Deploy ▸ Deploy latest commit (or a specific commit). Pushing to `main` never deploys by itself |
| Database | Neon project `ctrl-ex-delete`, branch **`production`**, database **`neondb`** (PostgreSQL 18, AWS us-east-1); `postgres` is Neon's built-in database |
| Photos | AWS S3 bucket **`ced-photos-prod`** (private, us-east-1, Block Public Access on, SSE-S3), IAM user **`ced-production`** (that bucket only, one active key) |
| Ced | **Groq** for text chat (`openai/gpt-oss-120b`), **Gemini Live** for voice calls (relayed by the backend, voice `Aoede`) |
| Backup | one manual Neon snapshot of `production` (2026-11-04, never expires) |

Render environment variables (names only): `DATABASE_URL`, `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET`, `GROQ_API_KEY`,
`GROQ_MODEL`, `GEMINI_API_KEY`, `GEMINI_VOICE`, `PYTHON_VERSION`. The same
values are in the git-ignored `backend/.env.production` on Sangye's Mac.
`render.yaml` documents the service but isn't a connected Blueprint.

## 2. Everyday commands

From `backend/` with the venv active (see `backend/README.md` for setup):

```bash
CED_ENV_FILE=.env.production python -m scripts.migrate --status
CED_ENV_FILE=.env.production python -m scripts.verify_database
SSL_CERT_FILE=$(python -m certifi) CED_ENV_FILE=.env.production python -m scripts.check_s3
```

Reset ONE installation for a demo (repository root): `./ced-reset <installation-id>`;
the phone notices on its next launch and shows a fresh day 1 (backend/README.md,
"Resetting one installation"). Tests run only against a local database
(backend/README.md, "Running the tests"); never with `.env.production`.

Checking production: `/health` → `{"status":"ok"}`, `/health/db` →
`{"status":"ok","database":"ok"}`.

## 3. Rules

Without Sangye's explicit approval, never: merge any branch, change the
production service (settings, branch, environment, deploys), create anything
billable, delete Neon data or the snapshot, or change AWS. Claude doesn't type
passwords or API keys into Render; Sangye enters secret values, Claude checks
names (or fingerprints) only. The original infrastructure (Leo's Neon database
and S3 bucket) is no longer used and is out of bounds: never read or change it.

## 4. Rollback

Render ▸ `ctrl-ex-delete-api` ▸ Deploys ▸ **Rollback** to an earlier deploy of
the optimized code (`7131e87` or later). The CED demo release is `ed07318`
(`ced-demo-v1` adds only a catalog seed-data fix); the previous release was
`ad2fca6`, and the current app works with both. Never roll back to `de1df9a`
or older: that code doesn't match the new schema. The database can be restored from the
Neon snapshot (Backup & Restore; one-step keeps the connection string).

## 5. Open items (not infrastructure)

- Gemini: if the key is on the free tier, Google may use call audio and
  transcripts to improve its products. Move the Gemini project to a paid tier
  with logging off before real use; its terms also require users 18+.
- Groq may keep requests up to 30 days for abuse checks: consider Zero Data
  Retention in the Groq console.
- The app doesn't yet tell users that messages go to Groq and Google.
- Keys pasted into chat earlier in development should be rotated (Groq, Gemini).
- `Config/Debug-Info.plist` still has an ATS exception for an old campus IP.
- The Neon snapshot predates the fresh start's cleanup and still contains a
  copy of the old `rehearsal` database; delete it only when Sangye decides.
- `main` is the production branch (fast-forwarded to the CED release on
  2026-11-09). `refactor/final-optimization` and `feature/ced-ai-improvements`
  point at the same commit and are kept until the team decides to remove them.
