from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

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


# ─────────────────────────────────────────────
# Activities and recommendations
# ─────────────────────────────────────────────

class Activity(BaseModel):
    """One activity from the catalog, with everything a card shows."""
    id: int
    slug: str
    title: str
    category: ActivityCategory
    category_label: str
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


class RecommendationsResponse(BaseModel):
    """
    Recommendations for the installation's most recent check-in.
    check_in_id is null (and the list is empty) if there are no check-ins yet.
    """
    check_in_id: int | None
    check_in_local_date: date | None
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
    activity in progress. The two questions are required; the notes and the
    photo are optional.
    """
    activity_selection_id: int
    thought_about_ex: ThoughtAboutEx
    mood_change: MoodChange
    note: str | None = Field(default=None, max_length=1000)
    noticed: str | None = Field(default=None, max_length=1000)
    photo_id: int | None = None
    local_date: date


class Reflection(BaseModel):
    """One saved memory. image_url is temporary (about 1 hour)."""
    id: int
    activity_selection_id: int | None
    activity: Activity | None
    note: str | None
    noticed: str | None
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
