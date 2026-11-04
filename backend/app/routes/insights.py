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
    today: date = Query(description="The user's local calendar day, YYYY-MM-DD",
                        ge=date(2020, 1, 1), le=date(2100, 12, 31)),
    period: Literal["week", "month"] = "week",
):
    """
    The Progress screen for the calendar week (Mon–Sun) or month containing
    `today`. The app sends its own local date so week and month boundaries
    follow the user's time zone, like check-in and reflection dates do.
    The month view's charts follow the user's own weeks (insights.journey_weeks).
    """
    start, end = insights.period_bounds(period, today)
    records = storage.get_insight_records(x_installation_id, start, end)
    if period == "week":
        return insights.build(period, today, records)
    weeks = insights.journey_weeks(storage.get_journey_start(x_installation_id), today)
    week_records = storage.get_insight_records(x_installation_id, weeks[0][1], weeks[-1][2])
    return insights.build(period, today, records, weeks, week_records)
