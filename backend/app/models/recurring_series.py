import uuid
from datetime import datetime

from sqlalchemy import ARRAY, DateTime, ForeignKey, Integer, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class RecurringSeries(Base):
    """A member's weekly repeating booking for a space (e.g. every Tuesday
    and Thursday 7:00-8:00 PM UTC). The series row itself is just the
    recurrence rule — the actual bookings are ordinary `Reservation` rows
    (one per occurrence, see recurring_service.py), each tagged with this
    series's id via `Reservation.recurring_series_id`. That's what makes
    every occurrence subject to the exact same EXCLUDE constraint and
    buffer as a manually-booked reservation, with no separate code path.
    """

    __tablename__ = "recurring_series"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True
    )
    space_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("spaces.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # 0=Monday .. 6=Sunday, Python's date.weekday() convention — matches
    # what recurring_service.py uses to walk candidate dates.
    weekdays: Mapped[list[int]] = mapped_column(ARRAY(Integer), nullable=False)
    start_hour_utc: Mapped[int] = mapped_column(Integer, nullable=False)
    start_minute_utc: Mapped[int] = mapped_column(Integer, nullable=False)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
