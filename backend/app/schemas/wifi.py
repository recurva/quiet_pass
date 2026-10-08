from datetime import datetime

from pydantic import BaseModel, Field


class WifiCredentialsSet(BaseModel):
    ssid: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=100)


class WifiCredentialsRead(BaseModel):
    ssid: str
    password: str
    updated_at: datetime
