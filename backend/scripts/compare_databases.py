"""
Compares two CED databases, for checking a copy (for example the move to a
new Neon project). Read-only on both sides. Run from the backend/ folder:

    TARGET_DATABASE_URL=... python -m scripts.compare_databases

The source is SOURCE_DATABASE_URL, or DATABASE_URL from backend/.env when
that isn't set. It checks the tables, each table's row count and a checksum
of all its rows, the constraints and indexes, sequence positions and the
applied migrations. Connection strings are never printed.
"""
import os
import sys
from urllib.parse import urlsplit

import psycopg

from app.config import settings


def same_database(a: str, b: str) -> bool:
    """True when both URLs name the same host and database."""
    ua, ub = urlsplit(a), urlsplit(b)
    host = lambda u: (u.hostname or "").replace("-pooler.", ".")
    return host(ua) == host(ub) and ua.path == ub.path


def snapshot(url: str) -> dict:
    with psycopg.connect(url) as conn:
        conn.read_only = True
        # Rows are compared as text, so dates and times must print the same way on both sides.
        conn.execute("SET TIME ZONE 'UTC'")
        conn.execute("SET DateStyle = 'ISO, YMD'")
        tables = [row[0] for row in conn.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY 1")]
        rows = {}
        for table in tables:
            # Order-independent: the md5 of the sorted md5s of every row.
            rows[table] = conn.execute(
                f'SELECT count(*), md5(coalesce(string_agg(md5(t::text), \'\' ORDER BY md5(t::text)), \'\')) '
                f'FROM "{table}" t').fetchone()
        constraints = set(conn.execute(
            "SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid) FROM pg_constraint "
            "WHERE connamespace = 'public'::regnamespace").fetchall())
        indexes = set(conn.execute(
            "SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'").fetchall())
        sequences = dict(conn.execute(
            "SELECT sequencename, last_value FROM pg_sequences WHERE schemaname = 'public'").fetchall())
        migrations = [row[0] for row in conn.execute("SELECT version FROM schema_migrations ORDER BY 1")] \
            if "schema_migrations" in tables else []
        version = conn.execute("SHOW server_version").fetchone()[0]
    return {"tables": tables, "rows": rows, "constraints": constraints, "indexes": indexes,
            "sequences": sequences, "migrations": migrations, "version": version}


def compare(source_url: str, target_url: str) -> bool:
    if same_database(source_url, target_url):
        print("  FAIL  source and target are the same database")
        return False
    source, target = snapshot(source_url), snapshot(target_url)
    print(f"  source: PostgreSQL {source['version']}, {len(source['tables'])} tables")
    print(f"  target: PostgreSQL {target['version']}, {len(target['tables'])} tables")
    ok = True

    def check(label: str, good: bool, detail: str = "") -> None:
        nonlocal ok
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'}  {label}{f'  ({detail})' if detail else ''}")

    missing = sorted(set(source["tables"]) - set(target["tables"]))
    extra = sorted(set(target["tables"]) - set(source["tables"]))
    check("same tables", not missing and not extra,
          ", ".join([f"missing {t}" for t in missing] + [f"extra {t}" for t in extra]))
    for table in source["tables"]:
        if table not in target["rows"]:
            continue
        (n_source, sum_source), (n_target, sum_target) = source["rows"][table], target["rows"][table]
        check(f"{table}: {n_source} rows", (n_source, sum_source) == (n_target, sum_target),
              "" if n_source == n_target else f"target has {n_target}")
        if n_source == n_target and sum_source != sum_target:
            print(f"        row contents differ in {table}")
    check("same constraints", source["constraints"] == target["constraints"],
          f"{len(source['constraints'] ^ target['constraints'])} differ")
    check("same indexes", source["indexes"] == target["indexes"],
          f"{len(source['indexes'] ^ target['indexes'])} differ")
    # A sequence behind its source would hand out ids that already exist.
    behind = [name for name, value in source["sequences"].items()
              if value is not None and (target["sequences"].get(name) or 0) < value]
    check("sequences at least as far as the source", not behind, ", ".join(behind))
    check("same applied migrations", source["migrations"] == target["migrations"],
          f"source {len(source['migrations'])}, target {len(target['migrations'])}")
    return ok


def main() -> int:
    source_url = os.environ.get("SOURCE_DATABASE_URL") or settings.database_url
    target_url = os.environ.get("TARGET_DATABASE_URL")
    if not target_url:
        print("Set TARGET_DATABASE_URL to the database to compare with.")
        return 2
    print("Comparing databases (read-only)")
    ok = compare(source_url, target_url)
    print("They match." if ok else "They differ (see above).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
