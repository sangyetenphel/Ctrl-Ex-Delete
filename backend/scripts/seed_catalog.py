"""
Loads the activity catalog (scripts/catalog_data.py) into the database.

    python -m scripts.seed_catalog

Safe to run any number of times, and it never deletes user history:
- Research approaches and activities are inserted or updated by their key
  (code / slug), so nothing is duplicated.
- The four categories (names and order) are inserted or updated first; an
  activity's category name is always read from them, never copied.
- An activity that isn't in the catalog any more is deleted if nothing
  points at it. If someone was recommended, chose or saved it, it's retired
  instead (is_active = false: never recommended again, history intact) and a
  warning is printed. To remove it completely, wipe the test data with
  `python -m scripts.reset_dev_data` and run this again.
So on a database without old history (a fresh one, or after a reset), the
activities table ends with exactly the catalog, all active.

`python -m scripts.migrate` runs this automatically after applying migrations.
To wipe the development database instead, see scripts/reset_dev_db.py.
"""
import psycopg

from app.config import settings
from scripts.catalog_data import CATEGORIES, RESEARCH_BASES, activities


def seed(conn: psycopg.Connection) -> dict:
    """Loads the catalog in the current transaction and returns counts."""
    for category, label, order in CATEGORIES:
        conn.execute(
            """
            INSERT INTO activity_categories (category, label, sort_order) VALUES (%s, %s, %s)
            ON CONFLICT (category) DO UPDATE SET label = EXCLUDED.label, sort_order = EXCLUDED.sort_order
            """,
            (category, label, order),
        )
    for code, base in RESEARCH_BASES.items():
        conn.execute(
            """
            INSERT INTO research_bases (code, approach, citation, url, evidence_scope)
            VALUES (%(code)s, %(approach)s, %(citation)s, %(url)s, %(evidence_scope)s)
            ON CONFLICT (code) DO UPDATE SET
                approach = EXCLUDED.approach, citation = EXCLUDED.citation,
                url = EXCLUDED.url, evidence_scope = EXCLUDED.evidence_scope
            """,
            {"code": code, **base},
        )

    rows = activities()
    inserted = updated = 0
    for row in rows:
        result = conn.execute(
            """
            INSERT INTO activities
                (slug, title, category, energy_level, duration_minutes,
                 involves_movement, instructions, why_it_fits, evidence_note,
                 sort_order, is_active)
            VALUES (%(slug)s, %(title)s, %(category)s, %(energy_level)s, %(duration_minutes)s,
                    %(involves_movement)s, %(instructions)s, %(why_it_fits)s, %(evidence_note)s,
                    %(sort_order)s, TRUE)
            ON CONFLICT (slug) DO UPDATE SET
                title = EXCLUDED.title,
                category = EXCLUDED.category,
                energy_level = EXCLUDED.energy_level,
                duration_minutes = EXCLUDED.duration_minutes,
                involves_movement = EXCLUDED.involves_movement,
                instructions = EXCLUDED.instructions,
                why_it_fits = EXCLUDED.why_it_fits,
                evidence_note = EXCLUDED.evidence_note,
                sort_order = EXCLUDED.sort_order,
                is_active = TRUE
            RETURNING id, (xmax = 0) AS inserted
            """,
            row,
        ).fetchone()
        activity_id, was_inserted = result
        inserted += was_inserted
        updated += not was_inserted

        conn.execute("DELETE FROM activity_research_bases WHERE activity_id = %s", (activity_id,))
        for code in row["research_codes"]:
            conn.execute(
                "INSERT INTO activity_research_bases (activity_id, code) VALUES (%s, %s)",
                (activity_id, code),
            )

    removed, retired = remove_activities_not_in(conn, [row["slug"] for row in rows])

    total, active = conn.execute(
        "SELECT count(*), count(*) FILTER (WHERE is_active) FROM activities").fetchone()
    return {"inserted": inserted, "reused": updated, "removed": removed, "retired": retired,
            "total": total, "active": active}


def remove_activities_not_in(conn: psycopg.Connection, slugs: list[str]) -> tuple[int, int]:
    """
    Activities whose slug isn't in `slugs`: deleted when nothing points at
    them, retired (kept with their history) otherwise. Returns (deleted, retired).
    """
    rows = conn.execute(
        """
        SELECT a.id, a.slug,
               EXISTS (SELECT 1 FROM recommendations r WHERE r.activity_id = a.id)
               OR EXISTS (SELECT 1 FROM activity_bookmarks b WHERE b.activity_id = a.id) AS has_history
        FROM activities a
        WHERE NOT (a.slug = ANY(%s))
        """,
        (slugs,),
    ).fetchall()
    unused = [activity_id for activity_id, _, has_history in rows if not has_history]
    kept = [(activity_id, slug) for activity_id, slug, has_history in rows if has_history]
    conn.execute("DELETE FROM activities WHERE id = ANY(%s)", (unused,))  # and their research links
    conn.execute("UPDATE activities SET is_active = FALSE WHERE id = ANY(%s)", ([i for i, _ in kept],))
    if kept:
        print(f"Warning: {len(kept)} activities left the catalog but have user history, so they were "
              f"retired instead of deleted: {', '.join(slug for _, slug in kept)}. "
              "Run `python -m scripts.reset_dev_data` to wipe test data, then seed again.")
    return len(unused), len(kept)


def main() -> None:
    with psycopg.connect(settings.database_url) as conn:
        counts = seed(conn)
    print(
        f"Catalog loaded: {counts['total']} activities, {counts['active']} active "
        f"({counts['inserted']} new, {counts['reused']} updated, {counts['removed']} removed, "
        f"{counts['retired']} retired)."
    )


if __name__ == "__main__":
    main()
