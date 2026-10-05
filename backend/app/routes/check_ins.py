from fastapi import APIRouter, status

from app import storage
from app.dependencies import InstallationId
from app.schemas import CheckIn, CheckInCreate

router = APIRouter(prefix="/check-ins", tags=["check-ins"])


@router.post("", response_model=CheckIn, status_code=status.HTTP_201_CREATED)
def create_check_in(payload: CheckInCreate, x_installation_id: InstallationId):
    """Saves a check-in and prepares its activity recommendations."""
    return storage.create_check_in(x_installation_id, payload)


@router.get("", response_model=list[CheckIn])
def get_check_ins(x_installation_id: InstallationId):
    return storage.list_check_ins(x_installation_id)
