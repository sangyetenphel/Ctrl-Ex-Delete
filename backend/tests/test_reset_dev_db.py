"""
scripts/reset_dev_db.py drops the tables in CED_TABLES. Every branch that adds
a migration must add its tables there too, or a reset leaves them behind (and
their foreign keys can block dropping installations). Read-only: it only looks
at the migrated test database's table names.
"""
import psycopg

from app.config import settings
from scripts import reset_dev_db


def test_reset_lists_every_table_the_migrations_create():
    with psycopg.connect(settings.database_url) as conn:
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
            )
        }
    assert tables - set(reset_dev_db.CED_TABLES) == set()
