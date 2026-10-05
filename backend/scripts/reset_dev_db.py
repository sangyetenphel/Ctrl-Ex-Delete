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
    "activity_selections",
    "recommendations",
    "activity_logs",
    "check_ins",
    "activities",
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
    print("Done. Now run: python -m scripts.migrate")


if __name__ == "__main__":
    main()
