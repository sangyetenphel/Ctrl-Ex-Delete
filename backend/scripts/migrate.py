"""
Applies the SQL files in db/migrations/ to the database in DATABASE_URL.

Run from the backend/ folder (with the venv active):

    python -m scripts.migrate            # apply new migrations, then load the activity and affirmation catalogs
    python -m scripts.migrate --no-seed  # apply new migrations only
    python -m scripts.migrate --status   # list which ones are applied (changes nothing)

Each file runs once, in filename order, inside its own transaction.
Applied files are recorded in the schema_migrations table, so running this
again only applies files that are new. Never edit a file that has already been
applied; add a new numbered file instead.

001_schema.sql creates the whole schema on a new, empty database. The 19
earlier files are kept in db/migrations/legacy/ for reference only; a database
that applied them (the original one) is refused, never "upgraded".
"""
import sys
from pathlib import Path

import psycopg

from app.config import settings
from scripts import seed_affirmations, seed_catalog, seed_room_messages

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "db" / "migrations"
LEGACY_DIR = MIGRATIONS_DIR / "legacy"


def migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


def applied_versions(conn: psycopg.Connection) -> set[str]:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version     TEXT PRIMARY KEY,
            applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    conn.commit()
    return {row[0] for row in conn.execute("SELECT version FROM schema_migrations")}


def main() -> None:
    show_status_only = "--status" in sys.argv

    with psycopg.connect(settings.database_url) as conn:
        done = applied_versions(conn)
        if done & {path.name for path in LEGACY_DIR.glob("*.sql")}:
            sys.exit("This database has the old schema history (db/migrations/legacy/) and is left as it is. "
                     "The current schema is for a new, empty database: see docs/DATABASE_DESIGN.md.")

        for path in migration_files():
            version = path.name
            if version in done:
                print(f"  applied  {version}")
                continue
            if show_status_only:
                print(f"  pending  {version}")
                continue

            print(f"  applying {version} ...", end=" ", flush=True)
            with conn.transaction():
                conn.execute(path.read_text())
                conn.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)", (version,)
                )
            print("done")

    print("Database is up to date." if not show_status_only else "")

    # Both catalog seeds are safe to repeat (see scripts/seed_catalog.py and
    # scripts/seed_affirmations.py); neither deletes user data.
    if not show_status_only and "--no-seed" not in sys.argv:
        seed_catalog.main()
        seed_affirmations.main()
        seed_room_messages.main()


if __name__ == "__main__":
    main()
