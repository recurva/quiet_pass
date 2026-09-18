import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DeviceTokenRegister(BaseModel):
    token: str = Field(min_length=10, max_length=512)
    platform: str = Field(default="android", pattern="^(android|ios|web)$")


class DeviceTokenRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    platform: str
    created_at: datetime
