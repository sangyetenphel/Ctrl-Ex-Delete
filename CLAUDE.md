# CLAUDE.md — Ctrl + Ex + Delete (CED)

SwiftUI iOS app (`CtrlExDelete/`) with a FastAPI backend (`backend/`), PostgreSQL, S3, and Groq and Gemini Live for Ced. Start with `README.md` and `docs/architecture.md`. The API contract is `docs/api.md` (update it with any endpoint change); the schema is in `docs/DATABASE_DESIGN.md`; backend setup, settings, migrations and tests are in `backend/README.md`. Production resource names and the operations runbook are private.

## Rules
- Never push, merge, or modify `main` or teammates' branches without explicit permission. Ask before committing the user's own uncommitted changes.
- Never print, commit or paste secrets. Settings files (`backend/.env*`) are git-ignored; check settings by name or length only.
- Tests run only against a local database (`CED_ENV_FILE=.env.test pytest -q`), never with `.env.production`.
- Database: `backend/db/migrations/001_schema.sql` is the baseline for new databases (`legacy/` is the earlier history, reference only; `scripts/migrate.py` uses it as a guard). Add `002_*.sql` and onwards, never edit an applied migration. Before applying anything to production: confirm the target, back it up, rehearse on a copy, and explain destructive steps. The original (pre-migration) Neon database and S3 bucket are no longer used: never read or write them.
- Ced privacy: no chat/voice text stored or logged (only usage counts). Crisis resources appear in context and open only on tap; safety must not rely on the model alone.
- Keep categories (`outdoor_movement`, `mindfulness_rest`, `solo_exploration`, `social_connection`) and store mood answers as given (never numeric).
- Preserve Ayusha's SwiftUI/Figma design (palette in `Theme/Theme.swift`, Lora/Nunito, pixel art). Functional additions are fine; no redesigns.

## Commands
```bash
cd backend && source venv/bin/activate
uvicorn app.main:app --reload            # restart (not just reload) after settings changes
CED_ENV_FILE=.env.test pytest -q         # LOCAL database only (backend/README.md, "Running the tests")
python -m scripts.migrate [--status]
python -m scripts.verify_database [--fresh]
python -m scripts.reset_installation <id> [--execute]   # ONE installation; dry run by default
cd CtrlExDelete && ./DevTests/run.sh     # Swift logic tests (no simulator)
cd CtrlExDelete && xcodebuild -scheme CtrlExDelete -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Debug launch args: `-CEDStartScreen <screen>`, `-CEDAPIBaseURL <url>` (Xcode runs only), `-CEDMockVoice YES`, `-CEDClearLocalJourneyCache YES` (clears the on-phone journey caches once per value; keeps the installation ID). A backend that also applies to Home Screen launches: `CED_API_BASE_URL = <host>` in the git-ignored `Config/DeveloperSettings.xcconfig`.

## Gotchas
- Project uses MainActor default isolation: audio/network callbacks need `nonisolated` types and `@Sendable` closures; avoid `async let` in `JourneyStore`.
- New Swift files are picked up automatically (file-system-synchronized groups).
- Signing: team and bundle ID come from `Config/Signing.xcconfig`; each developer overrides them in the gitignored `Config/DeveloperSettings.xcconfig`, never in Xcode's Signing tab (that edits `project.pbxproj`).
- Simulator: no usable echo cancellation (voice barge-in disabled there by design), `tel:`/`sms:` don't open, first taps after transitions are often dropped.
