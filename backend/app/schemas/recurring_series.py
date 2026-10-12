import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_validator

from app.schemas.reservation import ReservationDuration, ReservationWithChore


class RecurringSeriesCreate(BaseModel):
    weekdays: list[int]  # 0=Monday .. 6=Sunday
    start_hour_utc: int
    start_minute_utc: int
    duration_minutes: ReservationDuration

    @field_validator("weekdays")
    @classmethod
    def _weekdays_valid(cls, value: list[int]) -> list[int]:
        if not value:
            raise ValueError("Pick at least one weekday.")
        if len(set(value)) != len(value):
            raise ValueError("Weekdays must not repeat.")
        if any(day < 0 or day > 6 for day in value):
            raise ValueError("Each weekday must be between 0 (Monday) and 6 (Sunday).")
        return sorted(value)

    @field_validator("start_hour_utc")
    @classmethod
    def _hour_valid(cls, value: int) -> int:
        if value < 0 or value > 23:
            raise ValueError("start_hour_utc must be between 0 and 23.")
        return value

    @field_validator("start_minute_utc")
    @classmethod
    def _minute_valid(cls, value: int) -> int:
        if value < 0 or value > 59:
            raise ValueError("start_minute_utc must be between 0 and 59.")
        return value


class RecurringSeriesRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    group_id: uuid.UUID
    space_id: uuid.UUID
    user_id: uuid.UUID
    weekdays: list[int]
    start_hour_utc: int
    start_minute_utc: int
    duration_minutes: int
    created_at: datetime


class SkippedOccurrence(BaseModel):
    """One candidate occurrence the series wanted to book but couldn't —
    always "conflict" today (an existing reservation already held that
    slot); kept as a string rather than an enum so a future skip reason
    doesn't require a schema migration.
    """

    start_time: datetime
    end_time: datetime
    reason: str


class RecurringSeriesCreateResult(BaseModel):
    series: RecurringSeriesRead
    created: list[ReservationWithChore]
    skipped: list[SkippedOccurrence]


class RecurringSeriesCancelResult(BaseModel):
    series_id: uuid.UUID
    cancelled_occurrence_ids: list[uuid.UUID]
