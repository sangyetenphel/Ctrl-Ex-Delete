from fastapi import APIRouter

from app import storage
from app.dependencies import InstallationId
from app.schemas import CurrentSelectionResponse

router = APIRouter(prefix="/activity-selections", tags=["recommendations"])


@router.get("/current", response_model=CurrentSelectionResponse)
def get_current_selection(x_installation_id: InstallationId):
    """The activity chosen with "I'll try this" that still needs a reflection."""
    return CurrentSelectionResponse(selection=storage.get_current_selection(x_installation_id))
