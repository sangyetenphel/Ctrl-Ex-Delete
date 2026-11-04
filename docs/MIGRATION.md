# Moving the database and photo storage to new accounts

The Neon database and the S3 bucket were created in Leo's accounts. This is
how to move both to accounts you own without losing data or downtime that
matters. The old database and bucket are only ever read: nothing here
deletes, resets or changes them.

## Where it stands

| Step | Status |
|---|---|
| Inventory: Neon PostgreSQL 18.6, 21 tables, 9.7 MB; S3 (us-east-2) 14 objects, 7.4 MiB | done (2026-11-04) |
| Backups: `pg_dump` of Neon and a copy of every S3 object, in `.local-backup/2026-11-04/` (git-ignored, user data) | done, every object passed its size and MD5 check |
| Rehearsal: `scripts.copy_database` into an empty local PostgreSQL, then `scripts.compare_databases` | done: all 21 tables, row checksums, constraints, indexes, sequences and migrations match |
| New Neon project and S3 bucket in your accounts | **needs you** (below) |
| Copy into them and verify | ready to run |
| Render cutover | **needs your approval** |

## 1. What to create

Put every value in `backend/.env.migration` (git-ignored by the `.env.*`
rule). Don't paste them into chat or commit them.

```bash
# backend/.env.migration
TARGET_DATABASE_URL=postgresql://...neon.tech/neondb?sslmode=require
TARGET_AWS_ACCESS_KEY_ID=...
TARGET_AWS_SECRET_ACCESS_KEY=...
TARGET_AWS_REGION=us-east-1
TARGET_S3_BUCKET=...
```

### Neon

1. Sign in at console.neon.tech with your own account and create a project:
   **PostgreSQL 18** (the same major version as today) and region **AWS US
   East (N. Virginia)**, next to the Render service (Virginia). Today's
   database is in Ohio, so every query also crosses regions.
2. On the project dashboard, open **Connect**, keep **Connection pooling**
   on, copy the connection string (it ends in `?sslmode=require`) into
   `TARGET_DATABASE_URL`.
3. Leave the database empty. `copy_database` refuses a database that already
   has tables, so nothing can be overwritten by mistake.

### AWS S3

1. In your AWS account, create a bucket in **us-east-1** (or keep
   **us-east-2**; photos download straight to the phone, so either is fine).
   Keep the defaults: **Block all public access** on, ACLs disabled, SSE-S3
   encryption. No CORS rule is needed: the app uploads with presigned URLs
   from iOS, not from a browser.
2. In IAM, create a user (for example `ced-backend`) with no console access
   and this inline policy, using your bucket name:

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

   `ListBucket` lets the backend tell a missing photo (404) from a refused
   one (403). Nothing in the app needs more.
3. Create an access key for that user ("Application running outside AWS")
   and put it in `TARGET_AWS_ACCESS_KEY_ID` / `TARGET_AWS_SECRET_ACCESS_KEY`.

## 2. Rehearse, then copy

From `backend/` with the venv active:

```bash
set -a; source .env.migration; set +a
export PG_BIN=/opt/homebrew/opt/postgresql@18/bin   # Homebrew's PostgreSQL client tools

# Rehearsal: in Neon's SQL editor run  CREATE DATABASE rehearsal;  then
TARGET_DATABASE_URL="$(echo "$TARGET_DATABASE_URL" | sed 's#/neondb?#/rehearsal?#')" python -m scripts.copy_database
python -m scripts.copy_s3 --dry-run
python -m scripts.copy_s3            # safe to repeat: identical objects are skipped
```

`copy_database` dumps the current database (read-only), restores it into the
empty target and runs `compare_databases`: same tables, row counts and row
checksums, constraints, indexes, sequence positions and migrations.
`copy_s3` keeps every key, so the database's `scrapbook_photos.object_key`
values need no change; uploads carry their MD5 so a corrupted copy is refused.

Then check the backend against the new resources locally before anyone
depends on them:

```bash
DATABASE_URL="$TARGET_DATABASE_URL" AWS_ACCESS_KEY_ID="$TARGET_AWS_ACCESS_KEY_ID" \
AWS_SECRET_ACCESS_KEY="$TARGET_AWS_SECRET_ACCESS_KEY" AWS_REGION="$TARGET_AWS_REGION" \
S3_BUCKET="$TARGET_S3_BUCKET" python -m scripts.check_s3      # one test object, deleted again
```

Don't run `pytest` against a hosted database: the tests edit the shared
catalogs while they run (and the ones that wipe data only run locally).

## 3. Cutover (needs your approval)

Usage is low, so the final copy is simply made at cutover time:

1. Copy into the empty `neondb` database: `python -m scripts.copy_database`.
2. Run `python -m scripts.copy_s3` again to pick up any new photos.
3. In Render, service `ctrl-ex-delete-api` → **Environment**, change
   `DATABASE_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
   and `S3_BUCKET` to the new values, then **Save, rebuild, and deploy**.
4. Check `https://ctrl-ex-delete-api.onrender.com/health`, then in the app:
   Story (old photos load), a new reflection with a photo, the scrapbook.
5. Update your own `backend/.env` to the new values.

Anything written between step 1 and the deploy in step 3 stays only in the
old database, so do it when nobody is using the app.

**Rollback:** put the old values back in Render (keep them in a password
manager until the move is final). The old database and bucket are
untouched, so switching back works; anything written to the new ones in
between would need copying back.

## 4. Afterwards

Keep Leo's database and bucket until after the final presentation and
grading, then ask Leo to delete them and to revoke the old access key. The
keys that were pasted into chat during development should be rotated in any
case.
