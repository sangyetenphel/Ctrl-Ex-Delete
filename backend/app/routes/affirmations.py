from fastapi import APIRouter, Query

from app import storage
from app.schemas import Affirmation, AffirmationsResponse

router = APIRouter(prefix="/affirmations", tags=["affirmations"])


@router.get("", response_model=AffirmationsResponse)
def list_affirmations(language: str = Query("en", min_length=2, max_length=8)):
    """
    The active affirmations for the "Grow with Kindness" plant game, in
    catalog order. The same for everyone (no installation needed); the app
    caches it and also bundles a copy, so the game never waits for this.
    """
    rows = storage.list_affirmations(language)
    return AffirmationsResponse(language=language, affirmations=[Affirmation(**row) for row in rows])
