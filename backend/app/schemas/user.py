import re
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Matches the client's own cap (see name_sheet.dart / phone_entry_page.dart)
# — kept here as the actual source of truth, since a client-side max is
# only ever a convenience, never something the server can trust on its
# own. Also long enough that no real name gets clipped, short enough that
# a housemate row (group_detail_page.dart) can't be broken by one.
DISPLAY_NAME_MAX_LENGTH = 60

# Letters and spaces only — matches lib/core/validation.dart's own regex.
_LETTERS_AND_SPACES_ONLY = re.compile(r"^[a-zA-Z ]+$")


def _validate_display_name(value: str) -> str:
    # Strips first, so " Sam" saves as "Sam" and " " (space-only) is
    # rejected as empty rather than as a "letters and spaces only"
    # violation — the emptiness check is the more useful message.
    stripped = value.strip()
    if not stripped:
        raise ValueError("Name cannot be empty.")
    if not _LETTERS_AND_SPACES_ONLY.match(stripped):
        raise ValueError("Name can only contain letters and spaces.")
    return stripped


class UserBase(BaseModel):
    phone_number: str = Field(min_length=6, max_length=32)
    display_name: str = Field(min_length=1, max_length=DISPLAY_NAME_MAX_LENGTH)


class UserRead(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime


class UserUpdate(BaseModel):
    display_name: str = Field(min_length=1, max_length=DISPLAY_NAME_MAX_LENGTH)

    _validate = field_validator("display_name")(_validate_display_name)
