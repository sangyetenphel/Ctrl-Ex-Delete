"""
Neon (PostgreSQL) storage.
This is the ONLY file that talks to the database. The routes call these
functions and don't care how the data is stored.
"""
from uuid import UUID

import psycopg
from psycopg.rows import dict_row

from app.config import settings
from app.schemas import CheckIn, CheckInCreate

# Columns returned to the app, in one place so every query stays consistent.
CHECK_IN_COLUMNS = """
    id, installation_id, feeling, contact_urge, energy_level,
    hardest_areas, local_date, created_at
"""


def _connect() -> psycopg.Connection:
    # dict_row makes each row a dict, so it can be passed straight into CheckIn(**row).
    # Using "with _connect() as conn" commits automatically when the block ends
    # (or rolls back if something fails).
    return psycopg.connect(settings.database_url, row_factory=dict_row)


def _ensure_installation(conn: psycopg.Connection, installation_id: UUID) -> None:
    # First time we see this ID: add it. Every time after: update last_seen_at.
    conn.execute(
        """
        INSERT INTO installations (id) VALUES (%s)
        ON CONFLICT (id) DO UPDATE SET last_seen_at = now()
        """,
        (installation_id,),
    )


def create_check_in(installation_id: UUID, data: CheckInCreate) -> CheckIn:
    with _connect() as conn:
        _ensure_installation(conn, installation_id)
        row = conn.execute(
            f"""
            INSERT INTO check_ins
                (installation_id, feeling, contact_urge, energy_level,
                 hardest_areas, local_date)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING {CHECK_IN_COLUMNS}
            """,
            (
                installation_id,
                data.feeling,
                data.contact_urge,
                data.energy_level,
                data.hardest_areas,
                data.local_date,
            ),
        ).fetchone()
    return CheckIn(**row)


def list_check_ins(installation_id: UUID) -> list[CheckIn]:
    with _connect() as conn:
        rows = conn.execute(
            f"""
            SELECT {CHECK_IN_COLUMNS}
            FROM check_ins
            WHERE installation_id = %s
            ORDER BY created_at DESC
            """,
            (installation_id,),
        ).fetchall()
    return [CheckIn(**row) for row in rows]