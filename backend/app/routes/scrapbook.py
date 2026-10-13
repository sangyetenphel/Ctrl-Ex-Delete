from fastapi import APIRouter, Depends, HTTPException, status

from app import media, storage
from app.dependencies import InstallationId
from app.schemas import PhotoUpload, ScrapbookPhoto, ScrapbookPhotoCreate


def require_s3() -> None:
    if not media.is_configured():
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Photo storage isn't set up on the server yet.",
        )


router = APIRouter(prefix="/scrapbook", tags=["scrapbook"], dependencies=[Depends(require_s3)])

MAX_BYTES = 5 * 1024 * 1024  # 5 MB; compressed photos are far smaller


@router.post("/photos", response_model=PhotoUpload, status_code=status.HTTP_201_CREATED)
def start_upload(payload: ScrapbookPhotoCreate, x_installation_id: InstallationId):
    """Step 1: reserves a photo and returns a URL to upload the JPEG to."""
    key = media.new_key()
    photo_id = storage.create_scrapbook_photo(x_installation_id, key, payload)
    return PhotoUpload(id=photo_id, upload_url=media.upload_url(key))


@router.post("/photos/{photo_id}/complete", response_model=ScrapbookPhoto)
def complete_upload(photo_id: int, x_installation_id: InstallationId):
    """Step 2: called after the app has uploaded the JPEG to S3."""
    key = storage.get_scrapbook_key(x_installation_id, photo_id)
    if key is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found.")

    size = media.object_size(key)
    if size is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "The photo hasn't been uploaded yet.")
    if size > MAX_BYTES:
        media.delete(key)
        storage.delete_scrapbook_photo(x_installation_id, photo_id)
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Photo is too large.")

    row = storage.mark_scrapbook_uploaded(x_installation_id, photo_id, size)
    return ScrapbookPhoto(**row, image_url=media.download_url(key))


@router.get("/photos", response_model=list[ScrapbookPhoto])
def list_photos(x_installation_id: InstallationId):
    rows = storage.list_scrapbook_photos(x_installation_id)
    return [
        ScrapbookPhoto(**row, image_url=media.download_url(row["object_key"]))
        for row in rows
    ]


@router.delete("/photos/{photo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_photo(photo_id: int, x_installation_id: InstallationId):
    key = storage.get_scrapbook_key(x_installation_id, photo_id)
    if key is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Photo not found.")
    media.delete(key)
    storage.delete_scrapbook_photo(x_installation_id, photo_id)
