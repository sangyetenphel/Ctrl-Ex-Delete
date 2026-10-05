"""
Neon (PostgreSQL) storage.
This is the ONLY file that talks to the database. The routes call these
functions and don't care how the data is stored.
"""
from uuid import UUID

import psycopg
from psycopg.rows import dict_row

from app.config import settings
from app.recommendations import reason_for, recommend
from app.schemas import (
    Activity,
    ActivityLog,
    ActivityLogCreate,
    ActivitySelection,
    CheckIn,
    CheckInCreate,
    RecommendedActivity,
)

# Columns returned to the app, in one place so every query stays consistent.
CHECK_IN_COLUMNS = """
    id, installation_id, feeling, contact_urge, energy_level,
    hardest_areas, local_date, created_at
"""

ACTIVITY_COLUMNS = """
    a.id, a.slug, a.title, a.category, a.category_label,
    a.duration_minutes, a.instructions, a.why_it_fits, a.sort_order
"""

ACTIVITY_FIELDS = list(Activity.model_fields)


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


# ---------- Check-ins ----------

def create_check_in(installation_id: UUID, data: CheckInCreate) -> CheckIn:
    """Saves the check-in AND its recommendations in one transaction,
    so a check-in never exists without its cards."""
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
        check_in = CheckIn(**row)
        _save_recommendations(conn, check_in)
    return check_in


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


# ---------- Activities ----------

def _active_activities(conn: psycopg.Connection) -> list[Activity]:
    rows = conn.execute(
        f"SELECT {ACTIVITY_COLUMNS} FROM activities a "
        "WHERE a.is_active ORDER BY a.sort_order"
    ).fetchall()
    return [Activity(**row) for row in rows]


def list_activities() -> list[Activity]:
    with _connect() as conn:
        return _active_activities(conn)


# ---------- Recommendations ----------

def _save_recommendations(conn: psycopg.Connection, check_in: CheckIn) -> None:
    # Don't re-suggest anything already finished today.
    done_today = {
        r["activity_id"]
        for r in conn.execute(
            """
            SELECT activity_id FROM activity_logs
            WHERE installation_id = %s AND local_date = %s
            """,
            (check_in.installation_id, check_in.local_date),
        ).fetchall()
    }
    picks = recommend(check_in, _active_activities(conn), done_today)

    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO recommendations (installation_id, check_in_id, activity_id, position)
            VALUES (%s, %s, %s, %s)
            """,
            [
                (check_in.installation_id, check_in.id, activity.id, position)
                for position, activity in enumerate(picks, start=1)
            ],
        )


def get_latest_recommendations(installation_id: UUID) -> list[RecommendedActivity] | None:
    """Cards for the most recent check-in. None = no check-in yet."""
    with _connect() as conn:
        row = conn.execute(
            f"""
            SELECT {CHECK_IN_COLUMNS} FROM check_ins
            WHERE installation_id = %s
            ORDER BY created_at DESC LIMIT 1
            """,
            (installation_id,),
        ).fetchone()
        if row is None:
            return None
        check_in = CheckIn(**row)

        rows = conn.execute(
            f"""
            SELECT r.id AS recommendation_id, r.position, {ACTIVITY_COLUMNS}
            FROM recommendations r
            JOIN activities a ON a.id = r.activity_id
            WHERE r.check_in_id = %s
            ORDER BY r.position
            """,
            (check_in.id,),
        ).fetchall()

    results = []
    for r in rows:
        activity = Activity(**{k: r[k] for k in ACTIVITY_FIELDS})
        results.append(
            RecommendedActivity(
                recommendation_id=r["recommendation_id"],
                position=r["position"],
                activity=activity,
                reason=reason_for(check_in, activity),
            )
        )
    return results


def select_recommendation(installation_id: UUID, recommendation_id: int) -> ActivitySelection | None:
    """None = no such recommendation for THIS installation (so nobody can
    select someone else's card). Tapping twice returns the same selection
    instead of erroring, since the table only allows one per recommendation."""
    with _connect() as conn:
        owned = conn.execute(
            "SELECT 1 FROM recommendations WHERE id = %s AND installation_id = %s",
            (recommendation_id, installation_id),
        ).fetchone()
        if owned is None:
            return None

        row = conn.execute(
            """
            INSERT INTO activity_selections (installation_id, recommendation_id, selected_at)
            VALUES (%s, %s, now())
            ON CONFLICT (recommendation_id) DO NOTHING
            RETURNING id, installation_id, recommendation_id, selected_at
            """,
            (installation_id, recommendation_id),
        ).fetchone()
        if row is None:  # already selected earlier
            row = conn.execute(
                """
                SELECT id, installation_id, recommendation_id, selected_at
                FROM activity_selections WHERE recommendation_id = %s
                """,
                (recommendation_id,),
            ).fetchone()
    return ActivitySelection(**row)


# ---------- Activity logs ----------

def create_activity_log(
    installation_id: UUID, activity_id: int, data: ActivityLogCreate
) -> ActivityLog | None:
    """None = activity doesn't exist or isn't active."""
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM activities WHERE id = %s AND is_active", (activity_id,)
        ).fetchone()
        if exists is None:
            return None

        _ensure_installation(conn, installation_id)
        row = conn.execute(
            """
            INSERT INTO activity_logs
                (installation_id, activity_id, mood_after, local_date, completed_at)
            VALUES (%s, %s, %s, %s, now())
            RETURNING id, installation_id, activity_id, mood_after, local_date, completed_at
            """,
            (installation_id, activity_id, data.mood_after, data.local_date),
        ).fetchone()
    return ActivityLog(**row)