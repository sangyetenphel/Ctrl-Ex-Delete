import logging

from fastapi import APIRouter, HTTPException, Response, status

from app import media, storage
from app.dependencies import InstallationId
from app.schemas import Reflection, ReflectionCreate

router = APIRouter(prefix="/reflections", tags=["reflections"])
logger = logging.getLogger("ced")


def _to_reflection(row: dict) -> Reflection:
    photo_key = row.pop("photo_key")
    # Without S3 settings the memory still loads, just without its picture.
    image_url = media.download_url(photo_key) if photo_key and media.is_configured() else None
    return Reflection(**row, image_url=image_url)


@router.post(
    "",
    response_model=Reflection,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "This selection already has a reflection; returns it"}},
)
def create_reflection(payload: ReflectionCreate, x_installation_id: InstallationId, response: Response):
    """
    "Add to my scrapbook": saves the reflection and marks the selected
    activity as completed. Upload the photo first (POST /scrapbook/photos).
    """
    try:
        row, created = storage.create_reflection(x_installation_id, payload)
    except storage.NotFound as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(error)) from None
    except storage.Conflict as error:
        raise HTTPException(status.HTTP_409_CONFLICT, str(error)) from None

    if not created:
        response.status_code = status.HTTP_200_OK
    return _to_reflection(row)


@router.get("", response_model=list[Reflection])
def list_reflections(x_installation_id: InstallationId):
    """Every scrapbook memory, newest first."""
    return [_to_reflection(row) for row in storage.list_reflections(x_installation_id)]


@router.delete("/{reflection_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_reflection(reflection_id: int, x_installation_id: InstallationId):
    """
    Deletes a memory: its answers, its photo row and the photo file in S3.
    The activity still counts as completed.
    """
    try:
        photo_key = storage.delete_reflection(x_installation_id, reflection_id)
    except storage.NotFound as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(error)) from None
    # The rows are gone first, so the app never shows a memory whose file
    # was deleted. If S3 fails here, only an unreachable file is left behind.
    if photo_key and media.is_configured():
        try:
            media.delete(photo_key)
        except Exception as error:  # noqa: BLE001
            logger.warning("Couldn't delete a photo from S3: %s", type(error).__name__)
