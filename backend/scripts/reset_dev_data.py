"""
DEVELOPMENT ONLY: deletes all user data, so the app starts fresh.

    python -m scripts.reset_dev_data                     # asks you to type RESET DATA
    python -m scripts.reset_dev_data --yes-delete-all-test-data
    python -m scripts.reset_dev_data --database-only    # S3 files stay; listed instead

What it deletes:
- Every installation and everything that belongs to one: check-ins, their
  recommendations, "I'll try this" selections, bookmarks, reflections
  (memories and notes), photo records, and usage records (ced_usage, if that
  table exists).
- The uploaded photo files in S3 under this app's upload formats only
  (UPLOAD_KEY_PATTERNS), including any orphaned ones and, when the AWS user is
  allowed to list them, their old versions and delete markers.

What it keeps: the activity catalog, categories, research sources and links,
the schema and migration history, and anything else in the bucket (other
prefixes, files that don't match the upload formats, the bucket's settings).

Order: photo keys are collected first, files are deleted from S3 next, and
the database rows are deleted last, in one transaction, only if every S3
deletion worked (so a failed run can simply be repeated).

--database-only is for when the AWS user can't delete objects: the database
is still reset, and the upload files left in S3 are listed. They stay
findable (the upload prefixes and key formats above), so a later full run,
with delete permission, removes them as orphans.

Normal startup, `scripts.migrate` and `scripts.seed_catalog` never delete user
data. To drop the tables themselves, see scripts/reset_dev_db.py.
"""
import re
import sys

import psycopg
from botocore.exceptions import ClientError

from app import media
from app.config import settings

CONFIRM_FLAG = "--yes-delete-all-test-data"
DATABASE_ONLY_FLAG = "--database-only"

# User data, children first. Every table with a foreign key to installations
# must be here; reset() refuses to run if it finds one that isn't.
USER_TABLES = [
    "reflections",
    "scrapbook_photos",
    "activity_bookmarks",
    "activity_selections",
    "recommendations",
    "check_ins",
    "ced_usage",          # a teammate's usage counter; skipped if it doesn't exist
    "installations",
]

# The S3 keys this app creates (app/media.py, older uploads, scripts/check_s3.py).
UPLOAD_PREFIXES = ["scrapbook/", "installations/"]
UPLOAD_KEY_PATTERNS = [
    re.compile(r"^scrapbook/[0-9a-f]{32}\.jpg$"),
    re.compile(r"^installations/[0-9a-f-]{32,36}/[0-9a-f-]{32,36}\.jpg$"),
    re.compile(r"^scrapbook/_check-s3-[0-9a-f]{32}\.txt$"),
]


def is_upload_key(key: str) -> bool:
    return any(pattern.match(key) for pattern in UPLOAD_KEY_PATTERNS)


def _existing_tables(conn: psycopg.Connection) -> set[str]:
    return {row[0] for row in conn.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")}


def _tables_referencing_installations(conn: psycopg.Connection) -> set[str]:
    return {row[0] for row in conn.execute(
        """SELECT conrelid::regclass::text FROM pg_constraint
           WHERE contype = 'f' AND confrelid = 'installations'::regclass""")}


def inventory_s3(s3, bucket: str) -> dict:
    """Current objects and (if allowed) every version under the upload prefixes."""
    objects, skipped = set(), set()
    for prefix in UPLOAD_PREFIXES:
        for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
            for item in page.get("Contents", []):
                (objects if is_upload_key(item["Key"]) else skipped).add(item["Key"])
    versions, versions_listable = [], True
    try:
        for prefix in UPLOAD_PREFIXES:
            for page in s3.get_paginator("list_object_versions").paginate(Bucket=bucket, Prefix=prefix):
                for item in page.get("Versions", []) + page.get("DeleteMarkers", []):
                    if is_upload_key(item["Key"]):
                        versions.append({"Key": item["Key"], "VersionId": item["VersionId"]})
    except ClientError as error:
        if error.response["Error"]["Code"] not in ("AccessDenied", "AllAccessDisabled"):
            raise
        versions_listable = False
    return {"objects": objects, "skipped": skipped, "versions": versions, "versions_listable": versions_listable}


def _delete_batch(s3, bucket: str, items: list[dict]) -> list[str]:
    """Deletes up to 1000 keys/versions at a time; returns the ones that failed."""
    failed = []
    for start in range(0, len(items), 1000):
        result = s3.delete_objects(Bucket=bucket, Delete={"Objects": items[start:start + 1000], "Quiet": True})
        failed += [f"{e['Key']}: {e.get('Code')}" for e in result.get("Errors", [])]
    return failed


def reset(conn: psycopg.Connection, s3=None, bucket: str | None = None, delete_s3: bool = True) -> dict:
    """
    Runs the whole reset. `s3` is a boto3 client (or a test double); None skips
    S3 entirely. With delete_s3=False the files are only listed (report's
    "left_in_s3"). Returns a report; raises if anything would be left half-done.
    """
    existing = _existing_tables(conn)
    unknown = _tables_referencing_installations(conn) - set(USER_TABLES)
    if unknown:
        raise RuntimeError(f"These tables hold user data but aren't in USER_TABLES: {sorted(unknown)}")

    # 1. Inventory before anything is deleted.
    db_keys = {row[0] for row in conn.execute("SELECT object_key FROM scrapbook_photos")}
    report = {"db_photo_keys": len(db_keys), "s3": None}

    # 2. S3: the files, then their old versions / delete markers if visible.
    if s3 is not None and not delete_s3:
        found = inventory_s3(s3, bucket)
        report["s3"] = {"deleted": False, "left_in_s3": sorted(found["objects"]),
                        "versions_listable": found["versions_listable"]}
    elif s3 is not None:
        found = inventory_s3(s3, bucket)
        # Every file the database knows about plus orphans under the upload
        # prefixes, limited to the app's own key formats.
        targets = sorted(key for key in db_keys | found["objects"] if is_upload_key(key))
        failed = _delete_batch(s3, bucket, [{"Key": key} for key in targets])
        after = inventory_s3(s3, bucket)  # versions created by step above included
        failed += _delete_batch(s3, bucket, after["versions"]) if after["versions_listable"] else []
        final = inventory_s3(s3, bucket)
        report["s3"] = {
            "objects_before": len(found["objects"]),
            "orphans_before": len(found["objects"] - db_keys),
            "db_keys_without_file": len({k for k in db_keys if is_upload_key(k)} - found["objects"]),
            "delete_requests": len(targets),
            "versions_deleted": len(after["versions"]) if after["versions_listable"] else None,
            "versions_listable": final["versions_listable"],
            "objects_after": len(final["objects"]),
            "versions_after": len(final["versions"]) if final["versions_listable"] else None,
            "left_alone_in_prefixes": sorted(found["skipped"]),
            "db_keys_outside_upload_formats": sorted(k for k in db_keys if not is_upload_key(k)),
            "failed": failed,
        }
        if failed or final["objects"]:
            raise RuntimeError(f"S3 cleanup incomplete, database left untouched: {report['s3']}")

    # 3. The database, children first, in this transaction.
    deleted = {}
    for table in USER_TABLES:
        if table in existing:
            deleted[table] = conn.execute(f"DELETE FROM {table}").rowcount
    report["deleted_rows"] = deleted
    return report


def main() -> None:
    bucket = settings.s3_bucket if settings.s3_configured else None
    database = settings.database_url.rsplit("/", 1)[-1].split("?")[0]
    delete_s3 = DATABASE_ONLY_FLAG not in sys.argv
    print(f"This deletes ALL user data in database '{database}'"
          + (f" and the app's photo uploads in S3 bucket '{bucket}' ({', '.join(UPLOAD_PREFIXES)})."
             if bucket and delete_s3 else ". S3 files are kept and listed." if bucket else "."))
    print("The activity catalog, research sources and schema are kept.")
    if CONFIRM_FLAG not in sys.argv and input("Type RESET DATA to continue: ").strip() != "RESET DATA":
        print("Cancelled. Nothing was changed.")
        return
    with psycopg.connect(settings.database_url) as conn:
        report = reset(conn, media._s3() if bucket else None, bucket, delete_s3)
    print("Done.", report)


if __name__ == "__main__":
    main()
