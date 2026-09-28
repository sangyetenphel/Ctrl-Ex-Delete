"""
Temporary in-memory storage.
When Neon is ready, only THIS file changes. The routes stay the same.
Note: everything here is wiped whenever the server restarts.
"""
from datetime import datetime, timezone
from uuid import UUID

from app.schemas import CheckIn, CheckInCreate

_installations: set[UUID] = set()
_check_ins: list[CheckIn] = []
_next_id = 1


def ensure_installation(installation_id: UUID) -> None:
    _installations.add(installation_id)


def create_check_in(installation_id: UUID, data: CheckInCreate) -> CheckIn:
    global _next_id
    ensure_installation(installation_id)
    check_in = CheckIn(
        id=_next_id,
        installation_id=installation_id,
        created_at=datetime.now(timezone.utc),
        **data.model_dump(),
    )
    _next_id += 1
    _check_ins.append(check_in)
    return check_in


def list_check_ins(installation_id: UUID) -> list[CheckIn]:
    mine = [c for c in _check_ins if c.installation_id == installation_id]
    return sorted(mine, key=lambda c: c.created_at, reverse=True)