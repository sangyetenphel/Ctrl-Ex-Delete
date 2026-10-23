"""
Neon (PostgreSQL) storage.
This is the ONLY file that talks to the database. The routes call these
functions and don't care how the data is stored.
"""
from datetime import date
from uuid import UUID

import psycopg
from psycopg.rows import dict_row

from app import recommendation_rules
from app.config import settings
from app.schemas import (
    Activity,
    ActivitySelection,
    Bookmark,
    CheckIn,
    CheckInAnswers,
    CheckInCreate,
    CheckInStatus,
    Bookshelf,
    ShelfBook,
    MovingForward,
    MovingForwardSave,
    Milestone,
    ProgressSummary,
    Recommendation,
    RecommendationsResponse,
    ReflectionCreate,
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

# category_label is kept in step with activity_categories by the database
# (migration 011), so it's the same name everywhere.
ACTIVITY_COLUMNS = """
    a.id, a.slug, a.title, a.category, a.category_label, a.energy_level,
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

def create_check_in(installation_id: UUID, data: CheckInCreate) -> tuple[CheckIn, bool]:
    """
    Saves the check-in AND its recommendations in one transaction, so a saved
    check-in always has its recommendations ready for the Activities screen.

    One check-in per local calendar day (migration 014): if this installation
    already checked in on data.local_date, nothing is added and that check-in
    is returned instead. This also covers a repeated tap, a retry after a lost
    response, and two requests at once (the second waits on the unique index,
    then finds the first). Returns (check_in, created).
    """
    with _connect() as conn:
        _ensure_installation(conn, installation_id)
        row = conn.execute(
            f"""
            INSERT INTO check_ins
                (installation_id, feeling, contact_urge, energy_level,
                 hardest_areas, local_date)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (installation_id, local_date) WHERE counts_for_day DO NOTHING
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
        if row is None:
            return _check_in_for_day(conn, installation_id, data.local_date), False
        check_in = CheckIn(**row)
        _create_recommendations(conn, check_in)
    return check_in, True


def _check_in_for_day(conn: psycopg.Connection, installation_id: UUID, local_date: date) -> CheckIn | None:
    row = conn.execute(
        f"""
        SELECT {CHECK_IN_COLUMNS} FROM check_ins
        WHERE installation_id = %s AND local_date = %s AND counts_for_day
        """,
        (installation_id, local_date),
    ).fetchone()
    return CheckIn(**row) if row else None


def get_check_in_status(installation_id: UUID, local_date: date) -> CheckInStatus:
    """Whether this installation already checked in on its local day `local_date`."""
    with _connect() as conn:
        check_in = _check_in_for_day(conn, installation_id, local_date)
        has_any = check_in is not None or conn.execute(
            "SELECT EXISTS (SELECT 1 FROM check_ins WHERE installation_id = %s)", (installation_id,)
        ).fetchone()["exists"]
    return CheckInStatus(local_date=local_date, check_in=check_in, has_any_check_in=has_any)


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
    # Saved activities, except ones completed in the last few days: those wait
    # a bit before they can be offered again (as the last card, if they suit
    # today's check-in).
    saved_ids = {
        row["activity_id"]
        for row in conn.execute(
            """
            SELECT b.activity_id
            FROM activity_bookmarks b
            WHERE b.installation_id = %(installation)s
              AND NOT EXISTS (
                  SELECT 1
                  FROM activity_selections s
                  JOIN recommendations r ON r.id = s.recommendation_id
                  WHERE s.installation_id = %(installation)s
                    AND r.activity_id = b.activity_id
                    AND s.status = 'completed'
                    AND s.completed_on > %(today)s::date - %(days)s
              )
            """,
            {
                "installation": check_in.installation_id,
                "today": check_in.local_date,
                "days": recommendation_rules.SAVED_COMPLETED_HIDE_DAYS,
            },
        ).fetchall()
    }
    # Activities shown in this installation's last few check-ins (not this one)
    # or completed in the last few days, so the rules can skip them and the
    # deck feels fresh day to day.
    recent_ids = {
        row["activity_id"]
        for row in conn.execute(
            """
            SELECT r.activity_id
            FROM recommendations r
            WHERE r.installation_id = %(installation)s
              AND r.check_in_id IN (
                  SELECT id FROM check_ins
                  WHERE installation_id = %(installation)s AND id <> %(check_in)s
                  ORDER BY created_at DESC, id DESC
                  LIMIT %(window)s
              )
            UNION
            SELECT r.activity_id
            FROM activity_selections s
            JOIN recommendations r ON r.id = s.recommendation_id
            WHERE s.installation_id = %(installation)s
              AND s.status = 'completed'
              AND s.completed_on > %(today)s::date - %(days)s
            """,
            {
                "installation": check_in.installation_id,
                "check_in": check_in.id,
                "window": recommendation_rules.REPEAT_WINDOW,
                "today": check_in.local_date,
                "days": recommendation_rules.RECENTLY_COMPLETED_DAYS,
            },
        ).fetchall()
    }
    activity_ids = recommendation_rules.choose_activity_ids(
        check_in, active_activities, saved_ids, recent_ids
    )

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
            SELECT id, local_date, feeling, contact_urge, energy_level, hardest_areas
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
            SELECT r.id AS recommendation_id, r.position,
                   s.status, s.selected_at,
                   CASE WHEN s.status = 'completed' THEN s.ended_at END AS completed_at,
                   (b.activity_id IS NOT NULL) AS is_saved, {ACTIVITY_COLUMNS}
            FROM recommendations r
            JOIN activities a ON a.id = r.activity_id
            -- At most one attempt per card that wasn't abandoned.
            LEFT JOIN activity_selections s
                   ON s.recommendation_id = r.id AND s.status <> 'abandoned'
            LEFT JOIN activity_bookmarks b
                   ON b.installation_id = r.installation_id AND b.activity_id = r.activity_id
            WHERE r.check_in_id = %s AND r.installation_id = %s
              -- A retired activity is only shown if it was already chosen.
              AND (a.is_active OR s.status IS NOT NULL)
            ORDER BY r.position
            LIMIT %s
            """,
            (latest["id"], installation_id, recommendation_rules.MAX_RECOMMENDATIONS),
        ).fetchall()

    recommendations = [
        Recommendation(
            id=row.pop("recommendation_id"),
            position=row.pop("position"),
            status=row.pop("status"),
            is_saved=row.pop("is_saved"),
            selected_at=row.pop("selected_at"),
            completed_at=row.pop("completed_at"),
            activity=Activity(**row),
        )
        for row in rows
    ]
    return RecommendationsResponse(
        check_in_id=latest["id"],
        check_in_local_date=latest["local_date"],
        check_in=CheckInAnswers(
            feeling=latest["feeling"],
            contact_urge=latest["contact_urge"],
            energy_level=latest["energy_level"],
            hardest_areas=latest["hardest_areas"],
        ),
        recommendations=recommendations,
    )


# ─────────────────────────────────────────────
# Activity selection ("I'll try this")
# ─────────────────────────────────────────────

SELECTION_QUERY = """
    SELECT s.id, s.recommendation_id, r.activity_id, r.check_in_id,
           s.status, s.selected_at, s.ended_at
    FROM activity_selections s
    JOIN recommendations r ON r.id = s.recommendation_id
    WHERE s.id = %s
"""


def select_recommendation(
    installation_id: UUID, recommendation_id: int
) -> tuple[ActivitySelection, bool]:
    """
    "I'll try this": starts this activity (status in_progress).
    Returns (selection, created). created is False when this card is already
    the activity in progress, so a repeated tap never creates a second row.
    Raises NotFound for a card that isn't this installation's, and Conflict
    when another activity is in progress or this card is already completed.
    """
    with _connect() as conn:
        owned = conn.execute(
            """
            SELECT a.is_active
            FROM recommendations r JOIN activities a ON a.id = r.activity_id
            WHERE r.id = %s AND r.installation_id = %s
            """,
            (recommendation_id, installation_id),
        ).fetchone()
        if owned is None:
            raise NotFound("Recommendation not found.")

        _ensure_installation(conn, installation_id)
        # Lock this installation's live attempts so two requests can't race.
        live = conn.execute(
            """
            SELECT id, recommendation_id, status
            FROM activity_selections
            WHERE installation_id = %s
              AND (status = 'in_progress' OR (recommendation_id = %s AND status = 'completed'))
            FOR UPDATE
            """,
            (installation_id, recommendation_id),
        ).fetchall()
        for row in live:
            if row["recommendation_id"] == recommendation_id and row["status"] == "completed":
                raise Conflict("You\u2019ve already completed this activity.")
            if row["recommendation_id"] == recommendation_id:
                return _get_selection(conn, row["id"]), False
            raise Conflict(
                "You already have an activity in progress. "
                "Finish its reflection or change activity first."
            )

        # A retired activity can still be finished (above), but not started.
        if not owned["is_active"]:
            raise Conflict("This activity is no longer offered. Check in again for new ideas.")

        try:
            with conn.transaction():  # savepoint, so we can look around after a clash
                inserted = conn.execute(
                    """
                    INSERT INTO activity_selections (installation_id, recommendation_id)
                    VALUES (%s, %s)
                    RETURNING id
                    """,
                    (installation_id, recommendation_id),
                ).fetchone()
        except psycopg.errors.UniqueViolation:
            # A simultaneous request started an activity first. If it was this
            # same card, this is just a repeated tap.
            current = conn.execute(
                """
                SELECT id, recommendation_id FROM activity_selections
                WHERE installation_id = %s AND status = 'in_progress'
                """,
                (installation_id,),
            ).fetchone()
            if current and current["recommendation_id"] == recommendation_id:
                return _get_selection(conn, current["id"]), False
            raise Conflict("You already have an activity in progress.") from None
        return _get_selection(conn, inserted["id"]), True


def _get_selection(conn: psycopg.Connection, selection_id: int) -> ActivitySelection:
    return ActivitySelection(**conn.execute(SELECTION_QUERY, (selection_id,)).fetchone())


def abandon_selection(installation_id: UUID, selection_id: int) -> ActivitySelection:
    """
    "Change activity": ends the activity in progress without completing it.
    Asking again for an already abandoned one just returns it.
    Raises NotFound, or Conflict if it was already completed.
    """
    with _connect() as conn:
        row = conn.execute(
            """
            SELECT status FROM activity_selections
            WHERE id = %s AND installation_id = %s
            FOR UPDATE
            """,
            (selection_id, installation_id),
        ).fetchone()
        if row is None:
            raise NotFound("Activity selection not found.")
        if row["status"] == "completed":
            raise Conflict("This activity is already completed.")
        if row["status"] == "in_progress":
            conn.execute(
                "UPDATE activity_selections SET status = 'abandoned', ended_at = now() WHERE id = %s",
                (selection_id,),
            )
        return _get_selection(conn, selection_id)


def get_current_selection(installation_id: UUID) -> SelectedActivity | None:
    """The activity in progress (there is at most one), or None."""
    with _connect() as conn:
        row = conn.execute(
            f"""
            SELECT s.id AS selection_id, s.recommendation_id, r.check_in_id,
                   s.selected_at, {ACTIVITY_COLUMNS}
            FROM activity_selections s
            JOIN recommendations r ON r.id = s.recommendation_id
            JOIN activities a ON a.id = r.activity_id
            WHERE s.installation_id = %s AND s.status = 'in_progress'
            """,
            (installation_id,),
        ).fetchone()

    if row is None:
        return None
    return SelectedActivity(
        selection_id=row.pop("selection_id"),
        recommendation_id=row.pop("recommendation_id"),
        check_in_id=row.pop("check_in_id"),
        selected_at=row.pop("selected_at"),
        activity=Activity(**row),
    )


# ─────────────────────────────────────────────
# Bookmarks ("Save for later")
# ─────────────────────────────────────────────

def add_bookmark(installation_id: UUID, activity_id: int) -> tuple[Bookmark, bool]:
    """Returns (bookmark, created). Raises NotFound for an unknown activity."""
    with _connect() as conn:
        exists = conn.execute(
            "SELECT 1 FROM activities WHERE id = %s AND is_active", (activity_id,)
        ).fetchone()
        if exists is None:
            raise NotFound("Activity not found.")
        _ensure_installation(conn, installation_id)
        inserted = conn.execute(
            """
            INSERT INTO activity_bookmarks (installation_id, activity_id)
            VALUES (%s, %s)
            ON CONFLICT (installation_id, activity_id) DO NOTHING
            RETURNING activity_id
            """,
            (installation_id, activity_id),
        ).fetchone()
        bookmark = _bookmarks(conn, installation_id, activity_id)[0]
    return bookmark, inserted is not None


def remove_bookmark(installation_id: UUID, activity_id: int) -> None:
    """Removing one that isn't saved is fine (nothing happens)."""
    with _connect() as conn:
        conn.execute(
            "DELETE FROM activity_bookmarks WHERE installation_id = %s AND activity_id = %s",
            (installation_id, activity_id),
        )


def list_bookmarks(installation_id: UUID) -> list[Bookmark]:
    with _connect() as conn:
        return _bookmarks(conn, installation_id)


def _bookmarks(conn: psycopg.Connection, installation_id: UUID, activity_id: int | None = None) -> list[Bookmark]:
    rows = conn.execute(
        f"""
        SELECT b.created_at AS saved_at, {ACTIVITY_COLUMNS}
        FROM activity_bookmarks b
        JOIN activities a ON a.id = b.activity_id
        WHERE b.installation_id = %s AND (%s::int IS NULL OR b.activity_id = %s)
        ORDER BY b.created_at DESC
        """,
        (installation_id, activity_id, activity_id),
    ).fetchall()
    return [Bookmark(saved_at=row.pop("saved_at"), activity=Activity(**row)) for row in rows]


# ─────────────────────────────────────────────
# Scrapbook photos
# ─────────────────────────────────────────────

SCRAPBOOK_COLUMNS = "id, object_key, created_at"


def create_scrapbook_photo(installation_id: UUID, object_key: str) -> int:
    """Adds a not-yet-uploaded photo row and returns its id."""
    with _connect() as conn:
        _ensure_installation(conn, installation_id)
        row = conn.execute(
            """
            INSERT INTO scrapbook_photos (installation_id, object_key)
            VALUES (%s, %s)
            RETURNING id
            """,
            (installation_id, object_key),
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


def delete_scrapbook_photo(installation_id: UUID, photo_id: int) -> None:
    """Its memory (if any) is kept, without the photo (ON DELETE SET NULL)."""
    with _connect() as conn:
        conn.execute(
            "DELETE FROM scrapbook_photos WHERE id = %s AND installation_id = %s",
            (photo_id, installation_id),
        )


# Uploads that never became part of a memory (the app was closed between the
# upload and "Add to my scrapbook") are removed after this long.
ORPHAN_PHOTO_AGE = "1 day"


def take_orphan_photo_keys(installation_id: UUID) -> list[str]:
    """
    Deletes this installation's old photo rows that no memory uses and
    returns their S3 keys, so the caller can delete the files too.
    Only keys under scrapbook/ are touched (older test uploads used another
    prefix and are left alone).
    """
    with _connect() as conn:
        rows = conn.execute(
            f"""
            DELETE FROM scrapbook_photos p
            WHERE p.installation_id = %s
              AND p.created_at < now() - interval '{ORPHAN_PHOTO_AGE}'
              AND p.object_key LIKE 'scrapbook/%%'
              AND NOT EXISTS (SELECT 1 FROM reflections rf WHERE rf.photo_id = p.id)
            RETURNING p.object_key
            """,
            (installation_id,),
        ).fetchall()
    return [row["object_key"] for row in rows]


# ─────────────────────────────────────────────
# Reflections (scrapbook memories)
#
# One reflections row = one memory. Linked to a selection, it is also that
# activity's completion. See db/migrations/005_reflections.sql.
# ─────────────────────────────────────────────

REFLECTION_QUERY = """
    SELECT rf.id, rf.activity_selection_id, rf.note,
           rf.thought_about_ex, rf.mood_change, rf.local_date, rf.created_at,
           rf.photo_id, p.object_key AS photo_key,
           CASE WHEN a.id IS NULL THEN NULL ELSE to_jsonb(a) END AS activity
    FROM reflections rf
    LEFT JOIN activity_selections s ON s.id = rf.activity_selection_id
    LEFT JOIN recommendations r ON r.id = s.recommendation_id
    LEFT JOIN activities a ON a.id = r.activity_id
    LEFT JOIN scrapbook_photos p ON p.id = rf.photo_id AND p.uploaded_at IS NOT NULL
"""


def create_reflection(installation_id: UUID, data: ReflectionCreate) -> tuple[dict, bool]:
    """
    "Add to my scrapbook": saves the reflection and completes the activity in
    progress, in one transaction. Returns (reflection row, created). created
    is False when this activity was already completed: its reflection is
    returned and nothing changes, so a repeated submit never duplicates.
    Raises NotFound / Conflict for selections or photos that can't be used.
    """
    with _connect() as conn:
        # Lock the activity so "Change activity" can't happen at the same time.
        selection = conn.execute(
            """
            SELECT s.status, rf.id AS reflection_id
            FROM activity_selections s
            LEFT JOIN reflections rf ON rf.activity_selection_id = s.id
            WHERE s.id = %s AND s.installation_id = %s
            FOR UPDATE OF s
            """,
            (data.activity_selection_id, installation_id),
        ).fetchone()
        if selection is None:
            raise NotFound("Activity selection not found.")
        if selection["reflection_id"] is not None:
            return _get_reflection(conn, selection["reflection_id"]), False
        if selection["status"] != "in_progress":
            raise Conflict("This activity was changed, so it can\u2019t be completed.")

        if data.photo_id is not None:
            photo = conn.execute(
                """
                SELECT p.uploaded_at, rf.id AS reflection_id
                FROM scrapbook_photos p
                LEFT JOIN reflections rf ON rf.photo_id = p.id
                WHERE p.id = %s AND p.installation_id = %s
                """,
                (data.photo_id, installation_id),
            ).fetchone()
            if photo is None:
                raise NotFound("Photo not found.")
            if photo["uploaded_at"] is None:
                raise Conflict("The photo hasn\u2019t been uploaded yet.")
            if photo["reflection_id"] is not None:
                raise Conflict("That photo already belongs to another memory.")

        _ensure_installation(conn, installation_id)
        try:
            inserted = conn.execute(
                """
                INSERT INTO reflections
                    (installation_id, activity_selection_id, photo_id, note,
                     thought_about_ex, mood_change, local_date)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id, created_at
                """,
                (
                    installation_id, data.activity_selection_id, data.photo_id,
                    data.note, data.thought_about_ex,
                    data.mood_change, data.local_date,
                ),
            ).fetchone()
        except psycopg.errors.UniqueViolation:
            # Two saves raced for the same photo.
            raise Conflict("That photo already belongs to another memory.") from None

        conn.execute(
            """
            UPDATE activity_selections
            SET status = 'completed', ended_at = %s, completed_on = %s
            WHERE id = %s
            """,
            (inserted["created_at"], data.local_date, data.activity_selection_id),
        )
        return _get_reflection(conn, inserted["id"]), True


def _get_reflection(conn: psycopg.Connection, reflection_id: int) -> dict:
    return conn.execute(f"{REFLECTION_QUERY} WHERE rf.id = %s", (reflection_id,)).fetchone()


def delete_reflection(installation_id: UUID, reflection_id: int) -> str | None:
    """
    Deletes a memory and its photo row in one transaction, and returns the
    photo's S3 key (or None) so the caller can delete the file. The activity
    stays completed. Raises NotFound if it isn't this installation's.
    """
    with _connect() as conn:
        row = conn.execute(
            """
            DELETE FROM reflections
            WHERE id = %s AND installation_id = %s
            RETURNING photo_id
            """,
            (reflection_id, installation_id),
        ).fetchone()
        if row is None:
            raise NotFound("Memory not found.")
        if row["photo_id"] is None:
            return None
        photo = conn.execute(
            "DELETE FROM scrapbook_photos WHERE id = %s RETURNING object_key",
            (row["photo_id"],),
        ).fetchone()
    return photo["object_key"] if photo else None


def list_reflections(installation_id: UUID) -> list[dict]:
    """Every memory, newest first."""
    with _connect() as conn:
        return conn.execute(
            f"""
            {REFLECTION_QUERY}
            WHERE rf.installation_id = %s
            ORDER BY rf.created_at DESC, rf.id DESC
            """,
            (installation_id,),
        ).fetchall()


# ─────────────────────────────────────────────
# Progress
# ─────────────────────────────────────────────

MILESTONE_ACTIVITY_COUNT = 5


BOOKSHELF_CAPACITY = 32   # 4 shelves × 8 books in the room


def get_bookshelf(installation_id: UUID) -> Bookshelf:
    """
    One book per completed activity (its reflection was saved), earliest
    first, so a book's place never changes. Only completion counts: choosing
    "I'll try this", saving for later or checking in never adds a book, and a
    repeated submission completes nothing new. A deleted memory keeps its book
    (the activity stays completed).
    """
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT s.id AS selection_id, a.category, s.completed_on,
                   count(*) OVER () AS total
            FROM activity_selections s
            JOIN recommendations r ON r.id = s.recommendation_id
            JOIN activities a ON a.id = r.activity_id
            WHERE s.installation_id = %s AND s.status = 'completed'
            ORDER BY s.ended_at, s.id
            """,
            (installation_id,),
        ).fetchall()
    total = rows[0]["total"] if rows else 0
    books = [ShelfBook(selection_id=r["selection_id"], category=r["category"], completed_on=r["completed_on"])
             for r in rows[:BOOKSHELF_CAPACITY]]
    return Bookshelf(capacity=BOOKSHELF_CAPACITY, total_completed=total, books=books)


def get_progress_summary(installation_id: UUID) -> ProgressSummary:
    with _connect() as conn:
        row = conn.execute(
            """
            WITH memories AS (
                SELECT * FROM reflections WHERE installation_id = %(id)s
            ), completed AS (
                -- Counted from the activity itself, so deleting a memory
                -- doesn't undo the completion.
                SELECT completed_on AS local_date,
                       row_number() OVER (ORDER BY ended_at, id) AS n
                FROM activity_selections
                WHERE installation_id = %(id)s AND status = 'completed'
            )
            SELECT
                (SELECT min(local_date) FROM check_ins
                 WHERE installation_id = %(id)s)                       AS journey_started_on,
                (SELECT count(*) FROM check_ins
                 WHERE installation_id = %(id)s)                       AS check_ins,
                (SELECT count(*) FROM activity_selections
                 WHERE installation_id = %(id)s)                       AS activities_selected,
                (SELECT count(*) FROM completed)                       AS activities_completed,
                (SELECT count(*) FROM memories)                        AS memories,
                (SELECT count(*) FROM memories WHERE photo_id IS NOT NULL) AS photos,
                (SELECT local_date FROM completed WHERE n = 1)         AS first_activity_on,
                (SELECT local_date FROM completed WHERE n = %(goal)s)  AS goal_reached_on,
                (SELECT min(local_date) FROM memories
                 WHERE photo_id IS NOT NULL)                           AS first_photo_on,
                (SELECT moved_forward_on FROM moving_forward_check_ins
                 WHERE installation_id = %(id)s)                       AS moved_forward_on
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
        # Reached once the user chose "I'm ready to move forward".
        Milestone(label="Moving forward check-in", reached_on=row["moved_forward_on"]),
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


# ─────────────────────────────────────────────
# Moving forward and the farewell scrapbook
# ─────────────────────────────────────────────

MOVING_FORWARD_COLUMNS = "reflected_on, moved_forward_on, updated_at"


def get_moving_forward(installation_id: UUID) -> MovingForward | None:
    with _connect() as conn:
        return _moving_forward(conn, installation_id)


def _moving_forward(conn: psycopg.Connection, installation_id: UUID) -> MovingForward | None:
    row = conn.execute(
        f"SELECT {MOVING_FORWARD_COLUMNS} FROM moving_forward_check_ins WHERE installation_id = %s",
        (installation_id,),
    ).fetchone()
    return MovingForward(**row) if row else None


def save_moving_forward(installation_id: UUID, data: MovingForwardSave) -> tuple[MovingForward, bool]:
    """
    One per installation: the first save creates it, later saves (a repeated
    tap, a retry, an edit) update the answers and keep moved_forward_on.
    Returns (saved, created). Never deletes or changes anything else.
    """
    with _connect() as conn:
        _ensure_installation(conn, installation_id)
        row = conn.execute(
            f"""
            INSERT INTO moving_forward_check_ins (installation_id, reflected_on, moved_forward_on)
            VALUES (%s, %s, %s)
            ON CONFLICT (installation_id) DO UPDATE SET
                reflected_on = EXCLUDED.reflected_on,
                updated_at = now()
            RETURNING {MOVING_FORWARD_COLUMNS}, (xmax = 0) AS created
            """,
            (installation_id, data.reflected_on, data.local_date),
        ).fetchone()
    created = row.pop("created")
    return MovingForward(**row), created


def get_farewell_records(installation_id: UUID) -> dict:
    """
    Raw rows for the farewell scrapbook, oldest first, all scoped to this
    installation. Memories come with their photo's object key (or None).
    """
    with _connect() as conn:
        check_ins = conn.execute(
            """
            SELECT id, local_date, feeling, contact_urge, energy_level, hardest_areas
            FROM check_ins
            WHERE installation_id = %s AND counts_for_day
            ORDER BY local_date, created_at, id
            """,
            (installation_id,),
        ).fetchall()
        memories = conn.execute(
            """
            SELECT rf.id, rf.activity_selection_id, rf.note, rf.thought_about_ex, rf.mood_change,
                   rf.local_date, rf.created_at, rf.photo_id, p.object_key AS photo_key
            FROM reflections rf
            LEFT JOIN scrapbook_photos p ON p.id = rf.photo_id AND p.uploaded_at IS NOT NULL
            WHERE rf.installation_id = %s
            ORDER BY rf.local_date, rf.created_at, rf.id
            """,
            (installation_id,),
        ).fetchall()
        completed = conn.execute(
            f"""
            SELECT s.id AS selection_id, s.completed_on, {ACTIVITY_COLUMNS}
            FROM activity_selections s
            JOIN recommendations r ON r.id = s.recommendation_id
            JOIN activities a ON a.id = r.activity_id
            WHERE s.installation_id = %s AND s.status = 'completed'
            ORDER BY s.completed_on, s.ended_at, s.id
            """,
            (installation_id,),
        ).fetchall()
        moving_forward = _moving_forward(conn, installation_id)
    return {"check_ins": check_ins, "memories": memories, "completed": completed,
            "moving_forward": moving_forward}


def get_uploaded_photo_key(installation_id: UUID, photo_id: int) -> tuple[str, dict] | None:
    """(object key, row) for one of this installation's uploaded photos, or None."""
    with _connect() as conn:
        row = conn.execute(
            """SELECT id, created_at, object_key FROM scrapbook_photos
               WHERE id = %s AND installation_id = %s AND uploaded_at IS NOT NULL""",
            (photo_id, installation_id),
        ).fetchone()
    return (row.pop("object_key"), row) if row else None


# ─────────────────────────────────────────────
# Insights (raw records; app/insights.py does the calculations)
# ─────────────────────────────────────────────

def get_insight_records(installation_id: UUID, start: date, end: date) -> dict:
    """
    Everything the Progress screen needs between start and end (inclusive),
    by the user's own calendar days:
      check_ins:   [{local_date, contact_urge}]
      completed:   [{completed_on, category}]            (status completed only)
      moods:       [{local_date, mood_change, category}] (reflections of completed activities)
      categories:  [{category, label}]                   (every category, in display order)
    """
    with _connect() as conn:
        check_ins = conn.execute(
            """
            SELECT local_date, contact_urge
            FROM check_ins
            WHERE installation_id = %s AND local_date BETWEEN %s AND %s
            ORDER BY local_date, created_at
            """,
            (installation_id, start, end),
        ).fetchall()
        completed = conn.execute(
            """
            SELECT s.completed_on, a.category
            FROM activity_selections s
            JOIN recommendations r ON r.id = s.recommendation_id
            JOIN activities a ON a.id = r.activity_id
            WHERE s.installation_id = %s AND s.status = 'completed'
              AND s.completed_on BETWEEN %s AND %s
            """,
            (installation_id, start, end),
        ).fetchall()
        moods = conn.execute(
            """
            SELECT rf.local_date, rf.mood_change, a.category
            FROM reflections rf
            JOIN activity_selections s ON s.id = rf.activity_selection_id
            JOIN recommendations r ON r.id = s.recommendation_id
            JOIN activities a ON a.id = r.activity_id
            WHERE rf.installation_id = %s AND s.status = 'completed'
              AND rf.mood_change IS NOT NULL
              AND rf.local_date BETWEEN %s AND %s
            ORDER BY rf.local_date, rf.created_at
            """,
            (installation_id, start, end),
        ).fetchall()
        categories = conn.execute(
            "SELECT category, label FROM activity_categories ORDER BY sort_order, category"
        ).fetchall()
    return {"check_ins": check_ins, "completed": completed, "moods": moods, "categories": categories}

# ─────────────────────────────────────────────
# Affirmations
# ─────────────────────────────────────────────

def list_affirmations(language: str) -> list[dict]:
    """Active affirmations in catalog order (no notes, no sources)."""
    with _connect() as conn:
        return conn.execute(
            """
            SELECT a.id, a.text, a.theme, t.label AS theme_label
            FROM affirmations a
            JOIN affirmation_themes t ON t.code = a.theme
            WHERE a.is_active AND a.language = %s
            ORDER BY a.sort_order, a.id
            """,
            (language,),
        ).fetchall()
