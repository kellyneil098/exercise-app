import uuid
from datetime import UTC, datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, false
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def now() -> datetime:
    return datetime.now(UTC)


def new_id() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "user"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    apple_sub: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    # True only when `email` came from an identity provider claim marked verified; gates account linking.
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false(), nullable=False)
    display_name: Mapped[str] = mapped_column(String(80), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Session(Base):
    """Opaque bearer tokens. Only the SHA-256 of the token is stored."""

    __tablename__ = "session"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("user.id"), index=True)
    device_name: Mapped[str] = mapped_column(String(120), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Invite(Base):
    __tablename__ = "invite"
    code: Mapped[str] = mapped_column(String(16), primary_key=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("user.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_by: Mapped[str | None] = mapped_column(ForeignKey("user.id"), nullable=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # §2: directional read-only shares set up when the invite is accepted.
    grant_view_to_inviter: Mapped[bool] = mapped_column(Boolean, default=True)
    grant_view_of_inviter: Mapped[bool] = mapped_column(Boolean, default=True)


class Share(Base):
    """viewer may read everything owner has. Directional."""

    __tablename__ = "share"
    __table_args__ = (UniqueConstraint("owner_id", "viewer_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    owner_id: Mapped[str] = mapped_column(ForeignKey("user.id"), index=True)
    viewer_id: Mapped[str] = mapped_column(ForeignKey("user.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class SyncCounter(Base):
    """Single-row allocator for `Record.server_seq`; UPDATE ... RETURNING makes allocation atomic."""

    __tablename__ = "sync_counter"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    value: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class Record(Base):
    """One synced row of any client table. The server stores, scopes and orders; it never interprets.

    `server_seq` is the pull cursor: strictly increasing per commit, so a client that has seen seq N
    asks for everything > N.
    """

    __tablename__ = "record"
    __table_args__ = (
        Index("ix_record_user_seq", "user_id", "server_seq"),
        Index("ix_record_user_table", "user_id", "table_name"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("user.id"), nullable=False)
    table_name: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    server_seq: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
