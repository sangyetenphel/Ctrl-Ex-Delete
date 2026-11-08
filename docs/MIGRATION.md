# Setting up your own Neon and S3 (fresh start)

> **Completed (2026-11-04 to 2026-11-08).** Production now runs on Sangye's
> own Neon (`ctrl-ex-delete` / `production` / `neondb`), S3 (`ced-photos-prod`,
> IAM user `ced-production`) and the Render service `ctrl-ex-delete-api`; the
> test service, the `rehearsal` database and the migration backups are gone.
> The current setup is in `docs/RENDER_DEPLOYMENT_HANDOFF.md`. This guide stays
> as the recipe for building a fresh environment from scratch.

CED moved to a new Neon project and a new S3 bucket in Sangye's own accounts,
starting **without** the old user data (decision, 2026-11-04). The original
infrastructure in Leo's accounts is no longer used; nothing here reads from or
writes to it.

The schema is `backend/db/migrations/001_schema.sql` (see
`docs/DATABASE_DESIGN.md`); the shared catalogs come from the seed scripts.

## Where it stands

| Step | Status |
|---|---|
| New Neon project in your account: PostgreSQL 18.6, AWS us-east-1, empty `neondb` | done |
| Clean schema, seeds and `verify_database`, tested from scratch on empty local databases | done |
| Production database `neondb`: schema and catalogs initialized, `verify_database --fresh` passed | done (2026-11-04) |
| Production bucket and `ced-production` IAM user: us-east-1, Block Public Access on, key limited to the bucket; `check_s3` and the phone's presigned upload/download verified | done (2026-11-04) |
| Render service on the new setup (tested on a temporary `ced-backend-test`, since deleted) | done (2026-11-04) |
| Staging database and bucket of their own | not made (optional, sections 1 and 2) |
| Production cutover of `ctrl-ex-delete-api` | done (2026-11-04) |
| Clean-up (`rehearsal`, test service, local backups, old settings files) | done (2026-11-08) |

## How settings are chosen

Every command reads `backend/.env` (local development), unless `CED_ENV_FILE` names another file.
Keep one git-ignored file per environment, so a command can never mix them up:

| File | Database | Bucket |
|---|---|---|
| `backend/.env` | a local development database (optional) | none |
| `backend/.env.staging` | Neon `staging` (not made) | a staging bucket |
| `backend/.env.production` | Neon `neondb` | `ced-photos-prod` |

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

   On a Mac with Python from python.org, `CERTIFICATE_VERIFY_FAILED` means that
   Python has no root certificates yet: run its "Install Certificates.command",
   or prefix the command with `SSL_CERT_FILE=$(python -m certifi)`.

## 3–6. Local trial, test service, cutover, clean-up (done)

What was done, for the record (details in `docs/INFRASTRUCTURE_CONSOLIDATION_PLAN.md`):

- The optimized backend ran first on a temporary Render service
  (`ced-backend-test`, Auto-Deploy off) against the new database and bucket,
  and was tested from the iPhone.
- Cutover (2026-11-04): on `ctrl-ex-delete-api`, Auto-Deploy off, branch
  switched to `refactor/final-optimization` (no merge), the five database/AWS
  variables replaced, then one "Save, rebuild, and deploy" so code and settings
  changed together (the new code needs the new schema). Users started fresh.
- Clean-up (2026-11-08): `ced-backend-test` deleted, the `rehearsal` database
  deleted, `backend/.env` (the original infrastructure's settings) and
  `backend/.env.migration` removed, old local backups removed.

For a future environment of the same kind, repeat sections 1–2, then create a
Render web service with the settings in `backend/README.md` ("Deploying to
Render").

The copy tooling from the earlier plan (`scripts.copy_database`,
`compare_databases`, `copy_s3`) stays in the repo, unused for the fresh start;
it reads its source from the settings file named by `CED_ENV_FILE`.
