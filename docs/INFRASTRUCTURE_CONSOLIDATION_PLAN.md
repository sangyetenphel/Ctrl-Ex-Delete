# CED infrastructure consolidation (plan and record, 2026-11-04 to 2026-11-08)

> **Status: complete** except the items still marked open in step 4 (Auto-Deploy stays off by choice; the local `.local-backup/2026-11-04/` dumps await Sangye's decision). The current setup: `docs/RENDER_DEPLOYMENT_HANDOFF.md`.

Goal: one CED environment, entirely in Sangye's accounts. Leo's Neon and AWS
resources are out of scope: nothing here reads, changes or deletes them.
Nothing in this plan has been executed; every step marked **[approval]**
waits for an explicit yes.

## 1. Inventory (read-only, 2026-11-04)

### Render (Sangye's workspace) — 2 services, no Blueprints, no env groups

| | `ctrl-ex-delete-api` (live) | `ced-backend-test` (temporary) |
|---|---|---|
| URL | `https://ctrl-ex-delete-api.onrender.com` (built into Release) | `https://ced-backend-test.onrender.com` |
| Plan / region | Free, Virginia | Free, Virginia |
| Branch / Auto-Deploy | `integration/ai-room-progress`, **On Commit** | `refactor/final-optimization`, Off |
| Deployed code | `de1df9a` (old code, 10 days ago) | `7653fc7` (optimized code) |
| Points at | **Leo's** Neon database and S3 bucket | **Sangye's** `neondb` and `ced-photos-prod` (verified) |
| Variables (names) | the same 10 in both: `DATABASE_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET`, `GROQ_API_KEY`, `GROQ_MODEL`, `GEMINI_API_KEY`, `GEMINI_VOICE`, `PYTHON_VERSION` | |
| Status | **active** (Release app uses it) | **temporary** (Debug iPhone uses it) |

`render.yaml` is documentation only (no Blueprint instance), so dashboard
changes are not overwritten by it.

### Neon (Sangye's project `ctrl-ex-delete`, branch `production`, PostgreSQL 18.6)

| Database | Size | Use | Status |
|---|---|---|---|
| `neondb` | 9 MB | schema 001 + catalogs; 1 test installation (Sangye's iPhone: 1 check-in, 1 reflection, 1 photo) | **active** (test service) |
| `rehearsal` | 9 MB | copy of old user data from the migration rehearsal (3 installations, 4 check-ins, 4 reflections, 4 photo rows) | **temporary**; nothing depends on it (below) |
| `postgres` | 8 MB | Neon's default system database | keep (not ours to remove) |

Nothing depends on `rehearsal`: 0 open connections; no settings file, Render
service or code default names it (only the optional `--database` argument of
`scripts.copy_database` / `compare_databases`).

Neon console (step 0, read-only, 2026-11-04): one organization ("Sangye",
one member: Sangye, Admin), no organization API keys, no integrations; one
project `ctrl-ex-delete` (AWS us-east-1); one branch
`production` (default, never expires, **not protected**); one compute
(0.25–2 CU autoscaling); one role `neondb_owner` (owns `neondb` and
`rehearsal`); restore window **6 hours**; no snapshots yet (snapshots can be
created on this plan).

### AWS (Sangye's account)

- Bucket `ced-photos-prod` (us-east-1): Block Public Access on (all four),
  1 object (the iPhone test photo, SSE-S3). **Active.**
- IAM user `ced-production`: confirmed as the key's identity; refused for
  account-wide bucket listing, IAM listing and its own key listing (least
  privilege works). **Active.**
- Not visible with this key: other buckets, other IAM users, how many
  access keys `ced-production` has, root access keys, and the bucket's
  encryption/versioning/ownership/policy (the key may only list, read and
  write objects and read Block Public Access). Checked manually in Chrome
  (step 0 checklist below). The active key's ID is the one in `backend/.env.production`.

**Result (Sangye, in Chrome, 2026-11-04): every item below was as
expected.** So the AWS account holds only `ced-photos-prod` and
`ced-production` (one active key, `…redacted`); nothing to remove in AWS.

#### Step 0 AWS checklist (in Chrome, read-only)

1. Account ID (top right) is your own account. Security credentials (root):
   MFA assigned; **no root access keys**.
2. S3 → General purpose buckets (all regions): only `ced-photos-prod`
   (us-east-1) is expected; note any other bucket's name, region, objects.
   `ced-photos-prod`: Properties — default encryption SSE-S3, versioning
   Disabled, Object Lock off; Permissions — Block public access all On, no
   bucket policy, Object Ownership "Bucket owner enforced", no CORS;
   Management — no lifecycle or replication rules; 1 object.
3. IAM → Users: only `ced-production` expected. It has: no console
   password; only its inline policy (no AWS-managed or admin policies); no
   groups; **exactly one Active access key, ID as recorded on Sangye's Mac**, last used
   today (S3); no other keys (active or inactive).
4. IAM → Roles: only `AWSServiceRole…` roles expected; IAM → User groups and
   Identity providers: none expected.
5. Billing → Bills / Free Tier: charges by service (expected: S3 only, ~$0).
6. Resource Groups & Tag Editor → all regions, all resource types: nothing
   besides the bucket expected (catches stray EC2, CloudFront, etc.).

### This Mac (`backend/`, git-ignored)

| File | Points at | Status |
|---|---|---|
| `.env.production` | `neondb`, `ced-photos-prod`, `ced-production` key | **active** (scripts) |
| `.env.migration` | the same targets as `.env.production` (`TARGET_*` names) | redundant |
| `.env` | Leo's resources + the Groq/Gemini keys | used by the live service's values; local copy only |
| `.local-backup/` (7.7 MB) | copy of old user data and photos | temporary (privacy: delete after go-live) |
| `CtrlExDelete/Config/DeveloperSettings.xcconfig` | `CED_API_BASE_URL = ced-backend-test.onrender.com` | temporary (remove at cutover) |

### Git

`main` `f180e3b`; `integration/ai-room-progress` `3066b70`;
`refactor/final-optimization` `7131e87` (17 commits ahead, 0 behind, so a
merge later would be a fast-forward). Nothing is merged by this plan.

### Groq and Gemini keys (settled)

Both services use the same `GROQ_API_KEY` / `GEMINI_API_KEY`. Sangye
confirmed (2026-11-04) that both keys belong to Sangye's own accounts
(registered under an older email, still accessible). They are not part of
this cleanup: no migration or replacement. The Gemini paid-tier/logging
note in handoff section 6 still applies before real users.

## 2. Final architecture

```
iPhone (Release; Debug with no CED_API_BASE_URL)
   │ https / wss
   ▼
Render  ctrl-ex-delete-api  (Free, Virginia, same URL as today)
   │  branch refactor/final-optimization (later: whichever branch you choose)
   ├── Neon  ctrl-ex-delete / production / neondb     (DATABASE_URL)
   ├── S3    ced-photos-prod via IAM ced-production   (1 active key)
   ├── Groq  (your key)          └── Gemini Live (your key)
```

Keeping the existing service (not a new one) keeps the production URL, so
Release builds and `APIConfig.swift` need no change.

## 3. Cutover procedure

**Step 0 — read-only checks you sign in for** (no changes):
Neon console (projects, branches, restore window); AWS console (buckets, IAM
users, `ced-production` keys, no root keys, MFA).

**Step 1 — prepare** (no production change):
1. **Done 2026-11-04 ~11:11 UTC:** one manual Neon snapshot of the
   `production` branch (Free plan: 1 manual snapshot allowed, never expires,
   inside the included storage; Free has no usage billing). Restore options:
   one-step (same branch name and connection string; the old state kept as
   `production (old)`) or multi-step (new branch to inspect, then finalize).
   At that moment `neondb` held 1 installation, 1 check-in, 1 reflection,
   1 photo (the iPhone test).
2. Note the live service's current deploy (`de1df9a`) for rollback. The old
   variable values stay in `backend/.env` locally; nothing is read from
   Leo's accounts.
3. **Decided:** keep the iPhone test data in `neondb`. `rehearsal` stays
   until step 4; branch protection unchanged for now.

**Step 2 — DONE 2026-11-04 11:32 UTC.** Auto-Deploy Off (confirmed after
reload); branch switched with no deploy triggered; the 5 values entered and
checked by fingerprint against `.env.production` (Groq/Gemini values checked
unchanged); "Save, rebuild, and deploy" built `7131e87` as deploy
`dep-dblheo142hec7388a85g`: build successful, startup clean, Live. Verified
on the production URL: `/health`, `/health/db`, new OpenAPI text, 30
affirmations, a disposable check-in found in `neondb` (installation ending
`…288c`, kept until Sangye decides), photo link naming `ced-photos-prod`.
Previous deploy for reference: `dep-dbeggjo473hc73941j60` (`de1df9a`, old
code: not schema-compatible, do not roll back to it). iPhone Debug:
`CED_API_BASE_URL` commented out, Debug app reinstalled. AWS secret
confirmed by a test upload through production (S3 accepted the signed PUT;
disposable installation `…eff8` with an 871-byte test photo, kept). iPhone
test 11:36:49 UTC: `POST /reflections` 201 on `ctrl-ex-delete-api`; the
reflection and its 451 KB photo are in `neondb` and `ced-photos-prod`.
Still open: a Release build on the phone; step 4.

**Step 2 — cutover of `ctrl-ex-delete-api`** (as planned) (a few minutes; Free has a
short outage while it deploys) **[approval]**:
1. Settings → Auto-Deploy: **Off**.
2. Settings → Branch: `refactor/final-optimization` (no Git merge needed;
   every branch is kept). With Auto-Deploy off this alone doesn't deploy.
3. Environment: you replace `DATABASE_URL`, `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY` (from `.env.production`), and I set
   `AWS_REGION=us-east-1` and `S3_BUCKET=ced-photos-prod`. The Groq and
   Gemini variables stay as they are. Leave `CED_ENV_FILE` and
   `CED_VOICE_DIAGNOSTICS` unset.
4. **Save, rebuild, and deploy** (code and settings in one deploy: the new
   code needs the new schema, and the old code can't run against it).

**Step 3 — verify production** (same checks as the test service):
logs clean; `/health`, `/health/db`; `/openapi.json` shows the new code;
`/affirmations` = 30; one throwaway check-in found in `neondb` and a photo
link naming `ced-photos-prod`; that throwaway installation then deleted
**[approval]**. Then the iPhone: remove `CED_API_BASE_URL` from
`DeveloperSettings.xcconfig`, Run once, do a check-in and a reflection with a
photo, and I confirm they're in `neondb` / `ced-photos-prod` (read-only).
Also a Release build on the phone.

**Step 4 — settle** (after a day or so of normal use):
1. Auto-Deploy back **On** for the production branch. **[approval]** *(Open: left Off for now; deploys are manual.)*
2. **Done 2026-11-08:** `ced-backend-test` (`srv-dblgc45bedkc73aihnf0`) deleted with Sangye's approval, after checking that production (`aced983`, neondb, ced-photos-prod) didn't depend on it and nothing had used it since 2026-11-04 11:06 UTC. Only `ctrl-ex-delete-api` remains; `/health` and `/health/db` ok afterwards.
3. **Done 2026-11-08:** Sangye deleted the `rehearsal` database in the Neon console after a read-only check (no connections, nothing referencing it). Only `neondb` and Neon's `postgres` remain; the snapshot (never expires) is kept and still contains a copy of `rehearsal`.
4. AWS: nothing to remove (step 0 found only the bucket and
   `ced-production` with one active key).
5. **Done 2026-11-08 (Mac):** the Groq/Gemini settings moved into `backend/.env.production` (checked by fingerprint), then `backend/.env` (the original infrastructure's settings) and `backend/.env.migration` deleted; four old local-setup backups in `.local-backup/` deleted (all already contained in the current local project); the test-service line removed from `DeveloperSettings.xcconfig`. *(Open: `.local-backup/2026-11-04/`, two database dumps and photo copies from before the fresh start, kept until Sangye decides.)*
6. **Done 2026-11-08:** `render.yaml`, the READMEs, `CLAUDE.md`, `.env.example` and the handoff documents describe the final setup. Merging `refactor/final-optimization` into
   `integration/ai-room-progress` or `main` stays a separate decision with
   your teammates.

## 4. Rollback

- **Code problem after cutover (preferred rollback):** in Render, roll back
  to the previous good deploy of the optimized code, or deploy `7653fc7`
  (the version verified on `ced-backend-test`). It stays on `neondb` and
  `ced-photos-prod`, so nothing touches Leo's accounts.
- **Problem with the new database or bucket:** fix it in place (it's in
  your accounts), or restore `neondb` from the step 1 backup. Until step 4,
  `ced-backend-test` stays up as a second working copy; Debug builds can
  switch to it with `CED_API_BASE_URL`.
- **Full revert to the old setup** (old code `de1df9a` + the old variable
  values): possible, because Leo's resources are untouched, but it means the
  app writes to Leo's database and bucket again. Only with your explicit
  approval, as a last resort.
- Until step 4 nothing is deleted, so every step before it is reversible.
