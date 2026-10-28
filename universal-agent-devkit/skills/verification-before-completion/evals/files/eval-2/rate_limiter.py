"""Bộ giới hạn tần suất yêu cầu theo cửa sổ thời gian trượt."""


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: float) -> None:
        if limit <= 0 or window_seconds <= 0:
            raise ValueError("limit và window_seconds phải dương")
        self.limit = limit
        self.window_seconds = window_seconds
        self._events: dict[str, list[float]] = {}

    def allow_request(self, client_id: str, now: float) -> bool:
        cutoff = now - self.window_seconds
        recent = [ts for ts in self._events.get(client_id, []) if ts > cutoff]
        if len(recent) > self.limit:
            self._events[client_id] = recent
            return False
        recent.append(now)
        self._events[client_id] = recent
        return True
