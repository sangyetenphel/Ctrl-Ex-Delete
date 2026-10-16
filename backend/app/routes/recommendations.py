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
    responses={
        200: {"description": "This card is already the activity in progress; returns it"},
        409: {"description": "Another activity is in progress, or this one is completed"},
    },
)
def select_recommendation(
    recommendation_id: int, x_installation_id: InstallationId, response: Response
):
    """
    "I'll try this": starts this activity (in_progress). Only one activity can
    be in progress; finish its reflection or abandon it first.
    """
    try:
        selection, created = storage.select_recommendation(x_installation_id, recommendation_id)
    except storage.NotFound as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(error)) from None
    except storage.Conflict as error:
        raise HTTPException(status.HTTP_409_CONFLICT, str(error)) from None

    if not created:
        response.status_code = status.HTTP_200_OK
    return selection
