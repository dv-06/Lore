from typing import Literal

from pydantic import BaseModel


class RootResponse(BaseModel):
    name: str
    version: str
    status: Literal["ok"]


class SystemStatusResponse(BaseModel):
    status: Literal["ok"]
    database: Literal["ok"]

