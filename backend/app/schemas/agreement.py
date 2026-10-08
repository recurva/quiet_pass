import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class AgreementCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    content: str = Field(min_length=1)


class AgreementUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    content: str = Field(min_length=1)


class AgreementRead(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    created_by: uuid.UUID
    title: str
    content: str
    created_at: datetime
    updated_at: datetime
