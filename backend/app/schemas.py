from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

# Allowed values. These must match db/migrations and the Swift app exactly.
Feeling = Literal["heavy", "getting_through", "missing_them", "hopeful"]
EnergyLevel = Literal["low", "medium", "high"]
HardestArea = Literal[
    "feeling_lonely",
    "missing_relationship",
    "wanting_answers",
    "resisting_contact",
    "rebuilding_confidence",
]
ActivityCategory = Literal[
    "outdoor_movement", "mindfulness_rest", "solo_exploration", "social_connection"
]
# Reflection answers, stored exactly as the user chose them.
ThoughtAboutEx = Literal["not_really", "a_little", "a_lot"]
MoodChange = Literal["worse", "about_the_same", "a_little_better", "much_better"]
# An "I'll try this" choice: in progress until its reflection is saved
# (completed) or the user picks "Change activity" (abandoned).
SelectionStatus = Literal["in_progress", "completed", "abandoned"]


# ─────────────────────────────────────────────
# Check-ins
# ─────────────────────────────────────────────

class CheckInCreate(BaseModel):
    """What the iOS app SENDS when the user taps 'Enter my room'."""
    feeling: Feeling
    contact_urge: int = Field(ge=1, le=10)
    energy_level: EnergyLevel
    hardest_areas: list[HardestArea] = Field(default_factory=list)
    local_date: date


class CheckIn(CheckInCreate):
    """What the API SENDS BACK: the saved check-in plus server-made fields."""
    id: int
    installation_id: UUID
    created_at: datetime


class CheckInStatus(BaseModel):
    """
    GET /check-ins/today: has the user checked in on their local day?
    The app asks on startup, before choosing the welcome, check-in or room screen.
    """
    local_date: date
    check_in: CheckIn | None      # that day's check-in, or null if there isn't one yet
    has_any_check_in: bool        # false for someone who has never checked in


# ─────────────────────────────────────────────
# Activities and recommendations
# ─────────────────────────────────────────────

class Activity(BaseModel):
    """One activity from the catalog, with everything a card shows."""
    id: int
    slug: str
    title: str
    category: ActivityCategory
    # The category's display name, e.g. "Mindfulness & Rest". Stored on the
    # activity and kept in step with activity_categories by the database.
    category_label: str
    # Overall demand (physical, cognitive, social, preparation), separate from
    # duration; a check-in's energy decides which levels are recommended.
    energy_level: EnergyLevel
    duration_minutes: int
    instructions: str
    why_it_fits: str


class Recommendation(BaseModel):
    """One suggested activity for one check-in."""
    id: int
    position: int
    activity: Activity
    is_saved: bool = False                 # bookmarked with "Save for later"
    status: SelectionStatus | None = None  # null = not chosen (or abandoned)
    selected_at: datetime | None = None
    completed_at: datetime | None = None   # set once its reflection is saved


class CheckInAnswers(BaseModel):
    """The answers the recommendations were chosen from (shown as the page heading)."""
    feeling: Feeling
    contact_urge: int
    energy_level: EnergyLevel
    hardest_areas: list[HardestArea]


class RecommendationsResponse(BaseModel):
    """
    Recommendations for the installation's most recent check-in.
    check_in_id and check_in are null (and the list is empty) if there are no
    check-ins yet.
    """
    check_in_id: int | None
    check_in_local_date: date | None
    check_in: CheckInAnswers | None = None
    recommendations: list[Recommendation]


class ActivitySelection(BaseModel):
    """What the API SENDS BACK after the user taps 'I'll try this'."""
    id: int
    recommendation_id: int
    activity_id: int
    check_in_id: int
    status: SelectionStatus
    selected_at: datetime
    ended_at: datetime | None


class SelectedActivity(BaseModel):
    """The activity in progress: chosen with "I'll try this", not yet finished."""
    selection_id: int
    recommendation_id: int
    check_in_id: int
    selected_at: datetime
    activity: Activity


class CurrentSelectionResponse(BaseModel):
    """The activity in progress, or null."""
    selection: SelectedActivity | None


# ─────────────────────────────────────────────
# Scrapbook
# ─────────────────────────────────────────────

class PhotoUpload(BaseModel):
    """What the API SENDS BACK: where to PUT the JPEG."""
    id: int
    upload_url: str


class ScrapbookPhoto(BaseModel):
    """One uploaded photo. image_url is temporary (about 1 hour)."""
    id: int
    created_at: datetime
    image_url: str


# ─────────────────────────────────────────────
# Reflections (scrapbook memories)
# ─────────────────────────────────────────────

class ReflectionCreate(BaseModel):
    """
    What the iOS app SENDS from "Add to my scrapbook". Saving it completes the
    activity in progress. Everything is required: the two questions, the note
    ("What did you notice?", not blank) and an uploaded photo of this
    installation (see POST /scrapbook/photos; storage.py checks the photo).
    """
    activity_selection_id: int
    thought_about_ex: ThoughtAboutEx
    mood_change: MoodChange
    note: str | None = Field(default=None, max_length=1000)
    # Older app builds asked a second question and sent it as `noticed`.
    # It's still accepted so their text isn't lost, and joined into `note`.
    noticed: str | None = Field(default=None, max_length=1000, deprecated=True, exclude=True)
    photo_id: int
    local_date: date

    @model_validator(mode="after")
    def _note_is_required(self):
        note = (self.note or "").strip()
        extra = (self.__dict__.get("noticed") or "").strip()
        if extra:
            note = extra if not note or note == extra else f"{note}\n\n{extra}"
        self.__dict__["noticed"] = None
        if not note:
            raise ValueError("Please write what you noticed.")
        self.note = note
        return self


class Reflection(BaseModel):
    """One saved memory. image_url is temporary (about 1 hour)."""
    id: int
    activity_selection_id: int | None
    activity: Activity | None
    note: str | None              # the answer to "What did you notice?"
    thought_about_ex: ThoughtAboutEx | None
    mood_change: MoodChange | None
    local_date: date
    created_at: datetime          # when it was saved (= completed, with a selection)
    photo_id: int | None
    image_url: str | None


# ─────────────────────────────────────────────
# Bookmarks ("Save for later")
# ─────────────────────────────────────────────

class Bookmark(BaseModel):
    activity: Activity
    saved_at: datetime


# ─────────────────────────────────────────────
# Progress
# ─────────────────────────────────────────────

class Milestone(BaseModel):
    label: str
    reached_on: date | None   # null = not reached yet


class ProgressSummary(BaseModel):
    journey_started_on: date | None   # local date of the first check-in
    check_ins: int
    activities_selected: int
    activities_completed: int         # reflections linked to an activity
    memories: int                     # all reflections
    photos: int                       # reflections with a photo
    milestones: list[Milestone]


# ─────────────────────────────────────────────
# Insights (the Progress screen)
# ─────────────────────────────────────────────

class UrgePoint(BaseModel):
    """One bar: a day (week view) or a week of the month (month view)."""
    label: str                 # "Mon" … "Sun", or "W1" … "W5"
    start: date
    end: date
    value: int | None          # average urge (1–10); null = no check-in
    check_ins: int


class MoodPoint(BaseModel):
    """
    One bar of "Mood after activities": a day (week view) or a week of the
    month (month view). `value` is the average of the internal scores of the
    answers given then (see insights.MOOD_SCORES), only for sizing the bar;
    it is not a rating the user entered. null = no completed activity.
    """
    label: str                 # "Mon" … "Sun", or "W1" … "W5"
    start: date
    end: date
    value: float | None        # 1–10 scale, one decimal; null = gap
    answers: list[MoodChange]  # the answers behind the bar, in the order given


class MoodCount(BaseModel):
    """How often an answer to "How do you feel now compared to before?" was given."""
    response: MoodChange
    label: str
    count: int


class CategoryShare(BaseModel):
    category: ActivityCategory
    label: str
    count: int                 # completed activities only
    percent: int               # of all completed activities in the period


class Takeaway(BaseModel):
    headline: str
    body: str


class InsightsResponse(BaseModel):
    period: Literal["week", "month"]
    start: date
    end: date
    has_data: bool             # false = show the empty state
    check_in_days: int
    completed: int
    urges: list[UrgePoint]
    moods: list[MoodCount]     # how often each answer was given (totals)
    mood_points: list[MoodPoint] = []
    categories: list[CategoryShare]
    takeaway: Takeaway
    observations: list[str]
