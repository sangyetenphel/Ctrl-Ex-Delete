from fastapi import APIRouter, HTTPException, Response, status

from app import storage
from app.dependencies import InstallationId
from app.schemas import Bookmark

router = APIRouter(prefix="/bookmarks", tags=["bookmarks"])


@router.get("", response_model=list[Bookmark])
def list_bookmarks(x_installation_id: InstallationId):
    """Activities saved with "Save for later", newest first."""
    return storage.list_bookmarks(x_installation_id)


@router.put(
    "/{activity_id}",
    response_model=Bookmark,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "Already saved; returns the existing bookmark"}},
)
def save_activity(activity_id: int, x_installation_id: InstallationId, response: Response):
    """
    "Save for later". Saved activities come first in later recommendations.
    This never selects or completes the activity. Saving twice is harmless.
    """
    try:
        bookmark, created = storage.add_bookmark(x_installation_id, activity_id)
    except storage.NotFound as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(error)) from None
    if not created:
        response.status_code = status.HTTP_200_OK
    return bookmark


@router.delete("/{activity_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_saved_activity(activity_id: int, x_installation_id: InstallationId):
    """Removes the bookmark. Removing one that isn't saved is harmless."""
    storage.remove_bookmark(x_installation_id, activity_id)
