from datetime import date

from fastapi import APIRouter, Query, Response, status

from app import storage
from app.dependencies import InstallationId
from app.schemas import CheckIn, CheckInCreate, CheckInStatus

router = APIRouter(prefix="/check-ins", tags=["check-ins"])


@router.post(
    "",
    response_model=CheckIn,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "Already checked in on this local_date; returns that check-in"}},
)
def create_check_in(payload: CheckInCreate, x_installation_id: InstallationId, response: Response):
    """
    Saves a check-in and prepares its activity recommendations. One per local
    calendar day: sending another one for the same local_date (a second tap, a
    retry, two at once) adds nothing and returns the day's existing check-in.
    """
    check_in, created = storage.create_check_in(x_installation_id, payload)
    if not created:
        response.status_code = status.HTTP_200_OK
    return check_in


@router.get("", response_model=list[CheckIn])
def get_check_ins(x_installation_id: InstallationId):
    return storage.list_check_ins(x_installation_id)


@router.get("/today", response_model=CheckInStatus)
def get_check_in_status(
    x_installation_id: InstallationId,
    local_date: date = Query(description="The user's local calendar day, YYYY-MM-DD"),
):
    """Whether the user has checked in on their local day. Changes nothing."""
    return storage.get_check_in_status(x_installation_id, local_date)
