from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, HTTPException, status

from app import storage
from app.schemas import Activity, ActivityLog, ActivityLogCreate

router = APIRouter(prefix="/activities", tags=["activities"])

InstallationId = Annotated[UUID, Header()]


@router.get("", response_model=list[Activity])
def list_activities():
    """Full active catalog. Handy for testing in Postman."""
    return storage.list_activities()


@router.post(
    "/{activity_id}/logs",
    response_model=ActivityLog,
    status_code=status.HTTP_201_CREATED,
)
def log_activity(activity_id: int, payload: ActivityLogCreate, x_installation_id: InstallationId):
    log = storage.create_activity_log(x_installation_id, activity_id, payload)
    if log is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Activity not found")
    return log