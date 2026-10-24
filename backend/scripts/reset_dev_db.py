"""
DEVELOPMENT ONLY: deletes every CED table (and all their data) so the
migrations can rebuild the database from scratch.

    python -m scripts.reset_dev_db
    python -m scripts.migrate

It only drops the tables listed below, which all belong to this project,
and asks you to type RESET first. Never run it against a production database.
"""
import psycopg

from app.config import settings

# Children first, so foreign keys never block a drop.
CED_TABLES = [
    "ced_usage",
    "check_in_room_messages",
    "room_messages",
    "affirmation_notes",
    "affirmation_theme_sources",
    "affirmations",
    "affirmation_sources",
    "affirmation_themes",
    "moving_forward_check_ins",
    "activity_research_bases",
    "research_bases",
    "activity_bookmarks",
    "reflections",
    "activity_logs",        # replaced by reflections in 005; kept for older databases
    "scrapbook_photos",
    "activity_selections",
    "recommendations",
    "check_ins",
    "activities",
    "activity_categories",
    "installations",
    "schema_migrations",
]


def main() -> None:
    print("This deletes these tables and ALL their data:")
    for table in CED_TABLES:
        print(f"  - {table}")
    if input("Type RESET to continue: ").strip() != "RESET":
        print("Cancelled. Nothing was changed.")
        return

    with psycopg.connect(settings.database_url) as conn:
        for table in CED_TABLES:
            conn.execute(f"DROP TABLE IF EXISTS {table}")
        conn.execute("DROP FUNCTION IF EXISTS activities_set_category_label()")
    print("Done. Now run: python -m scripts.migrate")


if __name__ == "__main__":
    main()
