import logging

import psycopg
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.routes import (
    activity_selections,
    affirmations,
    bookmarks,
    check_ins,
    health,
    insights,
    moving_forward,
    progress,
    recommendations,
    reflections,
    scrapbook,
)

logger = logging.getLogger("ced")

app = FastAPI(title="Ctrl+Ex+Delete API")
app.include_router(health.router)
app.include_router(affirmations.router)
app.include_router(check_ins.router)
app.include_router(recommendations.router)
app.include_router(activity_selections.router)
app.include_router(bookmarks.router)
app.include_router(scrapbook.router)
app.include_router(reflections.router)
app.include_router(progress.router)
app.include_router(insights.router)
app.include_router(moving_forward.router)


@app.exception_handler(psycopg.OperationalError)
def database_unavailable(request: Request, exc: psycopg.OperationalError):
    # Can't reach Neon (offline, wrong DATABASE_URL, database asleep, ...).
    # Log the type only: the full message can include the database host.
    logger.error("Database connection failed: %s", type(exc).__name__)
    return JSONResponse(
        status_code=503,
        content={"detail": "The database is unavailable. Please try again shortly."},
    )
