from fastapi import APIRouter, Response, status

from app import media, storage
from app.dependencies import InstallationId
from app.schemas import (
    Activity,
    FarewellActivity,
    FarewellCheckIn,
    FarewellMemory,
    FarewellScrapbook,
    MovingForward,
    MovingForwardResponse,
    MovingForwardSave,
)

router = APIRouter(tags=["moving forward"])


@router.get("/moving-forward", response_model=MovingForwardResponse)
def get_moving_forward(x_installation_id: InstallationId):
    """The saved moving-forward check-in, or null if the user hasn't chosen it."""
    return MovingForwardResponse(moving_forward=storage.get_moving_forward(x_installation_id))


@router.put(
    "/moving-forward",
    response_model=MovingForward,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "Already saved; updated in place"}},
)
def save_moving_forward(payload: MovingForwardSave, x_installation_id: InstallationId, response: Response):
    """
    "I'm ready to move forward": saves the final reflection. One per
    installation; sending it again updates it (never a second one). Nothing
    is deleted or locked, and the app keeps working as before.
    """
    saved, created = storage.save_moving_forward(x_installation_id, payload)
    if not created:
        response.status_code = status.HTTP_200_OK
    return saved


def _memory(row: dict) -> FarewellMemory:
    row = dict(row)
    key = row.pop("photo_key")
    row.pop("activity_selection_id", None)
    return FarewellMemory(**row, image_url=media.photo_url(key))


@router.get("/farewell-scrapbook", response_model=FarewellScrapbook)
def get_farewell_scrapbook(x_installation_id: InstallationId):
    """
    Everything the keepsake PDF is made from, oldest first: check-ins,
    completed activities with their memories and photo links, other memories,
    and the moving-forward reflection. Only this installation's records.
    Photo links last about an hour; ask again for fresh ones.
    """
    records = storage.get_farewell_records(x_installation_id)
    memories_by_selection = {m["activity_selection_id"]: m for m in records["memories"]
                             if m["activity_selection_id"] is not None}

    completed = []
    for row in records["completed"]:
        row = dict(row)
        selection_id, completed_on = row.pop("selection_id"), row.pop("completed_on")
        memory = memories_by_selection.pop(selection_id, None)
        completed.append(FarewellActivity(selection_id=selection_id, activity=Activity(**row),
                                          completed_on=completed_on,
                                          memory=_memory(memory) if memory else None))
    completed_ids = {a.selection_id for a in completed}
    others = [_memory(m) for m in records["memories"] if m["activity_selection_id"] not in completed_ids]

    moving_forward = records["moving_forward"]
    dates = ([c["local_date"] for c in records["check_ins"]] + [a.completed_on for a in completed]
             + [m["local_date"] for m in records["memories"]]
             + ([moving_forward.moved_forward_on] if moving_forward else []))
    return FarewellScrapbook(
        journey_started_on=records["check_ins"][0]["local_date"] if records["check_ins"] else None,
        journey_last_on=max(dates) if dates else None,
        check_ins=[FarewellCheckIn(**row) for row in records["check_ins"]],
        completed_activities=completed,
        other_memories=others,
        moving_forward=moving_forward,
    )
