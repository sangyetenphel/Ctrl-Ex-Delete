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
    selected_at: datetime | None = None


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
    selected_at: datetime

# ─────────────────────────────────────────────
# Scrapbook
# ─────────────────────────────────────────────

class ScrapbookPhotoCreate(BaseModel):
    """What the iOS app SENDS to start a photo upload."""
    caption: str | None = Field(default=None, max_length=500)
    local_date: date


class PhotoUpload(BaseModel):
    """What the API SENDS BACK: where to PUT the JPEG."""
    id: int
    upload_url: str


class ScrapbookPhoto(BaseModel):
    """One uploaded photo. image_url is temporary (about 1 hour)."""
    id: int
    caption: str | None
    local_date: date
    created_at: datetime
    image_url: str
