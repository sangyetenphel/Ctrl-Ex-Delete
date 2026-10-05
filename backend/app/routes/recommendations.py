from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, HTTPException, status

from app import storage
from app.schemas import ActivitySelection, RecommendedActivity

router = APIRouter(prefix="/recommendations", tags=["recommendations"])

InstallationId = Annotated[UUID, Header()]


@router.get("", response_model=list[RecommendedActivity])
def get_recommendations(x_installation_id: InstallationId):
    """The cards for the user's most recent check-in, in order."""
    recs = storage.get_latest_recommendations(x_installation_id)
    if recs is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No check-in yet. Check in before getting recommendations.",
        )
    return recs


@router.post(
    "/{recommendation_id}/select",
    response_model=ActivitySelection,
    status_code=status.HTTP_201_CREATED,
)
def select_recommendation(recommendation_id: int, x_installation_id: InstallationId):
    selection = storage.select_recommendation(x_installation_id, recommendation_id)
    if selection is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recommendation not found")
    return selection