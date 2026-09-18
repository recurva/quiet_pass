import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ChoreRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reservation_id: uuid.UUID
    user_id: uuid.UUID
    template: str
    due_at: datetime
    done: bool
