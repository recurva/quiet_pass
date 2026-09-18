import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class SpaceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    group_id: uuid.UUID
    name: str
    created_at: datetime
