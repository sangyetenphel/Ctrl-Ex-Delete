from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

# Allowed values. These must match schema.sql and the Swift app exactly.
Feeling = Literal["heavy", "getting_through", "missing_them", "hopeful"]
EnergyLevel = Literal["low", "medium", "high"]
HardestArea = Literal[
    "feeling_lonely",
    "missing_relationship",
    "wanting_answers",
    "resisting_contact",
    "rebuilding_confidence",
]


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