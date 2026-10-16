from fastapi import APIRouter

from app import storage
from app.dependencies import InstallationId
from app.schemas import ProgressSummary

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("/summary", response_model=ProgressSummary)
def get_progress_summary(x_installation_id: InstallationId):
    """Journey start, counts and milestones for the room and the scrapbook."""
    return storage.get_progress_summary(x_installation_id)
