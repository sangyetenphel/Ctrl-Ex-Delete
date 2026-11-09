# CLAUDE.md — Ctrl + Ex + Delete (CED)

iOS breakup-recovery app (UNCG senior capstone). SwiftUI app (`CtrlExDelete/`) + FastAPI backend (`backend/`) + Neon PostgreSQL + AWS S3 (photos) + Groq (Ced text chat) + Gemini Live (Ced voice calls, relayed by the backend). Anonymous users: a Keychain UUID sent as `X-Installation-ID`.

Production (Sangye's accounts): Render `ctrl-ex-delete-api` (branch `main`, Auto-Deploy off: deploy manually; release tag `ced-demo-v1`), Neon `ctrl-ex-delete` / `production` / `neondb`, S3 `ced-photos-prod` with IAM user `ced-production`. Settings: git-ignored `backend/.env.production` (production), optional `backend/.env` (local development) and `.env.test` (tests).

For the current state of the AI/voice work, read `docs/AI_INTEGRATION_HANDOFF.md`. The API contract is `docs/api.md` — update it with any endpoint change. Schema design: `docs/DATABASE_DESIGN.md`; setting up your own Neon/S3 (fresh start): `docs/MIGRATION.md`. **Production setup (start here): `docs/RENDER_DEPLOYMENT_HANDOFF.md`**; how it was built: `docs/INFRASTRUCTURE_CONSOLIDATION_PLAN.md`.

## Rules
- Never push, merge, or modify `main` or teammates' branches without explicit permission. Ask before committing the user's own uncommitted changes.
- Never print, commit or paste secrets. `backend/.env` is git-ignored; check settings by name/length only.
- Preserve Ayusha's SwiftUI/Figma design (palette in `Theme/Theme.swift`, Lora/Nunito, pixel art). Functional additions are fine; no redesigns.
- Database: `backend/db/migrations/001_schema.sql` is the baseline for new databases (`legacy/` is the original database's history, reference only); add `002_*.sql` and onwards, never edit an applied migration. Before applying to Neon: confirm the target, back it up, rehearse on a copy, and explain destructive steps. The original Neon database and S3 bucket (Leo's accounts) are no longer used: never read or write them.
- Ced privacy: no chat/voice text stored or logged (only usage counts). Crisis resources appear in context and open only on tap; safety must not rely on the model alone.
- Keep categories (`outdoor_movement`, `mindfulness_rest`, `solo_exploration`, `social_connection`) and store mood answers as given (never numeric).

## Commands
```bash
cd backend && source venv/bin/activate
uvicorn app.main:app --reload            # restart (not just reload) after .env changes
CED_ENV_FILE=.env.test pytest -q         # LOCAL database only (backend/README.md, "Running the tests"); never .env.production
python -m scripts.migrate [--status]
python -m scripts.verify_database [--fresh]
python -m scripts.reset_installation <id> [--execute [--production]]   # ONE installation; dry run by default
./ced-reset <id> [--dry-run]             # (repo root) the same for production in one step; the phone notices by itself
CED_ENV_FILE=.env.production python -m scripts.migrate --status   # any command against production's settings
cd CtrlExDelete && xcodebuild -scheme CtrlExDelete -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Debug launch args: `-CEDStartScreen <screen>`, `-CEDAPIBaseURL <url>` (Xcode runs only), `-CEDMockVoice YES`, `-CEDClearLocalJourneyCache YES` (clears the on-phone journey caches once per value; keeps the installation ID). For a backend that also applies to Home Screen launches: `CED_API_BASE_URL = <host>` in the git-ignored `Config/DeveloperSettings.xcconfig`.

## Gotchas
- Project uses MainActor default isolation: audio/network callbacks need `nonisolated` types and `@Sendable` closures; avoid `async let` in `JourneyStore`.
- New Swift files are picked up automatically (file-system-synchronized groups).
- Signing: team and bundle ID come from `Config/Signing.xcconfig` (Debug and Release); each developer overrides them in the gitignored `Config/DeveloperSettings.xcconfig`, never in Xcode's Signing tab (that edits `project.pbxproj`).
- Simulator: no usable echo cancellation (voice barge-in disabled there by design), `tel:`/`sms:` don't open, first taps after transitions are often dropped.
