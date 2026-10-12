import uuid
from datetime import datetime

from pydantic import BaseModel


class UrgentAccessRequestRead(BaseModel):
    group_id: uuid.UUID
    space_id: uuid.UUID
    reservation_id: uuid.UUID
    holder_id: uuid.UUID
    requester_id: uuid.UUID
    created_at: datetime
