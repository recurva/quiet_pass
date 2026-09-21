import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


class HouseStatus(str, Enum):
    OPEN_TO_CHAT = "open_to_chat"
    DEEP_FOCUS = "deep_focus"
    IN_CALL = "in_call"
    SLEEPING_EARLY = "sleeping_early"
    AWAY = "away"


class StatusDurationRule(BaseModel):
    """Per-status duration policy (the Time Limits spec). Open to Chat has
    no rule at all — it's the one indefinite, uncapped status; every other
    status must pick a duration from `allowed_minutes`, defaulting to
    `default_minutes`, hard-capped server-side at `cap_minutes` regardless
    of what the client sends.
    """

    default_minutes: int
    allowed_minutes: tuple[int, ...]
    cap_minutes: int


# Source of truth for duration enforcement (see status_service.resolve_ttl_seconds).
# The Flutter app mirrors these values for the picker UI — see
# lib/features/groups/house_status_wire.dart's STATUS_DURATION_RULES comment
# for the same "must stay in sync" note that already applies to the
# HouseStatus values themselves across schemas/status.py, app_colors.dart,
# and house_status_wire.dart.
STATUS_DURATION_RULES: dict[HouseStatus, StatusDurationRule] = {
    HouseStatus.IN_CALL: StatusDurationRule(
        default_minutes=30, allowed_minutes=(15, 30, 60, 120), cap_minutes=180
    ),
    HouseStatus.DEEP_FOCUS: StatusDurationRule(
        default_minutes=120, allowed_minutes=(60, 120, 240), cap_minutes=360
    ),
    HouseStatus.SLEEPING_EARLY: StatusDurationRule(
        default_minutes=480, allowed_minutes=(360, 480, 600), cap_minutes=720
    ),
    HouseStatus.AWAY: StatusDurationRule(
        default_minutes=240, allowed_minutes=(120, 240, 480, 1440), cap_minutes=2880
    ),
}


class StatusSet(BaseModel):
    status: HouseStatus
    # None means "use this status's default duration" (or is simply ignored
    # for OPEN_TO_CHAT, which has no duration concept at all). Minutes, not
    # seconds, to match the spec's units and the allowed-preset lists above.
    duration_minutes: int | None = None


class StatusRead(BaseModel):
    user_id: uuid.UUID
    group_id: uuid.UUID
    # Never None on the wire: an expired or never-set status resolves to
    # OPEN_TO_CHAT (the spec's "open by default" rule) rather than a
    # separate null/"no status" state.
    status: HouseStatus
    ttl_seconds: int | None = Field(
        default=None, description="Seconds remaining before this status expires."
    )
    expires_at: datetime | None = Field(
        default=None,
        description="Absolute UTC expiry, for display (e.g. 'until 6:30 PM'). "
        "None for Open to Chat, which never expires.",
    )
