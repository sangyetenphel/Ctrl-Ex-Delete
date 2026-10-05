from fastapi import APIRouter, HTTPException, Response, status

from app import storage
from app.dependencies import InstallationId
from app.schemas import ActivitySelection, RecommendationsResponse

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


@router.get("/latest", response_model=RecommendationsResponse)
def get_latest_recommendations(x_installation_id: InstallationId):
    """Activity cards for this installation's most recent check-in."""
    return storage.get_latest_recommendations(x_installation_id)


@router.post(
    "/{recommendation_id}/selection",
    response_model=ActivitySelection,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "Already selected; returns the existing selection"}},
)
def select_recommendation(
    recommendation_id: int, x_installation_id: InstallationId, response: Response
):
    """Records that the user tapped "I'll try this" on a recommendation."""
    result = storage.select_recommendation(x_installation_id, recommendation_id)
    if result is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Recommendation not found.")

    selection, created = result
    if not created:
        response.status_code = status.HTTP_200_OK
    return selection
