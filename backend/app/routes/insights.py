from datetime import date
from typing import Literal

from fastapi import APIRouter, Query

from app import insights, storage
from app.dependencies import InstallationId
from app.schemas import InsightsResponse

router = APIRouter(prefix="/insights", tags=["progress"])


@router.get("", response_model=InsightsResponse)
def get_insights(
    x_installation_id: InstallationId,
    today: date = Query(description="The user's local calendar day, YYYY-MM-DD"),
    period: Literal["week", "month"] = "week",
):
    """
    The Progress screen for the calendar week (Mon–Sun) or month containing
    `today`. The app sends its own local date so week and month boundaries
    follow the user's time zone, like check-in and reflection dates do.
    """
    start, end = insights.period_bounds(period, today)
    records = storage.get_insight_records(x_installation_id, start, end)
    return insights.build(period, today, records)
