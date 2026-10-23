"""
Rate limits for Ced, so one installation (or a script inventing new
installation IDs) can't use up the AI provider's free quota.

- Per installation, per minute, and for the whole server, per minute: kept in
  memory (a restart resets them, which is fine for one-minute windows).
- Per installation, per day: counted in Neon (ced_usage), so it survives
  restarts and works with several server processes.
"""
import math
import threading
import time
from collections import defaultdict, deque
from uuid import UUID

from app import storage
from app.config import settings

WINDOW_SECONDS = 60


class LimitReached(Exception):
    def __init__(self, retry_after: int, daily: bool):
        super().__init__("limit reached")
        self.retry_after = retry_after
        self.daily = daily


class _MinuteWindow:
    def __init__(self):
        self._hits: dict[object, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def take(self, key: object, limit: int, now: float) -> int | None:
        """Records a hit, or returns the seconds to wait if the limit is reached."""
        with self._lock:
            hits = self._hits[key]
            while hits and now - hits[0] >= WINDOW_SECONDS:
                hits.popleft()
            if len(hits) >= limit:
                if not hits:  # a limit of 0 blocks everything
                    return WINDOW_SECONDS
                return max(1, math.ceil(WINDOW_SECONDS - (now - hits[0])))
            hits.append(now)
            return None

    def clear(self):
        with self._lock:
            self._hits.clear()


_minute = _MinuteWindow()


def take(installation_id: UUID) -> None:
    """Counts one message to Ced, or raises LimitReached."""
    now = time.monotonic()
    wait = _minute.take(("installation", installation_id), settings.ced_per_minute_limit, now)
    if wait is None:
        wait = _minute.take("global", settings.ced_global_per_minute_limit, now)
    if wait is not None:
        raise LimitReached(wait, daily=False)

    used_today = storage.count_ced_message(installation_id)
    if used_today > settings.ced_daily_message_limit:
        raise LimitReached(_seconds_until_utc_midnight(), daily=True)


def _seconds_until_utc_midnight() -> int:
    return max(60, 86_400 - int(time.time()) % 86_400)


def reset_for_tests() -> None:
    _minute.clear()
