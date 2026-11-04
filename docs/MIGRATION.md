# Setting up your own Neon and S3 (fresh start)

CED moves to a new Neon project and new S3 buckets in your own accounts,
starting **without** the old user data (your decision, 2026-11-04). The
original Neon database and S3 bucket in Leo's accounts stay untouched as the
backup; nothing here reads from or writes to them.

The schema is `backend/db/migrations/001_schema.sql` (see
`docs/DATABASE_DESIGN.md`); the shared catalogs come from the seed scripts.

## Where it stands

| Step | Status |
|---|---|
| New Neon project in your account: PostgreSQL 18.6, AWS us-east-1, empty `neondb` | done |
| Clean schema, seeds and `verify_database`, tested from scratch on empty local databases | done |
| `staging` database in the Neon project, schema initialized | **next** (below) |
| S3 buckets and IAM users (staging and production) | **needs you** (below) |
| Render staging service | after the above |
| Production cutover | **needs your approval** |

## How settings are chosen

Every command reads `backend/.env`, unless `CED_ENV_FILE` names another file.
Keep one git-ignored file per environment, so a command can never mix them up:

| File | Database | Bucket |
|---|---|---|
| `backend/.env` | the original database (backup) | the original bucket |
| `backend/.env.staging` | Neon `staging` | the staging bucket |
| `backend/.env.production` | Neon `neondb` | the production bucket |

```bash
# backend/.env.staging (same layout for .env.production)
DATABASE_URL=postgresql://...-pooler.us-east-1.aws.neon.tech/staging?sslmode=require&channel_binding=require
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
S3_BUCKET=ced-photos-staging-...
GROQ_API_KEY=...
GROQ_MODEL=openai/gpt-oss-120b
GEMINI_API_KEY=...
```

Paste values only into these files: never into chat, commits or docs.

## 1. Neon

The project exists. For staging:

1. In the Neon console, **Postgres database → Databases → Add database**,
   name `staging`, the default owner.
2. **Connect** → database `staging`, **Connection pooling** on → copy the
   string into `DATABASE_URL` in `backend/.env.staging`. Production later uses
   database `neondb` the same way, in `backend/.env.production`.
3. From `backend/` with the venv active:

   ```bash
   CED_ENV_FILE=.env.staging python -m scripts.migrate                 # schema, then the catalogs
   CED_ENV_FILE=.env.staging python -m scripts.verify_database --fresh # schema, catalogs, empty user tables
   ```

   `migrate` prints which settings file and database it uses. It refuses a
   database that has the old migration history.

## 2. AWS S3

Two buckets and two IAM users, so staging can never touch production photos.

1. **Buckets** (S3 → Create bucket), one per environment, for example
   `ced-photos-staging-<suffix>` and `ced-photos-prod-<suffix>`:
   - Region **us-east-1** (next to Render and the new Neon).
   - **Block all public access**: on. **Object Ownership**: ACLs disabled
     (bucket owner enforced). **Default encryption**: SSE-S3. **Versioning**:
     off (a deleted photo is really gone).
   - No CORS rule, no bucket policy: the app uploads and downloads through
     short-lived presigned links from the backend.
2. **IAM users** (IAM → Users → Create user), for example `ced-staging` and
   `ced-production`, no console access, each with this inline policy for its
   own bucket:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       { "Effect": "Allow",
         "Action": ["s3:ListBucket", "s3:GetBucketPublicAccessBlock"],
         "Resource": "arn:aws:s3:::YOUR-BUCKET" },
       { "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::YOUR-BUCKET/*" }
     ]
   }
   ```

   `ListBucket` lets the backend tell a missing photo (404) from a refused one
   (403); `GetBucketPublicAccessBlock` lets `check_s3` confirm the bucket is
   private.
3. **Access keys**: each user → Security credentials → Create access key
   ("Application running outside AWS") → into that environment's file.
4. Check:

   ```bash
   CED_ENV_FILE=.env.staging python -m scripts.check_s3   # one test object, then deleted
   ```

## 3. Try the backend locally against staging

```bash
CED_ENV_FILE=.env.staging uvicorn app.main:app --port 8001
```

Then run the app in the Simulator from Xcode with the launch argument
`-CEDAPIBaseURL http://127.0.0.1:8001` and try a check-in, an activity, a
reflection with a photo, Story, Insights, the scrapbook and Ced. (For a phone,
add `--host 0.0.0.0` and use your Mac's address.)

## 4. Render staging (dashboard only)

A second Free web service, so the live one is never touched:

- **New → Web Service**, this repository, branch `refactor/final-optimization`,
  root directory `backend`, build `pip install -r requirements.txt`, start
  `uvicorn app.main:app --host 0.0.0.0 --port $PORT --proxy-headers --forwarded-allow-ips "*"`,
  health check `/health`, **Auto-Deploy: off**.
- **Environment**: `PYTHON_VERSION=3.11` and the values from
  `backend/.env.staging` (Render's "Add from .env" accepts the file's
  contents). Leave `CED_VOICE_DIAGNOSTICS` unset (off).
- Don't add it to `render.yaml`: that file describes the live service.

## 5. Production cutover (needs your approval)

1. `CED_ENV_FILE=.env.production python -m scripts.migrate`, then
   `verify_database --fresh` (database `neondb`, production bucket).
2. Merge `refactor/final-optimization` into `integration/ai-room-progress`.
3. In the live Render service's **Environment**, replace `DATABASE_URL`,
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET` (and
   the AI keys if you made new ones) with the production values, then
   **Save, rebuild, and deploy**.
4. Check `/health/db`, then the app end to end. Users start fresh.

The new backend code expects the new schema: deploy it only together with the
new database. **Rollback:** restore the old values in Render and redeploy the
previous commit (`integration/ai-room-progress` before the merge); the
original database and bucket are untouched.

## 6. Clean-up afterwards

- Delete the `rehearsal` database in the new Neon project (it holds a copy of
  old user data from the migration rehearsal).
- Delete `backend/.env.migration` and the dumps in `.local-backup/` once the
  new setup is live.
- After grading, ask Leo to delete the original database and bucket and to
  revoke the old access key. Rotate the keys that were pasted into chat.

The copy tooling from the earlier plan (`scripts.copy_database`,
`compare_databases`, `copy_s3`) stays in the repo, unused for the fresh start.
