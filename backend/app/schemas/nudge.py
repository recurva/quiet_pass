import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, model_validator


class NudgeType(str, Enum):
    """Adding a new preset is just a new member here plus an entry in
    nudge_service's message table — nothing else needs to change.
    """

    QUIET_PULSE = "quiet_pulse"
    PACKAGE_ARRIVED = "package_arrived"
    FRONT_DOOR_UNLOCKED = "front_door_unlocked"
    SINK_FULL = "sink_full"


class QuietPulseDuration(int, Enum):
    FIFTEEN_MIN = 15
    THIRTY_MIN = 30
    SIXTY_MIN = 60


class NudgeSend(BaseModel):
    type: NudgeType
    duration_minutes: QuietPulseDuration | None = None

    @model_validator(mode="after")
    def _check_duration(self) -> "NudgeSend":
        if self.type == NudgeType.QUIET_PULSE and self.duration_minutes is None:
            raise ValueError("duration_minutes is required for a quiet pulse.")
        if self.type != NudgeType.QUIET_PULSE and self.duration_minutes is not None:
            raise ValueError("duration_minutes only applies to a quiet pulse.")
        return self


class NudgeRead(BaseModel):
    """What every group member (including the sender) receives — over the
    WebSocket and as the HTTP response to the send call. No sender field
    exists on this model at all: anonymity holds by construction, not by
    a filter someone could forget to apply.
    """

    id: uuid.UUID
    group_id: uuid.UUID
    type: NudgeType
    message: str
    duration_minutes: int | None
    created_at: datetime
