import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict

from app.schemas.chore import ChoreRead


class ReservationDuration(int, Enum):
    FIFTEEN_MIN = 15
    THIRTY_MIN = 30
    SIXTY_MIN = 60


class ReservationCreate(BaseModel):
    start_time: datetime
    duration_minutes: ReservationDuration


class ReservationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    group_id: uuid.UUID
    space_id: uuid.UUID
    user_id: uuid.UUID
    start_time: datetime
    end_time: datetime


class ReservationWithChore(BaseModel):
    reservation: ReservationRead
    chore: ChoreRead
