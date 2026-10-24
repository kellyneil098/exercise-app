import json
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, PrivateAttr, model_validator

SYNC_TABLES = frozenset(
    {
        "location",
        "location_equipment",
        "user_exercise",
        "exercise_state",
        "heavy_rotation",
        "split_state",
        "session",
        "exercise_result",
        "set_log",
        "run_plan",
        "planned_run",
        "run",
        "settings",
    }
)
MAX_RECORD_PAYLOAD_BYTES = 64 * 1024
MAX_PUSH_PAYLOAD_BYTES = 2 * 1024 * 1024


class AppleLoginIn(BaseModel):
    identity_token: str
    invite_code: str | None = None
    display_name: str | None = None
    device_name: str = ""


class DevLoginIn(BaseModel):
    email: str
    invite_code: str | None = None
    display_name: str | None = None
    device_name: str = ""


class UserOut(BaseModel):
    id: str
    email: str | None
    display_name: str


class TokenOut(BaseModel):
    token: str
    user: UserOut


class InviteCreateIn(BaseModel):
    grant_view_to_inviter: bool = True
    grant_view_of_inviter: bool = True


class InviteOut(BaseModel):
    code: str
    expires_at: datetime
    grant_view_to_inviter: bool
    grant_view_of_inviter: bool


class ShareOut(BaseModel):
    owner: UserOut
    viewer: UserOut


class SharesOut(BaseModel):
    i_can_view: list[UserOut]
    can_view_me: list[UserOut]


class RecordIn(BaseModel):
    id: str = Field(min_length=1, max_length=36)
    table: str = Field(max_length=32)
    op: Literal["upsert", "delete"]
    payload: dict = Field(default_factory=dict)
    updated_at: datetime
    _payload_bytes: int = PrivateAttr(0)

    @model_validator(mode="after")
    def _cap_payload(self) -> "RecordIn":
        self._payload_bytes = len(json.dumps(self.payload, separators=(",", ":"), ensure_ascii=False).encode())
        if self._payload_bytes > MAX_RECORD_PAYLOAD_BYTES:
            raise ValueError(f"payload exceeds {MAX_RECORD_PAYLOAD_BYTES} bytes")
        return self


class PushIn(BaseModel):
    records: list[RecordIn] = Field(max_length=2000)

    @model_validator(mode="after")
    def _cap_total_payload(self) -> "PushIn":
        if sum(r._payload_bytes for r in self.records) > MAX_PUSH_PAYLOAD_BYTES:
            raise ValueError(f"total payload exceeds {MAX_PUSH_PAYLOAD_BYTES} bytes")
        return self


class PushOut(BaseModel):
    accepted: int
    ignored: int
    cursor: int


class RecordOut(BaseModel):
    id: str
    user_id: str
    table: str
    payload: dict
    updated_at: datetime
    deleted: bool
    seq: int


class PullOut(BaseModel):
    records: list[RecordOut]
    cursor: int
    has_more: bool
    visible_user_ids: list[str] = Field(default_factory=list)
