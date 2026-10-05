from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

# Allowed values. These must match the Neon schema and the Swift app exactly.
Feeling = Literal["heavy", "getting_through", "missing_them", "hopeful"]
EnergyLevel = Literal["low", "medium", "high"]
HardestArea = Literal[
    "feeling_lonely",
    "missing_relationship",
    "wanting_answers",
    "resisting_contact",
    "rebuilding_confidence",
]
# Matches activities_category_check in Neon exactly.
Category = Literal[
    "mindfulness_rest",
    "outdoor_movement",
    "solo_exploration",
    "social_connection",
]


# ---------- Check-ins (Week 1) ----------

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


# ---------- Activities (Week 2) ----------

class Activity(BaseModel):
    """One row of the activities table."""
    id: int
    slug: str
    title: str
    category: Category
    category_label: str
    duration_minutes: int
    instructions: str
    why_it_fits: str
    sort_order: int


class RecommendedActivity(BaseModel):
    """One card the app shows. recommendation_id is what the app sends back
    when the user picks it."""
    recommendation_id: int
    position: int
    activity: Activity
    reason: str


class ActivitySelection(BaseModel):
    id: int
    installation_id: UUID
    recommendation_id: int
    selected_at: datetime


class ActivityLogCreate(BaseModel):
    """What the app SENDS when the user finishes an activity."""
    # Matches activity_logs_mood_after_check (1-10). Optional: column allows NULL.
    mood_after: int | None = Field(default=None, ge=1, le=10)
    local_date: date


class ActivityLog(ActivityLogCreate):
    id: int
    installation_id: UUID
    activity_id: int
    completed_at: datetime