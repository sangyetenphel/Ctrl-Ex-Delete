"""
Loads Ced's room messages (scripts/room_message_data.py).

    python -m scripts.seed_room_messages

Safe to run any number of times: messages are inserted or updated by id and
never deleted (one that left the catalog is only set inactive). Messages
already given to check-ins keep their original text. `scripts.migrate` runs
this after migrating.
"""
import psycopg

from app.config import settings
from scripts.room_message_data import CATALOG


def seed(conn: psycopg.Connection) -> dict:
    inserted = updated = 0
    for order, (message_id, pattern, text) in enumerate(CATALOG, start=1):
        created = conn.execute(
            """INSERT INTO room_messages (id, pattern, text, is_active, sort_order)
               VALUES (%s, %s, %s, TRUE, %s)
               ON CONFLICT (id) DO UPDATE SET
                   pattern = EXCLUDED.pattern, text = EXCLUDED.text, is_active = TRUE,
                   sort_order = EXCLUDED.sort_order,
                   updated_at = CASE WHEN (room_messages.pattern, room_messages.text, room_messages.is_active,
                                           room_messages.sort_order)
                                          IS DISTINCT FROM (EXCLUDED.pattern, EXCLUDED.text, TRUE, EXCLUDED.sort_order)
                                     THEN now() ELSE room_messages.updated_at END
               RETURNING (xmax = 0)""",
            (message_id, pattern, text, order),
        ).fetchone()[0]
        inserted += created
        updated += not created
    retired = conn.execute(
        "UPDATE room_messages SET is_active = FALSE, updated_at = now() WHERE is_active AND NOT (id = ANY(%s))",
        ([m[0] for m in CATALOG],),
    ).rowcount
    active = conn.execute("SELECT count(*) FROM room_messages WHERE is_active").fetchone()[0]
    return {"inserted": inserted, "updated": updated, "retired": retired, "active": active}


def main() -> None:
    with psycopg.connect(settings.database_url) as conn:
        counts = seed(conn)
    print(f"Room messages loaded: {counts['active']} active ({counts['inserted']} new, "
          f"{counts['updated']} updated, {counts['retired']} retired).")


if __name__ == "__main__":
    main()
