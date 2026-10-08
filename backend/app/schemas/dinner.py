import uuid
from datetime import date, datetime

from pydantic import BaseModel

from app.models.dinner_headcount import DinnerStatus


class DinnerSet(BaseModel):
    status: DinnerStatus


class DinnerResponseRead(BaseModel):
    user_id: uuid.UUID
    status: DinnerStatus
    updated_at: datetime


class DinnerTallyRead(BaseModel):
    """Today's (house-local/IST) tally. `responses` only ever contains
    members who have actually answered today — same "absence means
    nothing was set" shape status.py's StatusRead family already uses,
    not a padded list with null entries for the rest of the house.
    """

    day: date
    cutoff_at: datetime
    cutoff_passed: bool
    home_count: int
    staying_out_count: int
    responses: list[DinnerResponseRead]
