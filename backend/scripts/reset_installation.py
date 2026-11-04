"""
DEVELOPER ONLY: reset ONE installation (one phone) and everything that
belongs to it, e.g. before a demo. Other installations and the shared
catalogs are never touched. There is no API endpoint for this, on purpose.

    # 1. Dry run (the default): counts only, nothing changes
    python -m scripts.reset_installation <installation-id>
    python -m scripts.reset_installation <installation-id> --dry-run

    # 2. Reset: asks you to type the full installation ID
    python -m scripts.reset_installation <installation-id> --execute

    # Production (Sangye's Neon `neondb` + its photo bucket only): also needs
    # --production, and typing RESET PRODUCTION
    CED_ENV_FILE=.env.production python -m scripts.reset_installation <id> --execute --production

What is deleted (for that installation only): check-ins and their room
messages, recommendations, "I'll try this" selections, bookmarks,
reflections (memories), photo records and their S3 files, Moving Forward,
Ced usage counts, and the installation row. Progress, the bookshelf and
Insights are computed from these, so they reset too. The plant game and Ced
conversations store nothing per user on the server.

What is never deleted: activities, categories, research, affirmations, room
messages (the catalogs), the schema, other installations, and any S3 file
that isn't one of this installation's photos.

Where it may run (checked before anything is read):
- a local database (localhost / Unix socket) without real S3 settings, or
- exactly the production database and bucket, identified by SHA-256
  fingerprints below (no hostnames or bucket names in git).
Anything else, e.g. the original database and bucket, is refused.

Order, so a failure is always safe to retry:
1. the installation row is locked (no new rows can be added to it meanwhile),
2. its photo files are deleted from S3; if any delete fails, the database is
   left unchanged and the failures are reported,
3. its rows are deleted children-first in the same transaction, checked to
   be gone, and committed.
If step 3 fails after step 2, the files are gone but the rows remain: run it
again (deleting a missing S3 file succeeds, so the retry finishes the job).

Output is counts and table names only: never reflection text, credentials,
object keys or presigned URLs.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
import uuid
from dataclasses import dataclass, field
from urllib.parse import urlparse

import psycopg

# Every table that holds one installation's data, children first (the order
# rows are deleted in). The script refuses to run if the database's foreign
# keys or `installation_id` columns name a table that isn't here, so a new
# user table can't be skipped silently.
USER_TABLES = [
    "check_in_room_messages",   # via check_ins
    "reflections",
    "scrapbook_photos",
    "activity_bookmarks",
    "activity_selections",
    "recommendations",
    "check_ins",
    "moving_forward_check_ins",
    "ced_usage",
    "installations",
]

# Shared catalogs: must never be part of a reset.
PROTECTED_TABLES = {
    "activity_categories", "activities", "research_bases", "activity_research_bases",
    "affirmation_themes", "affirmations", "affirmation_sources", "affirmation_theme_sources",
    "affirmation_notes", "room_messages", "schema_migrations",
}

LOCAL_HOSTS = {None, "", "localhost", "127.0.0.1", "::1"}

# The only remote target: Sangye's Neon project `ctrl-ex-delete` (branch
# `production`, database `neondb`) and its private photo bucket.
# SHA-256 of the lower-case database host and of the bucket name.
PRODUCTION_TARGET = {
    "db_host_sha256": "64fb1f0ab4eb6b24a0ffccefc30f14848c53d9356c7c87854186ab5a301ec9aa",
    "db_name": "neondb",
    "bucket_sha256": "20e2dd59936387cffa364431b279812013719a5b05b05287be4510798f1d11d7",
}

# The S3 keys this app creates for photos (app/media.py; older uploads used
# installations/<installation-id>/<photo-id>.jpg).
PHOTO_KEY = re.compile(r"^scrapbook/[0-9a-f]{32}\.jpg$")
LEGACY_PREFIX = "installations/{id}/"
LEGACY_KEY = re.compile(r"^installations/[0-9a-f-]{36}/[0-9a-f-]{32,36}\.jpg$")


class Refused(Exception):
    """The target or the request isn't safe; nothing was changed."""


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def classify_target(database_url: str, s3_bucket: str | None) -> str:
    """'local' or 'production'; raises Refused for anything else."""
    url = urlparse(database_url)
    host = (url.hostname or "").lower()
    db_name = url.path.lstrip("/")
    if host in LOCAL_HOSTS:
        if s3_bucket:
            raise Refused("A local database with real S3 settings isn't supported: remove the AWS "
                          "settings from this environment file (photos are then counted, not deleted).")
        return "local"
    if _sha256(host) == PRODUCTION_TARGET["db_host_sha256"] and db_name == PRODUCTION_TARGET["db_name"]:
        if not s3_bucket or _sha256(s3_bucket) != PRODUCTION_TARGET["bucket_sha256"]:
            raise Refused("The production database must be used with the production bucket "
                          "(S3 settings missing or a different bucket).")
        return "production"
    raise Refused("This isn't a known CED database (only a local one or the production Neon database "
                  "are allowed). Nothing was read or changed.")


def parse_installation_id(text: str) -> str:
    try:
        value = uuid.UUID(text.strip())
    except (ValueError, AttributeError):
        raise Refused("That isn't an installation ID (a UUID like 0f8c…-…).") from None
    if str(value) != text.strip().lower():
        raise Refused("Give the installation ID in its usual form: 8-4-4-4-12 hexadecimal digits.")
    return str(value)


# ─────────────────────────────────────────────
# Finding the installation's rows
# ─────────────────────────────────────────────

def _foreign_keys(conn) -> list[tuple[str, str, list[str], list[str]]]:
    """(child, parent, child columns, parent columns) for every foreign key in public."""
    rows = conn.execute(
        """SELECT c.conrelid::regclass::text, c.confrelid::regclass::text,
                  array_agg(ca.attname ORDER BY k.ord), array_agg(pa.attname ORDER BY k.ord)
           FROM pg_constraint c
           CROSS JOIN LATERAL unnest(c.conkey, c.confkey) WITH ORDINALITY AS k(child_col, parent_col, ord)
           JOIN pg_attribute ca ON ca.attrelid = c.conrelid AND ca.attnum = k.child_col
           JOIN pg_attribute pa ON pa.attrelid = c.confrelid AND pa.attnum = k.parent_col
           WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
           GROUP BY c.oid, c.conrelid, c.confrelid"""
    ).fetchall()
    return [(child, parent, list(cc), list(pc)) for child, parent, cc, pc in rows]


def row_filters(conn) -> dict[str, str]:
    """
    For every table that holds installation data, a WHERE clause selecting the
    target installation's rows (parameter %(id)s). Built from the database's
    real foreign keys, then checked against USER_TABLES and PROTECTED_TABLES.
    """
    fks = _foreign_keys(conn)
    with_column = {row[0] for row in conn.execute(
        """SELECT table_name FROM information_schema.columns
           WHERE table_schema = 'public' AND column_name = 'installation_id'""")}

    # Every table reachable from installations through foreign keys.
    reached, frontier = {"installations"}, ["installations"]
    while frontier:
        parent = frontier.pop()
        for child, p, _, _ in fks:
            if p == parent and child not in reached:
                reached.add(child)
                frontier.append(child)

    # Application logic: a table with an installation_id column belongs here too.
    found = reached | with_column
    if found & PROTECTED_TABLES:
        raise Refused(f"Catalog tables would be affected: {sorted(found & PROTECTED_TABLES)}. Nothing was changed.")
    unknown = found - set(USER_TABLES)
    if unknown:
        raise Refused(f"These tables hold installation data but the script doesn't know them: {sorted(unknown)}. "
                      "Add them to USER_TABLES (children first) after checking. Nothing was changed.")
    missing = with_column - reached
    if missing:
        raise Refused(f"Tables with installation_id but no foreign key: {sorted(missing)}. Nothing was changed.")

    # One WHERE clause per table: its own installation_id column when it has
    # one (the schema's composite keys keep every row on its own
    # installation), otherwise through the foreign key to a parent that does.
    filters: dict[str, str] = {"installations": "id = %(id)s"}

    def where(table: str, seen: frozenset = frozenset()) -> str:
        if table in filters:
            return filters[table]
        if table in with_column:
            filters[table] = "installation_id = %(id)s"
            return filters[table]
        for child, parent, child_cols, parent_cols in fks:
            if child == table and parent in reached and parent not in seen:
                filters[table] = (f"({', '.join(child_cols)}) IN (SELECT {', '.join(parent_cols)} "
                                  f"FROM {parent} WHERE {where(parent, seen | {table})})")
                return filters[table]
        raise Refused(f"Can't tell which rows of {table} belong to an installation. Nothing was changed.")

    existing = {row[0] for row in conn.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")}
    return {t: where(t) for t in USER_TABLES if t in existing and t in found}


@dataclass
class Plan:
    installation_id: str
    exists: bool
    counts: dict[str, int]
    photo_keys: list[str] = field(default_factory=list)        # never printed
    unexpected_keys: int = 0                                   # rows whose key isn't an app photo key
    s3_present: int | None = None                              # None: no S3 in this environment
    s3_missing: int | None = None
    other_rows: dict[str, int] = field(default_factory=dict)   # other installations' rows, for the check after


def _count(conn, table: str, where: str, installation_id: str) -> int:
    return conn.execute(f"SELECT count(*) FROM {table} WHERE {where}", {"id": installation_id}).fetchone()[0]


def _photo_keys(conn, installation_id: str) -> tuple[list[str], int]:
    keys = [row[0] for row in conn.execute(
        "SELECT object_key FROM scrapbook_photos WHERE installation_id = %s ORDER BY id", (installation_id,))]
    good = [k for k in keys if PHOTO_KEY.match(k) or LEGACY_KEY.match(k)]
    return good, len(keys) - len(good)


def _legacy_objects(s3, bucket: str, installation_id: str) -> list[str]:
    """Older uploads kept the installation ID in the key; list them if S3 allows it."""
    keys = []
    for page in s3.get_paginator("list_objects_v2").paginate(
            Bucket=bucket, Prefix=LEGACY_PREFIX.format(id=installation_id)):
        keys += [item["Key"] for item in page.get("Contents", []) if LEGACY_KEY.match(item["Key"])]
    return keys


def _exists_in_s3(s3, bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except Exception as error:  # botocore ClientError (or a test double's)
        code = getattr(error, "response", {}).get("Error", {}).get("Code")
        if code in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def make_plan(conn, installation_id: str, s3=None, bucket: str | None = None) -> Plan:
    """Read-only: what a reset would delete."""
    filters = row_filters(conn)
    exists = _count(conn, "installations", filters["installations"], installation_id) == 1
    counts = {t: _count(conn, t, w, installation_id) for t, w in filters.items()}
    keys, unexpected = _photo_keys(conn, installation_id)
    plan = Plan(installation_id, exists, counts, unexpected_keys=unexpected)
    if s3 is not None and bucket:
        keys = sorted(set(keys) | set(_legacy_objects(s3, bucket, installation_id)))
        present = sum(_exists_in_s3(s3, bucket, k) for k in keys)
        plan.s3_present, plan.s3_missing = present, len(keys) - present
    plan.photo_keys = keys
    plan.other_rows = {t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0] - n for t, n in counts.items()}
    return plan


# ─────────────────────────────────────────────
# Reset
# ─────────────────────────────────────────────

class PartialReset(Exception):
    def __init__(self, message: str, report: dict):
        super().__init__(message)
        self.report = report


def execute_reset(conn, installation_id: str, s3=None, bucket: str | None = None) -> dict:
    """
    Deletes the installation's S3 photos, then its rows, in one transaction
    (the caller's connection must not be in autocommit). Returns a report.
    Raises PartialReset (with a report) if anything is left; safe to rerun.
    """
    filters = row_filters(conn)
    with conn.transaction():
        locked = conn.execute("SELECT id FROM installations WHERE id = %s FOR UPDATE",
                              (installation_id,)).fetchone()
        if not locked:
            raise Refused("No installation with that ID. Nothing was changed.")
        keys, unexpected = _photo_keys(conn, installation_id)
        if s3 is not None and bucket:
            keys = sorted(set(keys) | set(_legacy_objects(s3, bucket, installation_id)))
        before = {t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in filters}
        report = {"s3_deleted": 0, "s3_failed": 0, "s3_skipped": "no S3 in this environment" if s3 is None else None,
                  "unexpected_keys_left": unexpected, "deleted_rows": {}, "database": "unchanged"}

        # 1. S3 first: a failure here leaves the database untouched.
        if s3 is not None and bucket and keys:
            failed = []
            for start in range(0, len(keys), 1000):
                batch = [{"Key": k} for k in keys[start:start + 1000]]
                try:
                    result = s3.delete_objects(Bucket=bucket, Delete={"Objects": batch, "Quiet": True})
                    failed += [e.get("Code", "error") for e in result.get("Errors", [])]
                except Exception as error:
                    failed += [type(error).__name__] * len(batch)
            report["s3_failed"] = len(failed)
            report["s3_deleted"] = len(keys) - len(failed)
            if failed:
                report["s3_errors"] = sorted(set(failed))
                raise PartialReset(
                    f"{len(failed)} of {len(keys)} photo files couldn't be deleted from S3 "
                    f"({', '.join(sorted(set(failed)))}). The database was left unchanged; fix the cause and "
                    "run the same command again.", report)

        # 2. The rows, children first; checked before committing.
        try:
            for table in USER_TABLES:
                if table in filters:
                    report["deleted_rows"][table] = conn.execute(
                        f"DELETE FROM {table} WHERE {filters[table]}", {"id": installation_id}).rowcount
            left = {t: _count(conn, t, filters[t], installation_id) for t in filters}
            if any(left.values()):
                raise RuntimeError(f"rows left after delete: { {t: n for t, n in left.items() if n} }")
            after = {t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in filters}
            others_changed = {t for t in filters if after[t] != before[t] - report["deleted_rows"].get(t, 0)}
            if others_changed:
                raise RuntimeError(f"other installations' rows changed in {sorted(others_changed)}")
        except Exception as error:
            report["deleted_rows"] = {}
            raise PartialReset(
                f"The database delete failed ({type(error).__name__}) and was rolled back"
                + (f"; {report['s3_deleted']} photo files were already deleted from S3" if report["s3_deleted"] else "")
                + ". Run the same command again to finish.", report) from error
    report["database"] = "deleted"
    return report


# ─────────────────────────────────────────────
# Command line
# ─────────────────────────────────────────────

def _print_plan(plan: Plan, target: str, database: str, bucket: str | None) -> None:
    print(f"Target: {target} database '{database}'" + (" + production photo bucket" if bucket else " (no S3)"))
    print(f"Installation {plan.installation_id}: {'found' if plan.exists else 'NOT FOUND'}")
    for table, n in plan.counts.items():
        print(f"  {table:26} {n:6} row(s)")
    if plan.s3_present is None:
        print(f"  photo files                {len(plan.photo_keys):6} recorded (S3 not configured here: not deleted)")
    else:
        print(f"  photo files in S3          {plan.s3_present:6} present, {plan.s3_missing} already missing")
    if plan.unexpected_keys:
        print(f"  {plan.unexpected_keys} photo record(s) with an unexpected key format: their files are left alone")
    print("Kept: catalogs (activities, categories, research, affirmations, room messages) and other installations "
          f"({plan.other_rows.get('installations', 0)} installation(s)).")


def main(argv: list[str] | None = None, ask=input) -> int:
    parser = argparse.ArgumentParser(description="DEVELOPER ONLY: reset one installation (dry run by default).")
    parser.add_argument("installation_id")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="only count (the default)")
    mode.add_argument("--execute", action="store_true", help="delete, after typing the installation ID")
    parser.add_argument("--production", action="store_true", help="required when the target is production")
    args = parser.parse_args(argv)

    from app.config import settings   # after argparse, so --help works without settings
    try:
        installation_id = parse_installation_id(args.installation_id)
        target = classify_target(settings.database_url, settings.s3_bucket if settings.s3_configured else None)
        if target == "production" and args.execute and not args.production:
            raise Refused("This is the production database: add --production to confirm you mean it.")
        if target != "production" and args.production:
            raise Refused("--production given, but this isn't the production database.")
        bucket = settings.s3_bucket if target == "production" else None
        s3 = None
        if bucket:
            from app import media
            s3 = media._s3()
        database = urlparse(settings.database_url).path.lstrip("/")
        # autocommit: each `with conn.transaction()` below is a real transaction.
        with psycopg.connect(settings.database_url, autocommit=True) as conn:
            if conn.execute("SELECT current_database()").fetchone()[0] != database:
                raise Refused("Connected to a different database than the settings name. Nothing was changed.")
            with conn.transaction():
                conn.execute("SET TRANSACTION READ ONLY")
                plan = make_plan(conn, installation_id, s3, bucket)
            _print_plan(plan, target, database, bucket)
            if not plan.exists:
                print("Nothing to reset.")
                return 2
            if not args.execute:
                print("Dry run: nothing was changed. Add --execute to reset this installation.")
                return 0
            if ask(f"Type the full installation ID to delete its data: ").strip().lower() != installation_id:
                print("Cancelled. Nothing was changed.")
                return 1
            if target == "production" and ask("This is PRODUCTION. Type RESET PRODUCTION: ").strip() != "RESET PRODUCTION":
                print("Cancelled. Nothing was changed.")
                return 1
            try:
                report = execute_reset(conn, installation_id, s3, bucket)
            except PartialReset as error:
                print(f"NOT FINISHED: {error}")
                print("Report:", {k: v for k, v in error.report.items() if v not in (None, {})})
                return 3
    except Refused as error:
        print(f"Refused: {error}")
        return 4
    print("Done:", sum(report["deleted_rows"].values()), "row(s) deleted",
          f"({', '.join(f'{t} {n}' for t, n in report['deleted_rows'].items() if n)}),",
          f"{report['s3_deleted']} photo file(s) deleted" if s3 else "S3 not configured here",
          "| other installations unchanged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
