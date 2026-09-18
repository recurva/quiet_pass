import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.membership import MembershipRole


class MembershipCreate(BaseModel):
    user_id: uuid.UUID
    group_id: uuid.UUID
    role: MembershipRole = MembershipRole.MEMBER


class MembershipRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    group_id: uuid.UUID
    role: MembershipRole
    joined_at: datetime
