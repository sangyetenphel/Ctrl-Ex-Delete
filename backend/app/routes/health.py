from fastapi import APIRouter

from app import storage

router = APIRouter()

@router.get("/health")
def health():
    """The server is up. Doesn't touch the database (Render's health check)."""
    return {"status": "ok"}


@router.get("/health/db")
def health_db():
    """The server can reach the database; 503 otherwise (see main.py)."""
    storage.ping()
    return {"status": "ok", "database": "ok"}
