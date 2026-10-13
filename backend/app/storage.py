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
    Milestone,
    ProgressSummary,
    Recommendation,
    RecommendationsResponse,
    ReflectionCreate,
    ScrapbookPhotoCreate,
    SelectedActivity,
)


class NotFound(Exception):
    """The record doesn't exist for this installation (the API answers 404)."""


class Conflict(Exception):
    """The request clashes with what is already saved (the API answers 409)."""

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
                   l.completed_at, {ACTIVITY_COLUMNS}
            FROM recommendations r
            JOIN activities a ON a.id = r.activity_id
            LEFT JOIN activity_selections s ON s.recommendation_id = r.id
            LEFT JOIN activity_logs l ON l.activity_selection_id = s.id
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
            completed_at=row.pop("completed_at"),
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


def get_current_selection(installation_id: UUID) -> SelectedActivity | None:
    """
    The activity the user most recently chose with "I'll try this", as long
    as no reflection has been saved for it yet. Choosing another activity
    replaces it; saving its reflection completes it. Either way, earlier
    memories keep pointing at their own selection.
    """
    with _connect() as conn:
        row = conn.execute(
            f"""
            SELECT s.id AS selection_id, s.recommendation_id, r.check_in_id,
                   s.selected_at, l.id AS reflection_id, {ACTIVITY_COLUMNS}
            FROM activity_selections s
            JOIN recommendations r ON r.id = s.recommendation_id
            JOIN activities a ON a.id = r.activity_id
            LEFT JOIN activity_logs l ON l.activity_selection_id = s.id
            WHERE s.installation_id = %s
            ORDER BY s.selected_at DESC, s.id DESC
            LIMIT 1
            """,
            (installation_id,),
        ).fetchone()

    if row is None or row.pop("reflection_id") is not None:
        return None
    return SelectedActivity(
        selection_id=row.pop("selection_id"),
        recommendation_id=row.pop("recommendation_id"),
        check_in_id=row.pop("check_in_id"),
        selected_at=row.pop("selected_at"),
        activity=Activity(**row),
    )


# ─────────────────────────────────────────────
# Scrapbook photos
# ─────────────────────────────────────────────

SCRAPBOOK_COLUMNS = "id, object_key, caption, local_date, created_at"


def create_scrapbook_photo(
    installation_id: UUID, object_key: str, data: ScrapbookPhotoCreate
) -> int:
    """Adds a not-yet-uploaded photo row and returns its id."""
    with _connect() as conn:
        _ensure_installation(conn, installation_id)
        row = conn.execute(
            """
            INSERT INTO scrapbook_photos (installation_id, object_key, caption, local_date)
            VALUES (%s, %s, %s, %s)
            RETURNING id
            """,
            (installation_id, object_key, data.caption, data.local_date),
        ).fetchone()
    return row["id"]


def get_scrapbook_key(installation_id: UUID, photo_id: int) -> str | None:
    """The photo's S3 key, or None if it doesn't exist for this installation."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT object_key FROM scrapbook_photos WHERE id = %s AND installation_id = %s",
            (photo_id, installation_id),
        ).fetchone()
    return row["object_key"] if row else None


def mark_scrapbook_uploaded(installation_id: UUID, photo_id: int, byte_size: int) -> dict:
    with _connect() as conn:
        return conn.execute(
            f"""
            UPDATE scrapbook_photos
            SET uploaded_at = COALESCE(uploaded_at, now()), byte_size = %s
            WHERE id = %s AND installation_id = %s
            RETURNING {SCRAPBOOK_COLUMNS}
            """,
            (byte_size, photo_id, installation_id),
        ).fetchone()


def list_scrapbook_photos(installation_id: UUID) -> list[dict]:
    """Uploaded photos only, newest first."""
    with _connect() as conn:
        return conn.execute(
            f"""
            SELECT {SCRAPBOOK_COLUMNS}
            FROM scrapbook_photos
            WHERE installation_id = %s AND uploaded_at IS NOT NULL
            ORDER BY created_at DESC
            """,
            (installation_id,),
        ).fetchall()


def delete_scrapbook_photo(installation_id: UUID, photo_id: int) -> None:
    with _connect() as conn:
        conn.execute(
            "DELETE FROM scrapbook_photos WHERE id = %s AND installation_id = %s",
            (photo_id, installation_id),
        )


# ─────────────────────────────────────────────
# Reflections (scrapbook memories)
#
# Stored in activity_logs: one row = one completed activity (or a memory
# captured without one). See db/migrations/005_reflections.sql.
# ─────────────────────────────────────────────

REFLECTION_QUERY = """
    SELECT l.id, l.activity_selection_id, l.note, l.noticed,
           l.thought_about_ex, l.mood_change, l.local_date, l.completed_at,
           l.photo_id, p.object_key AS photo_key,
           CASE WHEN a.id IS NULL THEN NULL ELSE to_jsonb(a) END AS activity
    FROM activity_logs l
    LEFT JOIN activities a ON a.id = l.activity_id
    LEFT JOIN scrapbook_photos p ON p.id = l.photo_id AND p.uploaded_at IS NOT NULL
"""


def create_reflection(installation_id: UUID, data: ReflectionCreate) -> tuple[dict, bool]:
    """
    Saves a reflection, which completes its selected activity.
    Returns (reflection row, created). created is False when this selection
    already had a reflection: that one is returned and nothing is added.
    Raises NotFound / Conflict for selections or photos that can't be used.
    """
    with _connect() as conn:
        activity_id = None
        if data.activity_selection_id is not None:
            selection = conn.execute(
                """
                SELECT r.activity_id, l.id AS reflection_id
                FROM activity_selections s
                JOIN recommendations r ON r.id = s.recommendation_id
                LEFT JOIN activity_logs l ON l.activity_selection_id = s.id
                WHERE s.id = %s AND s.installation_id = %s
                """,
                (data.activity_selection_id, installation_id),
            ).fetchone()
            if selection is None:
                raise NotFound("Activity selection not found.")
            if selection["reflection_id"] is not None:
                return _get_reflection(conn, selection["reflection_id"]), False
            activity_id = selection["activity_id"]

        if data.photo_id is not None:
            photo = conn.execute(
                """
                SELECT p.uploaded_at, l.id AS reflection_id
                FROM scrapbook_photos p
                LEFT JOIN activity_logs l ON l.photo_id = p.id
                WHERE p.id = %s AND p.installation_id = %s
                """,
                (data.photo_id, installation_id),
            ).fetchone()
            if photo is None:
                raise NotFound("Photo not found.")
            if photo["uploaded_at"] is None:
                raise Conflict("The photo hasn't been uploaded yet.")
            if photo["reflection_id"] is not None:
                raise Conflict("That photo already belongs to another memory.")

        _ensure_installation(conn, installation_id)
        try:
            inserted = conn.execute(
                """
                INSERT INTO activity_logs
                    (installation_id, activity_id, activity_selection_id, photo_id,
                     note, noticed, thought_about_ex, mood_change, local_date)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (activity_selection_id) DO NOTHING
                RETURNING id
                """,
                (
                    installation_id, activity_id, data.activity_selection_id,
                    data.photo_id, data.note, data.noticed,
                    data.thought_about_ex, data.mood_change, data.local_date,
                ),
            ).fetchone()
        except psycopg.errors.UniqueViolation:
            # Two saves raced for the same photo.
            raise Conflict("That photo already belongs to another memory.") from None

        if inserted is None:
            # Two saves raced for the same selection: return the first one.
            existing = conn.execute(
                "SELECT id FROM activity_logs WHERE activity_selection_id = %s",
                (data.activity_selection_id,),
            ).fetchone()
            return _get_reflection(conn, existing["id"]), False
        return _get_reflection(conn, inserted["id"]), True


def _get_reflection(conn: psycopg.Connection, reflection_id: int) -> dict:
    return conn.execute(f"{REFLECTION_QUERY} WHERE l.id = %s", (reflection_id,)).fetchone()


def list_reflections(installation_id: UUID) -> list[dict]:
    """Every memory, newest first."""
    with _connect() as conn:
        return conn.execute(
            f"""
            {REFLECTION_QUERY}
            WHERE l.installation_id = %s
            ORDER BY l.completed_at DESC, l.id DESC
            """,
            (installation_id,),
        ).fetchall()


# ─────────────────────────────────────────────
# Progress
# ─────────────────────────────────────────────

MILESTONE_ACTIVITY_COUNT = 5


def get_progress_summary(installation_id: UUID) -> ProgressSummary:
    with _connect() as conn:
        row = conn.execute(
            """
            WITH logs AS (
                SELECT * FROM activity_logs WHERE installation_id = %(id)s
            ), done AS (
                SELECT local_date, row_number() OVER (ORDER BY completed_at, id) AS n
                FROM logs WHERE activity_id IS NOT NULL
            )
            SELECT
                (SELECT min(local_date) FROM check_ins
                 WHERE installation_id = %(id)s)                     AS journey_started_on,
                (SELECT count(*) FROM check_ins
                 WHERE installation_id = %(id)s)                     AS check_ins,
                (SELECT count(*) FROM activity_selections
                 WHERE installation_id = %(id)s)                     AS activities_selected,
                (SELECT count(*) FROM done)                          AS activities_completed,
                (SELECT count(*) FROM logs)                          AS memories,
                (SELECT count(*) FROM logs WHERE photo_id IS NOT NULL) AS photos,
                (SELECT local_date FROM done WHERE n = 1)            AS first_activity_on,
                (SELECT local_date FROM done WHERE n = %(goal)s)     AS goal_reached_on,
                (SELECT min(local_date) FROM logs
                 WHERE photo_id IS NOT NULL)                         AS first_photo_on
            """,
            {"id": installation_id, "goal": MILESTONE_ACTIVITY_COUNT},
        ).fetchone()

    milestones = [
        Milestone(label="Started the journey", reached_on=row["journey_started_on"]),
        Milestone(label="Completed a first activity", reached_on=row["first_activity_on"]),
        Milestone(label="Added a first photo memory", reached_on=row["first_photo_on"]),
        Milestone(
            label=f"{MILESTONE_ACTIVITY_COUNT} activities milestone",
            reached_on=row["goal_reached_on"],
        ),
        # Reached once the moving-forward check-in is saved (not stored yet).
        Milestone(label="Moving forward check-in", reached_on=None),
    ]
    return ProgressSummary(
        journey_started_on=row["journey_started_on"],
        check_ins=row["check_ins"],
        activities_selected=row["activities_selected"],
        activities_completed=row["activities_completed"],
        memories=row["memories"],
        photos=row["photos"],
        milestones=milestones,
    )
