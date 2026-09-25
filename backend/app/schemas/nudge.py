import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field, model_validator

# Generous enough for a real one-line nudge, short enough that it can't
# become a chat message in disguise — a custom nudge is still meant to be
# glanceable, the same as every preset's fixed wording.
CUSTOM_NUDGE_MESSAGE_MAX_LENGTH = 140


class NudgeType(str, Enum):
    """Adding a new preset is just a new member here plus an entry in
    nudge_service's message table — nothing else needs to change. CUSTOM
    is the one exception: its wording comes from the sender
    (NudgeSend.message) instead of a fixed table entry — see
    nudge_service.render_message.
    """

    QUIET_PULSE = "quiet_pulse"
    PACKAGE_ARRIVED = "package_arrived"
    FRONT_DOOR_UNLOCKED = "front_door_unlocked"
    SINK_FULL = "sink_full"
    CUSTOM = "custom"


class QuietPulseDuration(int, Enum):
    FIFTEEN_MIN = 15
    THIRTY_MIN = 30
    SIXTY_MIN = 60


class NudgeSend(BaseModel):
    type: NudgeType
    duration_minutes: QuietPulseDuration | None = None
    # Required for CUSTOM, forbidden for every other type — same
    # either-or shape as duration_minutes above, just for a different
    # pair of types.
    message: str | None = Field(default=None, max_length=CUSTOM_NUDGE_MESSAGE_MAX_LENGTH)

    @model_validator(mode="after")
    def _check_duration(self) -> "NudgeSend":
        if self.type == NudgeType.QUIET_PULSE and self.duration_minutes is None:
            raise ValueError("duration_minutes is required for a quiet pulse.")
        if self.type != NudgeType.QUIET_PULSE and self.duration_minutes is not None:
            raise ValueError("duration_minutes only applies to a quiet pulse.")
        return self

    @model_validator(mode="after")
    def _check_message(self) -> "NudgeSend":
        if self.type == NudgeType.CUSTOM:
            stripped = (self.message or "").strip()
            if not stripped:
                raise ValueError("message is required for a custom nudge.")
            self.message = stripped
        elif self.message is not None:
            raise ValueError("message only applies to a custom nudge.")
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
