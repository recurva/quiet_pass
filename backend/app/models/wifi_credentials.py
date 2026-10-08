import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class WifiCredentials(Base):
    """A house's Wi-Fi SSID/password, admin-set, one row per group — used
    to render a standard `WIFI:` QR code in-app for guests. The app never
    connects anyone to this network itself (Android/iOS give third-party
    apps no API to do that); this is purely storage plus QR rendering, the
    actual joining happens when a guest's own camera scans the code.
    """

    __tablename__ = "wifi_credentials"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    ssid: Mapped[str] = mapped_column(String(100), nullable=False)
    password: Mapped[str] = mapped_column(String(100), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
