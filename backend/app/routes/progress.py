from fastapi import APIRouter

from app import storage
from app.dependencies import InstallationId
from app.schemas import Bookshelf, ProgressSummary

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("/summary", response_model=ProgressSummary)
def get_progress_summary(x_installation_id: InstallationId):
    """Journey start, counts and milestones for the room and the scrapbook."""
    return storage.get_progress_summary(x_installation_id)


@router.get("/bookshelf", response_model=Bookshelf)
def get_bookshelf(x_installation_id: InstallationId):
    """
    The room's bookshelf: one book per completed activity, earliest first,
    up to 32. Read-only; the shelf's fullness affects nothing else.
    """
    return storage.get_bookshelf(x_installation_id)
