from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, status

from app import storage
from app.schemas import CheckIn, CheckInCreate

router = APIRouter(prefix="/check-ins", tags=["check-ins"])

# FastAPI turns x_installation_id into the "X-Installation-ID" header.
# Typing it as UUID means anything that isn't a valid UUID gets rejected.
InstallationId = Annotated[UUID, Header()]


@router.post("", response_model=CheckIn, status_code=status.HTTP_201_CREATED)
def create_check_in(payload: CheckInCreate, x_installation_id: InstallationId):
    return storage.create_check_in(x_installation_id, payload)


@router.get("", response_model=list[CheckIn])
def get_check_ins(x_installation_id: InstallationId):
    return storage.list_check_ins(x_installation_id)