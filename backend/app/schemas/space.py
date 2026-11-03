import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class SpaceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    group_id: uuid.UUID
    name: str
    created_at: datetime


class SpaceCreate(BaseModel):
    # 80 matches Space.name's column width (app/models/space.py).
    name: str = Field(min_length=1, max_length=80)
