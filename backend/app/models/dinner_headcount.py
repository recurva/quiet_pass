import enum
import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Enum, ForeignKey, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class DinnerStatus(str, enum.Enum):
    HOME = "home"
    STAYING_OUT = "staying_out"


class DinnerHeadcount(Base):
    """One member's dinner response for one house on one day. "Reset
    daily" is implicit, not a cleanup job: a new day simply has no rows
    yet for anyone, so "today's tally" is always exactly today's rows —
    no scheduled task to forget to run, nothing to clean up. `day` is
    the house's local (IST) calendar date — see
    app.services.dinner_service for why IST specifically and not UTC.
    """

    __tablename__ = "dinner_headcounts"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", "day", name="uq_dinner_headcount_group_user_day"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    day: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[DinnerStatus] = mapped_column(
        Enum(
            DinnerStatus,
            name="dinner_status",
            values_callable=lambda enum_cls: [member.value for member in enum_cls],
        ),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
