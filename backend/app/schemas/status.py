import uuid
from enum import Enum

from pydantic import BaseModel, Field


class HouseStatus(str, Enum):
    OPEN_TO_CHAT = "open_to_chat"
    DEEP_FOCUS = "deep_focus"
    IN_CALL = "in_call"
    SLEEPING_EARLY = "sleeping_early"
    AWAY = "away"


class StatusTtl(int, Enum):
    """Allowed TTLs, in seconds, for a live status entry."""

    TWO_HOURS = 2 * 60 * 60
    FOUR_HOURS = 4 * 60 * 60
    EIGHT_HOURS = 8 * 60 * 60


class StatusSet(BaseModel):
    status: HouseStatus
    ttl_seconds: StatusTtl = StatusTtl.FOUR_HOURS


class StatusRead(BaseModel):
    user_id: uuid.UUID
    group_id: uuid.UUID
    status: HouseStatus | None
    ttl_seconds: int | None = Field(
        default=None, description="Seconds remaining before this status expires."
    )
