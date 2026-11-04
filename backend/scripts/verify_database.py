"""
Checks the database in DATABASE_URL against the CED schema and the repo's
catalogs. Read-only. Run from the backend/ folder:

    python -m scripts.verify_database           # schema, catalogs, relationships
    python -m scripts.verify_database --fresh   # ...and no user data yet (a new database)

Schema: exactly the expected tables, the baseline migration and no older
history, no triggers, every foreign key validated, and the rules the app
relies on (one check-in per day, one activity in progress, one live choice
per card). Catalogs: every row the seed scripts load, compared with the data
files themselves (scripts/catalog_data.py, affirmation_data.py,
room_message_data.py), including each activity's research links.
"""
import sys

import psycopg

from app import room_messages
from app.config import settings
from scripts import affirmation_data, catalog_data, room_message_data

CATALOG_TABLES = [
    "activity_categories", "activities", "research_bases", "activity_research_bases",
    "affirmation_themes", "affirmations", "affirmation_sources", "affirmation_theme_sources",
    "affirmation_notes", "room_messages",
]
USER_TABLES = [
    "installations", "check_ins", "recommendations", "activity_selections", "scrapbook_photos",
    "reflections", "activity_bookmarks", "check_in_room_messages", "moving_forward_check_ins", "ced_usage",
]
EXPECTED_TABLES = set(CATALOG_TABLES + USER_TABLES + ["schema_migrations"])

# Rules the app depends on: (table, columns, unique?, partial condition or None)
REQUIRED_INDEXES = [
    ("check_ins", "(installation_id, local_date)", True, None),
    ("activity_selections", "(installation_id)", True, "(status = 'in_progress'::text)"),
    ("activity_selections", "(recommendation_id)", True, "(status <> 'abandoned'::text)"),
    ("recommendations", "(activity_id)", False, None),
    ("activity_bookmarks", "(activity_id)", False, None),
    ("reflections", "(installation_id, created_at DESC)", False, None),
]


def check_schema(conn, check) -> None:
    tables = {r[0] for r in conn.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")}
    check("tables", tables == EXPECTED_TABLES,
          ", ".join([f"missing {t}" for t in sorted(EXPECTED_TABLES - tables)]
                    + [f"unexpected {t}" for t in sorted(tables - EXPECTED_TABLES)]))
    versions = [r[0] for r in conn.execute("SELECT version FROM schema_migrations ORDER BY 1")]
    check("migrations: the baseline, no older history", versions[:1] == ["001_schema.sql"], ", ".join(versions))
    triggers = conn.execute("SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal").fetchone()[0]
    check("no triggers", triggers == 0, f"{triggers} found")
    invalid = conn.execute(
        "SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND NOT convalidated").fetchone()[0]
    foreign_keys = conn.execute(
        "SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace").fetchone()[0]
    check(f"{foreign_keys} foreign keys, all validated", invalid == 0, f"{invalid} not validated")
    indexes = conn.execute("SELECT tablename, indexdef FROM pg_indexes WHERE schemaname = 'public'").fetchall()
    for table, columns, unique, where in REQUIRED_INDEXES:
        found = any(
            t == table and f"btree {columns}" in d and ("UNIQUE" in d) == unique
            and (where is None and " WHERE " not in d or where is not None and d.endswith(f"WHERE {where}"))
            for t, d in indexes)
        check(f"index {table} {columns}{' unique' if unique else ''}{' where ' + where if where else ''}", found)


def check_catalogs(conn, check) -> None:
    rows = lambda sql: set(conn.execute(sql).fetchall())
    check("4 categories as in catalog_data.CATEGORIES",
          rows("SELECT category, label, sort_order FROM activity_categories") == set(catalog_data.CATEGORIES))
    check(f"{len(catalog_data.RESEARCH_BASES)} research bases",
          {r[0] for r in rows("SELECT code FROM research_bases")} == set(catalog_data.RESEARCH_BASES))
    expected = catalog_data.activities()
    active = rows("SELECT slug, category, energy_level, duration_minutes, title FROM activities WHERE is_active")
    check(f"{len(expected)} active activities, each as in catalog_data",
          active == {(a["slug"], a["category"], a["energy_level"], a["duration_minutes"], a["title"]) for a in expected},
          f"database has {len(active)}")
    links = rows("SELECT a.slug, l.code FROM activity_research_bases l JOIN activities a ON a.id = l.activity_id WHERE a.is_active")
    expected_links = {(a["slug"], code) for a in expected for code in a["research_codes"]}
    check(f"{len(expected_links)} activity research links", links == expected_links, f"database has {len(links)}")
    without = conn.execute(
        """SELECT count(*) FROM activities a WHERE a.is_active
           AND NOT EXISTS (SELECT 1 FROM activity_research_bases l WHERE l.activity_id = a.id)""").fetchone()[0]
    check("every active activity has a research base", without == 0, f"{without} without")

    check(f"{len(affirmation_data.THEMES)} affirmation themes",
          rows("SELECT code, label FROM affirmation_themes") == set(affirmation_data.THEMES))
    check(f"{len(affirmation_data.AFFIRMATIONS)} active affirmations, each as in affirmation_data",
          rows("SELECT id, theme, text FROM affirmations WHERE is_active") == {a[:3] for a in affirmation_data.AFFIRMATIONS})
    check(f"{len(affirmation_data.SOURCES)} affirmation sources",
          {r[0] for r in rows("SELECT code FROM affirmation_sources")} == set(affirmation_data.SOURCES))
    check(f"{len(affirmation_data.THEME_SOURCES)} theme-source links",
          rows("SELECT theme, source_code FROM affirmation_theme_sources") == {t[:2] for t in affirmation_data.THEME_SOURCES})
    check("every affirmation has its wording note, as in affirmation_data",
          rows("SELECT affirmation_id, note FROM affirmation_notes") == {(a[0], a[3]) for a in affirmation_data.AFFIRMATIONS})

    check(f"{len(room_message_data.CATALOG)} active room messages, each as in room_message_data",
          rows("SELECT id, pattern, text FROM room_messages WHERE is_active") == set(room_message_data.CATALOG))
    patterns = {r[0] for r in rows("SELECT DISTINCT pattern FROM room_messages WHERE is_active")}
    needed = set(room_messages.PRIORITY) | {room_messages.BEFORE_CHECK_IN}
    check("every room-message pattern has a message", needed <= patterns,
          ", ".join(sorted(needed - patterns)))


def check_empty(conn, check) -> None:
    for table in USER_TABLES:
        count = conn.execute(f'SELECT count(*) FROM "{table}"').fetchone()[0]
        check(f"{table} is empty", count == 0, f"{count} rows")


def verify(url: str, fresh: bool = False) -> bool:
    ok = True

    def check(label: str, good: bool, detail: str = "") -> None:
        nonlocal ok
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'}  {label}{f'  ({detail})' if detail and not good else ''}")

    with psycopg.connect(url) as conn:
        conn.read_only = True
        print("Schema"); check_schema(conn, check)
        print("Catalogs"); check_catalogs(conn, check)
        if fresh:
            print("No user data yet"); check_empty(conn, check)
    return ok


def main() -> int:
    ok = verify(settings.database_url, fresh="--fresh" in sys.argv)
    print("Database verified." if ok else "Problems found (see above).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
