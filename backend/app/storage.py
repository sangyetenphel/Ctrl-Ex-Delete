"""
Neon (PostgreSQL) storage.
This is the ONLY file that talks to the database. The routes call these
functions and don't care how the data is stored.
"""
from uuid import UUID

import psycopg
from psycopg.rows import dict_row

from app import recommendation_rules
from app.config import settings
from app.schemas import (
    Activity,
    ActivitySelection,
    CheckIn,
    CheckInCreate,
    Recommendation,
    RecommendationsResponse,
)

# Columns returned to the app, in one place so every query stays consistent.
CHECK_IN_COLUMNS = """
    id, installation_id, feeling, contact_urge, energy_level,
    hardest_areas, local_date, created_at
"""

ACTIVITY_COLUMNS = """
    a.id, a.slug, a.title, a.category, a.category_label,
    a.duration_minutes, a.instructions, a.why_it_fits
"""


def _connect() -> psycopg.Connection:
    # dict_row makes each row a dict, so it can be passed straight into CheckIn(**row).
    # Using "with _connect() as conn" commits automatically when the block ends
    # (or rolls back if something fails).
    # connect_timeout: give up after 10 seconds instead of leaving the app waiting.
    return psycopg.connect(settings.database_url, row_factory=dict_row, connect_timeout=10)


def _ensure_installation(conn: psycopg.Connection, installation_id: UUID) -> None:
    # First time we see this ID: add it. Every time after: update last_seen_at.
    conn.execute(
        """
        INSERT INTO installations (id) VALUES (%s)
        ON CONFLICT (id) DO UPDATE SET last_seen_at = now()
        """,
        (installation_id,),
    )


# ─────────────────────────────────────────────
# Check-ins
# ─────────────────────────────────────────────

def create_check_in(installation_id: UUID, data: CheckInCreate) -> CheckIn:
    """
    Saves the check-in AND its recommendations in one transaction, so a saved
    check-in always has its recommendations ready for the Activities screen.
    """
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
        _create_recommendations(conn, check_in)
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


# ─────────────────────────────────────────────
# Recommendations
# ─────────────────────────────────────────────

def _create_recommendations(conn: psycopg.Connection, check_in: CheckIn) -> None:
    active_activities = conn.execute(
        "SELECT * FROM activities WHERE is_active ORDER BY sort_order, id"
    ).fetchall()
    activity_ids = recommendation_rules.choose_activity_ids(check_in, active_activities)

    for position, activity_id in enumerate(activity_ids, start=1):
        conn.execute(
            """
            INSERT INTO recommendations
                (installation_id, check_in_id, activity_id, position)
            VALUES (%s, %s, %s, %s)
            """,
            (check_in.installation_id, check_in.id, activity_id, position),
        )


def get_latest_recommendations(installation_id: UUID) -> RecommendationsResponse:
    """Recommendations for this installation's most recent check-in."""
    with _connect() as conn:
        latest = conn.execute(
            """
            SELECT id, local_date
            FROM check_ins
            WHERE installation_id = %s
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            (installation_id,),
        ).fetchone()

        if latest is None:
            return RecommendationsResponse(
                check_in_id=None, check_in_local_date=None, recommendations=[]
            )

        rows = conn.execute(
            f"""
            SELECT r.id AS recommendation_id, r.position, s.selected_at,
                   {ACTIVITY_COLUMNS}
            FROM recommendations r
            JOIN activities a ON a.id = r.activity_id
            LEFT JOIN activity_selections s ON s.recommendation_id = r.id
            WHERE r.check_in_id = %s AND r.installation_id = %s
            ORDER BY r.position
            """,
            (latest["id"], installation_id),
        ).fetchall()

    recommendations = [
        Recommendation(
            id=row.pop("recommendation_id"),
            position=row.pop("position"),
            selected_at=row.pop("selected_at"),
            activity=Activity(**row),
        )
        for row in rows
    ]
    return RecommendationsResponse(
        check_in_id=latest["id"],
        check_in_local_date=latest["local_date"],
        recommendations=recommendations,
    )


# ─────────────────────────────────────────────
# Activity selection ("I'll try this")
# ─────────────────────────────────────────────

SELECTION_QUERY = """
    SELECT s.id, s.recommendation_id, r.activity_id, r.check_in_id, s.selected_at
    FROM activity_selections s
    JOIN recommendations r ON r.id = s.recommendation_id
    WHERE s.recommendation_id = %s
"""


def select_recommendation(
    installation_id: UUID, recommendation_id: int
) -> tuple[ActivitySelection, bool] | None:
    """
    Records that the user picked this recommendation.
    Returns (selection, created). created is False if it was already picked.
    Returns None if the recommendation doesn't exist for this installation.
    """
    with _connect() as conn:
        owned = conn.execute(
            "SELECT 1 FROM recommendations WHERE id = %s AND installation_id = %s",
            (recommendation_id, installation_id),
        ).fetchone()
        if owned is None:
            return None

        _ensure_installation(conn, installation_id)
        inserted = conn.execute(
            """
            INSERT INTO activity_selections (installation_id, recommendation_id)
            VALUES (%s, %s)
            ON CONFLICT (recommendation_id) DO NOTHING
            RETURNING id
            """,
            (installation_id, recommendation_id),
        ).fetchone()

        row = conn.execute(SELECTION_QUERY, (recommendation_id,)).fetchone()
    return ActivitySelection(**row), inserted is not None
