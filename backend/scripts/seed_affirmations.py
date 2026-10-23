"""
Loads the affirmation catalog (scripts/affirmation_data.py) into the database.

    python -m scripts.seed_affirmations

Safe to run any number of times. Themes, sources, links and affirmations are
inserted or updated by their key; nothing is duplicated and no affirmation is
ever deleted: one that left the catalog is only set inactive (the game stops
showing it). `python -m scripts.migrate` runs this after migrating.
"""
import psycopg

from app.config import settings
from scripts.affirmation_data import AFFIRMATIONS, SOURCES, THEME_SOURCES, THEMES


def seed(conn: psycopg.Connection) -> dict:
    for order, (code, label) in enumerate(THEMES, start=1):
        conn.execute(
            """INSERT INTO affirmation_themes (code, label, sort_order) VALUES (%s, %s, %s)
               ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, sort_order = EXCLUDED.sort_order""",
            (code, label, order),
        )
    for code, source in SOURCES.items():
        conn.execute(
            """INSERT INTO affirmation_sources (code, citation, url, kind, finding, limitations)
               VALUES (%(code)s, %(citation)s, %(url)s, %(kind)s, %(finding)s, %(limitations)s)
               ON CONFLICT (code) DO UPDATE SET citation = EXCLUDED.citation, url = EXCLUDED.url,
                   kind = EXCLUDED.kind, finding = EXCLUDED.finding, limitations = EXCLUDED.limitations""",
            {"code": code, **source},
        )
    # Links are editorial (not user data): keep exactly the catalog's.
    conn.execute("DELETE FROM affirmation_theme_sources")
    for theme, source, principle, rationale in THEME_SOURCES:
        conn.execute(
            """INSERT INTO affirmation_theme_sources (theme, source_code, principle, rationale)
               VALUES (%s, %s, %s, %s)""",
            (theme, source, principle, rationale),
        )

    inserted = updated = 0
    for order, (affirmation_id, theme, text, note) in enumerate(AFFIRMATIONS, start=1):
        created = conn.execute(
            """INSERT INTO affirmations (id, text, theme, language, is_active, sort_order)
               VALUES (%s, %s, %s, 'en', TRUE, %s)
               ON CONFLICT (id) DO UPDATE SET
                   text = EXCLUDED.text, theme = EXCLUDED.theme, is_active = TRUE,
                   sort_order = EXCLUDED.sort_order,
                   updated_at = CASE WHEN (affirmations.text, affirmations.theme, affirmations.is_active,
                                           affirmations.sort_order)
                                          IS DISTINCT FROM (EXCLUDED.text, EXCLUDED.theme, TRUE, EXCLUDED.sort_order)
                                     THEN now() ELSE affirmations.updated_at END
               RETURNING (xmax = 0)""",
            (affirmation_id, text, theme, order),
        ).fetchone()[0]
        inserted += created
        updated += not created
        conn.execute(
            """INSERT INTO affirmation_notes (affirmation_id, note) VALUES (%s, %s)
               ON CONFLICT (affirmation_id) DO UPDATE SET note = EXCLUDED.note""",
            (affirmation_id, note),
        )
    retired = conn.execute(
        """UPDATE affirmations SET is_active = FALSE, updated_at = now()
           WHERE is_active AND NOT (id = ANY(%s))""",
        ([a[0] for a in AFFIRMATIONS],),
    ).rowcount
    active = conn.execute("SELECT count(*) FROM affirmations WHERE is_active").fetchone()[0]
    return {"inserted": inserted, "updated": updated, "retired": retired, "active": active}


def main() -> None:
    with psycopg.connect(settings.database_url) as conn:
        counts = seed(conn)
    print(f"Affirmations loaded: {counts['active']} active ({counts['inserted']} new, "
          f"{counts['updated']} updated, {counts['retired']} retired).")


if __name__ == "__main__":
    main()
