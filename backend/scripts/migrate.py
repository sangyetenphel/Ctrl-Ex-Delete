"""
Applies the SQL files in db/migrations/ to the database in DATABASE_URL.

Run from the backend/ folder (with the venv active):

    python -m scripts.migrate            # apply new migrations, then load the activity catalog
    python -m scripts.migrate --no-seed  # apply new migrations only
    python -m scripts.migrate --status   # list which ones are applied (changes nothing)

Each file runs once, in filename order, inside its own transaction.
Applied files are recorded in the schema_migrations table, so running this
again only applies files that are new. Never edit a file that has already been
applied; add a new numbered file instead.
"""
import sys
from pathlib import Path

import psycopg

from app.config import settings
from scripts import seed_catalog

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "db" / "migrations"


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

    # The catalog seed is safe to repeat (see scripts/seed_catalog.py).
    if not show_status_only and "--no-seed" not in sys.argv:
        seed_catalog.main()


if __name__ == "__main__":
    main()
