from fastapi import APIRouter, HTTPException, status

from app import storage
from app.dependencies import InstallationId
from app.schemas import ActivitySelection, CurrentSelectionResponse

router = APIRouter(prefix="/activity-selections", tags=["recommendations"])


@router.get("/current", response_model=CurrentSelectionResponse)
def get_current_selection(x_installation_id: InstallationId):
    """The activity in progress (at most one), or null."""
    return CurrentSelectionResponse(selection=storage.get_current_selection(x_installation_id))


@router.post(
    "/{selection_id}/abandon",
    response_model=ActivitySelection,
    responses={409: {"description": "Already completed"}},
)
def abandon_selection(selection_id: int, x_installation_id: InstallationId):
    """
    "Change activity": ends the activity in progress without counting it as
    completed. Saved memories are not affected. Safe to repeat.
    """
    try:
        return storage.abandon_selection(x_installation_id, selection_id)
    except storage.NotFound as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(error)) from None
    except storage.Conflict as error:
        raise HTTPException(status.HTTP_409_CONFLICT, str(error)) from None
