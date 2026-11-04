"""
Copies the CED database into a new, EMPTY database (for example a Neon
project in another account), then checks the copy. Read-only on the source.
Run from the backend/ folder:

    TARGET_DATABASE_URL=... python -m scripts.copy_database

The source is SOURCE_DATABASE_URL, or DATABASE_URL from backend/.env when
that isn't set. Steps:

1. Refuses unless the target is a different database and has no tables, so
   nothing can be overwritten.
2. pg_dump of the source into ../.local-backup/<date>/database.dump (git-ignored;
   it holds user data, so keep it off shared drives).
3. pg_restore into the target, without owners or grants (Neon roles differ).
4. scripts.compare_databases: rows, checksums, constraints, indexes,
   sequences, migrations.

Use the same PostgreSQL major version on both sides (the CED Neon project
runs 18). pg_dump and pg_restore come from PG_BIN if set, else from PATH.
Connection strings are never printed.
"""
import os
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import psycopg

from app.config import settings
from scripts.compare_databases import compare, same_database

BACKUP_DIR = Path(__file__).resolve().parents[2] / ".local-backup"


def direct(url: str) -> str:
    """Neon's pooled host ("-pooler") doesn't suit pg_dump/pg_restore; use the direct one."""
    parts = urlsplit(url)
    return urlunsplit(parts._replace(netloc=parts.netloc.replace("-pooler.", ".")))


def tool(name: str) -> str:
    found = os.path.join(os.environ["PG_BIN"], name) if os.environ.get("PG_BIN") else shutil.which(name)
    if not found or not os.path.exists(found):
        sys.exit(f"Can't find {name}. Install PostgreSQL client tools or set PG_BIN.")
    return found


def run(args: list[str], secret: str) -> None:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"{Path(args[0]).name} failed:\n{result.stderr.replace(secret, '<database>')[-2000:]}")


def main() -> int:
    source_url = os.environ.get("SOURCE_DATABASE_URL") or settings.database_url
    target_url = os.environ.get("TARGET_DATABASE_URL")
    if not target_url:
        print("Set TARGET_DATABASE_URL to the new, empty database.")
        return 2
    if same_database(source_url, target_url):
        print("Refusing: the target is the source database.")
        return 2
    with psycopg.connect(target_url) as conn:
        tables = conn.execute("SELECT count(*) FROM information_schema.tables "
                              "WHERE table_schema = 'public'").fetchone()[0]
    if tables:
        print(f"Refusing: the target already has {tables} tables. Use a new, empty database.")
        return 2

    dump = BACKUP_DIR / date.today().isoformat() / "database.dump"
    dump.parent.mkdir(parents=True, exist_ok=True)
    print(f"1/3 pg_dump of the source -> {dump}")
    run([tool("pg_dump"), "--format=custom", "--no-owner", "--no-privileges",
         "--file", str(dump), "--dbname", direct(source_url)], direct(source_url))
    dump.chmod(0o600)
    print("2/3 pg_restore into the target")
    run([tool("pg_restore"), "--no-owner", "--no-privileges", "--exit-on-error",
         "--dbname", direct(target_url), str(dump)], direct(target_url))
    print("3/3 comparing")
    ok = compare(source_url, target_url)
    print("Copy verified." if ok else "The copy differs from the source (see above).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
