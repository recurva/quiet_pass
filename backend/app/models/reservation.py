import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import ExcludeConstraint, TSTZRANGE, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Reservation(Base):
    """A member booking one space for a time block.

    `during` is NOT the reservation's actual [start_time, end_time) window
    — it's that window with its trailing edge padded by the booking buffer
    (reservation_service.create_reservation), i.e. [start_time, end_time +
    buffer). The EXCLUDE constraint below checks overlap against `during`,
    so a single atomic, database-enforced check covers both "no
    double-booking" and "respect the buffer between bookings" at once —
    there's no separate app-level buffer check that could race with a
    concurrent insert.

    This needs the btree_gist extension (enabled in this table's
    migration) so GiST can index the plain `space_id` UUID equality
    alongside the range overlap.
    """

    __tablename__ = "reservations"
    __table_args__ = (
        ExcludeConstraint(
            ("space_id", "="),
            ("during", "&&"),
            using="gist",
            name="ex_reservations_no_overlap",
        ),
    )

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
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # Buffer-padded range used only for the exclusion check; see docstring.
    during: Mapped[Any] = mapped_column(TSTZRANGE, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
