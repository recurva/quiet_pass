from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class DeletedFirebaseUid(Base):
    """A tombstone: every firebase_uid a User row was ever deleted under,
    kept forever. Firebase ID tokens stay cryptographically valid for up
    to an hour after issuance regardless of whether the account they name
    still exists — this hand-rolled verification never checks revocation
    (see app/core/firebase.py) — so without this, a still-unexpired token
    from *before* a deletion could reach authenticate_token's
    fetch-or-create path after the deletion and silently provision a
    brand-new, blank account under the same firebase_uid the caller
    thought they'd just deleted. Checked before every such provisioning
    attempt; see authenticate_token.
    """

    __tablename__ = "deleted_firebase_uids"

    firebase_uid: Mapped[str] = mapped_column(String(128), primary_key=True)
    deleted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
